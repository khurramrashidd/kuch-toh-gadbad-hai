"""Monthly cube -> one value per year (per season), anomalies and region means."""
from __future__ import annotations

import math

import numpy as np
import pandas as pd
import xarray as xr

from .util import DetectiveError

SEASONS: dict[str, list[int]] = {
    "ANN": list(range(1, 13)),
    "JJAS": [6, 7, 8, 9],     # Indian summer monsoon
    "DJF": [12, 1, 2],
    "MAM": [3, 4, 5],
    "JJA": [6, 7, 8],
    "SON": [9, 10, 11],
    "OND": [10, 11, 12],      # NE monsoon (Tamil Nadu)
    "FEB": [2], "MAR": [3], "SEP": [9],
}

SEASON_LABELS: dict[str, tuple[str, str]] = {
    "ANN": ("Whole year", "पूरा साल"),
    "JJAS": ("Monsoon (Jun-Sep)", "मानसून (जून-सितंबर)"),
    "DJF": ("Winter (Dec-Feb)", "सर्दी (दिसंबर-फ़रवरी)"),
    "MAM": ("Pre-monsoon (Mar-May)", "मानसून से पहले (मार्च-मई)"),
    "JJA": ("Jun-Aug", "जून-अगस्त"),
    "SON": ("Sep-Nov", "सितंबर-नवंबर"),
    "OND": ("Oct-Dec", "अक्टूबर-दिसंबर"),
    "FEB": ("February", "फ़रवरी"),
    "MAR": ("March", "मार्च"),
    "SEP": ("September", "सितंबर"),
}


def seasonal_series(da: xr.DataArray, season: str = "ANN", how: str = "mean", min_coverage: float = 0.75):
    """Return (years, values[n_years, ...spatial]) for one season.

    Years with too few valid months get NaN, so a half-finished current year never
    sneaks into a trend.
    """
    spatial_shape = da.shape[1:]
    if da.attrs.get("freq") == "A":
        if season != "ANN":
            raise DetectiveError("annual data only supports season ANN")
        years = pd.DatetimeIndex(da["time"].values).year.values.astype(int)
        return years, np.asarray(da.values, dtype="float64")
    if season not in SEASONS:
        raise DetectiveError(f"unknown season {season!r}; choose from {list(SEASONS)}")
    months = SEASONS[season]
    t = pd.DatetimeIndex(da["time"].values)
    yr, mo = t.year.values.astype(int), t.month.values.astype(int)
    wraps = len(months) > 1 and months[0] > months[-1]
    syear = yr + ((mo >= months[0]) & wraps).astype(int) if wraps else yr.copy()
    sel = np.isin(mo, months)
    vals = np.asarray(da.values, dtype="float64")[sel]
    sy = syear[sel]
    years = np.unique(sy)
    out = np.full((len(years),) + spatial_shape, np.nan)
    need = math.ceil(min_coverage * len(months))
    with np.errstate(invalid="ignore", divide="ignore"):
        for i, y in enumerate(years):
            block = vals[sy == y]
            cnt = np.isfinite(block).sum(axis=0)
            if how == "sum":
                agg = np.nansum(block, axis=0) * (len(months) / np.maximum(cnt, 1))
            else:
                agg = np.nanmean(block, axis=0) if block.size else np.full(spatial_shape, np.nan)
            agg = np.where(cnt >= need, agg, np.nan)
            out[i] = agg
    return years, out


def resolve_period(period: dict | None, years: np.ndarray, values: np.ndarray) -> tuple[int, int]:
    period = period or {}
    finite = np.isfinite(values).reshape(len(years), -1).sum(axis=1)
    good = years[finite >= 0.5 * max(1, finite.max())]
    if good.size == 0:
        raise DetectiveError("no years with data")
    start = period.get("start", "auto")
    end = period.get("end", "auto")
    start = int(good.min()) if start in (None, "auto") else int(start)
    end = int(good.max()) if end in (None, "auto") else int(end)
    return max(start, int(good.min())), min(end, int(good.max()))


def restrict(years: np.ndarray, values: np.ndarray, start: int, end: int):
    m = (years >= start) & (years <= end)
    return years[m], values[m]


def anomalies(years: np.ndarray, values: np.ndarray, baseline=(1991, 2020)) -> np.ndarray:
    b = (years >= baseline[0]) & (years <= baseline[1])
    with np.errstate(invalid="ignore"):
        if b.sum() >= 10:
            ref = np.nanmean(values[b], axis=0)
        else:
            ref = np.nanmean(values, axis=0)
    return values - ref


def baseline_mean(years: np.ndarray, values: np.ndarray, baseline=(1991, 2020)) -> np.ndarray:
    b = (years >= baseline[0]) & (years <= baseline[1])
    with np.errstate(invalid="ignore"):
        return np.nanmean(values[b], axis=0) if b.sum() >= 10 else np.nanmean(values, axis=0)


def area_weights(lat: np.ndarray) -> np.ndarray:
    return np.cos(np.deg2rad(np.asarray(lat, dtype="float64")))


def cell_area_km2(lat: np.ndarray, dlat: float, dlon: float) -> np.ndarray:
    r = 6371.0
    lat = np.asarray(lat, dtype="float64")
    return (r**2) * np.deg2rad(dlon) * np.abs(np.sin(np.deg2rad(lat + dlat / 2)) - np.sin(np.deg2rad(lat - dlat / 2)))


def bbox_mask(lat: np.ndarray, lon: np.ndarray, bbox) -> np.ndarray:
    """bbox = [lon_min, lat_min, lon_max, lat_max]; lon_min > lon_max wraps the dateline."""
    lon0, lat0, lon1, lat1 = [float(x) for x in bbox]
    la = (lat >= lat0) & (lat <= lat1)
    lo = ((lon >= lon0) & (lon <= lon1)) if lon0 <= lon1 else ((lon >= lon0) | (lon <= lon1))
    return la[:, None] & lo[None, :]


def region_mean(values: np.ndarray, lat: np.ndarray, mask: np.ndarray, min_frac: float = 0.5) -> np.ndarray:
    """Area-weighted mean series over a boolean mask; NaN when too little of the region has data."""
    w = area_weights(lat)[:, None] * mask
    total = w.sum()
    if total <= 0:
        return np.full(values.shape[0], np.nan)
    out = np.full(values.shape[0], np.nan)
    for i in range(values.shape[0]):
        v = values[i]
        ok = np.isfinite(v) & mask
        den = w[ok].sum()
        if den >= min_frac * total:
            out[i] = float((v[ok] * w[ok]).sum() / den)
    return out


def global_mean(values: np.ndarray, lat: np.ndarray) -> np.ndarray:
    return region_mean(values, lat, np.ones(values.shape[1:], dtype=bool), min_frac=0.3)
