"""Format-agnostic readers ("360-degree compatibility").

`open_raw(paths, read_cfg)` returns an ``xarray.Dataset`` for any of:

  NetCDF3/4, HDF5 / HDF-EOS5, HDF4 (MODIS, needs pyhdf), GeoTIFF/COG (needs
  rioxarray), Zarr, GRIB (needs cfgrib), CSV/TSV/TXT tables (long, wide-monthly
  GISTEMP style, NOAA PSL standard format, NOAA CPC ONI format), Excel,
  NASA POWER JSON and generic JSON/GeoJSON records.

Formats are sniffed from magic bytes, not just file extensions, so a renamed
or extension-less file from a resource page still opens.
"""
from __future__ import annotations

import io
import json
import re
from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd
import xarray as xr

from .util import DetectiveError, log

MONTHS = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
MISSING_DEFAULT = [-9999, -9999.0, -9999.9, -999, -999.0, -999.9, -99.99, -99.9, 9.96921e36, 1e20, -1e20, 32767, -32767]
_MAGIC = [
    (b"\x89HDF\r\n\x1a\n", "hdf5"),
    (b"CDF\x01", "netcdf3"),
    (b"CDF\x02", "netcdf3"),
    (b"CDF\x05", "netcdf3"),
    (b"\x0e\x03\x13\x01", "hdf4"),
    (b"II*\x00", "tiff"),
    (b"MM\x00*", "tiff"),
    (b"II+\x00", "tiff"),
    (b"MM\x00+", "tiff"),
    (b"GRIB", "grib"),
    (b"\x1f\x8b", "gzip"),
    (b"PK\x03\x04", "zip"),
]


# ----------------------------------------------------------------------------- sniffing
def sniff(path: Path | str) -> str:
    p = Path(path)
    if p.is_dir():
        if (p / ".zgroup").exists() or (p / ".zarray").exists() or (p / "zarr.json").exists() or p.suffix == ".zarr":
            return "zarr"
        return "dir"
    with open(p, "rb") as f:
        head = f.read(16)
        for magic, fmt in _MAGIC:
            if head.startswith(magic):
                if fmt == "zip":
                    return "excel" if p.suffix.lower() in (".xlsx", ".xlsm") else "zip"
                return fmt
        for offset in (512, 1024, 2048):  # HDF5 user block
            f.seek(offset)
            if f.read(8) == b"\x89HDF\r\n\x1a\n":
                return "hdf5"
        f.seek(0)
        sample = f.read(4096)
    if p.suffix.lower() == ".xls":
        return "excel"
    text = sample.decode("utf-8", errors="ignore").lstrip()
    if text.startswith("{") or text.startswith("["):
        return "json"
    return "text"


# ----------------------------------------------------------------------------- time helpers
_FILENAME_TIME = [
    (re.compile(r"doy(\d{4})(\d{3})", re.I), "yj"),               # AppEEARS ..._doy2010182_aid0001.tif
    (re.compile(r"A(\d{4})(\d{3})"), "yj"),                      # MODIS A2010182
    (re.compile(r"(?<!\d)(\d{4})[-_.]?(\d{2})[-_.]?(\d{2})(?!\d)"), "ymd"),
    (re.compile(r"(?<!\d)(\d{4})[-_.]?(\d{2})(?!\d)"), "ym"),
]


def time_from_filename(name: str, pattern: str | None = None) -> np.datetime64 | None:
    pats = [(re.compile(pattern), "custom")] if pattern else _FILENAME_TIME
    for rx, kind in pats:
        m = rx.search(name)
        if not m:
            continue
        g = [int(x) for x in m.groups()]
        try:
            if kind == "yj":
                return np.datetime64(f"{g[0]:04d}-01-01") + np.timedelta64(g[1] - 1, "D")
            if kind == "ymd" or (kind == "custom" and len(g) >= 3):
                if not (1 <= g[1] <= 12 and 1 <= g[2] <= 31):
                    continue
                return np.datetime64(f"{g[0]:04d}-{g[1]:02d}-{g[2]:02d}")
            if 1 <= g[1] <= 12 and 1800 < g[0] < 2200:
                return np.datetime64(f"{g[0]:04d}-{g[1]:02d}-01")
        except Exception:
            continue
    return None


