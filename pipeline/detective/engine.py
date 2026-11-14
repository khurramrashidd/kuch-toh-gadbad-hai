"""Glue between sources, cubes and statistics.

`Context` lazily builds (and caches on disk) each source's canonical monthly
cube, and serves seasonal fields, region series and driver series to the
publishing and mirror-case code.
"""
from __future__ import annotations

import math
import time
from pathlib import Path

import numpy as np
import xarray as xr

from . import access, aggregate as agg, canonical, readers, stats
from .registry import Config, Source
from .util import LOCK_SUFFIX, DetectiveError, ensure_dir, file_lock, log, replace_file, tmp_path
from .verdict import TREND, trend_verdict


def refresh_now(path: Path, refresh: bool, started: float) -> bool:
    """--refresh rebuilds a cube, unless another tab rebuilt it while we were waiting for the lock."""
    if not refresh:
        return False
    try:
        return path.stat().st_mtime < started
    except FileNotFoundError:
        return True


class Context:
    def __init__(self, cfg: Config, sources: dict[str, Source], demo: bool = False):
        self.cfg = cfg
        self.sources = sources
        self.demo = demo
        self.errors: dict[str, str] = {}
        self._cubes: dict[str, xr.DataArray] = {}
        self._fields: dict[tuple, dict] = {}
        self._started = time.time()

    # ------------------------------------------------------------------ cubes
    def source(self, sid: str) -> Source:
        if sid not in self.sources:
            raise DetectiveError(f"unknown source {sid!r} (is its YAML enabled?)")
        return self.sources[sid]

    def cube(self, sid: str, refresh: bool = False) -> xr.DataArray:
        if sid in self._cubes and not refresh:
            return self._cubes[sid]
        if sid in self.errors and not refresh:
            raise DetectiveError(self.errors[sid])
        src = self.source(sid)
        path = self.cfg.path_cube(sid)
        try:
            if path.exists() and not refresh:
                da = self._load_cube(path)
            else:
                # one tab at a time per dataset (two tabs never download the same files at once)
                with file_lock(self.cfg.cache_dir / f"{sid}{LOCK_SUFFIX}", f"dataset {sid}"):
                    if path.exists() and not refresh_now(path, refresh, self._started):
                        da = self._load_cube(path)  # another tab just built it
                    else:
                        log.info("[%s] fetching + reading", sid)
                        files = access.iter_files(access.fetch(src, self.cfg))
                        ds = readers.open_raw(files, src.read)
                        da = canonical.to_canonical(ds, src)
                        ensure_dir(path.parent)
                        enc = {"value": {"zlib": True, "complevel": 4, "dtype": "float32"}}
                        tmp = tmp_path(path)
                        da.to_dataset(name="value").to_netcdf(tmp, encoding=enc)
                        replace_file(tmp, path)
                        log.info("[%s] cube %s %s", sid, dict(da.sizes), da.attrs.get("units", ""))
        except Exception as e:
            self.errors[sid] = f"{type(e).__name__}: {e}"
            raise
        self._cubes[sid] = da
        return da

    @staticmethod
    def _load_cube(path) -> xr.DataArray:
        with xr.open_dataarray(path) as cached:  # close the handle (Windows locks open files)
            return cached.load()

    # ------------------------------------------------------------------ fields
    def field(self, sid: str, season: str = "ANN", period: dict | None = None) -> dict:
        """Seasonal values for a grid source: years x lat x lon, anomalies and trend stats."""
        key = (sid, season, repr(period))
        if key in self._fields:
            return self._fields[key]
        src = self.source(sid)
        da = self.cube(sid)
        if src.kind != "grid":
            raise DetectiveError(f"{sid} is not a grid source")
        years, vals = agg.seasonal_series(da, season, how=src.aggregate, min_coverage=src.min_coverage)
        start, end = agg.resolve_period(period or src.period, years, vals)
        years, vals = agg.restrict(years, vals, start, end)
        a = self.cfg.analysis
        frac = np.isfinite(vals).mean(axis=0)
        vals = np.where(frac[None] >= a["min_valid_frac"], vals, np.nan)
        base = agg.baseline_mean(years, vals, tuple(a["baseline"]))
        anom = vals - base[None]
        lat = da["lat"].values.astype("float64")
        lon = da["lon"].values.astype("float64")
        f = {"source": sid, "season": season, "years": years, "lat": lat, "lon": lon, "values": vals, "anom": anom,
             "base": base, "period": (int(start), int(end)),
             "dlat": float(np.median(np.diff(lat))) if lat.size > 1 else 1.0,
             "dlon": float(np.median(np.diff(lon))) if lon.size > 1 else 1.0}
        f["trend"] = analyze_field(f, src, self.cfg)
        self._fields[key] = f
        return f

    # ------------------------------------------------------------------ series
    def series(self, spec, season: str = "ANN", period: dict | None = None) -> dict:
        """Annual (seasonal) anomaly series for an index source, or a reduced grid source.

        spec: "source_id" | {"source": id, "reduce": global_mean|bbox_mean, "bbox": [...], "season": ...}
        """
        if isinstance(spec, str):
            spec = {"source": spec}
        sid = spec["source"]
        src = self.source(sid)
        season = spec.get("season", season)
        da = self.cube(sid)
        a = self.cfg.analysis
        if src.kind == "index":
            s = season if (season in agg.SEASONS and da.attrs.get("freq") != "A") else "ANN"
            years, vals = agg.seasonal_series(da, s, how=src.aggregate, min_coverage=src.min_coverage)
        elif src.kind == "grid":
            years, vals = agg.seasonal_series(da, season, how=src.aggregate, min_coverage=src.min_coverage)
            lat = da["lat"].values
            if spec.get("reduce", "global_mean") == "bbox_mean":
                mask = agg.bbox_mask(lat, da["lon"].values, spec["bbox"])
            else:
                mask = np.ones(vals.shape[1:], dtype=bool)
            vals = agg.region_mean(vals, lat, mask, min_frac=0.3)
        else:
            raise DetectiveError(f"{sid}: use level_series for levels data")
        start, end = agg.resolve_period(period or spec.get("period") or src.period, years, vals)
        years, vals = agg.restrict(years, vals, start, end)
        base = float(agg.baseline_mean(years, vals, tuple(a["baseline"])))
        return {"source": sid, "season": season, "years": years, "values": vals, "anom": vals - base, "base": base,
                "period": (int(start), int(end))}

    def level_series(self, sid: str, levels: list, season: str = "ANN", period: dict | None = None) -> dict:
        src = self.source(sid)
        da = self.cube(sid)
        if src.kind != "levels":
            raise DetectiveError(f"{sid} is not a levels source")
        lv = da["level"].values
        lo, hi = min(levels), max(levels)
        sel = da.isel(level=np.where((lv >= lo) & (lv <= hi))[0])
        if sel.sizes["level"] == 0:
            raise DetectiveError(f"{sid}: no levels between {lo} and {hi} (have {lv.tolist()})")
        years, vals = agg.seasonal_series(sel, season, how=src.aggregate, min_coverage=src.min_coverage)
        lat = sel["lat"].values
        per_level = np.stack([agg.global_mean(vals[:, k], lat) for k in range(vals.shape[1])], axis=1)
        series = np.nanmean(per_level, axis=1)
        start, end = agg.resolve_period(period or src.period, years, series)
        years, series = agg.restrict(years, series, start, end)
        base = float(agg.baseline_mean(years, series, tuple(self.cfg.analysis["baseline"])))
        return {"source": sid, "season": season, "years": years, "values": series, "anom": series - base, "base": base,
                "period": (int(start), int(end)), "levels": [float(lo), float(hi)]}


