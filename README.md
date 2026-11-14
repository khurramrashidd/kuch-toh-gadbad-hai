# Kuch Toh Gadbad Hai — Earth System Trend Detective 🕵️🌍

> *"Something's fishy with Earth."* NASA data. Real statistics. No WhatsApp forwards.

NASA Space Apps Challenge 2026 · **Be An Earth System Trend Detective!**

The challenge asks: using variables measured by NASA missions or produced by NASA models,
**what** is changing, **where**, **how much**, and **is it statistically significant?** It also
points out that a variable can trend one way in one region and the opposite way in another,
*even when the same process drives both*.

This project answers that last point head-on:

| Feature | What it does |
|---|---|
| **Mirror Cases** | Finds places where the same variable moves in *opposite* directions, then tests whether one driver's year-to-year fingerprint explains **both** (or whether a local suspect has an alibi). |
| **My Place, 40 years** | GPS, city search or a tap on the map → 40+ years of NASA POWER data for that exact spot, run live through the same statistical tests on the phone. |
| **Explore** | Planet-wide trend maps (GISTEMP temperature, GPCP rainfall, GRACE water storage, …) with false-discovery-rate stippling and a tap-to-interrogate readout. |
| **How we know** | Monte Carlo honesty tests (false-alarm rates), a synthetic mirror test, benchmarks against published NASA/NSIDC numbers, full citations. |
| **5-check evidence board** | Witnesses · Signal vs noise · Alibi check (instrument changes) · Timeline (time of emergence) · Motive (shared driver). |
| **English + हिंदी** | Every screen and every verdict in both languages; the AI narrator writes in both too. |
| **Light / dark** | Light mode by default; the moon icon in every header switches to dark "case-file noir" (remembered on the device). |

Everything runs on free tools: Python, Flutter (web + Android), Firebase **Spark** plan (no card),
and Gemini through Firebase AI Logic (free tier) with number-checking guard-rails.

---

## Repository layout

```
kuch-toh-gadbad-hai/
├── pipeline/            Python "detective" pipeline (download → standard cube → statistics → app data)
│   ├── detective/       the package (python -m detective ...)
│   ├── sources/         one YAML per dataset  ← plug new NASA resources in here
│   ├── cases/           one YAML per mirror case
│   ├── places.yaml      showcase cities for My Place
│   ├── demo/            synthetic twins of every dataset (offline testing)
│   └── tests/           pytest suite
├── app/                 Flutter app (web + Android) + Firebase config
│   ├── lib/             screens, widgets, Dart port of the statistics
│   ├── web/data/        pipeline output, served by Firebase Hosting at /data/
│   └── tool/            patch_platforms.py, icons, stats golden check
├── docs/                METHODS, DATASETS, RESOURCES_DAY, PITCH
└── TASKS.md             running checklist (done / remaining)
```

---

## Running it

Two folders: `pipeline\` (Python: downloads NASA data, runs the statistics, writes `app\web\data`) and `app\` (Flutter web + Android).

```bat
cd pipeline
pip install -r requirements.txt
python -m detective login          :: free NASA Earthdata Login, once
python -m detective run            :: all datasets; downloads are cached and never fetched twice
python -m detective status         :: what is published, what failed and why

cd ..\app
flutter create --org com.ibtidaatech --project-name kuchtohgadbadhai --platforms=android,web .
python tool\patch_platforms.py
flutter pub get
flutter run -d chrome
flutter build web && firebase deploy --only hosting
flutter build apk --release
```

Other pipeline commands: `run <dataset ids>`, `cases`, `places`, `selftest`, `inspect <file-or-url>`, `add <file-or-url>`,
`serve` (share the app and live data on Wi-Fi), `unlock`, `--demo demo` (synthetic demo pack).

## Use of AI

This is an AI-assisted project. Code, documentation and the synthetic sample/demo files were written with the help of an
AI assistant (Anthropic Claude) and reviewed by the team. Inside the app, Google Gemini (Firebase AI Logic) writes the
"Detective's notes" and investigation suggestions, always labelled as AI. No verdict, number, map or chart is produced by
AI: they are computed from the cited data. No NASA logos or mission emblems are used.

Team Xplorer (Khurram Rashid, Kinza Zahra), NASA Space Apps Challenge 2026, Panaji, Goa.

## The science in one paragraph

Each dataset becomes a standard monthly cube → seasonal yearly values → anomalies vs 1991–2020.
Every map cell and region gets a **Mann-Kendall** test with a **lag-1 autocorrelation correction**
(plain Mann-Kendall raised false alarms on 26–30% of trend-free series with strong year-to-year memory
in our own Monte Carlo tests), a **Sen's slope** with 95% interval, **Benjamini–Hochberg FDR**
across the map (α = 0.10, Wilks 2016), signal-to-noise, **time of emergence**,
**Weatherhead years-needed**, and a **Pettitt** change-point test that is matched against known
instrument transitions (the *alibi check*). Mirror cases test candidate drivers (global temperature,
El Niño, Indian Ocean Dipole, CO₂, local rainfall) with a **detrended fingerprint regression**: does the
driver's year-to-year wiggle predict *both* opposite trends? Co-trends alone never count.
Details and references: **docs/METHODS.md**.

---

## Troubleshooting

| Problem | Fix |
|---|---|
| `Python not found` | Reinstall Python with "Add python.exe to PATH" ticked, then `01_setup_python.bat`. |
| `NASA Earthdata Login needed` / `invalid_credentials` | Run `02_earthdata_login.bat` on its own; type the Earthdata **username** (not e-mail) and **password** (not a token). Forgot it? Reset on urs.earthdata.nasa.gov. Meanwhile `03_run_pipeline.bat --skip-login` runs everything else. |
| `The system cannot find the path specified` | `python -m detective` runs in `pipeline\`, `flutter` runs in `app\` . |
| A dataset download fails | Run `03_run_pipeline.bat` again: downloads are cached and mirrors are tried automatically. The Lab tab → *Pipeline report* shows what failed. |
| App says "No evidence yet" | `app\web\data\catalog.json` is missing → run 03 (or 03b), then 06. |
| Android app shows no data | Deploy the web app first (06): the APK reads `https://<project>.web.app/data/`. |
| AI notes show the plain summary | Firebase not configured, AI Logic not enabled, or the answer failed our number check (then the template is shown on purpose). |
| `flutter analyze` complains about files in `android/` | Run `04_setup_app.bat` again (it re-patches). |

---

## Credits, data and licence

Data: NASA GISS GISTEMP v4 · GPCP v2.3 (NASA GSFC, via NOAA PSL) · NASA JPL GRACE/GRACE-FO mascons (PO.DAAC) ·
NSIDC Sea Ice Index v4 · NASA POWER · NOAA CPC ONI · NOAA PSL DMI · NOAA GML CO₂ · optional NASA MERRA-2 and
Aura OMI. Full citations are in the app (How we know → Data sources) and in `app/web/data/sources.json`.
Map outlines and city list: Natural Earth (public domain).

Code © 2026 the Kuch Toh Gadbad Hai team, released under the Apache License 2.0 (see `LICENSE`).
