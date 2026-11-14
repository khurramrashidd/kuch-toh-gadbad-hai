"""Synthetic stand-ins for every real dataset, written in the REAL file formats.

Used for (a) testing the whole pipeline end to end without internet and
(b) a clearly labelled DEMO data pack so the app can be tried before the real
NASA data have been downloaded. Demo output is flagged `demo: true` and the
app shows a red DEMO banner - never present it as real data.
"""
from __future__ import annotations

import json
import math
from pathlib import Path

import numpy as np
import pandas as pd
import xarray as xr

from .util import PIPELINE_DIR, ensure_dir, log

DEMO_DIR = PIPELINE_DIR / "demo"
RAW = DEMO_DIR / "raw"


def _ar1(n, phi, rng, sd=1.0):
    x = np.zeros(n)
    e = rng.normal(0, sd, n)
    for i in range(1, n):
        x[i] = phi * x[i - 1] + e[i]
    return x


def _land_mask(lat, lon) -> np.ndarray:
    """Rasterise the Natural Earth land outline shipped with the app (point-in-polygon)."""
    geo = PIPELINE_DIR.parent / "app" / "assets" / "geo" / "land_110m.json"
    mask = np.zeros((lat.size, lon.size), dtype=bool)
    if not geo.exists():
        return np.abs(lat)[:, None] < 60  # crude fallback
    data = json.loads(geo.read_text(encoding="utf-8"))
    LO, LA = np.meshgrid(lon, lat)
    px, py = LO.ravel(), LA.ravel()
    for ring in data["rings"]:
        ring = np.asarray(ring, dtype="float64")
        if len(ring) < 3:
            continue
        inside = np.zeros(px.size, dtype=bool)
        x0, y0 = ring[:, 0], ring[:, 1]
        x1, y1 = np.roll(x0, -1), np.roll(y0, -1)
        for a, b, c, d in zip(x0, y0, x1, y1):  # even-odd ray casting
            cond = (b > py) != (d > py)
            with np.errstate(divide="ignore", invalid="ignore"):
                xint = a + (py - b) * (c - a) / (d - b)
            inside ^= cond & (px < xint)
        mask |= inside.reshape(mask.shape)
    return mask


def _blob(lat, lon, clat, clon, rlat, rlon):
    dl = ((lon[None, :] - clon + 180) % 360) - 180
    return np.exp(-(((lat[:, None] - clat) / rlat) ** 2 + (dl / rlon) ** 2))