def analyze_field(f: dict, src: Source, cfg: Config) -> dict:
    a = cfg.analysis
    anom = f["anom"]
    res = stats.mk_trend(anom, f["years"], method=a["grid_method"], alpha=a["alpha"], min_years=a["min_years"])
    res["q"] = stats.fdr_bh(res["p"])
    if src.trend_units == "percent":
        base = f["base"]
        thresh = float(src.read.get("percent_min_base", 0.1)) if src.read else 0.1
        with np.errstate(invalid="ignore", divide="ignore"):
            ok = np.abs(base) > thresh
            for k in ("slope", "ci_lo", "ci_hi"):
                res[k + "_pct"] = np.where(ok, res[k] / np.abs(base) * 100.0, np.nan)
    # verdict code per cell
    code = np.full(anom.shape[1:], TREND["insufficient"]["code"], dtype="int8")
    p, q, snr, n = res["p"], res["q"], res["snr"], res["n"]
    with np.errstate(invalid="ignore"):
        valid = np.isfinite(p)
        conf = valid & (q < a["fdr_alpha"]) & (snr >= a["snr_confirm"])
        likely = valid & ~conf & ((q < a["fdr_alpha"]) | (p < 0.10))
    code[valid] = TREND["not_proven"]["code"]
    code[likely] = TREND["likely"]["code"]
    code[conf] = TREND["confirmed"]["code"]
    res["verdict"] = code
    # field significance (area-weighted)
    w = agg.area_weights(f["lat"])[:, None] * np.ones_like(p)
    wv = np.where(valid, w, 0.0)
    tot = wv.sum()
    sig = valid & (q < a["fdr_alpha"])
    res["field"] = {
        "valid_area_frac": float(tot / w.sum()) if w.sum() else 0.0,
        "sig_area_frac": float((w * sig).sum() / tot) if tot else 0.0,
        "sig_up_frac": float((w * (sig & (res["slope"] > 0))).sum() / tot) if tot else 0.0,
        "sig_down_frac": float((w * (sig & (res["slope"] < 0))).sum() / tot) if tot else 0.0,
        "n_cells": int(valid.sum()),
    }
    return res


