"""Writes everything the app needs into output_dir (app/web/data by default).

Layout:
  catalog.json                      - index of everything below (the app's entry point)
  index/datasets|cases|status/*.json - one small file per dataset/case/status; catalog.json is
                                      assembled from these, so several tabs can run at once
  layers/<source>/<season>/meta.json, trend.png, sig.png, cells.json, series/<bi>_<bj>.json
  series/<source>.json              - index datasets (drivers, sea ice, ...)
  cases/<case>.json                 - mirror-case evidence files
  places/<slug>.json                - precomputed "My Place" reports (NASA POWER)
  selftest.json, sources.json, report.json
"""
from __future__ import annotations

import math
import shutil
from pathlib import Path

import numpy as np

from . import __version__
from . import aggregate as agg
from . import render
from .engine import Context, series_evidence
from .mirror import run_case
from .registry import Source
from .util import ensure_dir, file_lock, log, now_iso, read_json, write_json
from .verdict import TREND


def _per_decade_field(tr: dict, src: Source) -> tuple[np.ndarray, np.ndarray, np.ndarray, str, str]:
    if src.trend_units == "percent" and "slope_pct" in tr:
        return tr["slope_pct"] * 10, tr["ci_lo_pct"] * 10, tr["ci_hi_pct"] * 10, "% per decade", "% प्रति दशक"
    u = src.units or ""
    return tr["slope"] * 10, tr["ci_lo"] * 10, tr["ci_hi"] * 10, f"{u}/decade", f"{u}/दशक"


def publish_layer(ctx: Context, src: Source, season: str) -> dict:
    cfg = ctx.cfg
    f = ctx.field(src.id, season)
    tr = f["trend"]
    out = ensure_dir(cfg.output_dir / "layers" / src.id / season)
    s_dec, lo_dec, hi_dec, per, per_hi = _per_decade_field(tr, src)
    sig = np.isfinite(tr["q"]) & (tr["q"] < cfg.analysis["fdr_alpha"])
    vmax = render.robust_vmax(s_dec)
    scale = int(cfg.raw["publish"]["png_scale"])
    render.trend_png(s_dec, sig, vmax, src.palette, scale, out / "trend.png")
    render.stipple_png(sig, scale, out / "sig.png")

    lat, lon = f["lat"], f["lon"]
    nlat, nlon = lat.size, lon.size
    emerged = np.isfinite(tr["toe1"]) & (tr["toe1"] <= tr["t1"]) & (tr["p"] < 0.10)
    toe = np.where(emerged, tr["toe1"], np.nan)
    valid = np.isfinite(tr["p"]).ravel()
    idx = np.nonzero(valid)[0]

    def take(a):
        return np.asarray(a).ravel()[idx]

    cells = {  # sparse: only cells with a test result; idx = row-major index (lat ascending)
        "nlat": nlat, "nlon": nlon, "sparse": True, "idx": idx.astype(int),
        "fields": ["s", "lo", "hi", "p", "q", "snr", "toe", "yn", "v", "b"],
        "s": take(s_dec), "lo": take(lo_dec), "hi": take(hi_dec),
        "p": take(tr["p"]), "q": take(tr["q"]), "snr": take(tr["snr"]),
        "toe": np.round(take(toe)), "yn": np.ceil(take(np.where(np.isfinite(tr["years_needed"]), tr["years_needed"], np.nan))),
        "v": take(tr["verdict"].astype(int)), "b": take(f["base"]),
    }
    write_json(out / "cells.json", cells, sig=3)

    B = int(cfg.raw["publish"]["series_block"])
    sdir = out / "series"
    if sdir.exists():
        shutil.rmtree(sdir)
    ensure_dir(sdir)
    years = f["years"]
    for bi in range(math.ceil(nlat / B)):
        for bj in range(math.ceil(nlon / B)):
            i0, j0 = bi * B, bj * B
            block = f["anom"][:, i0:i0 + B, j0:j0 + B]
            ni, nj = block.shape[1], block.shape[2]
            vals = []
            any_data = False
            for i in range(ni):
                for j in range(nj):
                    col = block[:, i, j]
                    if np.isfinite(col).any():
                        vals.append(col)
                        any_data = True
                    else:
                        vals.append(None)
            if any_data:
                write_json(sdir / f"{bi}_{bj}.json", {"years": years, "i0": i0, "j0": j0, "ni": ni, "nj": nj, "v": vals}, sig=3)

    meta = {
        "source": src.id, "season": season, "season_label": list(agg.SEASON_LABELS.get(season, (season, season))),
        "period": list(f["period"]),
        "grid": {"lat0": float(lat[0]), "dlat": f["dlat"], "nlat": nlat, "lon0": float(lon[0]), "dlon": f["dlon"], "nlon": nlon},
        "bounds": [float(lon[0] - f["dlon"] / 2), float(lat[0] - f["dlat"] / 2), float(lon[-1] + f["dlon"] / 2), float(lat[-1] + f["dlat"] / 2)],
        "units_per": per, "units_per_hi": per_hi, "units": src.units, "vmax": vmax,
        "palette": render.palette(src.palette), "png": "trend.png", "stipple": "sig.png", "cells": "cells.json",
        "series_block": B, "field": tr["field"],
        "method": {"test": "Mann-Kendall", "autocorrelation": cfg.analysis["grid_method"], "slope": "Sen",
                   "multiple_testing": "Benjamini-Hochberg FDR", "fdr_alpha": cfg.analysis["fdr_alpha"],
                   "baseline": cfg.analysis["baseline"]},
        "generated_at": now_iso(),
    }
    write_json(out / "meta.json", meta)
    fs = tr["field"]
    log.info("  layer %s/%s: %d cells, %.0f%% of area significant (%.0f%% up, %.0f%% down)", src.id, season, fs["n_cells"],
             100 * fs["sig_area_frac"], 100 * fs["sig_up_frac"], 100 * fs["sig_down_frac"])
    return {"season": season, "path": f"layers/{src.id}/{season}", "period": list(f["period"]), "field": fs, "vmax": vmax, "units_per": per}


