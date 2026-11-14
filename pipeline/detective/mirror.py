"""Mirror cases: the same variable trending in OPPOSITE directions in two places
(or two altitudes, or two poles) - and the hunt for one shared cause.

Evidence board, five checks:
  1 Witnesses       - do independent datasets see the same thing?
  2 Signal vs noise - is each side's trend statistically significant?
  3 Alibi check     - is a jump explained by a satellite / instrument change?
  4 Timeline        - when did each signal rise above the year-to-year noise?
  5 Motive          - does one driver's year-to-year "fingerprint" predict both
                      opposite trends?  (local drivers can also give an alibi:
                      "rain did not change, so rain is not the culprit")
"""
from __future__ import annotations

import math

import numpy as np
from scipy import ndimage

from . import aggregate as agg
from . import regions, stats
from .engine import Context, series_evidence
from .registry import Source
from .util import DetectiveError, log
from .verdict import CASE, CHECKS, TREND, direction_words, fmt, fmt_p


class NoMirror(DetectiveError):
    """Raised when one side of a mirror simply does not exist in the data."""


# ----------------------------------------------------------------------------- clusters
def find_clusters(sig: np.ndarray, f: dict, min_cells: int) -> list[dict]:
    lat, lon = f["lat"], f["lon"]
    lab, n = ndimage.label(sig, structure=np.ones((3, 3), dtype=int))
    if n == 0:
        return []
    span = lon[-1] - lon[0] + f["dlon"]
    if lon.size > 2 and span > 359:  # global in longitude: join across the dateline
        parent = list(range(n + 1))

        def find(x):
            while parent[x] != x:
                parent[x] = parent[parent[x]]
                x = parent[x]
            return x

        for i in range(lab.shape[0]):
            for di in (-1, 0, 1):
                k = i + di
                if 0 <= k < lab.shape[0] and lab[i, 0] and lab[k, -1]:
                    ra, rb = find(lab[i, 0]), find(lab[k, -1])
                    if ra != rb:
                        parent[ra] = rb
        roots = np.array([find(x) for x in range(n + 1)])
        lab = roots[lab]
    area = agg.cell_area_km2(lat, f["dlat"], f["dlon"])[:, None] * np.ones_like(sig, dtype="float64")
    z = np.abs(f["trend"]["z"])
    out = []
    for k in np.unique(lab[lab > 0]):
        m = lab == k
        nc = int(m.sum())
        if nc < min_cells:
            continue
        a = float(area[m].sum())
        out.append({"mask": m, "n_cells": nc, "area_km2": a, "strength": a * float(np.nanmean(z[m]))})
    out.sort(key=lambda c: -c["strength"])
    return out


def _describe_mask(mask: np.ndarray, f: dict) -> dict:
    lat, lon = f["lat"], f["lon"]
    ii, jj = np.nonzero(mask)
    w = agg.area_weights(lat[ii])
    clat = float(np.sum(lat[ii] * w) / np.sum(w))
    ang = np.deg2rad(lon[jj])
    clon = float(np.rad2deg(math.atan2(np.sum(np.sin(ang) * w), np.sum(np.cos(ang) * w))))
    area = float((agg.cell_area_km2(lat, f["dlat"], f["dlon"])[:, None] * np.ones_like(mask, dtype="float64"))[mask].sum())
    return {
        "centroid": [clat, clon],
        "bbox": [float(lon[jj].min() - f["dlon"] / 2), float(lat[ii].min() - f["dlat"] / 2),
                 float(lon[jj].max() + f["dlon"] / 2), float(lat[ii].max() + f["dlat"] / 2)],
        "area_km2": area,
        "n_cells": int(mask.sum()),
        "res": [f["dlat"], f["dlon"]],
        "cells": [[float(lat[i]), float(lon[j])] for i, j in zip(ii, jj)][:4000],
    }