# ----------------------------------------------------------------------------- gridded
def _pick_group_hdf5(path: Path, variable: str | None) -> str | None:
    try:
        import h5py
    except ImportError:
        return None
    best = None
    with h5py.File(path, "r") as h:
        candidates: list[tuple[int, str]] = []

        def visit(name, obj):
            if isinstance(obj, h5py.Dataset) and obj.ndim >= 2:
                leaf = name.split("/")[-1]
                parent = "/".join(name.split("/")[:-1])
                score = obj.size
                if variable and leaf == variable:
                    score = 10**18
                candidates.append((score, parent))

        h.visititems(visit)
        if candidates:
            best = max(candidates)[1]
    return best or None


def _open_netcdf_like(path: Path, cfg: dict, fmt: str) -> xr.Dataset:
    group = cfg.get("group")
    engines = ["netcdf4", "h5netcdf"] if fmt == "hdf5" else ["netcdf4", "scipy", "h5netcdf"]
    last: Exception | None = None
    for decode_times in (True, False):
        for eng in engines:
            try:
                ds = xr.open_dataset(path, engine=eng, group=group, decode_times=decode_times, mask_and_scale=True)
                if not ds.data_vars and fmt == "hdf5" and not group:
                    g = _pick_group_hdf5(path, cfg.get("variable") if isinstance(cfg.get("variable"), str) else None)
                    if g:
                        ds.close()
                        ds = xr.open_dataset(path, engine=eng, group=g, decode_times=decode_times)
                return ds
            except Exception as e:  # try the next engine / decoding
                last = e
    raise DetectiveError(f"Could not open {path.name} as {fmt}: {last}")


def _open_hdf4(path: Path, cfg: dict) -> xr.Dataset:
    try:
        from pyhdf.SD import SD, SDC  # type: ignore
    except ImportError:
        try:
            import rioxarray  # noqa: F401
        except ImportError as e:
            raise DetectiveError(
                f"{path.name} is HDF4. Install the optional reader: pip install pyhdf (or rioxarray)"
            ) from e
        return _open_tiff(path, cfg)  # GDAL can read HDF4 subdatasets
    sd = SD(str(path), SDC.READ)
    names = list(sd.datasets().keys())
    var = cfg.get("variable")
    if isinstance(var, list):
        var = next((v for v in var if v in names), None)
    if not var:
        var = max(names, key=lambda n: np.prod(sd.select(n).info()[2]) if isinstance(sd.select(n).info()[2], list) else 0)
    sds = sd.select(var)
    data = sds.get().astype("float64")
    attrs = sds.attributes()
    fill = attrs.get("_FillValue")
    if fill is not None:
        data[data == fill] = np.nan
    vr = attrs.get("valid_range")
    if vr is not None and len(vr) == 2:
        data[(data < vr[0]) | (data > vr[1])] = np.nan
    while data.ndim > 2:
        data = data[0]
    ny, nx = data.shape
    lat = 90 - (np.arange(ny) + 0.5) * 180.0 / ny
    lon = -180 + (np.arange(nx) + 0.5) * 360.0 / nx
    da = xr.DataArray(data, dims=("lat", "lon"), coords={"lat": lat, "lon": lon}, name=var, attrs={k: v for k, v in attrs.items() if isinstance(v, (str, int, float))})
    return da.to_dataset()


def _open_tiff_pillow(path: Path, cfg: dict) -> xr.Dataset:
    """Plain global lat/lon TIFF (NASA NEO float GeoTIFFs) without GDAL: assumes it spans the grid_bbox."""
    from PIL import Image

    Image.MAX_IMAGE_PIXELS = None
    with Image.open(path) as im:
        arr = np.asarray(im, dtype="float64")
    if arr.ndim == 3:
        arr = arr[..., 0]
    for mv in list(cfg.get("fill_values", []) or []) + [99999.0, -99999.0, -9999.0]:
        arr[np.isclose(arr, mv)] = np.nan
    w, s_, e, n = cfg.get("grid_bbox", [-180, -90, 180, 90])
    ny, nx = arr.shape
    dy, dx = (n - s_) / ny, (e - w) / nx
    lat = n - dy / 2 - dy * np.arange(ny)
    lon = w + dx / 2 + dx * np.arange(nx)
    name = cfg.get("variable") if isinstance(cfg.get("variable"), str) else "value"
    return xr.Dataset({name: (("lat", "lon"), arr)}, coords={"lat": lat, "lon": lon})