def series_evidence(years, anom, cfg: Config, transitions: list | None = None) -> dict:
    """Trend + change point + alibi for one region/series."""
    a = cfg.analysis
    r = stats.trend_1d(anom, years, method=a["series_method"], alpha=a["alpha"], min_years=a["min_years"])
    alibi = {"flag": False, "survives": None, "label": None}
    pt = r.get("pettitt")
    if pt and pt["p"] < 0.05:
        alibi["break_year"] = pt["year"]
        alibi["break_p"] = pt["p"]
        near = []
        for tr in transitions or []:
            ty = int(str(tr.get("date", ""))[:4] or 0)
            if ty and abs(ty - pt["year"]) <= 1:
                near.append((abs(ty - pt["year"]), -ty, tr))
        if near:
            tr = min(near, key=lambda x: (x[0], x[1]))[2]
            alibi["flag"] = True
            alibi["label"] = tr.get("label")
            alibi["label_hi"] = tr.get("label_hi")
        seg = stats.segment_trends(anom, years, pt["year"], method=a["series_method"], alpha=a["alpha"])
        alibi["segments"] = seg
        b, af = seg.get("before"), seg.get("after")
        if b and af and np.isfinite(b["slope"]) and np.isfinite(af["slope"]) and np.isfinite(r["slope"]):
            alibi["survives"] = bool(np.sign(b["slope"]) == np.sign(af["slope"]) == np.sign(r["slope"]))
    r["alibi"] = alibi
    artifact = alibi["flag"] and alibi["survives"] is False
    r["verdict"] = trend_verdict(r["p"], r["snr"], r["n"], a, artifact=artifact)
    r["emerged"] = bool(r["n"] and np.isfinite(r["p"]) and r["p"] < 0.10 and np.isfinite(r["toe1"]) and r["toe1"] <= r["t1"])
    return r


def finite_or_none(x):
    try:
        x = float(x)
    except (TypeError, ValueError):
        return None
    return x if math.isfinite(x) else None


def save_path(cfg: Config, *parts) -> Path:
    return ensure_dir(cfg.output_dir.joinpath(*parts[:-1])) / parts[-1]