def make_demo(seed: int = 2026) -> Path:
    rng = np.random.default_rng(seed)
    ensure_dir(RAW)
    # ---------------------------------------------------------- shared drivers (monthly)
    months = pd.date_range("1900-01-01", "2025-12-01", freq="MS")
    nm = len(months)
    tyear = months.year.values + (months.month.values - 0.5) / 12
    enso = _ar1(nm, 0.92, rng, 0.28)
    forced = np.where(tyear < 1975, 0.004 * (tyear - 1900), 0.3 + 0.019 * (tyear - 1975)) - 0.35
    gmt = forced + 0.09 * np.roll(enso, 3) + _ar1(nm, 0.6, rng, 0.06)
    iod = _ar1(nm, 0.8, rng, 0.25) + 0.25 * enso
    co2 = 296 + 0.0125 * np.maximum(tyear - 1900, 0) ** 2 * 0.1 + 3 * np.sin(2 * np.pi * (months.month.values - 4) / 12)

    # GISTEMP global table (wide monthly csv, '***' for missing)
    rows = ["Land-Ocean: Global Means", "Year,Jan,Feb,Mar,Apr,May,Jun,Jul,Aug,Sep,Oct,Nov,Dec,J-D,D-N,DJF,MAM,JJA,SON"]
    # (filled after the grid is built so the table equals the grid's global mean)

    # ONI (CPC format)
    seas = ["DJF", "JFM", "FMA", "MAM", "AMJ", "MJJ", "JJA", "JAS", "ASO", "SON", "OND", "NDJ"]
    oni_lines = ["SEAS  YR   TOTAL   ANOM"]
    enso3 = pd.Series(enso).rolling(3, center=True, min_periods=1).mean().values
    for i, t in enumerate(months):
        if t.year < 1950:
            continue
        oni_lines.append(f"  {seas[t.month - 1]} {t.year}  {26.5 + enso3[i]:6.2f}  {enso3[i]:6.2f}")
    (RAW / "oni.ascii.txt").write_text("\n".join(oni_lines) + "\n", encoding="utf-8")

    # DMI (NOAA PSL standard format)
    psl = [f" 1900 2025"]
    for y in range(1900, 2026):
        vals = iod[(months.year == y)]
        psl.append(f" {y} " + " ".join(f"{v:8.3f}" for v in vals))
    psl += ["  -9999", "  DMI demo (synthetic)"]
    (RAW / "dmi.had.long.data").write_text("\n".join(psl) + "\n", encoding="utf-8")

    # CO2 (NOAA GML csv with comments)
    co2_lines = ["# NOAA GML demo (synthetic)", "year,month,decimal date,average,deseasonalized,ndays,sdev,unc"]
    for i, t in enumerate(months):
        if t.year < 1958:
            continue
        co2_lines.append(f"{t.year},{t.month},{tyear[i]:.4f},{co2[i]:.2f},{co2[i]:.2f},-1,-9.99,-0.99")
    (RAW / "co2_mm_mlo.csv").write_text("\n".join(co2_lines) + "\n", encoding="utf-8")

    # ---------------------------------------------------------- GISTEMP-like grid (2 deg, 1950-2025)
    lat = np.arange(-89, 90, 2.0)
    lon = np.arange(-179, 180, 2.0)
    land = _land_mask(lat, lon)
    sel = months.year >= 1950
    tm = months[sel]
    amp = 0.9 + 0.6 * land + 1.4 * np.clip((lat[:, None] - 55) / 30, 0, 1) + 0 * lon[None, :]
    hole = _blob(lat, lon, 54, -38, 7, 14)
    amp = amp - 1.6 * hole  # North Atlantic "warming hole"
    enso_pat = 1.1 * _blob(lat, lon, 0, -120, 10, 40) - 0.3 * _blob(lat, lon, 15, 140, 15, 25)
    g = gmt[sel][:, None, None]
    e = enso[sel][:, None, None]
    noise = np.zeros((sel.sum(), lat.size, lon.size), dtype="float32")
    acc = np.zeros((lat.size, lon.size))
    for i in range(noise.shape[0]):
        acc = 0.5 * acc + rng.normal(0, 0.35, acc.shape)
        noise[i] = acc
    temp = (amp[None] * g + enso_pat[None] * e + noise).astype("float32")
    time_days = (tm - pd.Timestamp("1800-01-01")).days.values
    ds = xr.Dataset({"tempanomaly": (("time", "lat", "lon"), temp, {"units": "K", "long_name": "Surface temperature anomaly", "_FillValue": np.float32(32767)})},
                    coords={"time": ("time", time_days, {"units": "days since 1800-01-01"}), "lat": lat, "lon": lon})
    ds.to_netcdf(RAW / "gistemp1200_demo.nc", encoding={"tempanomaly": {"zlib": True}, "time": {"dtype": "int32"}}, engine="netcdf4")
    w = np.cos(np.deg2rad(lat))[:, None] * np.ones_like(lon)[None, :]
    gm = (temp * w).sum(axis=(1, 2)) / w.sum()
    full = pd.Series(np.nan, index=months)
    full[tm] = gm
    full[months.year < 1950] = gmt[months.year < 1950] - gmt[(months.year >= 1951) & (months.year <= 1980)].mean()
    for y in range(1900, 2026):
        v = full[full.index.year == y].values
        jd = np.mean(v)
        cells = [f"{x:.2f}" for x in v] + [f"{jd:.2f}", "***", "***", "***", "***", "***"]
        rows.append(f"{y}," + ",".join(cells))
    (RAW / "GLB.Ts+dSST.csv").write_text("\n".join(rows) + "\n", encoding="utf-8")

    # ---------------------------------------------------------- GPCP-like precip (2.5 deg, 0-360 lon, lat descending)
    plat = np.arange(88.75, -90, -2.5)
    plon = np.arange(1.25, 360, 2.5)
    plon180 = ((plon + 180) % 360) - 180
    pland = _land_mask(plat, plon180)
    selp = months.year >= 1979
    tp = months[selp]
    clim = (2.5 + 7 * np.exp(-((plat[:, None] - 6) / 8) ** 2) + 1.2 * np.exp(-((np.abs(plat[:, None]) - 55) / 10) ** 2)
            - 1.5 * np.exp(-((np.abs(plat[:, None]) - 25) / 7) ** 2)) * np.ones_like(plon)[None, :]
    clim = np.clip(clim, 0.2, None)
    sens = (0.10 * np.exp(-((plat[:, None] - 5) / 9) ** 2) + 0.07 * np.exp(-((np.abs(plat[:, None]) - 60) / 10) ** 2)
            - 0.12 * np.exp(-((np.abs(plat[:, None]) - 25) / 6) ** 2)) * np.ones_like(plon)[None, :]
    india = _blob(plat, plon180, 22, 79, 8, 9)
    enso_p = 0.35 * _blob(plat, plon180, -5, -85, 8, 20) - 0.25 * india - 0.3 * _blob(plat, plon180, -2, 120, 10, 20)
    gp = (gmt[selp] - gmt[selp][:120].mean())[:, None, None]
    ep = enso[selp][:, None, None]
    season = 1 + 0.8 * india[None] * np.sin(np.pi * np.clip((tp.month.values - 5) / 5, 0, 1))[:, None, None]
    mult = np.exp(rng.normal(0, 0.18, (selp.sum(), plat.size, plon.size)))
    pr = np.clip(clim[None] * season * (1 + sens[None] * gp * 4 + enso_p[None] * ep) * mult, 0, None).astype("float32")
    tdays = (tp - pd.Timestamp("1800-01-01")).days.values
    xr.Dataset({"precip": (("time", "lat", "lon"), pr, {"units": "mm/day"})},
               coords={"time": ("time", tdays, {"units": "days since 1800-1-1 00:00:00"}), "lat": plat, "lon": plon}
               ).to_netcdf(RAW / "precip.mon.mean.demo.nc", encoding={"precip": {"zlib": True}}, engine="netcdf4")

    # ---------------------------------------------------------- GRACE-like water storage (2 deg monthly, gap 2017-18)
    glat, glon = np.arange(-89, 90, 2.0), np.arange(-179, 180, 2.0)
    gland = _land_mask(glat, glon)
    gm_ = pd.date_range("2002-04-01", "2025-09-01", freq="MS")
    keep = ~((gm_ >= "2017-07-01") & (gm_ < "2018-06-01"))
    keep &= rng.uniform(size=len(gm_)) > 0.04
    gm_ = gm_[keep]
    tt = (gm_.year.values + (gm_.month.values - 0.5) / 12) - 2002.3
    rate = (-1.9 * _blob(glat, glon, 28.5, 75, 4.5, 5) - 1.0 * _blob(glat, glon, 34, 48, 5, 8) - 0.9 * _blob(glat, glon, 72, -40, 8, 18)
            + 0.9 * _blob(glat, glon, 13, 5, 6, 14) + 0.7 * _blob(glat, glon, 47, -100, 5, 9) + 0.6 * _blob(glat, glon, 21, 79, 3, 4))
    seasonal = 8 * np.sin(2 * np.pi * (gm_.month.values - 5) / 12)[:, None, None] * (_blob(glat, glon, 20, 80, 12, 20)[None] + 0.3)
    step = np.where(gm_ >= "2018-06-01", 4.0, 0.0)[:, None, None] * _blob(glat, glon, -8, -50, 5, 6)[None]  # artificial GRACE-FO jump
    lwe = rate[None] * tt[:, None, None] + seasonal + step + rng.normal(0, 2.0, (len(gm_), glat.size, glon.size))
    lwe = np.where(gland[None], lwe, rng.normal(0, 1.0, lwe.shape)).astype("float32")
    days = (gm_ + pd.Timedelta(days=14) - pd.Timestamp("2002-01-01")).days.values.astype("float64")
    xr.Dataset({"lwe_thickness": (("time", "lat", "lon"), lwe, {"units": "cm"}),
                "land_mask": (("lat", "lon"), gland.astype("float64")),
                "scale_factor": (("lat", "lon"), np.where(gland, 1.05, -99999.0))},
               coords={"time": ("time", days, {"units": "days since 2002-01-01T00:00:00Z"}),
                       "lat": glat, "lon": (glon + 360) % 360}
               ).sortby("lon").to_netcdf(RAW / "GRCTellus.JPL.demo.MSCNv04CRI.nc", engine="netcdf4")

    # ---------------------------------------------------------- Sea Ice Index monthly CSVs (NSIDC layout)
    sdir = ensure_dir(RAW / "seaice")
    years = np.arange(1979, 2026)
    for hemi, prefix in (("N", "north"), ("S", "south")):
        for mo in range(1, 13):
            lines = ["year, mo, source_dataset, region, extent, area"]
            for y in years:
                if hemi == "N":
                    base = {9: 7.2, 2: 16.0}.get(mo, 12.0)
                    ext = base - (0.085 if mo == 9 else 0.045) * (y - 1979) + rng.normal(0, 0.33 if mo == 9 else 0.18)
                else:
                    base = {2: 3.0, 9: 18.8}.get(mo, 11.0)
                    ext = base + 0.012 * (y - 1979) + rng.normal(0, 0.22) - (0.9 if (y >= 2016 and mo == 2) else 0.0) - (0.5 if y >= 2016 else 0)
                if y == 1987 and mo == 12 and hemi == "N":
                    lines.append(f"{y}, {mo:2d}, NSIDC-0051, {hemi}, -9999, -9999")
                    continue
                lines.append(f"{y}, {mo:2d}, NSIDC-0051, {hemi}, {ext:6.2f}, {ext * 0.8:6.2f}")
            (sdir / f"{hemi}_{mo:02d}_extent_v4.0.csv").write_text("\n".join(lines) + "\n", encoding="utf-8")
    log.info("demo files written to %s", RAW)
    return RAW