def _open_tiff(path: Path, cfg: dict) -> xr.Dataset:
    if cfg.get("tiff_reader") == "pillow":
        return _open_tiff_pillow(path, cfg)
    try:
        import rioxarray  # noqa: F401
    except ImportError:
        return _open_tiff_pillow(path, cfg)
    import rioxarray as rxr

    da = rxr.open_rasterio(path, masked=True)
    if "band" in da.dims:
        band = int(cfg.get("band", 1))
        da = da.sel(band=band) if band in da["band"].values else da.isel(band=0)
    da = da.rename({"y": "lat", "x": "lon"})
    da = da.drop_vars([c for c in da.coords if c not in ("lat", "lon")], errors="ignore")
    da.name = cfg.get("variable") if isinstance(cfg.get("variable"), str) else (path.stem or "value")
    return da.to_dataset()


def _open_zarr(path: Path, cfg: dict) -> xr.Dataset:
    try:
        return xr.open_zarr(path, decode_times=True)
    except Exception:
        return xr.open_zarr(path, decode_times=False)


def _open_grib(path: Path, cfg: dict) -> xr.Dataset:
    try:
        return xr.open_dataset(path, engine="cfgrib")
    except Exception as e:
        raise DetectiveError(f"{path.name} is GRIB. Install the optional reader: pip install cfgrib eccodes ({e})") from e


# ----------------------------------------------------------------------------- tables
def _is_year(tok: str) -> bool:
    return bool(re.fullmatch(r"\d{4}", tok)) and 1700 < int(tok) < 2200


def _parse_psl(lines: list[str], cfg: dict) -> xr.Dataset | None:
    """NOAA PSL 'standard format': 'start end' line then rows of year + 12 values."""
    body = [ln.split() for ln in lines if ln.strip()]
    if not body or len(body[0]) != 2 or not all(_is_year(t) for t in body[0]):
        return None
    start, end = int(body[0][0]), int(body[0][1])
    times, vals = [], []
    missing = None
    for toks in body[1:]:
        if len(toks) == 13 and _is_year(toks[0]):
            y = int(toks[0])
            for m, v in enumerate(toks[1:], 1):
                times.append(np.datetime64(f"{y:04d}-{m:02d}-01"))
                vals.append(float(v))
        elif len(toks) == 1 and missing is None:
            try:
                missing = float(toks[0])
            except ValueError:
                pass
            break
    if not times:
        return None
    arr = np.array(vals, dtype="float64")
    for mv in ([missing] if missing is not None else []) + [-99.99, -999.0, -9999.0]:
        arr[np.isclose(arr, mv)] = np.nan
    log.debug("PSL table %d-%d", start, end)
    return xr.Dataset({cfg.get("variable") or "value": ("time", arr)}, coords={"time": np.array(times)})


_ONI_SEAS = {"DJF": 1, "JFM": 2, "FMA": 3, "MAM": 4, "AMJ": 5, "MJJ": 6, "JJA": 7, "JAS": 8, "ASO": 9, "SON": 10, "OND": 11, "NDJ": 12}


def _parse_oni(lines: list[str], cfg: dict) -> xr.Dataset | None:
    head = lines[0].split() if lines else []
    if len(head) < 3 or head[0].upper() != "SEAS":
        return None
    col = cfg.get("column", "ANOM").upper()
    idx = [h.upper() for h in head].index(col) if col in [h.upper() for h in head] else len(head) - 1
    times, vals = [], []
    for ln in lines[1:]:
        t = ln.split()
        if len(t) < len(head) or t[0].upper() not in _ONI_SEAS:
            continue
        m = _ONI_SEAS[t[0].upper()]
        times.append(np.datetime64(f"{int(t[1]):04d}-{m:02d}-01"))
        vals.append(float(t[idx]))
    if not times:
        return None
    return xr.Dataset({cfg.get("variable") or "value": ("time", np.array(vals))}, coords={"time": np.array(times)})


_DATA_START = re.compile(r"^\s*[-+]?(\d|\.\d)")
_META_LINE = re.compile(r"^[^,;\t]{1,80}:\s*[,;\t]")  # Giovanni "Title:,..." / "Fill Value (x):,-9999.9"


def _looks_like_data(line: str) -> bool:
    return bool(_DATA_START.match(line))