def resolve_region(spec: dict, f: dict, cfg) -> dict:
    tr = f["trend"]
    lat, lon = f["lat"], f["lon"]
    valid = np.isfinite(tr["p"])
    within = agg.bbox_mask(lat, lon, spec["within"]) if spec.get("within") else np.ones_like(valid)
    how = "bbox"
    if "bbox" in spec:
        mask = agg.bbox_mask(lat, lon, spec["bbox"]) & valid
        if not mask.any():
            raise DetectiveError(f"region {spec.get('name')} has no valid cells")
    elif "auto" in spec:
        want = 1.0 if str(spec["auto"]).lower() in ("positive", "up", "rising", "+") else -1.0
        mc = int(spec.get("min_cells", cfg.mirror["min_cells"]))
        with np.errstate(invalid="ignore"):
            strict = valid & within & (tr["q"] < cfg.analysis["fdr_alpha"]) & (np.sign(tr["slope"]) == want)
            relaxed = valid & within & (tr["p"] < 0.10) & (np.sign(tr["slope"]) == want)
        clusters = find_clusters(strict, f, mc)
        how = "cluster"
        if not clusters:
            clusters = find_clusters(relaxed, f, mc)
            how = "cluster_relaxed"
        if clusters:
            rank = min(int(spec.get("rank", 0)), len(clusters) - 1)
            mask = clusters[rank]["mask"]
        elif spec.get("bbox_fallback"):
            mask = agg.bbox_mask(lat, lon, spec["bbox_fallback"]) & valid
            how = "bbox_fallback"
            if not mask.any():
                raise DetectiveError(f"region {spec.get('name')} has no valid cells")
        else:
            raise NoMirror(f"no significant {'rising' if want > 0 else 'falling'} region found"
                           f"{' within ' + str(spec['within']) if spec.get('within') else ''} - the variable may move one way everywhere (no mirror)")
    else:
        raise DetectiveError("region needs 'bbox' or 'auto'")
    info = _describe_mask(mask, f)
    en, hi = regions.name_for(*info["centroid"])
    info.update(name=spec.get("name") or en, name_hi=spec.get("name_hi") or hi, how=how, mask=mask)
    return info


def remap_mask(mask: np.ndarray, f_from: dict, f_to: dict) -> np.ndarray:
    lat, lon, dlat, dlon = f_from["lat"], f_from["lon"], f_from["dlat"], f_from["dlon"]
    lat2, lon2 = f_to["lat"], f_to["lon"]
    out = np.zeros((lat2.size, lon2.size), dtype=bool)
    i = np.round((lat2 - lat[0]) / dlat).astype(int)
    j = np.round((((lon2 - lon[0]) + 360) % 360) / dlon).astype(int) % max(lon.size, 1)
    oi = (i >= 0) & (i < lat.size)
    oj = (j >= 0) & (j < lon.size)
    if oi.any() and oj.any():
        out[np.ix_(oi, oj)] = mask[np.ix_(i[oi], j[oj])]
    # coarser target grid: mark target cells that contain any source cell
    ii, jj = np.nonzero(mask)
    ti = np.round((lat[ii] - lat2[0]) / f_to["dlat"]).astype(int)
    tj = np.round((((lon[jj] - lon2[0]) + 360) % 360) / f_to["dlon"]).astype(int) % max(lon2.size, 1)
    ok = (ti >= 0) & (ti < lat2.size)
    out[ti[ok], tj[ok]] = True
    return out


# ----------------------------------------------------------------------------- helpers
def _units(src: Source) -> dict:
    if src.trend_units == "percent":
        return {"per_decade": "% per decade", "per_decade_hi": "% प्रति दशक", "percent": True}
    u = src.units or ""
    return {"per_decade": f"{u}/decade".strip("/"), "per_decade_hi": f"{u}/दशक".strip("/"), "percent": False}


def _per_decade(ev: dict, base: float, percent: bool) -> dict:
    scale = 10.0
    if percent and base and math.isfinite(base) and abs(base) > 0:
        scale = 10.0 / abs(base) * 100.0
    return {k: (ev[k] * scale if ev.get(k) is not None and math.isfinite(ev[k]) else None) for k in ("slope", "ci_lo", "ci_hi")}


