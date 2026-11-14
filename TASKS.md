# Running checklist

Updated with every code drop. ✅ done · ⬜ remaining · 🔁 run again whenever data changes.

## Built (v1.0, 11 Nov)
- ✅ Python pipeline: YAML dataset registry, http / Earthdata (earthaccess) / local access, format sniffing, readers for 12+ formats, standard monthly cube
- ✅ Statistics: Mann-Kendall + lag-1 & Hamed-Rao corrections, Sen slope + CI, FDR, SNR, time of emergence, years-needed, Pettitt + alibi check
- ✅ Mirror engine: cluster finding, region naming, global + local driver fingerprint tests, witnesses, 5-check evidence board, verdicts EN/HI
- ✅ Publisher: trend PNGs + FDR stippling, per-cell JSON, time-series chunks, cases, places, catalog, sources, pipeline report
- ✅ Selftest: Monte Carlo false alarms & power, slope CI coverage, synthetic mirror test, NSIDC benchmark
- ✅ Demo pack: synthetic twins of every dataset in the real formats (offline testing)
- ✅ `add` / `inspect`: plug in any new file or URL, with an automatic mirror case
- ✅ Flutter app: Cases board, Case file (map + red string, region charts, evidence board, suspects, AI notes, share), My Place (GPS / search / tap, live NASA POWER, satellite samples, mirror link), Explore (maps, FDR dots, tap readout, legend), How we know (selftest, benchmarks, sources, pipeline report), English + Hindi
- ✅ Dart port of the statistics, checked number-for-number against Python (60 golden cases)
- ✅ Firebase: Hosting config, Firestore rules (AI narration cache), Gemini via Firebase AI Logic with number guard-rails
- ✅ Windows scripts 01–07, add/inspect resource, tests; README + docs

## Fixes (v1.0.1, 11 Nov)
- ✅ Scripts no longer leave your window inside `pipeline\` with the venv active (SETLOCAL in every script)
- ✅ Works with or without `pipeline\.venv` (`01_setup_python.bat --system` = laptop Python)
- ✅ Earthdata login script explains username (not e-mail) + password (not a token)

## Changes (v1.0.2, 11 Nov)
- ✅ Light mode by default, dark mode on the moon/sun toggle in every header (saved on the device)
- ✅ All colours moved into a theme palette (charts, map, stamps, evidence board follow the mode)
- ✅ `08_install_on_phone.bat` (= `cd app` + `flutter install --release`)

## Changes (v1.1.0, 14 Nov — hackathon day 1)
- ✅ No more scripts: every command is plain and given in chat
- ✅ Several pipeline tabs can run at once (per-dataset result files, locked catalog, atomic writes)
- ✅ `run <ids>` is fast: only those datasets + the cases that use them
- ✅ New commands: `status`, `catalog`, `unlock`, `serve`
- ✅ `serve`: web app + live data on Wi-Fi for tablet/phone; `?live=1` auto-refresh
- ✅ App: Reload data button + Live switch (Lab tab); debug builds can read laptop data
- ✅ `inspect` prints a paste-to-Claude block
- ✅ Readers: Giovanni CSV, NASA NEO grid CSV, decimal-year tables (sea level), AppEEARS file names
- ✅ Carried forward: v1.0.1 fixes, v1.0.2 light/dark theme

## Built (v1.2.0, 14 Nov)
- ✅ Investigate tab: 3 guided questions -> variables with plain definitions; AI suggestions (labelled)
- ✅ Bring your own evidence: Giovanni / AppEEARS / NOAA CDO / any CSV -> verdict; 4 labelled sample files
- ✅ "Can you beat the test?" game
- ✅ Verdict panel everywhere: t-test + Mann-Kendall + Seasonal Kendall + 95% interval, years-needed, cherry-pick shield, naive-test warning, year slider, Reproduce, Share
- ✅ Explore: flat map default + 3D globe toggle, country/ocean/city names, hotspot pins, sphere/variable/season/verdict/direction filters, draw-your-own region, 18 region presets
- ✅ Watchable demo tour of the top case
- ✅ Simple / Scientist switch
- ✅ NASA POWER results cached on the device and in Firestore
- ✅ References section (what, from where, why; non-US partners), AI-use disclosure, team sign-in (admin)
- ✅ Pipeline: GLDAS soil / evaporation / runoff, GPM IMERG, MERRA-2 T2M, MODIS NDVI + land heat and OMI NO2 (via NASA NEO); 3 new cases
- ⚠ Not run on a device or against NASA servers by the builder: test the globe, upload and the new datasets first

## Changes (v1.2.1, 14 Nov afternoon)
- ✅ Responsive frame: phone (header + bottom bar), tablet (header + left rail + footer), desktop (header + left sidebar + right sidebar + footer)
- ✅ Header strip: date, time, nearest city, current weather (Open-Meteo, cited); right sidebar "Here and now", verdict guide, strongest case, data status
- ✅ "Zoom to my location" button on the flat map and the globe
- ✅ Phone: icon-only header actions, filters collapsed behind a Filters button, duplicate titles removed
- ✅ NASA NEO folder reader accepts more link styles and reports what it found
- ✅ Real data in the app: 12 datasets, 6 cases, 30 cities (site live at ktgh-nasa.web.app)

## Remaining
- ⬜ Real data run: paste the summary table and `python -m detective status`
- ⬜ Firebase console: Firestore, Anonymous + Google sign-in, AI Logic (Gemini Developer API)
- ⬜ Pick the hero case from the real results; climate teammate sanity-checks its physics
- ⬜ 7 slides, 4-minute script, 30-second video script, project page text
- ⬜ Public GitHub repo; **Submit for Judging before Sun 15 Nov 23:59**