def _find_header(lines: list[str]) -> int:
    """Header = line naming a time column, followed by a data line (skips Giovanni-style metadata)."""
    first_kw = None
    for i, ln in enumerate(lines[:200]):
        low = ln.lower()
        if not ln.strip() or ln.lstrip().startswith(("#", "%", "HDR")) or _META_LINE.match(ln):
            continue
        if re.search(r"\b(year|yr|date|time|datetime|decimal_year)\b", low):
            first_kw = i if first_kw is None else first_kw
            nxt = next((x for x in lines[i + 1:i + 6] if x.strip()), "")
            if _looks_like_data(nxt):
                return i
    return first_kw or 0


def _header_missing(lines: list[str]) -> list[float]:
    """Fill values announced in header lines (Giovanni: 'Fill Value (var):,-9999.9')."""
    out = []
    for ln in lines[:200]:
        m = re.match(r"^\s*[#%]?\s*(?:_?fill[ _]?value|missing[ _]?value|nodata)[^,:=]*[:=,]\s*,?\s*([-+]?[\d.]+(?:[eE][-+]?\d+)?)", ln, re.I)
        if m:
            try:
                out.append(float(m.group(1)))
            except ValueError:
                pass
    return out


def _parse_matrix_grid(lines: list[str], cfg: dict) -> xr.Dataset | None:
    """Grid as a matrix: header = longitudes, first column = latitudes (NASA NEO CSV, many portals)."""
    if not lines:
        return None
    sep = "," if lines[0].count(",") >= 10 else ("\t" if lines[0].count("\t") >= 10 else None)
    if sep is None:
        return None
    head = [x.strip() for x in lines[0].split(sep)]
    try:
        lons = np.array([float(x) for x in head[1:] if x != ""])
    except ValueError:
        return None
    if lons.size < 10 or np.nanmax(np.abs(lons)) > 360:
        return None
    lats, rows = [], []
    for ln in lines[1:]:
        parts = ln.split(sep)
        try:
            la = float(parts[0])
            row = [float(x) if x.strip() not in ("", "NaN", "nan") else np.nan for x in parts[1:1 + lons.size]]
        except (ValueError, IndexError):
            return None
        if abs(la) > 90 or len(row) != lons.size:
            return None
        lats.append(la)
        rows.append(row)
    if len(lats) < 5:
        return None
    v = np.array(rows, dtype="float64")
    for mv in list(cfg.get("missing", [])) + [99999.0, -99999.0, -9999.0]:
        v[np.isclose(v, mv)] = np.nan
    name = cfg.get("variable") if isinstance(cfg.get("variable"), str) else "value"
    return xr.Dataset({name: (("lat", "lon"), v)}, coords={"lat": np.array(lats), "lon": lons})


def _decimal_years(y: pd.Series) -> pd.Series:
    """1993.0417 -> 1993-01-16 (mid-month-ish); integers stay Jan 1."""
    y = pd.to_numeric(y, errors="coerce")
    yr = np.floor(y)
    start = pd.to_datetime(yr.astype("Int64").astype(str) + "-01-01", errors="coerce")
    days = (y - yr) * np.where(((yr % 4 == 0) & (yr % 100 != 0)) | (yr % 400 == 0), 366, 365)
    return start + pd.to_timedelta(days, unit="D")