def _trend_block(ev: dict, base: float, percent: bool) -> dict:
    pd_ = _per_decade(ev, base, percent)
    v = ev["verdict"]
    return {
        "slope_dec": pd_["slope"], "ci_lo_dec": pd_["ci_lo"], "ci_hi_dec": pd_["ci_hi"],
        "slope_yr": ev["slope"], "p": ev["p"], "p_raw": ev["p_raw"], "z": ev["z"], "snr": ev["snr"],
        "sigma": ev["sigma"], "r1": ev["r1"], "n": ev["n"], "t0": ev["t0"], "t1": ev["t1"],
        "toe1": ev["toe1"] if math.isfinite(ev["toe1"]) else None,
        "toe2": ev["toe2"] if math.isfinite(ev["toe2"]) else None,
        "emerged": ev["emerged"],
        "years_needed": ev["years_needed"] if math.isfinite(ev["years_needed"]) else None,
        "method": ev["method"], "pettitt": ev.get("pettitt"), "alibi": ev.get("alibi"),
        "verdict": v, "verdict_en": TREND[v]["en"], "verdict_hi": TREND[v]["hi"],
    }


def _driver_specs(case: dict, ctx: Context) -> list:
    specs = case.get("drivers")
    if specs is None:
        specs = ctx.cfg.raw.get("drivers_default", [])
    return list(specs)


def _driver_meta(spec, ctx: Context) -> dict:
    sid = spec if isinstance(spec, str) else spec["source"]
    src = ctx.source(sid)
    label = spec.get("label") if isinstance(spec, dict) else None
    label_hi = spec.get("label_hi") if isinstance(spec, dict) else None
    return {"id": sid, "title": label or src.short or src.title, "title_hi": label_hi or src.short_hi or src.title_hi or src.title,
            "units": src.units}


def _pct(x) -> str:
    if x is None or not math.isfinite(x):
        return "-"
    return "over 100%" if x > 1.5 else f"{round(100 * x)}%"


def _status(ok: bool | None, warn: bool = False) -> str:
    if ok is None:
        return "na"
    return "pass" if ok else ("warn" if warn else "fail")


