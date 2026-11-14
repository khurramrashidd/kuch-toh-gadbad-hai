"""Forensic trend statistics, vectorised over map cells.

Everything here works on arrays shaped (n_years, n_cells) so a whole planet is
tested at once; 1-D series are handled as one cell.

Methods (see docs/METHODS.md for references):
  * Mann-Kendall test with tie correction                     (Mann 1945; Kendall 1975)
  * autocorrelation corrections: lag-1 variance correction with
    small-sample bias correction, or Hamed & Rao (1998)
  * Sen's slope + confidence interval                         (Sen 1968; Gilbert 1987)
  * Benjamini-Hochberg false discovery rate                   (Benjamini & Hochberg 1995; Wilks 2016)
  * signal-to-noise and time of emergence                     (Hawkins & Sutton 2012)
  * years of data needed to detect a trend                    (Weatherhead et al. 1998)
  * Pettitt change-point test                                 (Pettitt 1979)
  * correlation with effective sample size                    (Bretherton et al. 1999)
"""
from __future__ import annotations

import math
import warnings

import numpy as np
from scipy import stats as sps

METHODS = ("none", "lag1", "hamed_rao")


def _as2d(Y):
    Y = np.asarray(Y, dtype="float64")
    if Y.ndim == 1:
        return Y[:, None], True
    return Y.reshape(Y.shape[0], -1), False


def _mk_s_var(Y: np.ndarray):
    n, m = Y.shape
    nv = np.isfinite(Y).sum(axis=0).astype("float64")
    S = np.zeros(m)
    for i in range(n - 1):
        d = Y[i + 1:] - Y[i]
        s = np.sign(d)
        s[~np.isfinite(d)] = 0.0
        S += s.sum(axis=0)
    # tie correction from runs of equal values in the sorted columns
    Ys = np.sort(Y, axis=0)
    tie = np.zeros(m)
    run = np.ones(m)
    for i in range(1, n):
        same = (Ys[i] == Ys[i - 1]) & np.isfinite(Ys[i])
        tie += np.where(~same & (run > 1), run * (run - 1) * (2 * run + 5), 0.0)
        run = np.where(same, run + 1, 1.0)
    tie += np.where(run > 1, run * (run - 1) * (2 * run + 5), 0.0)
    var = (nv * (nv - 1) * (2 * nv + 5) - tie) / 18.0
    return S, var, nv