def frame_to_dataset(df: pd.DataFrame, cfg: dict) -> xr.Dataset:
    df = df.copy()
    df.columns = [str(c).strip() for c in df.columns]
    lower = {c.lower(): c for c in df.columns}
    missing = cfg.get("missing", MISSING_DEFAULT)
    want = cfg.get("variable")
    if isinstance(want, list):
        want = next((w for w in want if w in df.columns or w.lower() in lower), want[0])

    def col(*names):
        for n in names:
            if n in lower:
                return lower[n]
        return None

    year_c = col("year", "yr", "years")
    # --- wide monthly (GISTEMP tables: Year,Jan..Dec,J-D,...)
    if year_c and all(m in lower for m in MONTHS):
        rows = []
        for _, r in df.iterrows():
            try:
                y = int(float(r[year_c]))
            except (TypeError, ValueError):
                continue
            for mi, m in enumerate(MONTHS, 1):
                rows.append((np.datetime64(f"{y:04d}-{mi:02d}-01"), pd.to_numeric(r[lower[m]], errors="coerce")))
        t = np.array([r[0] for r in rows])
        v = np.array([r[1] for r in rows], dtype="float64")
        return _series_ds(t, v, want or "value", missing)

    # --- time column(s)
    date_c = col("date", "time", "datetime", "timestamp")
    month_c = col("month", "mo", "mon", "mm")
    day_c = col("day", "dd", "dy")
    dec_c = col("decimal_year", "decyear", "year_decimal", "time_decimal", "yearfrac", "year_frac")
    if date_c is None and dec_c is None and year_c is not None and month_c is None:
        yv = pd.to_numeric(df[year_c], errors="coerce")
        if (yv.dropna() % 1 != 0).mean() > 0.5:  # fractional years (sea level, GRACE time series ...)
            dec_c = year_c
    if cfg.get("time_format") == "decimal_year" and cfg.get("time_column"):
        dec_c = col(str(cfg["time_column"]).lower()) or dec_c
    if dec_c is not None and (date_c is None or cfg.get("time_format") == "decimal_year"):
        t = _decimal_years(df[dec_c])
        year_c = None if dec_c == year_c else year_c
        date_c = dec_c
    elif date_c is not None:
        tt = df[date_c].astype(str).str.strip()
        if tt.str.fullmatch(r"\d{6}").mean() > 0.8:  # YYYYMM
            t = pd.to_datetime(tt, format="%Y%m", errors="coerce")
        else:
            t = pd.to_datetime(tt, errors="coerce", utc=True).dt.tz_convert(None)
    elif year_c is not None:
        y = pd.to_numeric(df[year_c], errors="coerce")
        m = pd.to_numeric(df[month_c], errors="coerce") if month_c else pd.Series(np.ones(len(df)))
        d = pd.to_numeric(df[day_c], errors="coerce") if day_c else pd.Series(np.ones(len(df)))
        t = pd.to_datetime(dict(year=y, month=m, day=d), errors="coerce")
        if month_c is None and day_c is None:
            df["_annual"] = True
    else:
        raise DetectiveError("Table has no date/time or year column; set read.variable and add a 'date' column")

    lat_c, lon_c = col("lat", "latitude", "y"), col("lon", "longitude", "long", "x")
    skip = {c for c in (year_c, month_c, day_c, date_c, dec_c, lat_c, lon_c) if c}
    if want and (want in df.columns or want.lower() in lower):
        vcol = want if want in df.columns else lower[want.lower()]
    else:
        numeric = [c for c in df.columns if c not in skip and not c.startswith("_") and pd.to_numeric(df[c], errors="coerce").notna().mean() > 0.5]
        if not numeric:
            raise DetectiveError(f"No numeric value column found among {list(df.columns)}")
        vcol = numeric[0]
    vals = pd.to_numeric(df[vcol], errors="coerce").astype("float64")
    ok = t.notna().to_numpy()
    if lat_c and lon_c and df[lat_c].nunique() > 1:
        sub = pd.DataFrame({"time": t[ok].to_numpy(), "lat": pd.to_numeric(df[lat_c])[ok].to_numpy(), "lon": pd.to_numeric(df[lon_c])[ok].to_numpy(), "v": vals[ok].to_numpy()})
        cube = sub.set_index(["time", "lat", "lon"])["v"].to_xarray()
        for mv in missing:
            cube = cube.where(~np.isclose(cube, mv))
        return cube.rename(vcol).to_dataset()
    ds = _series_ds(t[ok].to_numpy().astype("datetime64[ns]"), vals[ok].to_numpy(), vcol, missing)
    if "_annual" in df.columns:
        ds.attrs["freq"] = "A"
    return ds


def _series_ds(t, v, name: str, missing) -> xr.Dataset:
    v = np.asarray(v, dtype="float64")
    for mv in missing:
        v[np.isclose(v, mv)] = np.nan
    order = np.argsort(t)
    return xr.Dataset({name: ("time", v[order])}, coords={"time": np.asarray(t)[order]})


