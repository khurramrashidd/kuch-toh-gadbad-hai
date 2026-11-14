# Methods — how the detective decides

Code: `pipeline/detective/stats.py` (vectorised over every map cell), `mirror.py`, `engine.py`;
the same trend statistics are ported to Dart in `app/lib/stats/trend.dart` (verified against Python
with `app/tool/stats_golden_check.dart`).

## 1. From any file to a comparable yearly series
1. **Standard cube.** Every dataset is converted to monthly values on `(time, lat, lon)` (or a single
   series), longitudes −180…180, latitudes ascending, physical units. Daily/8-day data → monthly means.
2. **Seasons.** One value per year for the whole year (ANN), the monsoon (JJAS), winter (DJF, December
   counted with the following year) or single months (e.g. SEP for the sea-ice minimum). A year counts
   only if enough months are present (`min_coverage`, e.g. 75%). Half-finished current years never enter.
3. **Anomalies** relative to the WMO 1991–2020 normal (the trend does not depend on this, the charts do).
4. Cells with fewer than 80% valid years in the period are left out (shown as "not enough data").

## 2. Is it changing? (signal vs noise)
* **Mann-Kendall test** (Mann 1945; Kendall 1975) with tie correction — distribution-free, robust to outliers.
* **Autocorrelation correction.** Climate years "remember" each other (lag-1 autocorrelation), which makes
  the textbook test cry wolf. We inflate the variance of S by `1 + 2 Σ (1 − k/n) ρ^k` using the lag-1
  autocorrelation of the detrended residuals, bias-corrected for short records `ρ̂ = (n·r₁ + 1)/(n − 3)`,
  clipped to [0, 0.9] (never makes a result *more* significant). Hamed & Rao (1998) is implemented too.
  Our own Monte Carlo (pipeline `selftest`, shown in the app) chose lag-1 because it kept false alarms
  at 4–9% (target 5%) where the plain test reached 26–30% and Hamed-Rao 20–26% (25–45 years, ρ = 0.6).
* **Sen's slope** (Sen 1968) with a 95% confidence interval from the ordered pairwise slopes (Gilbert 1987),
  using the corrected variance. Reported per decade (rainfall and sea ice as % of the 1991–2020 normal).
* **Many map cells = many tests.** Benjamini–Hochberg **false discovery rate** across all cells at
  α_FDR = 0.10, as recommended for spatially correlated fields by Wilks (2016, BAMS) to give roughly
  a 5% global error rate. Stippled cells survive FDR; faded cells are "not proven".
* **Verdicts**: *Confirmed* = significant (p < 0.05; q < 0.10 on maps) **and** total change ≥ 1× the
  year-to-year noise; *Likely* = p < 0.10; *Not proven yet* otherwise; *Artifact suspected* (see 4);
  *Not enough data* when fewer than 15 valid years. "Not proven" never means "no change".

## 3. Timeline
* **Signal-to-noise** = |slope| × record length / σ(residuals).
* **Time of emergence** (Hawkins & Sutton 2012 idea): the year the fitted change first exceeds 1σ
  (and 2σ) of natural year-to-year noise. Only reported for trends that are at least *Likely*.
* **Years needed** (Weatherhead et al. 1998, JGR 103:17149): years of data required to detect the
  current slope with 90% probability at 5% significance,
  `n* = [ (3.3·√12·σ / |ω|) · √((1+φ)/(1−φ)) ]^(2/3)` for annual data (σ noise SD, ω slope per year,
  φ lag-1 autocorrelation). Turns "not significant" into "come back in N years".

## 4. Alibi check (instrument artifacts)
* **Pettitt (1979)** single change-point test on each region/series.
* If a significant break (p < 0.05) falls within ±1 year of a known **instrument transition** listed in
  the dataset YAML (e.g. GRACE ended Jun 2017, GRACE-FO began Jun 2018; OMI row anomaly 2007), the trend
  is re-tested **before and after** the break. Same direction on both sides → the trend survives the
  alibi; otherwise → *Artifact suspected* and the case cannot be a mirror.

## 5. Mirror cases and the motive
* **Where:** connected clusters of FDR-significant cells of each sign (8-connectivity, joined across the
  dateline), ranked by area × mean |z|; or a fixed box (e.g. North-West India). Region series are
  area-weighted (cos latitude) means of anomalies.
* **Is it a mirror?** Both sides significant (p < 0.05), opposite signs, neither side an artifact.
* **Motive — fingerprint test.** For each suspect driver D (global mean temperature from GISTEMP,
  El Niño/ONI, Indian Ocean Dipole, CO₂, or a *local* variable such as rainfall over the same region):
  1. remove the linear trend from the region series and from D;
  2. regress region wiggles on driver wiggles → sensitivity β; correlation tested with an
     **effective sample size** n_eff = n(1 − r_x r_y)/(1 + r_x r_y) (Bretherton et al. 1999);
  3. predicted trend = β × trend(D); explained share = predicted / observed.
  *Prime suspect*: both regions p < 0.10, predicted directions match the observed opposite trends,
  each explains ≥ 25%. *Person of interest*: one side passes, the other points the right way (p < 0.25).
  **Co-trends alone never count** — any two trending series correlate. The selftest's negative
  control (opposite trends from unrelated causes) checks that this rule does not convict the innocent.
* **Local alibi.** If a local suspect (e.g. rainfall over NW India) shows no matching trend or
  fingerprint, it is cleared and the case points to another culprit (e.g. groundwater pumping, as
  NASA GRACE scientists reported: Rodell, Velicogna & Famiglietti 2009, Nature 460:999).
* **Witnesses.** Optional second datasets resampled onto the same regions must agree in sign (p < 0.10).
* **Evidence strength** (0–100): 20 per passed check, 10 per warning, 8 if a check is not applicable;
  capped at 30–40 when the mirror itself is not proven.

## 6. Honesty tests (`python -m detective selftest`)
* False-alarm rate and power for none / lag-1 / Hamed-Rao on AR(1) noise (n = 25, 45; φ = 0, 0.3, 0.6).
* Sen-slope bias, RMSE and 95% CI coverage.
* Mirror test: shared-driver detection rate on synthetic shared-cause pairs, and false "same cause"
  verdicts on the negative control.
* Benchmarks against published values (e.g. NSIDC/NASA September Arctic sea-ice decline,
  1979–2025, % per decade vs 1981–2010).

## 7. AI narrator guard-rails
Gemini (Firebase AI Logic) only sees the evidence JSON. Every number it writes must match a number in
the evidence at its shown precision, otherwise the answer is discarded and the pipeline's template is
shown. Accepted answers are cached in Firestore; the screen labels which kind of text you are reading.

## Limits
Trends describe the observed period; they are not forecasts. A shared driver is evidence of a common
process, not proof of causation. Coarse grids (1–2.5°) smooth local detail. GRACE resolves ~300 km
mascons. Reanalysis and gridded products inherit their own input changes — hence the alibi check.

## References
Benjamini & Hochberg 1995, JRSS-B 57:289 · Bretherton et al. 1999, J. Climate 12:1990 · Gilbert 1987,
*Statistical Methods for Environmental Pollution Monitoring* · Hamed & Rao 1998, J. Hydrol. 204:182 ·
Hawkins & Sutton 2012, GRL 39:L01702 · Kendall 1975, *Rank Correlation Methods* · Mann 1945, Econometrica
13:245 · Pettitt 1979, Appl. Stat. 28:126 · Rodell et al. 2009, Nature 460:999 · Sen 1968, JASA 63:1379 ·
Weatherhead et al. 1998, JGR 103:17149 · Wilks 2016, BAMS 97:2263.
