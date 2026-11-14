"""Run with:  python -m pytest -q   (from the pipeline folder)"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
import pandas as pd
import pytest
import xarray as xr

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from detective import aggregate as agg  # noqa: E402
from detective import canonical, readers, stats  # noqa: E402
from detective.registry import load_config, source_from_dict  # noqa: E402


def _src(**kw):
    d = {"id": "t", "title": "t", "kind": "grid", "access": {"method": "local", "path": "x"}}
    d.update(kw)
    return source_from_dict(d)


# --------------------------------------------------------------------------- readers
def test_netcdf_0_360_descending_lat_daily_time(tmp_path):
    t = pd.date_range("2000-01-01", "2001-12-31", freq="D")
    lat = np.array([10.0, 0.0, -10.0])
    lon = np.array([0.0, 120.0, 240.0])
    v = np.random.default_rng(0).normal(size=(len(t), 3, 3))
    ds = xr.Dataset({"precip": (("time", "latitude", "longitude"), v)},
                    coords={"time": ("time", np.arange(len(t)), {"units": "days since 2000-01-01"}), "latitude": lat, "longitude": lon})
    p = tmp_path / "a.nc"
    ds.to_netcdf(p)
    raw = readers.open_raw([p], {"variable": "precip"})
    da = canonical.to_canonical(raw, _src(read={"variable": "precip"}))
    assert da.dims == ("time", "lat", "lon")
    assert list(da["lat"].values) == [-10.0, 0.0, 10.0]
    assert list(da["lon"].values) == [-120.0, 0.0, 120.0]
    assert da.sizes["time"] == 24  # daily -> monthly


def test_gistemp_wide_table(tmp_path):
    p = tmp_path / "GLB.csv"
    p.write_text("Land-Ocean: Global Means\nYear,Jan,Feb,Mar,Apr,May,Jun,Jul,Aug,Sep,Oct,Nov,Dec,J-D\n"
                 "2000,.1,.2,.3,.4,.5,.6,.7,.8,.9,1,1.1,1.2,.65\n2001,***,.2,.3,.4,.5,.6,.7,.8,.9,1,1.1,1.2,***\n")
    ds = readers.open_raw([p], {"variable": "value"})
    v = ds[list(ds.data_vars)[0]]
    assert v.sizes["time"] == 24 and np.isnan(v.values[12])


def test_psl_and_oni_and_nsidc(tmp_path):
    psl = tmp_path / "dmi.data"
    psl.write_text(" 2000 2001\n 2000 " + " ".join(["0.1"] * 12) + "\n 2001 " + " ".join(["-99.99"] * 12) + "\n  -99.99\n note\n")
    ds = readers.open_raw([psl], {})
    assert int(np.isfinite(ds[list(ds.data_vars)[0]].values).sum()) == 12
    oni = tmp_path / "oni.txt"
    oni.write_text("SEAS  YR   TOTAL   ANOM\n  DJF 2000  24.7  -1.5\n  JFM 2000  25.1  -1.3\n")
    ds = readers.open_raw([oni], {})
    assert ds[list(ds.data_vars)[0]].values.tolist() == [-1.5, -1.3]
    ns = tmp_path / "N_09_extent_v4.0.csv"
    ns.write_text("year, mo, source_dataset, region, extent, area\n1979,  9, x, N, 7.05, 4.58\n1980,  9, x, N, -9999, -9999\n")
    ds = readers.open_raw([ns], {"variable": "extent"})
    vals = ds["extent"].values
    assert vals[0] == 7.05 and np.isnan(vals[1])


def test_power_json(tmp_path):
    obj = {"geometry": {"coordinates": [77.2, 28.6, 200]}, "header": {"fill_value": -999},
           "properties": {"parameter": {"T2M": {"200001": 14.0, "200002": -999, "200013": 25.0}}}}
    p = tmp_path / "power.json"
    p.write_text(json.dumps(obj))
    ds = readers.open_raw([p], {"variable": "T2M"})
    assert ds["T2M"].sizes["time"] == 2 and np.isnan(ds["T2M"].values[1])


def test_sniff_magic(tmp_path):
    p = tmp_path / "noext"
    xr.Dataset({"a": ("x", [1, 2])}).to_netcdf(p, engine="netcdf4")
    assert readers.sniff(p) == "hdf5"


def test_filename_dates():
    assert str(readers.time_from_filename("MOD13C2.A2010182.061.hdf"))[:10] == "2010-07-01"
    assert str(readers.time_from_filename("x_201507.nc"))[:7] == "2015-07"


# --------------------------------------------------------------------------- aggregation
def test_djf_belongs_to_next_year():
    t = pd.date_range("2000-01-01", "2002-12-01", freq="MS")
    da = xr.DataArray(np.arange(len(t), dtype=float), dims="time", coords={"time": t})
    da.attrs["freq"] = "M"
    years, vals = agg.seasonal_series(da, "DJF", min_coverage=1.0)
    i = list(years).index(2001)
    assert vals[i] == pytest.approx((11 + 12 + 13) / 3)  # Dec-2000, Jan-2001, Feb-2001


def test_region_mean_area_weighted():
    lat = np.array([0.0, 60.0])
    v = np.array([[[1.0], [3.0]]])
    m = np.ones((2, 1), bool)
    assert agg.region_mean(v, lat, m)[0] == pytest.approx((1 * 1 + 3 * 0.5) / 1.5)


# --------------------------------------------------------------------------- stats
def test_mk_matches_textbook_and_detects_trend():
    rng = np.random.default_rng(1)
    t = np.arange(40, dtype=float)
    y = 0.05 * t + rng.normal(0, 0.3, 40)
    r = stats.mk_trend(y, t, method="lag1")
    assert r["p"] < 0.001 and 0.04 < r["slope"] < 0.06 and r["ci_lo"] < r["slope"] < r["ci_hi"]
    flat = stats.mk_trend(rng.normal(size=40), t)
    assert flat["p"] > 0.01


def test_vectorised_equals_single_with_gaps():
    rng = np.random.default_rng(2)
    Y = rng.normal(size=(30, 7))
    Y[5, 2] = np.nan
    t = np.arange(30.0)
    v = stats.mk_trend(Y, t)
    for j in range(7):
        s = stats.mk_trend(Y[:, j], t)
        assert s["p"] == pytest.approx(v["p"][j]) and s["slope"] == pytest.approx(v["slope"][j])


def test_fdr_monotone():
    q = stats.fdr_bh(np.array([0.001, 0.01, 0.03, 0.5]))
    assert np.all(np.diff(q) >= -1e-12) and q[-1] == pytest.approx(0.5)


def test_fingerprint_shared_vs_unrelated():
    rng = np.random.default_rng(5)
    yrs = np.arange(1980, 2020, dtype=float)
    d = 0.02 * (yrs - 1980) + rng.normal(0, 0.15, 40)
    a = 1.5 * d + rng.normal(0, 0.1, 40)
    assert stats.fingerprint(a, d, yrs)["p"] < 0.01
    b = -0.03 * (yrs - 1980) + rng.normal(0, 0.15, 40)
    assert stats.fingerprint(b, d, yrs)["p"] > 0.05  # trends opposite, but no shared wiggles


def test_pettitt_finds_step():
    x = np.r_[np.zeros(15), np.ones(15)] + np.random.default_rng(3).normal(0, 0.2, 30)
    assert stats.pettitt(x, np.arange(2000, 2030))["year"] == 2015


def test_config_loads():
    cfg = load_config()
    assert cfg.analysis["fdr_alpha"] == 0.10