def read_table(path: Path, cfg: dict) -> xr.Dataset:
    """CSV / TXT. Options in read: columns: [names] (headerless files), comment: ["HDR", "#"],
    skip_rows: N, time_column + time_format: decimal_year, missing: [values]."""
    text = Path(path).read_text(encoding="utf-8-sig", errors="replace")
    lines = [ln.rstrip("\n") for ln in text.splitlines()]
    prefixes = tuple(cfg.get("comment") or ("#", "%", "HDR"))
    if isinstance(cfg.get("comment"), str):
        prefixes = (cfg["comment"],)
    body = [ln for ln in lines[int(cfg.get("skip_rows", 0) or 0):] if not ln.lstrip().startswith(prefixes)]
    nonempty = [ln for ln in body if ln.strip()]
    cfg = dict(cfg)
    cfg["missing"] = list(cfg.get("missing", MISSING_DEFAULT)) + _header_missing(lines)
    if not cfg.get("columns"):
        for parser in (_parse_psl, _parse_oni, _parse_matrix_grid):
            ds = parser(nonempty, cfg)
            if ds is not None:
                return ds
    na = ["***", "****", "*****", "NaN", "nan", "NA", "", "--", "N/A"]
    if cfg.get("columns"):  # headerless numeric table, names given in the YAML
        chunk = "\n".join(ln for ln in nonempty if _looks_like_data(ln))
        df = pd.read_csv(io.StringIO(chunk), sep=r"[\s,;]+", engine="python", header=None, na_values=na)
        names = list(cfg["columns"])
        df = df.iloc[:, :len(names)]
        df.columns = names[:df.shape[1]]
        return frame_to_dataset(df, cfg)
    h = _find_header(body)
    chunk = "\n".join(body[h:])
    try:
        df = pd.read_csv(io.StringIO(chunk), sep=None, engine="python", skipinitialspace=True, na_values=na)
        if df.shape[1] < 2:
            raise ValueError("one column")
    except Exception:
        df = pd.read_csv(io.StringIO(chunk), sep=r"\s+", engine="python", na_values=na)
    return frame_to_dataset(df, cfg)


def read_excel(path: Path, cfg: dict) -> xr.Dataset:
    sheet = cfg.get("sheet", 0)
    raw = pd.read_excel(path, sheet_name=sheet, header=None)
    header = 0
    for i in range(min(40, len(raw))):
        row = " ".join(str(x).lower() for x in raw.iloc[i].tolist())
        if re.search(r"\b(year|date|time)\b", row):
            header = i
            break
    df = pd.read_excel(path, sheet_name=sheet, header=header)
    return frame_to_dataset(df, cfg)


def read_json_any(path: Path, cfg: dict) -> xr.Dataset:
    with open(path, "r", encoding="utf-8") as f:
        obj = json.load(f)
    if isinstance(obj, dict) and "properties" in obj and isinstance(obj["properties"], dict) and "parameter" in obj["properties"]:
        return read_power_json(obj, cfg)
    if isinstance(obj, dict) and obj.get("type") == "FeatureCollection":
        rows = []
        for feat in obj.get("features", []):
            props = dict(feat.get("properties") or {})
            geom = feat.get("geometry") or {}
            if geom.get("type") == "Point":
                props.setdefault("lon", geom["coordinates"][0])
                props.setdefault("lat", geom["coordinates"][1])
            rows.append(props)
        return frame_to_dataset(pd.DataFrame(rows), cfg)
    if isinstance(obj, dict):
        for key in ("data", "records", "items", "results", "values"):
            if isinstance(obj.get(key), list):
                obj = obj[key]
                break
    if isinstance(obj, list):
        return frame_to_dataset(pd.DataFrame(obj), cfg)
    raise DetectiveError(f"Unrecognised JSON layout in {path.name}")


def read_power_json(obj: dict, cfg: dict) -> xr.Dataset:
    """NASA POWER API JSON (monthly keys YYYYMM incl. YYYY13 annual, or daily YYYYMMDD)."""
    params = obj["properties"]["parameter"]
    fill = float(obj.get("header", {}).get("fill_value", -999.0))
    want = cfg.get("variable") or next(iter(params))
    if want not in params:
        raise DetectiveError(f"POWER parameter {want} not in response ({list(params)})")
    times, vals = [], []
    for k, v in params[want].items():
        if len(k) == 6:
            y, m = int(k[:4]), int(k[4:])
            if m == 13:
                continue
            times.append(np.datetime64(f"{y:04d}-{m:02d}-01"))
        elif len(k) == 8:
            times.append(np.datetime64(f"{k[:4]}-{k[4:6]}-{k[6:]}"))
        else:
            continue
        vals.append(np.nan if v is None or float(v) == fill else float(v))
    ds = _series_ds(np.array(times), np.array(vals), want, [fill])
    try:
        lon, lat = obj["geometry"]["coordinates"][:2]
        ds.attrs.update(lat=float(lat), lon=float(lon))
    except Exception:
        pass
    return ds