def make_power_demo(lat: float, lon: float, seed: int = 0) -> tuple[dict, dict]:
    """NASA POWER-shaped JSON (monthly + daily) with a warming, drying signal - for offline tests."""
    rng = np.random.default_rng(seed + int(abs(lat * 100 + lon)))
    years = np.arange(1981, 2026)
    monthly = {"T2M": {}, "PRECTOTCORR": {}, "GWETROOT": {}, "RH2M": {}}
    for y in years:
        warm = 0.03 * (y - 1981) + rng.normal(0, 0.25)
        for m in range(1, 13):
            season = math.cos(2 * math.pi * (m - 6) / 12)
            monthly["T2M"][f"{y}{m:02d}"] = round(25 + 7 * season * np.sign(lat or 1) + warm + rng.normal(0, 0.5), 2)
            monsoon = 9.0 if m in (6, 7, 8, 9) else 0.6
            monthly["PRECTOTCORR"][f"{y}{m:02d}"] = round(max(0.0, monsoon * (1 - 0.004 * (y - 1981)) * math.exp(rng.normal(0, 0.3))), 2)
            monthly["GWETROOT"][f"{y}{m:02d}"] = round(min(1, max(0, 0.45 - 0.002 * (y - 1981) + 0.1 * (m in (7, 8, 9)) + rng.normal(0, 0.03))), 3)
            monthly["RH2M"][f"{y}{m:02d}"] = round(55 + 20 * (m in (7, 8, 9)) + rng.normal(0, 3), 1)
        for k in monthly:
            vals = [monthly[k][f"{y}{m:02d}"] for m in range(1, 13)]
            monthly[k][f"{y}13"] = round(float(np.mean(vals)), 2)
    days = pd.date_range("1981-01-01", "2025-12-31", freq="D")
    doy = days.dayofyear.values
    tx = 32 + 8 * np.cos(2 * np.pi * (doy - 140) / 365.25) + 0.035 * (days.year.values - 1981) + rng.normal(0, 2.0, len(days))
    daily = {"T2M_MAX": {d.strftime("%Y%m%d"): round(float(v), 2) for d, v in zip(days, tx)}}
    geom = {"type": "Point", "coordinates": [lon, lat, 200.0]}
    return ({"type": "Feature", "geometry": geom, "properties": {"parameter": monthly}, "header": {"fill_value": -999.0}},
            {"type": "Feature", "geometry": geom, "properties": {"parameter": daily}, "header": {"fill_value": -999.0}})