# ----------------------------------------------------------------------------- core assembly
def _assemble(case: dict, ctx: Context, src: Source, A: dict, B: dict, years, sa, sb, base_a, base_b,
              local_tests: list, witness_results: list, extra: dict) -> dict:
    cfg = ctx.cfg
    u = _units(src)
    trans = src.known_transitions or []
    evA = series_evidence(years, sa, cfg, trans)
    evB = series_evidence(years, sb, cfg, trans)
    tA, tB = _trend_block(evA, base_a, u["percent"]), _trend_block(evB, base_b, u["percent"])
    sA, sB = np.sign(evA["slope"]), np.sign(evB["slope"])
    alpha = cfg.analysis["alpha"]
    clean_sides = evA["verdict"] not in ("artifact", "insufficient") and evB["verdict"] not in ("artifact", "insufficient")
    is_mirror = bool(clean_sides and sA * sB < 0 and evA["p"] < alpha and evB["p"] < alpha)
    likely_mirror = bool(clean_sides and sA * sB < 0 and evA["p"] < 0.10 and evB["p"] < 0.10)

    # ---------------- motive: global drivers
    tests = []
    for spec in _driver_specs(case, ctx):
        try:
            d = ctx.series(spec, season=case.get("season", "ANN"))
        except Exception as e:
            log.warning("  driver %s unavailable: %s", spec, e)
            continue
        common, ia, idd = np.intersect1d(years, d["years"], return_indices=True)
        if common.size < 10:
            continue
        fa = stats.fingerprint(sa[ia], d["anom"][idd], common)
        fb = stats.fingerprint(sb[ia], d["anom"][idd], common)
        meta = _driver_meta(spec, ctx)
        tests.append({**meta, "kind": "global", "A": fa, "B": fb,
                      "series": {"years": d["years"], "values": d["anom"]}})
    tests += local_tests

    mp = cfg.mirror["driver_p"]
    emin = cfg.mirror["explained_min"]

    def fp_ok(fp, sign):
        return (fp.get("p") is not None and math.isfinite(fp.get("p", np.nan)) and fp["p"] < mp
                and np.sign(fp.get("predicted_slope", 0)) == sign and (fp.get("explained") or 0) >= emin)

    def fp_dir(fp, sign, pmax=0.25):
        # right direction with at least a hint of a year-to-year link (co-trends alone never count:
        # any two trending series correlate - see the negative control in the selftest)
        return (fp.get("p") is not None and math.isfinite(fp.get("p", np.nan)) and fp["p"] < pmax
                and np.sign(fp.get("predicted_slope", 0)) == sign)

    for t in tests:
        a_ok, b_ok = fp_ok(t["A"], sA), fp_ok(t["B"], sB)
        if a_ok and b_ok:
            t["verdict"] = "strong"
        elif (a_ok and fp_dir(t["B"], sB)) or (b_ok and fp_dir(t["A"], sA)):
            t["verdict"] = "weak"
        else:
            t["verdict"] = "none"
        t["score"] = (2 if t["verdict"] == "strong" else 1 if t["verdict"] == "weak" else 0) + 0.01 * (
            (t["A"].get("explained") or 0) + (t["B"].get("explained") or 0))
    best = max([t for t in tests if t["kind"] == "global"], key=lambda t: t["score"], default=None)
    local_alibi = [t for t in tests if t["kind"] == "local" and t.get("alibi")]

    if not is_mirror:
        code = "not_mirror"
    elif best and best["verdict"] == "strong":
        code = "shared_strong"
    elif local_alibi:
        code = "other_cause"
    elif best and best["verdict"] == "weak":
        code = "shared_weak"
    elif tests:
        code = "other_cause"
    else:
        code = "open"

    # ---------------- five checks
    checks = []
    # 1 witnesses
    if witness_results:
        agree = [w["agrees"] for w in witness_results]
        st = "pass" if all(agree) else ("warn" if any(agree) else "fail")
        names = ", ".join(w["title"] for w in witness_results)
        names_hi = ", ".join(w["title_hi"] for w in witness_results)
        checks.append({"key": "witnesses", "status": st,
                       "en": f"Independent witness ({names}) {'agrees on both sides' if st == 'pass' else 'partly agrees' if st == 'warn' else 'disagrees'}.",
                       "hi": f"स्वतंत्र गवाह ({names_hi}) {'दोनों तरफ़ सहमत है' if st == 'pass' else 'आंशिक रूप से सहमत है' if st == 'warn' else 'सहमत नहीं है'}।",
                       "details": witness_results})
    else:
        checks.append({"key": "witnesses", "status": "na",
                       "en": "Single dataset - no second witness was available for this case.",
                       "hi": "एक ही डेटासेट - इस केस के लिए दूसरा गवाह उपलब्ध नहीं था।"})
    # 2 signal
    vA, vB = evA["verdict"], evB["verdict"]
    if vA == "confirmed" and vB == "confirmed":
        sst = "pass"
    elif vA in ("confirmed", "likely") and vB in ("confirmed", "likely"):
        sst = "warn"
    else:
        sst = "fail"
    checks.append({"key": "signal", "status": sst,
                   "en": f"{A['name']}: p {fmt_p(evA['p'])}, change = {fmt(evA['snr'],1)}x the noise. {B['name']}: p {fmt_p(evB['p'])}, {fmt(evB['snr'],1)}x the noise.",
                   "hi": f"{A['name_hi']}: p {fmt_p(evA['p'])}, बदलाव = शोर का {fmt(evA['snr'],1)} गुना। {B['name_hi']}: p {fmt_p(evB['p'])}, शोर का {fmt(evB['snr'],1)} गुना।"})
    # 3 alibi
    al = [(A, evA["alibi"]), (B, evB["alibi"])]
    bad = [(R, x) for R, x in al if x["flag"] and x["survives"] is False]
    flagged = [(R, x) for R, x in al if x["flag"]]
    shifted = [(R, x) for R, x in al if x.get("break_year") and not x["flag"]]
    if bad:
        R, x = bad[0]
        ast = "fail"
        en = f"{R['name']}: the jump in {x['break_year']} lines up with '{x['label']}' and the trend vanishes on either side of it - likely an instrument artifact."
        hi = f"{R['name_hi']}: {x['break_year']} का उछाल '{x.get('label_hi') or x['label']}' से मेल खाता है और उसके दोनों तरफ़ रुझान गायब है - शायद उपकरण का दोष।"
    elif flagged:
        R, x = flagged[0]
        ast = "pass"
        en = f"{R['name']}: a jump in {x['break_year']} coincides with '{x['label']}', but the trend holds on both sides of it."
        hi = f"{R['name_hi']}: {x['break_year']} का उछाल '{x.get('label_hi') or x['label']}' के समय आता है, पर रुझान उसके दोनों तरफ़ बना रहता है।"
    elif shifted:
        parts = "; ".join(f"{R['name']} {x['break_year']}" for R, x in shifted)
        parts_hi = "; ".join(f"{R['name_hi']} {x['break_year']}" for R, x in shifted)
        ast, en, hi = "pass", f"Shift detected ({parts}) with no instrument change at that time.", f"बदलाव मिला ({parts_hi}), उस समय कोई उपकरण नहीं बदला।"
    else:
        ast, en, hi = "pass", "No suspicious jumps - the change is gradual.", "कोई संदिग्ध उछाल नहीं - बदलाव धीरे-धीरे है।"
    checks.append({"key": "alibi", "status": ast, "en": en, "hi": hi})
    # 4 timeline
    eA, eB = evA["emerged"], evB["emerged"]
    tst = "pass" if (eA and eB) else ("warn" if (eA or eB) else "fail")

    def toe_txt(name, ev, lang):
        if ev["emerged"]:
            return f"{name}: {'rose above noise in' if lang == 'en' else 'शोर से ऊपर निकला'} {int(round(ev['toe1']))}"
        yn = ev["years_needed"]
        if math.isfinite(yn):
            return f"{name}: {'needs ~' if lang == 'en' else 'लगभग'} {int(math.ceil(yn))} {'years of data to be sure' if lang == 'en' else 'साल का डेटा चाहिए'}"
        return f"{name}: -"

    checks.append({"key": "timeline", "status": tst,
                   "en": "; ".join([toe_txt(A["name"], evA, "en"), toe_txt(B["name"], evB, "en")]) + ".",
                   "hi": "; ".join([toe_txt(A["name_hi"], evA, "hi"), toe_txt(B["name_hi"], evB, "hi")]) + "।"})
    # 5 motive
    if code == "shared_strong":
        mst = "pass"
        pa, pb = _pct(best['A']['explained']), _pct(best['B']['explained'])
        men = f"{best['title']}'s year-to-year swings predict {pa} and {pb} of the two opposite trends."
        mhi = f"{best['title_hi']} के साल-दर-साल उतार-चढ़ाव दोनों उल्टे रुझानों का {pa} और {pb} हिस्सा समझाते हैं।"
    elif local_alibi and is_mirror:
        la = local_alibi[0]
        mst = "warn"
        men = la["alibi_en"]
        mhi = la["alibi_hi"]
    elif code == "shared_weak":
        mst = "warn"
        men = f"{best['title']} explains one side well and points the right way on the other - probably the same cause, not proven."
        mhi = f"{best['title_hi']} एक तरफ़ को अच्छी तरह समझाता है और दूसरी तरफ़ सही दिशा दिखाता है - शायद एक ही वजह, पर साबित नहीं।"
    else:
        mst = "fail" if is_mirror else "na"
        men = "No tested suspect explains both sides - the cause is still at large." if is_mirror else "Motive not tested: the two sides are not yet a proven mirror."
        mhi = "जाँचा गया कोई भी संदिग्ध दोनों तरफ़ नहीं समझाता - असली वजह अभी फ़रार है।" if is_mirror else "मक़सद नहीं जाँचा गया: दोनों तरफ़ का उल्टा रुझान अभी साबित नहीं।"
    checks.append({"key": "motive", "status": mst, "en": men, "hi": mhi})
    for c in checks:
        c["title_en"], c["title_hi"] = CHECKS[c["key"]]["en"], CHECKS[c["key"]]["hi"]

    pts = {"pass": 20, "warn": 10, "na": 8, "fail": 0}
    strength = int(sum(pts[c["status"]] for c in checks))
    if not is_mirror:
        strength = min(strength, 40 if likely_mirror else 30)

    # ---------------- headline sentences
    var_en = case.get("short") or src.short or src.title
    var_hi = case.get("short_hi") or src.short_hi or src.title_hi or var_en
    gender = case.get("gender_hi") or src.gender_hi
    dA, hA = direction_words(evA["slope"], gender)
    dB, hB = direction_words(evB["slope"], gender)
    if sA * sB < 0:
        head_en = (f"{var_en} is {dA} in {A['name']} ({fmt(tA['slope_dec'])} {u['per_decade']}) "
                   f"but {dB} in {B['name']} ({fmt(tB['slope_dec'])} {u['per_decade']}).")
        head_hi = (f"{A['name_hi']} में {var_hi} {hA} ({fmt(tA['slope_dec'])} {u['per_decade_hi']}), "
                   f"जबकि {B['name_hi']} में {hB} ({fmt(tB['slope_dec'])} {u['per_decade_hi']})।")
    else:
        head_en = (f"{var_en} is {dA} in {A['name']} ({fmt(tA['slope_dec'])} {u['per_decade']}) "
                   f"and {dB} in {B['name']} too ({fmt(tB['slope_dec'])} {u['per_decade']}).")
        head_hi = (f"{A['name_hi']} में {var_hi} {hA} ({fmt(tA['slope_dec'])} {u['per_decade_hi']}), "
                   f"और {B['name_hi']} में भी {hB} ({fmt(tB['slope_dec'])} {u['per_decade_hi']})।")
    if code == "not_mirror":
        arte = [x for x, ev in ((A, evA), (B, evB)) if ev["verdict"] == "artifact"]
        weak = [x for x, ev in ((A, evA), (B, evB)) if ev["p"] >= alpha and ev["verdict"] != "artifact"]
        if arte:
            detail_en = f"{arte[0]['name']}'s trend looks like an instrument artifact, so this is not a real mirror."
            detail_hi = f"{arte[0]['name_hi']} का रुझान उपकरण का दोष लगता है, इसलिए यह असली उल्टा रुझान नहीं।"
        elif sA * sB >= 0:
            detail_en = "Both sides move the same way - no mirror here."
            detail_hi = "दोनों तरफ़ एक ही दिशा में - यहाँ उल्टा रुझान नहीं।"
        else:
            detail_en = f"Not proven yet in {', '.join(x['name'] for x in weak) or 'one side'} - more years of data are needed."
            detail_hi = f"{', '.join(x['name_hi'] for x in weak) or 'एक तरफ़'} में अभी साबित नहीं - और सालों का डेटा चाहिए।"
    else:
        detail_en, detail_hi = men, mhi

    out = {
        "id": case["id"], "type": case["type"],
        "title": case["title"], "title_hi": case.get("title_hi", case["title"]),
        "tagline": case.get("tagline", ""), "tagline_hi": case.get("tagline_hi", case.get("tagline", "")),
        "question": case.get("question", ""), "question_hi": case.get("question_hi", case.get("question", "")),
        "spotlight": case.get("spotlight", "global"),
        "source": {"id": src.id, "title": src.title, "title_hi": src.title_hi or src.title, "short": var_en, "short_hi": var_hi,
                   "units": src.units, "per_decade": u["per_decade"], "per_decade_hi": u["per_decade_hi"],
                   "mission": src.mission, "citation": src.citation, "url_info": src.url_info},
        "season": case.get("season", "ANN"),
        "season_label": list(agg.SEASON_LABELS.get(case.get("season", "ANN"), ("", ""))),
        "period": [int(np.nanmin(years)), int(np.nanmax(years))],
        "regions": [
            {**{k: v for k, v in A.items() if k != "mask"}, "key": "A", "sign": int(sA),
             "series": {"years": years, "values": sa}, "trend": tA},
            {**{k: v for k, v in B.items() if k != "mask"}, "key": "B", "sign": int(sB),
             "series": {"years": years, "values": sb}, "trend": tB},
        ],
        "drivers": [{k: v for k, v in t.items() if k not in ("score",)} for t in tests],
        "best_driver": best["id"] if best else None,
        "verdict": {"code": code, "en": CASE[code]["en"], "hi": CASE[code]["hi"],
                    "headline_en": head_en, "headline_hi": head_hi, "detail_en": detail_en, "detail_hi": detail_hi},
        "checks": checks,
        "strength": strength,
        "is_mirror": is_mirror,
    }
    out.update(extra)
    return out