# ----------------------------------------------------------------------------- dispatcher
def open_one(path: Path, cfg: dict) -> xr.Dataset:
    fmt = cfg.get("format", "auto")
    if fmt in (None, "auto"):
        fmt = sniff(path)
    if fmt in ("hdf5", "netcdf3", "netcdf", "netcdf4"):
        return _open_netcdf_like(path, cfg, "hdf5" if fmt in ("hdf5", "netcdf4") else "netcdf3")
    if fmt == "hdf4":
        return _open_hdf4(path, cfg)
    if fmt in ("tiff", "geotiff"):
        return _open_tiff(path, cfg)
    if fmt == "zarr":
        return _open_zarr(path, cfg)
    if fmt == "grib":
        return _open_grib(path, cfg)
    if fmt == "excel":
        return read_excel(path, cfg)
    if fmt == "json":
        return read_json_any(path, cfg)
    if fmt in ("text", "csv"):
        return read_table(path, cfg)
    if fmt == "gzip":
        raise DetectiveError(f"{path.name} is gzip-compressed; set access.decompress: gzip")
    raise DetectiveError(f"Unsupported format {fmt!r} for {path.name}")


def _aux_vars(cfg: dict) -> list[str]:
    out = []
    for key in ("multiply_by", "mask_with"):
        spec = cfg.get(key)
        if isinstance(spec, dict) and spec.get("variable"):
            out.append(spec["variable"])
        elif isinstance(spec, str):
            out.append(spec)
    return out


def _select_vars(ds: xr.Dataset, cfg: dict) -> xr.Dataset:
    var = cfg.get("variable")
    names = var if isinstance(var, list) else ([var] if var else [])
    for n in names:
        if n in ds.data_vars:
            keep = [n] + [a for a in _aux_vars(cfg) if a in ds.data_vars and a != n]
            return ds[keep]
    return ds


def open_raw(paths: list[Path], cfg: dict) -> xr.Dataset:
    """Open one or many files into a single Dataset (concatenated along time)."""
    paths = [Path(p) for p in paths]
    if not paths:
        raise DetectiveError("No input files")
    if len(paths) == 1:
        return _select_vars(open_one(paths[0], cfg), cfg)
    coarsen = int(cfg.get("coarsen_on_read", 1) or 1)
    parts = []
    bad = 0
    for p in paths:
        try:
            ds = _select_vars(open_one(p, cfg), cfg)
        except DetectiveError:
            raise
        except Exception as e:  # one damaged file must not sink a 300-file dataset
            bad += 1
            log.warning("  skipping unreadable file %s (%s)", p.name, str(e)[:100])
            if bad > max(3, len(paths) // 5):
                raise DetectiveError(f"too many unreadable files ({bad}); last: {p.name}: {e}") from e
            continue
        if "time" not in ds.dims and "time" not in ds.coords:
            t = time_from_filename(p.name, cfg.get("time_regex"))
            if t is None:
                raise DetectiveError(f"Cannot find a date in {p.name}; set read.time_regex")
            ds = ds.expand_dims(time=[t.astype("datetime64[ns]")])
        if coarsen > 1:
            dims = {d: coarsen for d in ds.dims if d in ("lat", "lon", "latitude", "longitude", "y", "x", "XDim", "YDim")}
            if dims:
                ds = ds.coarsen(dims, boundary="trim").mean()
        parts.append(ds.load())
    try:
        out = xr.concat(parts, dim="time", data_vars="minimal", coords="minimal", compat="override", join="outer")
    except Exception:
        out = xr.concat(parts, dim="time")
    if "time" in out.dims:
        out = out.sortby("time")
        _, idx = np.unique(out["time"].values, return_index=True)
        out = out.isel(time=np.sort(idx))
    return out


# ----------------------------------------------------------------------------- inspect
def describe(ds: xr.Dataset) -> dict[str, Any]:
    info: dict[str, Any] = {"dims": {k: int(v) for k, v in ds.sizes.items()}, "variables": [], "coords": {}}
    for name, da in ds.data_vars.items():
        info["variables"].append({
            "name": name,
            "dims": list(da.dims),
            "shape": [int(s) for s in da.shape],
            "units": str(da.attrs.get("units", "")),
            "long_name": str(da.attrs.get("long_name", da.attrs.get("standard_name", ""))),
        })
    for c in ds.coords:
        vals = ds[c].values
        if vals.size and vals.ndim == 1:
            try:
                info["coords"][c] = [str(vals.min()), str(vals.max()), int(vals.size)]
            except Exception:
                info["coords"][c] = [str(vals[0]), str(vals[-1]), int(vals.size)]
    return info