def publish_series(ctx: Context, src: Source) -> dict:
    out = {"id": src.id, "title": src.title, "title_hi": src.title_hi or src.title, "units": src.units, "seasons": {}}
    seasons = src.seasons or ["ANN"]
    for season in seasons:
        try:
            s = ctx.series(src.id, season=season)
        except Exception as e:
            log.warning("  series %s/%s: %s", src.id, season, e)
            continue
        ev = series_evidence(s["years"], s["anom"], ctx.cfg, src.known_transitions)
        scale = 10.0
        per = f"{src.units}/decade"
        if src.trend_units == "percent" and s["base"]:
            scale = 10.0 / abs(s["base"]) * 100
            per = "% per decade"
        out["seasons"][season] = {
            "years": s["years"], "anom": s["anom"], "values": s["values"], "base": s["base"], "period": list(s["period"]),
            "trend": {"slope_dec": ev["slope"] * scale, "ci_lo_dec": ev["ci_lo"] * scale, "ci_hi_dec": ev["ci_hi"] * scale,
                      "p": ev["p"], "snr": ev["snr"], "toe1": ev["toe1"] if math.isfinite(ev["toe1"]) else None,
                      "emerged": ev["emerged"], "years_needed": ev["years_needed"] if math.isfinite(ev["years_needed"]) else None,
                      "verdict": ev["verdict"], "verdict_en": TREND[ev["verdict"]]["en"], "verdict_hi": TREND[ev["verdict"]]["hi"],
                      "pettitt": ev.get("pettitt"), "alibi": ev.get("alibi"), "per": per},
        }
    write_json(ctx.cfg.output_dir / "series" / f"{src.id}.json", out)
    return {"path": f"series/{src.id}.json", "seasons": list(out["seasons"])}


def publish_case(ctx: Context, case: dict) -> dict:
    res = run_case(case, ctx)
    write_json(ctx.cfg.output_dir / "cases" / f"{case['id']}.json", res)
    log.info("  case %-28s %-28s strength %d", case["id"], res["verdict"]["en"], res["strength"])
    return {
        "id": res["id"], "title": res["title"], "title_hi": res["title_hi"], "tagline": res["tagline"], "tagline_hi": res["tagline_hi"],
        "type": res["type"], "spotlight": res["spotlight"], "strength": res["strength"], "verdict": res["verdict"],
        "source": res["source"]["id"], "regions": [{"name": r["name"], "name_hi": r["name_hi"], "sign": r["sign"],
                                                    "slope_dec": r["trend"]["slope_dec"], "spark": r["series"]["values"]} for r in res["regions"]],
        "per_decade": res["source"]["per_decade"], "per_decade_hi": res["source"]["per_decade_hi"],
        "period": res["period"], "file": f"cases/{case['id']}.json", "is_mirror": res["is_mirror"],
    }


