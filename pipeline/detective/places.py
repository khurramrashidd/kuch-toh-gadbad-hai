"""'My Place, 40 years' reports from the NASA POWER API (no login needed).

The app computes the same thing live on the phone; these precomputed files make
showcase cities instant and work even when the venue Wi-Fi is bad.
"""
from __future__ import annotations

import datetime as _dt
import math
import time

import numpy as np
import requests

from . import aggregate as agg
from .engine import Context, series_evidence
from .util import DetectiveError, log, now_iso, slugify, write_json
from .verdict import TREND

POWER_MONTHLY = "https://power.larc.nasa.gov/api/temporal/monthly/point"
POWER_DAILY = "https://power.larc.nasa.gov/api/temporal/daily/point"
UA = {"User-Agent": "KuchTohGadbadHai/1.0 (NASA Space Apps 2026)"}

VARIABLES = [
    {"key": "temp", "param": "T2M", "season": "ANN", "how": "mean", "units": "°C", "scale": 1.0,
     "title": "Average temperature", "title_hi": "औसत तापमान"},
    {"key": "rain", "param": "PRECTOTCORR", "season": "ANN", "how": "total", "units": "mm", "scale": 1.0,
     "title": "Rainfall in a year", "title_hi": "साल भर की बारिश"},
    {"key": "monsoon", "param": "PRECTOTCORR", "season": "JJAS", "how": "total", "units": "mm", "scale": 1.0,
     "title": "Monsoon rainfall (Jun-Sep)", "title_hi": "मानसून की बारिश (जून-सितंबर)"},
    {"key": "soil", "param": "GWETROOT", "season": "ANN", "how": "mean", "units": "%", "scale": 100.0,
     "title": "Soil wetness (root zone)", "title_hi": "मिट्टी की नमी (जड़ तक)"},
    {"key": "humid", "param": "RH2M", "season": "ANN", "how": "mean", "units": "%", "scale": 1.0,
     "title": "Humidity", "title_hi": "नमी (हवा में)"},
]
MONTH_DAYS = np.array([31, 28.25, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31])


def _get(url: str, params: dict, retries: int = 3) -> dict:
    last = None
    for i in range(retries):
        try:
            r = requests.get(url, params=params, headers=UA, timeout=(20, 180))
            if r.status_code == 429:
                time.sleep(10 * (i + 1))
                continue
            r.raise_for_status()
            return r.json()
        except Exception as e:
            last = e
            time.sleep(3 * (i + 1))
    raise DetectiveError(f"NASA POWER request failed: {last}")


def last_full_year() -> int:
    return _dt.date.today().year - 1


def fetch_power(lat: float, lon: float, start: int = 1981, end: int | None = None) -> tuple[dict, dict]:
    end = end or last_full_year()
    monthly = _get(POWER_MONTHLY, {
        "parameters": ",".join(sorted({v["param"] for v in VARIABLES})), "community": "AG",
        "longitude": f"{lon:.4f}", "latitude": f"{lat:.4f}", "start": start, "end": end, "format": "JSON"})
    daily = _get(POWER_DAILY, {
        "parameters": "T2M_MAX", "community": "AG", "longitude": f"{lon:.4f}", "latitude": f"{lat:.4f}",
        "start": f"{start}0101", "end": f"{end}1231", "format": "JSON"})
    return monthly, daily


def _monthly_array(obj: dict, param: str):
    fill = float(obj.get("header", {}).get("fill_value", -999.0))
    data = obj["properties"]["parameter"][param]
    years = sorted({int(k[:4]) for k in data})
    arr = np.full((len(years), 12), np.nan)
    for k, v in data.items():
        m = int(k[4:])
        if m > 12 or v is None:
            continue
        val = float(v)
        if val == fill or val <= -998:
            continue
        arr[years.index(int(k[:4])), m - 1] = val
    return np.array(years), arr


