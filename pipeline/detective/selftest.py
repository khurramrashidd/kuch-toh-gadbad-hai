"""'How do we know the detective is honest?'

1. False alarms: on pure red noise (no trend) a 5% test should cry "trend" ~5%
   of the time. Plain Mann-Kendall does far worse when years are correlated.
2. Power: how often a real trend is caught.
3. Mirror test: two regions driven by one driver with opposite sensitivity must
   be flagged "same cause"; two unrelated opposite trends must NOT be.
4. Benchmarks: our numbers vs published NASA/NSIDC values (when data are built).
"""
from __future__ import annotations

import math

import numpy as np

from . import stats
from .engine import Context
from .util import log, now_iso, write_json


def ar1(n: int, m: int, phi: float, rng) -> np.ndarray:
    e = rng.normal(size=(n, m))
    x = np.zeros((n, m))
    x[0] = e[0] / math.sqrt(max(1e-9, 1 - phi * phi))
    for i in range(1, n):
        x[i] = phi * x[i - 1] + e[i]
    return x * math.sqrt(1 - phi * phi)  # unit variance


def false_alarms(sims: int = 2000, seed: int = 7) -> list[dict]:
    rng = np.random.default_rng(seed)
    rows = []
    for n in (25, 45):
        t = np.arange(n, dtype="float64")
        for phi in (0.0, 0.3, 0.6):
            noise = ar1(n, sims, phi, rng)
            trend = noise + (1.5 / n) * t[:, None] * 1.0  # total change = 1.5 noise SD over the record
            row = {"n_years": n, "autocorr": phi}
            for method in stats.METHODS:
                fa = stats.mk_trend(noise, t, method=method, min_years=5)["p"]
                pw = stats.mk_trend(trend, t, method=method, min_years=5)["p"]
                row[f"false_alarm_{method}"] = float(np.mean(fa < 0.05))
                row[f"power_{method}"] = float(np.mean(pw < 0.05))
            rows.append(row)
            log.info("    n=%d phi=%.1f  false alarms: none %.0f%%  lag1 %.0f%%  HR %.0f%%", n, phi,
                     100 * row["false_alarm_none"], 100 * row["false_alarm_lag1"], 100 * row["false_alarm_hamed_rao"])
    return rows


def slope_recovery(sims: int = 1000, seed: int = 11) -> dict:
    rng = np.random.default_rng(seed)
    n = 40
    t = np.arange(n, dtype="float64")
    true = rng.uniform(-0.1, 0.1, size=sims)
    y = ar1(n, sims, 0.3, rng) + true[None, :] * t[:, None]
    r = stats.mk_trend(y, t, method="lag1", min_years=5)
    err = r["slope"] - true
    cover = np.mean((r["ci_lo"] <= true) & (true <= r["ci_hi"]))
    return {"n_years": n, "bias": float(np.mean(err)), "rmse": float(np.sqrt(np.mean(err**2))), "ci95_coverage": float(cover)}


def mirror_test(sims: int = 300, seed: int = 3, driver_p: float = 0.10, explained_min: float = 0.25) -> dict:
    """Shared driver vs. two unrelated opposite trends."""
    rng = np.random.default_rng(seed)
    n = 40
    years = np.arange(1985, 1985 + n, dtype="float64")
    hit, false_hit = 0, 0
    for _ in range(sims):
        driver = 0.02 * (years - years[0]) + ar1(n, 1, 0.4, rng)[:, 0] * 0.15
        a = 1.5 * driver + rng.normal(0, 0.12, n)
        b = -1.2 * driver + rng.normal(0, 0.12, n)
        fa, fb = stats.fingerprint(a, driver, years), stats.fingerprint(b, driver, years)
        ok = all(fp["p"] < driver_p and (fp["explained"] or 0) >= explained_min for fp in (fa, fb))
        hit += ok
        # negative control: opposite trends from DIFFERENT causes; driver is unrelated
        a2 = 0.03 * (years - years[0]) + ar1(n, 1, 0.3, rng)[:, 0] * 0.2
        b2 = -0.025 * (years - years[0]) + ar1(n, 1, 0.3, rng)[:, 0] * 0.2
        fa2, fb2 = stats.fingerprint(a2, driver, years), stats.fingerprint(b2, driver, years)
        bad = all(fp["p"] < driver_p and (fp["explained"] or 0) >= explained_min for fp in (fa2, fb2))
        false_hit += bad
    return {"sims": sims, "shared_driver_detected": hit / sims, "false_shared_driver": false_hit / sims,
            "note": "Negative control: both series trend in opposite directions but are unrelated to the driver's year-to-year swings."}


def benchmarks(ctx: Context) -> list[dict]:
    out = []
    for src in ctx.sources.values():
        for b in src.benchmarks or []:
            row = {"source": src.id, "title": b.get("title", src.title), "expected": b["expected"], "tolerance": b.get("tolerance", 0),
                   "units": b.get("units", ""), "reference": b.get("reference", ""), "url": b.get("url", "")}
            try:
                s = ctx.series(src.id, season=b.get("season", "ANN"), period={"start": b["period"][0], "end": b["period"][1]})
                y, v = s["years"], s["values"]
                slope = stats.ols_slope(v, y) if b.get("method", "ols") == "ols" else stats.mk_trend(v, y)["slope"]
                if b.get("as") == "percent_per_decade":
                    bl = b.get("baseline", [1981, 2010])
                    ref = np.nanmean(v[(y >= bl[0]) & (y <= bl[1])])
                    value = slope * 10 / ref * 100
                else:
                    value = slope * 10 * float(b.get("multiply", 1.0))
                row["ours"] = float(value)
                row["pass"] = bool(abs(value - b["expected"]) <= b.get("tolerance", 0))
            except Exception as e:
                row["ours"] = None
                row["pass"] = None
                row["error"] = str(e)
            out.append(row)
            log.info("    benchmark %s: ours %s vs published %s -> %s", row["title"], row.get("ours"), row["expected"], row.get("pass"))
    return out


def run_selftest(ctx: Context, quick: bool = False) -> dict:
    log.info("[selftest] Monte Carlo false-alarm test")
    sims = 400 if quick else 2000
    res = {
        "generated_at": now_iso(),
        "false_alarms": false_alarms(sims=sims),
        "slope_recovery": slope_recovery(sims=300 if quick else 1000),
        "mirror": mirror_test(sims=100 if quick else 300, driver_p=ctx.cfg.mirror["driver_p"], explained_min=ctx.cfg.mirror["explained_min"]),
        "benchmarks": benchmarks(ctx),
        "chosen_method": ctx.cfg.analysis["series_method"],
    }
    m = res["mirror"]
    log.info("    mirror test: shared driver found %.0f%%, false 'same cause' %.0f%%", 100 * m["shared_driver_detected"], 100 * m["false_shared_driver"])
    write_json(ctx.cfg.output_dir / "selftest.json", res)
    return res
