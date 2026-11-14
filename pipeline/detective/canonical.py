"""Turns whatever a reader produced into ONE standard monthly cube.

Contract (checked by `validate_cube`):
  * grid   -> DataArray dims (time, lat, lon)
  * levels -> DataArray dims (time, level, lat, lon)
  * index  -> DataArray dims (time,)
  * time   = first day of each month (or 1 Jan for annual data, attrs['freq']='A')
  * lat ascending in [-90, 90]; lon ascending in [-180, 180)
  * float64 values in the source's physical units (attrs['units'])
"""
from __future__ import annotations

import re

import numpy as np
import pandas as pd
import xarray as xr

from .registry import Source
from .util import DetectiveError, log

LAT_NAMES = ["lat", "latitude", "Latitude", "LAT", "Lat", "nlat", "y", "YDim", "ydim", "lat_dim", "Latitude_dim"]
LON_NAMES = ["lon", "longitude", "Longitude", "LON", "Lon", "nlon", "x", "XDim", "xdim", "lon_dim", "Longitude_dim"]
TIME_NAMES = ["time", "Time", "TIME", "t", "date", "valid_time"]
LEVEL_NAMES = ["level", "lev", "plev", "pressure", "isobaricInhPa", "pressure_level", "Height", "z", "depth"]
SKIP_VAR = re.compile(r"(bnds|bounds|_bnd|mask|uncert|error|_err|crs|spatial_ref|mascon_id|count|flag|qa|quality)", re.I)

CONVERSIONS = {
    "K_to_C": (1.0, -273.15),
    "kg_m2_s_to_mm_day": (86400.0, 0.0),
    "m_to_cm": (100.0, 0.0),
    "m_to_mm": (1000.0, 0.0),
    "km2_to_million_km2": (1e-6, 0.0),
    "mol_cm2_to_1e15_molec": (1e-15, 0.0),
    "mm_hr_to_mm_day": (24.0, 0.0),
    "kg_m2_3h_to_mm_day": (8.0, 0.0),
    "frac_to_percent": (100.0, 0.0),
}


def _first(names, pool):
    for n in names:
        if n in pool:
            return n
    return None


def pick_variable(ds: xr.Dataset, want) -> str:
    names = want if isinstance(want, list) else ([want] if want else [])
    for n in names:
        if n in ds.data_vars:
            return n
    if names:
        log.warning("variable %s not found; available: %s", names, list(ds.data_vars))
    cands = [(len(da.dims), da.size, n) for n, da in ds.data_vars.items() if not SKIP_VAR.search(n) and np.issubdtype(da.dtype, np.number)]
    if not cands:
        raise DetectiveError(f"No numeric data variable found (have {list(ds.data_vars)})")
    return max(cands)[2]


def decode_time_values(values, units: str | None) -> np.ndarray:
    v = np.asarray(values)
    if np.issubdtype(v.dtype, np.datetime64):
        return v.astype("datetime64[ns]")
    if v.dtype.kind in "OUS":
        return pd.to_datetime([str(x) for x in v], errors="coerce").values
    units = (units or "").strip()
    m = re.match(r"(\w+)\s+since\s+(.+)", units)
    if m:
        unit, ref = m.group(1).lower(), m.group(2).strip().replace("T", " ").rstrip("Z")
        ref_ts = pd.Timestamp(ref.split(" UTC")[0])
        if unit.startswith("month"):
            out = []
            for x in v:
                whole = int(np.floor(x))
                out.append((ref_ts + pd.DateOffset(months=whole)).to_datetime64())
            return np.array(out, dtype="datetime64[ns]")
        if unit.startswith("year"):
            return np.array([(ref_ts + pd.DateOffset(years=int(np.floor(x)))).to_datetime64() for x in v], dtype="datetime64[ns]")
        scale = {"day": "D", "days": "D", "hour": "h", "hours": "h", "minute": "m", "minutes": "m", "second": "s", "seconds": "s"}.get(unit)
        if scale:
            return (np.datetime64(ref_ts.to_datetime64(), "ns") + (v.astype("float64") * pd.Timedelta(1, scale).value).astype("timedelta64[ns]"))
    # YYYYMM / YYYYMMDD / decimal years
    iv = v.astype("float64")
    if np.nanmin(iv) > 100000 and np.nanmax(iv) < 300000:  # YYYYMM
        return np.array([np.datetime64(f"{int(x)//100:04d}-{int(x)%100:02d}-01") for x in iv], dtype="datetime64[ns]")
    if np.nanmin(iv) > 10000000:  # YYYYMMDD
        return pd.to_datetime([str(int(x)) for x in iv], format="%Y%m%d").values
    if 1700 < np.nanmin(iv) < 2200:  # (decimal) years
        return np.array([(pd.Timestamp(f"{int(np.floor(x))}-01-01") + pd.Timedelta(days=(x % 1) * 365.25)).to_datetime64() for x in iv], dtype="datetime64[ns]")
    raise DetectiveError(f"Cannot decode time values with units {units!r}")