def analyse_power(monthly: dict, daily: dict, cfg) -> list[dict]:
    out = []
    a = cfg.analysis
    for v in VARIABLES:
        try:
            years, arr = _monthly_array(monthly, v["param"])
        except KeyError:
            continue
        months = agg.SEASONS[v["season"]]
        idx = [m - 1 for m in months]
        block = arr[:, idx]
        ok = np.isfinite(block).sum(axis=1) == len(idx)
        if v["how"] == "total":
            vals = np.nansum(block * MONTH_DAYS[idx][None, :], axis=1)
        else:
            vals = np.nanmean(block, axis=1)
        vals = np.where(ok, vals * v["scale"], np.nan)
        out.append(_variable_report(v, years, vals, a, cfg))
    # very hot days: days above this place's own 1981-2010 90th percentile of daily max temperature
    try:
        fill = float(daily.get("header", {}).get("fill_value", -999.0))
        d = daily["properties"]["parameter"]["T2M_MAX"]
        keys = sorted(d)
        yrs = np.array([int(k[:4]) for k in keys])
        tx = np.array([np.nan if (d[k] is None or float(d[k]) == fill) else float(d[k]) for k in keys])
        ref = tx[(yrs >= 1981) & (yrs <= 2010)]
        thr = float(np.nanpercentile(ref, 90)) if np.isfinite(ref).sum() > 3000 else float(np.nanpercentile(tx, 90))
        uy = np.unique(yrs)
        counts = np.array([np.nansum(tx[yrs == y] > thr) if np.isfinite(tx[yrs == y]).sum() >= 330 else np.nan for y in uy])
        v = {"key": "hotdays", "units": "days", "title": f"Very hot days (above {thr:.1f} °C)",
             "title_hi": f"बहुत गर्म दिन ({thr:.1f} °C से ऊपर)", "threshold": thr}
        out.insert(1, _variable_report(v, uy, counts, a, cfg))
    except Exception as e:
        log.debug("hot days unavailable: %s", e)
    return out


def _variable_report(v: dict, years, vals, a: dict, cfg) -> dict:
    years = np.asarray(years)
    base = float(agg.baseline_mean(years, vals, tuple(a["baseline"])))
    ev = series_evidence(years, vals - base, cfg)
    early = vals[:10][np.isfinite(vals[:10])]
    late = vals[-10:][np.isfinite(vals[-10:])]
    return {
        "key": v["key"], "title": v["title"], "title_hi": v["title_hi"], "units": v["units"],
        "years": years, "values": vals, "base": base,
        "trend": {"slope_dec": ev["slope"] * 10, "ci_lo_dec": ev["ci_lo"] * 10, "ci_hi_dec": ev["ci_hi"] * 10,
                  "p": ev["p"], "snr": ev["snr"], "toe1": ev["toe1"] if math.isfinite(ev["toe1"]) else None,
                  "emerged": ev["emerged"], "years_needed": ev["years_needed"] if math.isfinite(ev["years_needed"]) else None,
                  "verdict": ev["verdict"], "verdict_en": TREND[ev["verdict"]]["en"], "verdict_hi": TREND[ev["verdict"]]["hi"],
                  "pettitt": ev.get("pettitt")},
        "then_now": {"early": [int(years[0]), int(years[min(9, len(years) - 1)]), float(early.mean()) if early.size else None],
                     "late": [int(years[max(0, len(years) - 10)]), int(years[-1]), float(late.mean()) if late.size else None]},
        **({"threshold": v["threshold"]} if "threshold" in v else {}),
    }


def build_places(ctx: Context, places: list[dict], only: list[str] | None = None) -> list[dict]:
    out = []
    for p in places:
        slug = p.get("slug") or slugify(p["name"])
        if only and slug not in only:
            continue
        try:
            log.info("  place %s", p["name"])
            monthly, daily = fetch_power(float(p["lat"]), float(p["lon"]))
            variables = analyse_power(monthly, daily, ctx.cfg)
            doc = {"slug": slug, "name": p["name"], "name_hi": p.get("name_hi", p["name"]), "country": p.get("country", ""),
                   "lat": p["lat"], "lon": p["lon"], "source": "NASA POWER (MERRA-2 meteorology, GPM IMERG/MERRA-2 precipitation)",
                   "fetched_at": now_iso(), "variables": variables}
            write_json(ctx.cfg.output_dir / "places" / f"{slug}.json", doc)
            out.append({"slug": slug, "name": p["name"], "name_hi": doc["name_hi"], "country": doc["country"],
                        "lat": p["lat"], "lon": p["lon"], "file": f"places/{slug}.json"})
            time.sleep(1.0)
        except Exception as e:
            log.warning("  place %s failed: %s", p["name"], e)
    return out
