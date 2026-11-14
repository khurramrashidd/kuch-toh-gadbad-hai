# Pitch kit

Submission rules: a demo video of **up to 30 seconds** (English subtitles) **or** up to **7 slides**
including the title slide; projects over these limits are not eligible for Global Judging. Judged on
Impact · Creativity · Validity · Relevance · Presentation. Cite every data source on the project page.

**Fill in the real numbers after running the pipeline on real data** — open each case in the app and copy the
headline. Never put demo-pack numbers in the pitch.

## 30-second video (shot list)
| Time | Picture | Voice / subtitle |
|---|---|---|
| 0–4 s | Team at the laptop, app logo | "We're team ___, and we built *Kuch Toh Gadbad Hai* — something's fishy with Earth." |
| 4–12 s | Case board → open **The Thirsty North**; red string between NW India and the rising region | "NASA's GRACE satellites show the same South Asia losing water in one place and gaining it in another." |
| 12–18 s | Evidence board stamps: Signal ✓, Alibi ✓, Motive: *rainfall has an alibi* | "Five forensic checks: rainfall didn't drop — so groundwater pumping is the prime suspect." |
| 18–25 s | Phone: My Place → GPS → hot days & rainfall cards with verdicts | "Tap any spot on Earth: 40 years of NASA data, tested live — confirmed, or not proven yet." |
| 25–30 s | Lab tab false-alarm bars, NASA logos of datasets used | "Honest statistics, free tools, English and Hindi. NASA data, no WhatsApp forwards." |

## 7 slides
1. **Title** — Kuch Toh Gadbad Hai · team name & members · challenge: *Be An Earth System Trend Detective!*
2. **The problem** — Earth is changing in opposite directions in different places; raw maps mislead, and
   "is it significant?" is the question nobody answers for the public.
3. **Our solution** — Mirror Cases + My Place + Explore; the 5-check evidence board (screenshot).
4. **Hero case** — The Thirsty North (map with red string, two trend charts, verdict stamp, real numbers).
5. **Validity** — false alarms: textbook test vs ours (bar chart from the Lab tab); NSIDC benchmark;
   synthetic mirror test; alibi check catching instrument jumps.
6. **NASA data & tech** — GISTEMP, GPCP, GRACE/GRACE-FO, Sea Ice Index, POWER (+ MERRA-2, OMI); Python
   pipeline that plugs in any new resource; Flutter web + Android; Firebase Spark + Gemini with guard-rails.
7. **Impact & next** — farmers, students, journalists, district planners; Hindi first, more Indian languages
   next; any NASA dataset in one command.

## Live pitch (local judges, ~3 min)
1. Hook (15 s): "Punjab is running out of water — but is it the rain, or us?"
2. Open The Thirsty North; walk the five checks (60 s).
3. **"Judge, what's your hometown?"** → My Place → type it → read out the verdicts (45 s).
   (Have 3 cities pre-tested; the ready-made reports work even on bad Wi-Fi.)
4. Explore: GRACE map, tap NW India, show "rose above the noise in ____" (20 s).
5. Lab: "Here's why you can trust it" — the false-alarm bars (20 s).
6. Close: plug-in pipeline + Hindi + free (10 s).

## Likely questions
* *Why not just linear regression?* — Non-normal, outlier-prone data; Mann-Kendall + Sen is the standard
  in hydro-climatology, and we correct it for autocorrelation and multiple testing.
* *Does "same driver" prove causation?* — No. It is a fingerprint test: the driver's year-to-year swings
  predict both trends. We say "evidence of a shared cause", and co-trends alone never count.
* *What if a satellite changed?* — The alibi check: Pettitt change point vs known instrument transitions,
  trend re-tested on both sides.
* *How do you avoid AI hallucinations?* — Gemini only sees our numbers; any number it writes that isn't in
  the evidence → its text is discarded.
* *Can it use other data?* — Yes: `add_resource` takes NetCDF/HDF/GeoTIFF/Zarr/CSV/Excel/JSON/URLs.