# ----------------------------------------------------------------------------- case types
def _local_tests(case: dict, ctx: Context, f: dict, A: dict, B: dict, years, sa, sb) -> list:
    out = []
    for spec in case.get("local_drivers", []) or []:
        if isinstance(spec, str):
            spec = {"source": spec}
        try:
            cf = ctx.field(spec["source"], spec.get("season", case.get("season", "ANN")))
        except Exception as e:
            log.warning("  local driver %s unavailable: %s", spec.get("source"), e)
            continue
        csrc = ctx.source(spec["source"])
        label = spec.get("label") or csrc.short or csrc.title
        label_hi = spec.get("label_hi") or csrc.short_hi or label
        res = {"id": csrc.id, "title": label, "title_hi": label_hi, "units": csrc.units, "kind": "local"}
        per = {}
        for key, R, s in (("A", A, sa), ("B", B, sb)):
            m2 = remap_mask(R["mask"], f, cf)
            cs = agg.region_mean(cf["anom"], cf["lat"], m2)
            common, ia, ic = np.intersect1d(years, cf["years"], return_indices=True)
            fp = stats.fingerprint(s[ia], cs[ic], common) if common.size >= 10 else {"p": np.nan}
            ev = series_evidence(cf["years"], cs, ctx.cfg, csrc.known_transitions)
            fp["own_trend"] = {"slope_dec": ev["slope"] * 10 if math.isfinite(ev["slope"]) else None, "p": ev["p"], "verdict": ev["verdict"]}
            fp["series"] = {"years": cf["years"], "values": cs}
            per[key] = fp
        res["A"], res["B"] = per["A"], per["B"]
        # "alibi": the local suspect cannot explain region A (or B)
        for key, R in (("A", A), ("B", B)):
            fp = per[key]
            weak = not (fp.get("p") is not None and math.isfinite(fp.get("p", np.nan)) and fp["p"] < ctx.cfg.mirror["driver_p"]
                        and (fp.get("explained") or 0) >= ctx.cfg.mirror["explained_min"])
            if weak:
                own = fp["own_trend"]
                src_main = ctx.source(case["source"])
                var_en = (case.get("short") or src_main.short or "the trend").lower()
                var_hi = case.get("short_hi") or src_main.short_hi or src_main.short
                flat = own["verdict"] in ("not_proven", "insufficient")
                trend_en = "shows no clear trend" if flat else f"does not move in step with {var_en}"
                trend_hi = f"का कोई साफ़ रुझान नहीं है" if flat else f"का रुझान {var_hi} से मेल नहीं खाता"
                res["alibi"] = True
                res["alibi_region"] = key
                res["alibi_en"] = (f"{label} over {R['name']} {trend_en}, so {label.lower()} has an alibi - "
                                   f"{case.get('suspect_en', 'another culprit (for example human water use) must be at work')}.")
                res["alibi_hi"] = (f"{R['name_hi']} में {label_hi} {trend_hi}, इसलिए {label_hi} बेगुनाह है - "
                                   f"{case.get('suspect_hi', 'कोई और वजह (जैसे इंसानों का पानी इस्तेमाल) ज़िम्मेदार है')}।")
                break
        out.append(res)
    return out