def _monthly(da: xr.DataArray, how: str) -> xr.DataArray:
    t = pd.DatetimeIndex(da["time"].values)
    if len(t) < 2:
        da.attrs["freq"] = "M"
        return da.assign_coords(time=t.to_period("M").to_timestamp().values)
    step = float(np.median(np.diff(t.values).astype("timedelta64[h]").astype("float64"))) / 24.0
    if step > 300:  # annual data
        da = da.assign_coords(time=pd.DatetimeIndex([pd.Timestamp(year=x.year, month=1, day=1) for x in t]).values)
        da.attrs["freq"] = "A"
        return da
    if 20 <= step <= 40:  # monthly - normalise stamps to month start
        months = t.to_period("M").to_timestamp().values
        da = da.assign_coords(time=months)
        if len(np.unique(months)) != len(months):
            da = da.groupby("time").mean()
        da.attrs["freq"] = "M"
        return da
    # sub-monthly (daily, 8-day, 16-day ...) -> monthly mean / sum
    log.info("  aggregating %.1f-day data to monthly (%s)", step, how)
    grouped = da.resample(time="MS")
    out = grouped.sum(skipna=True, min_count=1) if how == "sum" else grouped.mean(skipna=True)
    counts = da.notnull().resample(time="MS").sum()
    expected = max(1.0, 30.4 / step)
    out = out.where(counts >= 0.5 * expected)
    out.attrs = dict(da.attrs)
    out.attrs["freq"] = "M"
    return out


def coarsen_grid(da: xr.DataArray, target_deg: float | None) -> xr.DataArray:
    if not target_deg or "lat" not in da.dims or da.sizes["lat"] < 2:
        return da
    native = float(abs(np.median(np.diff(da["lat"].values))))
    factor = int(round(target_deg / native)) if native > 0 else 1
    if factor < 2:
        return da
    log.info("  coarsening %.3g deg -> %.3g deg (x%d)", native, native * factor, factor)
    attrs = dict(da.attrs)
    out = da.coarsen(lat=factor, lon=factor, boundary="trim").mean(skipna=True)
    out.attrs = attrs
    return out