def _sen(Y: np.ndarray, t: np.ndarray, alpha: float, var_s: np.ndarray):
    n, m = Y.shape
    ii, jj = np.triu_indices(n, k=1)
    dt = (t[jj] - t[ii]).astype("float64")
    npairs = len(ii)
    slope = np.full(m, np.nan)
    lo = np.full(m, np.nan)
    hi = np.full(m, np.nan)
    if npairs == 0:
        return slope, lo, hi
    z = sps.norm.ppf(1 - alpha / 2)
    chunk = max(1, int(1.2e7 // npairs))
    for c0 in range(0, m, chunk):
        Yc = Y[:, c0:c0 + chunk]
        P = (Yc[jj] - Yc[ii]) / dt[:, None]
        P.sort(axis=0)
        N = np.isfinite(P).sum(axis=0)
        has = N > 0
        Nn = np.maximum(N, 1)
        a = ((Nn - 1) // 2)[None, :]
        b = (Nn // 2)[None, :]
        med = 0.5 * (np.take_along_axis(P, a, 0)[0] + np.take_along_axis(P, b, 0)[0])
        C = z * np.sqrt(np.maximum(var_s[c0:c0 + chunk], 0))
        m1 = np.clip(np.round((Nn - C) / 2.0).astype(int) - 1, 0, Nn - 1)
        m2 = np.clip(np.round((Nn + C) / 2.0).astype(int), 0, Nn - 1)
        lo_c = np.take_along_axis(P, m1[None, :], 0)[0]
        hi_c = np.take_along_axis(P, m2[None, :], 0)[0]
        slope[c0:c0 + chunk] = np.where(has, med, np.nan)
        lo[c0:c0 + chunk] = np.where(has, lo_c, np.nan)
        hi[c0:c0 + chunk] = np.where(has, hi_c, np.nan)
    return slope, lo, hi


def _lag1(R: np.ndarray) -> np.ndarray:
    """Lag-1 autocorrelation per column of residuals (gaps skip pairs)."""
    with np.errstate(invalid="ignore", divide="ignore"):
        mu = np.nanmean(R, axis=0)
        X = R - mu
        a, b = X[:-1], X[1:]
        ok = np.isfinite(a) & np.isfinite(b)
        num = np.where(ok, a * b, 0.0).sum(axis=0)
        den = np.nansum(X * X, axis=0)
        return np.where(den > 0, num / den, np.nan)


def _lag1_factor(r1: np.ndarray, nv: np.ndarray) -> np.ndarray:
    rho = np.where(nv > 4, (nv * r1 + 1.0) / np.maximum(nv - 3.0, 1.0), r1)  # small-sample bias correction
    rho = np.clip(np.nan_to_num(rho, nan=0.0), 0.0, 0.9)  # conservative: never shrink the variance
    nmax = int(np.nanmax(nv)) if nv.size else 0
    k = np.arange(1, max(nmax, 2))[:, None].astype("float64")
    w = np.clip(1.0 - k / np.maximum(nv[None, :], 1), 0.0, None)
    return 1.0 + 2.0 * (w * rho[None, :] ** k).sum(axis=0)


def _hamed_rao_factor(R: np.ndarray, nv: np.ndarray, alpha: float = 0.05) -> np.ndarray:
    n, m = R.shape
    ranks = sps.rankdata(R, axis=0, nan_policy="omit")
    with np.errstate(invalid="ignore", divide="ignore"):
        X = ranks - np.nanmean(ranks, axis=0)
        den = np.nansum(X * X, axis=0)
        total = np.zeros(m)
        crit = sps.norm.ppf(1 - alpha / 2) / np.sqrt(np.maximum(nv, 1))
        for k in range(1, n - 1):
            a, b = X[:-k], X[k:]
            ok = np.isfinite(a) & np.isfinite(b)
            rk = np.where(den > 0, np.where(ok, a * b, 0.0).sum(axis=0) / den, 0.0)
            rk = np.where(np.abs(rk) > crit, rk, 0.0)
            total += (nv - k) * (nv - k - 1) * (nv - k - 2) * rk
        factor = 1.0 + 2.0 / np.maximum(nv * (nv - 1) * (nv - 2), 1.0) * total
    return np.where(np.isfinite(factor) & (factor > 0), factor, 1.0)


def mk_trend(Y, t, method: str = "lag1", alpha: float = 0.05, min_years: int = 10) -> dict:
    """Mann-Kendall + Sen's slope (+ noise, emergence, detectability) for every column."""
    with warnings.catch_warnings():
        warnings.simplefilter("ignore", RuntimeWarning)
        return _mk_trend(Y, t, method, alpha, min_years)


def _mk_trend(Y, t, method, alpha, min_years) -> dict:
    if method not in METHODS:
        raise ValueError(f"method must be one of {METHODS}")
    Y2, single = _as2d(Y)
    t = np.asarray(t, dtype="float64")
    n, m = Y2.shape
    S, var_raw, nv = _mk_s_var(Y2)
    # slope first (needed for detrended residuals), with uncorrected variance for now
    slope, _, _ = _sen(Y2, t, alpha, var_raw)
    # detrend on time relative to the first year: keeps rounding small so exact
    # Sen-slope ties in the residual ranks survive (matches reference implementations)
    tr = t - (t[0] if n else 0.0)
    with np.errstate(invalid="ignore"):
        icpt_rel = np.nanmedian(Y2 - slope[None, :] * tr[:, None], axis=0) if n else np.full(m, np.nan)
    resid = Y2 - (icpt_rel[None, :] + slope[None, :] * tr[:, None])
    intercept = icpt_rel - slope * (t[0] if n else 0.0)
    r1 = _lag1(resid)
    if method == "none":
        factor = np.ones(m)
    elif method == "lag1":
        factor = _lag1_factor(r1, nv)
    else:
        # rank the plain detrended series, rounded so genuine ties stay ties
        factor = _hamed_rao_factor(np.round(Y2 - slope[None, :] * (tr[:, None] + 1.0), 9), nv, alpha)
    var_c = var_raw * factor
    _, lo, hi = _sen(Y2, t, alpha, var_c)
    with np.errstate(invalid="ignore", divide="ignore"):
        sd = np.sqrt(var_c)
        sd_raw = np.sqrt(var_raw)
        z = np.where(S > 0, (S - 1) / sd, np.where(S < 0, (S + 1) / sd, 0.0))
        z_raw = np.where(S > 0, (S - 1) / sd_raw, np.where(S < 0, (S + 1) / sd_raw, 0.0))
        p = 2 * sps.norm.sf(np.abs(z))
        p_raw = 2 * sps.norm.sf(np.abs(z_raw))
        sigma = np.nanstd(resid, axis=0, ddof=1)
        valid = np.isfinite(Y2)
        first = np.where(valid.any(0), valid.argmax(0), 0)
        last = np.where(valid.any(0), n - 1 - valid[::-1].argmax(0), 0)
        t0, t1 = t[first], t[last]
        span = t1 - t0
        abs_s = np.abs(slope)
        snr = abs_s * span / sigma
        toe1 = np.where(abs_s > 0, t0 + 1.0 * sigma / abs_s, np.inf)
        toe2 = np.where(abs_s > 0, t0 + 2.0 * sigma / abs_s, np.inf)
        phi = np.clip(np.nan_to_num(r1, nan=0.0), 0.0, 0.95)
        years_needed = np.where(abs_s > 0, ((3.3 * math.sqrt(12.0) * sigma / abs_s) * np.sqrt((1 + phi) / (1 - phi))) ** (2.0 / 3.0), np.inf)
    bad = nv < max(3, min_years)
    out = {
        "n": nv, "S": S, "var_s": var_c, "factor": factor, "z": z, "p": p, "p_raw": p_raw,
        "slope": slope, "ci_lo": lo, "ci_hi": hi, "intercept": intercept,
        "sigma": sigma, "r1": r1, "snr": snr, "t0": t0, "t1": t1,
        "toe1": toe1, "toe2": toe2, "years_needed": years_needed,
    }
    for k in out:
        if k != "n":
            out[k] = np.where(bad, np.nan, out[k])
    if single:
        return {k: (float(v[0]) if np.ndim(v) else float(v)) for k, v in out.items()}
    shape = np.asarray(Y).shape[1:]
    return {k: v.reshape(shape) for k, v in out.items()}


def fdr_bh(p) -> np.ndarray:
    """Benjamini-Hochberg q-values (NaN-safe)."""
    p = np.asarray(p, dtype="float64")
    flat = p.ravel()
    ok = np.isfinite(flat)
    pv = flat[ok]
    out = np.full_like(flat, np.nan)
    m = pv.size
    if m:
        order = np.argsort(pv)
        ranked = pv[order] * m / np.arange(1, m + 1)
        q = np.minimum.accumulate(ranked[::-1])[::-1]
        tmp = np.empty(m)
        tmp[order] = np.clip(q, 0, 1)
        out[ok] = tmp
    return out.reshape(p.shape)


def pettitt(x, t) -> dict | None:
    """Pettitt (1979) single change-point test. Returns the first year of the new regime."""
    x = np.asarray(x, dtype="float64")
    t = np.asarray(t)
    ok = np.isfinite(x)
    xv, tv = x[ok], t[ok]
    n = xv.size
    if n < 8:
        return None
    r = sps.rankdata(xv)
    U = 2 * np.cumsum(r) - np.arange(1, n + 1) * (n + 1)
    k = int(np.argmax(np.abs(U[:-1])))
    K = float(abs(U[k]))
    p = float(min(1.0, 2 * math.exp(-6 * K * K / (n**3 + n**2))))
    return {
        "year": int(tv[k + 1]),
        "p": p,
        "K": K,
        "mean_before": float(np.mean(xv[: k + 1])),
        "mean_after": float(np.mean(xv[k + 1:])),
    }


def lag1_series(x) -> float:
    x = np.asarray(x, dtype="float64")
    return float(_lag1(x[:, None])[0])


def detrend_ols(y, t):
    y = np.asarray(y, dtype="float64")
    t = np.asarray(t, dtype="float64")
    ok = np.isfinite(y)
    out = np.full_like(y, np.nan)
    if ok.sum() < 3:
        return out, np.nan
    b, a = np.polyfit(t[ok], y[ok], 1)
    out[ok] = y[ok] - (a + b * t[ok])
    return out, float(b)


def corr_eff(x, y) -> dict:
    """Pearson r with a p-value using the effective sample size for autocorrelated series."""
    x = np.asarray(x, dtype="float64")
    y = np.asarray(y, dtype="float64")
    ok = np.isfinite(x) & np.isfinite(y)
    n = int(ok.sum())
    if n < 6:
        return {"r": np.nan, "p": np.nan, "n": n, "n_eff": np.nan}
    xv, yv = x[ok], y[ok]
    if np.std(xv) == 0 or np.std(yv) == 0:
        return {"r": np.nan, "p": np.nan, "n": n, "n_eff": np.nan}
    r = float(np.corrcoef(xv, yv)[0, 1])
    rx = np.nan_to_num(lag1_series(np.where(ok, x, np.nan)), nan=0.0)
    ry = np.nan_to_num(lag1_series(np.where(ok, y, np.nan)), nan=0.0)
    prod = max(-0.95, min(0.95, rx * ry))
    n_eff = float(np.clip(n * (1 - prod) / (1 + prod), 4, n))
    tstat = r * math.sqrt(max(n_eff - 2, 1) / max(1e-12, 1 - r * r))
    p = float(2 * sps.t.sf(abs(tstat), max(n_eff - 2, 1)))
    return {"r": r, "p": p, "n": n, "n_eff": n_eff}


def fingerprint(region, driver, years) -> dict:
    """Does the driver's year-to-year wiggle predict the region's long-term trend?

    1. remove the linear trend from both series,
    2. regress region wiggles on driver wiggles -> sensitivity beta (per driver unit),
    3. predicted trend = beta x driver trend; explained = predicted / observed trend.
    Also reports the plain co-trend correlation (weaker evidence: any two trending
    series correlate).
    """
    region = np.asarray(region, dtype="float64")
    driver = np.asarray(driver, dtype="float64")
    years = np.asarray(years, dtype="float64")
    ok = np.isfinite(region) & np.isfinite(driver)
    res = {"n": int(ok.sum())}
    if ok.sum() < 10:
        res.update(beta=np.nan, r=np.nan, p=np.nan, explained=np.nan, cotrend_r=np.nan, cotrend_p=np.nan)
        return res
    rr, region_slope = detrend_ols(np.where(ok, region, np.nan), years)
    dd, driver_slope = detrend_ols(np.where(ok, driver, np.nan), years)
    m = np.isfinite(rr) & np.isfinite(dd)
    var_d = float(np.var(dd[m]))
    beta = float(np.cov(dd[m], rr[m], bias=True)[0, 1] / var_d) if var_d > 0 else np.nan
    c = corr_eff(dd, rr)
    co = corr_eff(np.where(ok, driver, np.nan), np.where(ok, region, np.nan))
    predicted = beta * driver_slope if np.isfinite(beta) else np.nan
    explained = predicted / region_slope if region_slope not in (0.0,) and np.isfinite(region_slope) else np.nan
    res.update(
        beta=beta, r=c["r"], p=c["p"], n_eff=c["n_eff"],
        region_slope=region_slope, driver_slope=driver_slope,
        predicted_slope=predicted, explained=explained,
        cotrend_r=co["r"], cotrend_p=co["p"],
    )
    return res


def trend_1d(y, t, method: str = "lag1", alpha: float = 0.05, min_years: int = 10) -> dict:
    """Full evidence for one series: MK/Sen + change point."""
    res = mk_trend(np.asarray(y, dtype="float64"), t, method=method, alpha=alpha, min_years=min_years)
    res["pettitt"] = pettitt(y, t)
    res["method"] = method
    return res


def segment_trends(y, t, split_year: int, method: str = "lag1", alpha: float = 0.05) -> dict:
    """Trend before and after a break (does the trend survive the alibi check?)."""
    y = np.asarray(y, dtype="float64")
    t = np.asarray(t)
    a = t < split_year
    b = t >= split_year
    out = {}
    for key, msk in (("before", a), ("after", b)):
        if np.isfinite(y[msk]).sum() >= 6:
            r = mk_trend(y[msk], t[msk], method=method, alpha=alpha, min_years=6)
            out[key] = {"slope": r["slope"], "p": r["p"], "n": r["n"]}
        else:
            out[key] = None
    return out


def ols_slope(y, t) -> float:
    y = np.asarray(y, dtype="float64")
    t = np.asarray(t, dtype="float64")
    ok = np.isfinite(y)
    if ok.sum() < 3:
        return float("nan")
    return float(np.polyfit(t[ok], y[ok], 1)[0])