def _witnesses(case: dict, ctx: Context, f: dict, A: dict, B: dict, signs) -> list:
    out = []
    for spec in case.get("witnesses", []) or []:
        if isinstance(spec, str):
            spec = {"source": spec}
        try:
            wf = ctx.field(spec["source"], spec.get("season", case.get("season", "ANN")))
        except Exception as e:
            log.warning("  witness %s unavailable: %s", spec.get("source"), e)
            continue
        wsrc = ctx.source(spec["source"])
        agrees = True
        per = {}
        for key, R, sgn in (("A", A, signs[0]), ("B", B, signs[1])):
            m2 = remap_mask(R["mask"], f, wf)
            ws = agg.region_mean(wf["anom"], wf["lat"], m2)
            ev = series_evidence(wf["years"], ws, ctx.cfg)
            ok = bool(np.sign(ev["slope"]) == sgn and ev["p"] < 0.10)
            agrees &= ok
            per[key] = {"slope_dec": ev["slope"] * 10, "p": ev["p"], "agrees": ok}
        out.append({"id": wsrc.id, "title": wsrc.short or wsrc.title, "title_hi": wsrc.short_hi or wsrc.title_hi or wsrc.title,
                    "agrees": agrees, **per})
    return out


def case_regions(case: dict, ctx: Context) -> dict:
    src = ctx.source(case["source"])
    f = ctx.field(src.id, case.get("season", "ANN"), case.get("period"))
    spec_a = case.get("region_a") or {"auto": "positive"}
    spec_b = case.get("region_b") or {"auto": "negative"}
    A = resolve_region(spec_a, f, ctx.cfg)
    B = resolve_region(spec_b, f, ctx.cfg)
    if (A["mask"] & B["mask"]).any():
        B["mask"] = B["mask"] & ~A["mask"]
    sa = agg.region_mean(f["anom"], f["lat"], A["mask"])
    sb = agg.region_mean(f["anom"], f["lat"], B["mask"])
    base_a = float(np.nanmean(np.where(A["mask"], f["base"], np.nan)))
    base_b = float(np.nanmean(np.where(B["mask"], f["base"], np.nan)))
    years = f["years"]
    local = _local_tests(case, ctx, f, A, B, years, sa, sb)
    sA = np.sign(stats.ols_slope(sa, years))
    sB = np.sign(stats.ols_slope(sb, years))
    wit = _witnesses(case, ctx, f, A, B, (sA, sB))
    extra = {"layer": {"source": src.id, "season": case.get("season", "ANN")},
             "map_bounds": _union_bbox(A["bbox"], B["bbox"])}
    return _assemble(case, ctx, src, A, B, years, sa, sb, base_a, base_b, local, wit, extra)