def to_canonical(ds: xr.Dataset, src: Source) -> xr.DataArray:
    cfg = src.read or {}
    var = pick_variable(ds, cfg.get("variable"))
    da = ds[var]
    aux = {}
    for key in ("multiply_by", "mask_with"):
        spec = cfg.get(key)
        if isinstance(spec, str):
            spec = {"variable": spec}
        if spec and spec.get("variable") in ds:
            aux[key] = (spec, ds[spec["variable"]])

    # ---- rename dims / coords
    def rename_to(obj, names, target):
        hit = _first(names, list(obj.dims) + list(obj.coords))
        if hit and hit != target:
            obj = obj.rename({hit: target})
        return obj

    da = rename_to(da, TIME_NAMES, "time")
    da = rename_to(da, LAT_NAMES, "lat")
    da = rename_to(da, LON_NAMES, "lon")
    if src.kind == "levels":
        da = rename_to(da, LEVEL_NAMES, "level")
    for key, (spec, a) in list(aux.items()):
        a = rename_to(rename_to(rename_to(a, TIME_NAMES, "time"), LAT_NAMES, "lat"), LON_NAMES, "lon")
        aux[key] = (spec, a)

    # phony dims (HDF-EOS etc.): build a global regular grid from the shape
    if src.kind in ("grid", "levels") and ("lat" not in da.dims or "lon" not in da.dims):
        spatial = [d for d in da.dims if d not in ("time", "level")]
        if len(spatial) >= 2:
            ydim, xdim = spatial[-2], spatial[-1]
            ny, nx = da.sizes[ydim], da.sizes[xdim]
            bbox = cfg.get("grid_bbox", [-180, -90, 180, 90])
            lat = bbox[1] + (np.arange(ny) + 0.5) * (bbox[3] - bbox[1]) / ny
            if cfg.get("lat_descending", True):
                lat = lat[::-1]
            lon = bbox[0] + (np.arange(nx) + 0.5) * (bbox[2] - bbox[0]) / nx
            da = da.rename({ydim: "lat", xdim: "lon"}).assign_coords(lat=lat, lon=lon)
            log.info("  built a regular %dx%d grid for unnamed dims", ny, nx)

    if src.kind in ("grid", "levels"):
        for c in ("lat", "lon"):
            if c not in da.coords or da[c].ndim != 1:
                raise DetectiveError(f"{src.id}: needs 1-D {c} coordinates (curvilinear grids must be regridded first)")

    # ---- time
    if "time" not in da.dims:
        if "time" in da.coords:
            da = da.expand_dims("time")
        else:
            raise DetectiveError(f"{src.id}: no time dimension found (dims {da.dims})")
    tvals = decode_time_values(da["time"].values, da["time"].attrs.get("units") or ds.get("time", da["time"]).attrs.get("units"))
    da = da.assign_coords(time=tvals)
    da = da.isel(time=np.where(~np.isnat(da["time"].values))[0])

    # ---- extra dims
    keep = {"time", "lat", "lon"} | ({"level"} if src.kind == "levels" else set())
    for d in list(da.dims):
        if d in keep:
            continue
        sel = (cfg.get("sel") or {}).get(d)
        if sel is not None:
            da = da.sel({d: sel}, method="nearest")
        elif da.sizes[d] == 1:
            da = da.isel({d: 0})
        else:
            log.warning("  %s: extra dimension %r (%d) - taking the first slice; set read.sel.%s", src.id, d, da.sizes[d], d)
            da = da.isel({d: 0})
    da = da.drop_vars([c for c in da.coords if c not in da.dims], errors="ignore")
    if src.kind == "index":
        for d in ("lat", "lon"):
            if d in da.dims:
                da = da.mean(d, skipna=True)

    da = da.astype("float64")

    # ---- values: fill, scale, convert
    for fv in cfg.get("fill_values", []) or []:
        da = da.where(~np.isclose(da, float(fv)))
    if cfg.get("valid_range"):
        lo, hi = cfg["valid_range"]
        da = da.where((da >= lo) & (da <= hi))
    if cfg.get("scale"):
        da = da * float(cfg["scale"].get("multiply", 1.0)) + float(cfg["scale"].get("add", 0.0))
    for key, (spec, a) in aux.items():
        a = a.astype("float64")
        if "time" in a.dims:
            a = a.isel(time=0, drop=True)
        a = a.drop_vars([c for c in a.coords if c not in a.dims], errors="ignore")
        if key == "multiply_by":
            fill_as = float(spec.get("fill_as", 1.0))
            bad = (~np.isfinite(a)) | (a <= -9999) | (a > 1e6)
            a = a.where(~bad, fill_as)
            da = da * a.reindex_like(da, method="nearest")
        elif key == "mask_with":
            keepv = float(spec.get("keep", 1))
            da = da.where(a.reindex_like(da, method="nearest") == keepv)
    conv = src.convert
    if isinstance(conv, str):
        if conv not in CONVERSIONS:
            raise DetectiveError(f"{src.id}: unknown conversion {conv!r} (known: {list(CONVERSIONS)})")
        mul, add = CONVERSIONS[conv]
        da = da * mul + add
    elif isinstance(conv, dict):
        da = da * float(conv.get("multiply", 1.0)) + float(conv.get("add", 0.0))

    # ---- geometry
    if "lon" in da.dims:
        lon = da["lon"].values
        if np.nanmax(lon) > 180:
            da = da.assign_coords(lon=((lon + 180) % 360) - 180)
        da = da.sortby("lon")
        _, idx = np.unique(da["lon"].values, return_index=True)
        da = da.isel(lon=np.sort(idx))
    if "lat" in da.dims:
        da = da.sortby("lat")
    if "level" in da.dims:
        levels = cfg.get("levels")
        if levels:
            da = da.sel(level=levels, method="nearest")

    # ---- time to monthly
    da = da.sortby("time")
    da = _monthly(da, src.aggregate)
    if "lat" in da.dims:
        da = coarsen_grid(da, src.analysis_grid)

    order = [d for d in ("time", "level", "lat", "lon") if d in da.dims]
    da = da.transpose(*order)
    da.name = "value"
    da.attrs.update(
        units=src.units or str(ds[var].attrs.get("units", "")),
        source_id=src.id,
        source_variable=var,
        freq=da.attrs.get("freq", "M"),
    )
    validate_cube(da, src.kind)
    return da


def validate_cube(da: xr.DataArray, kind: str) -> None:
    want = {"grid": ("time", "lat", "lon"), "levels": ("time", "level", "lat", "lon"), "index": ("time",)}[kind]
    if tuple(da.dims) != want:
        raise DetectiveError(f"cube dims {da.dims} != {want}")
    t = da["time"].values
    if len(t) < 3:
        raise DetectiveError("cube has fewer than 3 time steps")
    if len(np.unique(t)) != len(t):
        raise DetectiveError("duplicate time stamps in cube")
    if "lat" in da.dims:
        lat = da["lat"].values
        if lat.min() < -90.01 or lat.max() > 90.01 or np.any(np.diff(lat) <= 0):
            raise DetectiveError("latitudes must be ascending within [-90, 90]")
        lon = da["lon"].values
        if lon.min() < -180.01 or lon.max() > 180.01 or np.any(np.diff(lon) <= 0):
            raise DetectiveError("longitudes must be ascending within [-180, 180]")
    finite = np.isfinite(da.values).mean()
    if finite == 0:
        raise DetectiveError("cube contains no finite values (check fill values / scale)")