def dataset_entry(src: Source, layers: list, series: dict | None) -> dict:
    return {
        "id": src.id, "title": src.title, "title_hi": src.title_hi or src.title, "short": src.short, "short_hi": src.short_hi or src.short,
        "sphere": src.sphere, "mission": src.mission, "kind": src.kind, "role": src.role, "units": src.units,
        "trend_units": src.trend_units, "palette": src.palette, "good_direction": src.good_direction,
        "citation": src.citation, "url_info": src.url_info, "notes": src.notes, "login": src.needs_login,
        "explain": src.explain, "explain_hi": src.explain_hi or src.explain, "quality_note": src.quality_note,
        "known_transitions": src.known_transitions, "layers": layers, "series": series,
    }


# ----------------------------------------------------------------------------- index (parallel-safe catalog)
INDEX = "index"


def _index_dir(ctx: Context, kind: str) -> Path:
    return ctx.cfg.output_dir / INDEX / kind


def save_index(ctx: Context, kind: str, item_id: str, entry: dict) -> None:
    """kind = datasets | cases. One file per item: tabs never overwrite each other's work."""
    write_json(_index_dir(ctx, kind) / f"{item_id}.json", dict(entry) | {"_demo": bool(ctx.demo), "_saved": now_iso()})


def save_status(ctx: Context, kind: str, item_id: str, status: dict) -> None:
    write_json(_index_dir(ctx, "status") / f"{kind}__{item_id}.json",
               dict(status) | {"kind": kind, "id": item_id, "_demo": bool(ctx.demo), "at": now_iso()})


def _read_dir(d: Path) -> list[dict]:
    out = []
    if d.exists():
        for f in sorted(d.glob("*.json")):
            if f.name.startswith("."):
                continue
            try:
                out.append(read_json(f))
            except Exception:  # half-copied by hand etc. - skip, never crash the catalog
                continue
    return out


def migrate_index(ctx: Context) -> None:
    """First run after the v1.1 update: seed index/ from the old catalog.json + report.json."""
    if (ctx.cfg.output_dir / INDEX).exists():
        return
    cat_path = ctx.cfg.output_dir / "catalog.json"
    if not cat_path.exists():
        return
    try:
        cat = read_json(cat_path)
    except Exception:
        return
    demo = bool((cat.get("app") or {}).get("demo"))
    for d in cat.get("datasets", []):
        write_json(_index_dir(ctx, "datasets") / f"{d['id']}.json", dict(d) | {"_demo": demo, "_saved": now_iso()})
    for c in cat.get("cases", []):
        write_json(_index_dir(ctx, "cases") / f"{c['id']}.json", dict(c) | {"_demo": demo, "_saved": now_iso()})
    try:
        rep = read_json(ctx.cfg.output_dir / "report.json")
        for kind, key in (("dataset", "datasets"), ("case", "cases")):
            for k, v in (rep.get(key) or {}).items():
                write_json(_index_dir(ctx, "status") / f"{kind}__{k}.json", dict(v) | {"kind": kind, "id": k, "_demo": demo, "at": rep.get("finished")})
    except Exception:
        pass
    log.info("index/ created from the existing catalog.json (%d datasets, %d cases)", len(cat.get("datasets", [])), len(cat.get("cases", [])))


def _strip(d: dict) -> dict:
    return {k: v for k, v in d.items() if not k.startswith("_")}


def current_items(ctx: Context, case_ids: set[str] | None) -> tuple[list, list, list, list]:
    """What the catalog shows now: last good result of every enabled dataset / case of this mode (real or demo)."""
    order = {sid: i for i, sid in enumerate(ctx.sources)}
    ds = [d for d in _read_dir(_index_dir(ctx, "datasets")) if d.get("id") in order and bool(d.get("_demo")) == bool(ctx.demo)]
    ds.sort(key=lambda d: order[d["id"]])
    cs = [c for c in _read_dir(_index_dir(ctx, "cases"))
          if bool(c.get("_demo")) == bool(ctx.demo) and (case_ids is None or c.get("id") in case_ids)]
    st = [x for x in _read_dir(_index_dir(ctx, "status")) if bool(x.get("_demo")) == bool(ctx.demo)
          and ((x.get("kind") == "dataset" and x.get("id") in order) or (x.get("kind") == "case" and (case_ids is None or x.get("id") in case_ids)))]
    return [_strip(d) for d in ds], [_strip(c) for c in cs], load_existing_places(ctx), st