def case_series(case: dict, ctx: Context) -> dict:
    a, b = case["series_a"], case["series_b"]
    da = ctx.series(a, season=a.get("season", case.get("season", "ANN")))
    db = ctx.series(b, season=b.get("season", case.get("season", "ANN")))
    common, ia, ib = np.intersect1d(da["years"], db["years"], return_indices=True)
    src = ctx.source(a["source"])
    A = {"name": a.get("name", src.short), "name_hi": a.get("name_hi", src.short_hi or src.short), "how": "series",
         "bbox": a.get("bbox"), "cells": [], "res": None}
    srcb = ctx.source(b["source"])
    B = {"name": b.get("name", srcb.short), "name_hi": b.get("name_hi", srcb.short_hi or srcb.short), "how": "series",
         "bbox": b.get("bbox"), "cells": [], "res": None}
    case = dict(case, season=a.get("season", case.get("season", "ANN")))
    extra = {"map_bounds": _union_bbox(A["bbox"], B["bbox"]) if A["bbox"] and B["bbox"] else None,
             "seasons_ab": [a.get("season", "ANN"), b.get("season", "ANN")]}
    return _assemble(case, ctx, src, A, B, common, da["anom"][ia], db["anom"][ib], da["base"], db["base"], [], [], extra)


def case_levels(case: dict, ctx: Context) -> dict:
    src = ctx.source(case["source"])
    a, b = case["band_a"], case["band_b"]
    season = case.get("season", "ANN")
    sa = ctx.level_series(src.id, a["levels"], season, case.get("period"))
    sb = ctx.level_series(src.id, b["levels"], season, case.get("period"))
    common, ia, ib = np.intersect1d(sa["years"], sb["years"], return_indices=True)
    A = {"name": a["name"], "name_hi": a.get("name_hi", a["name"]), "how": "levels", "levels": a["levels"], "cells": [], "res": None, "bbox": None}
    B = {"name": b["name"], "name_hi": b.get("name_hi", b["name"]), "how": "levels", "levels": b["levels"], "cells": [], "res": None, "bbox": None}
    return _assemble(case, ctx, src, A, B, common, sa["anom"][ia], sb["anom"][ib], sa["base"], sb["base"], [], [], {"map_bounds": None})


def _union_bbox(a, b):
    if not a or not b:
        return a or b
    return [min(a[0], b[0]), min(a[1], b[1]), max(a[2], b[2]), max(a[3], b[3])]


def run_case(case: dict, ctx: Context) -> dict:
    t = case["type"]
    if t in ("mirror_regions", "auto_mirror"):
        return case_regions(case, ctx)
    if t == "mirror_series":
        return case_series(case, ctx)
    if t == "mirror_levels":
        return case_levels(case, ctx)
    raise DetectiveError(f"unknown case type {t!r}")