def assemble(ctx: Context, case_ids: set[str] | None) -> dict:
    """(Re)build catalog.json, sources.json and report.json from index/ - under a lock, atomically."""
    out = ctx.cfg.output_dir
    ensure_dir(out)
    with file_lock(out / ".catalog.lock", "catalog.json", timeout=300):
        migrate_index(ctx)
        datasets, cases, places, statuses = current_items(ctx, case_ids)
        report = {"generated_at": now_iso(), "demo": bool(ctx.demo), "datasets": {}, "cases": {}}
        for x in sorted(statuses, key=lambda x: (x.get("kind", ""), x.get("id", ""))):
            key = "datasets" if x["kind"] == "dataset" else "cases"
            report[key][x["id"]] = {k: v for k, v in x.items() if k not in ("kind", "id", "_demo")}
        write_sources(ctx, datasets)
        catalog = write_catalog(ctx, datasets, cases, places, report)
    return catalog


def write_catalog(ctx: Context, datasets: list, cases: list, places: list, report: dict) -> dict:
    cfg = ctx.cfg
    out = cfg.output_dir
    cases = sorted(cases, key=lambda c: (-c["strength"], c["id"]))
    catalog = {
        "schema": 1,
        "app": {"name": "Kuch Toh Gadbad Hai", "tagline": "Something's fishy with Earth - NASA data, real statistics",
                "generated_at": now_iso(), "pipeline_version": __version__, "demo": bool(ctx.demo)},
        "ai": {"models": cfg.raw["app"]["ai_models"]},
        "analysis": {k: cfg.analysis[k] for k in ("baseline", "alpha", "fdr_alpha", "grid_method", "series_method", "min_years", "snr_confirm")},
        "seasons": {k: list(v) for k, v in agg.SEASON_LABELS.items()},
        "verdicts": {k: {"code": v["code"], "en": v["en"], "hi": v["hi"]} for k, v in TREND.items()},
        "datasets": datasets,
        "cases": cases,
        "places": places,
        "selftest": "selftest.json" if (out / "selftest.json").exists() else None,
        "sources": "sources.json",
        "report": "report.json",
    }
    write_json(out / "catalog.json", catalog)
    write_json(out / "report.json", report)
    return catalog


def write_sources(ctx: Context, datasets: list) -> None:
    items = []
    for d in datasets:
        items.append({k: d.get(k, "") for k in ("id", "title", "mission", "citation", "url_info", "login", "explain", "quality_note")})
    software = [
        {"name": "xarray", "license": "Apache-2.0", "url": "https://xarray.dev"},
        {"name": "NumPy / SciPy / pandas", "license": "BSD-3-Clause", "url": "https://scipy.org"},
        {"name": "earthaccess (NASA Openscapes)", "license": "MIT", "url": "https://github.com/nsidc/earthaccess"},
        {"name": "Natural Earth (land outlines)", "license": "Public domain", "url": "https://www.naturalearthdata.com"},
        {"name": "Flutter", "license": "BSD-3-Clause", "url": "https://flutter.dev"},
        {"name": "Firebase (Hosting, Firestore, AI Logic / Gemini)", "license": "Google terms", "url": "https://firebase.google.com"},
    ]
    write_json(ctx.cfg.output_dir / "sources.json", {"datasets": items, "software": software, "generated_at": now_iso()})


def load_existing_places(ctx: Context) -> list:
    pdir = ctx.cfg.output_dir / "places"
    out = []
    if pdir.exists():
        for p in sorted(pdir.glob("*.json")):
            if p.name.startswith("."):
                continue
            try:
                d = read_json(p)
                is_demo = bool(d.get("demo")) or str(d.get("name", "")).startswith("[DEMO]")
                if is_demo != bool(ctx.demo):
                    continue
                out.append({k: d.get(k) for k in ("slug", "name", "name_hi", "country", "lat", "lon")} | {"file": f"places/{p.name}"})
            except Exception:
                continue
    return out

