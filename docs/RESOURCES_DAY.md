# 13 November: plugging in the official challenge resources

The pipeline does not care where a dataset comes from. When the challenge's Resources tab goes live:

## 1. Triage (10 min, no laptop needed)
For each resource, note: variable, mission/model, format (NetCDF / HDF / CSV / API / portal),
coverage (global or regional), time span (≥ 15 years is needed for trends), login needed?
Prefer **gridded monthly** data with **20+ years** — that's what trend maps and mirror cases need.

## 2. Get the file(s)
* Direct link → just pass the URL to `add_resource.bat`.
* Earthdata collection → note its *short name* (e.g. `MOD13C2`), then copy `pipeline\sources\_TEMPLATE.yaml`
  and use `access: {method: earthaccess, short_name: [MOD13C2], sample: {months: [8]}}` for big products.
* Portal download (Giovanni, AppEEARS, Worldview…) → save into `pipeline\inbox\` and add the folder.

## 3. Inspect and add
```bat
python -m detective inspect pipeline\inbox\the_file.nc
python -m detective add pipeline\inbox\the_file.nc --id short_id --units "unit"
```
Many files at once (one per month): put them in a folder and add the folder — dates are read from the
time variable or from the file names (`A2010182`, `201007`, `2010-07-01`… or set `read.time_regex`).

What `add` prints at the end tells you if the map layer was built and whether a mirror (rising *and*
falling regions) exists in the data. If it says *no mirror*, the variable moves one way everywhere: still a
good map for Explore, just not a mirror case.

## 4. Polish
Edit `pipeline\sources\<id>.yaml`: titles (EN/HI), `palette`, `citation` (copy from the resource page —
Space Apps requires citing every source), `known_transitions` if the product changed satellites.
Edit `pipeline\cases\auto-<id>.yaml`: a catchy title, a question, `drivers`, maybe a fixed `bbox` for an
Indian region. Then:
```bat
python -m detective run <id>
flutter build web && firebase deploy --only hosting   (in app\)
```

## 5. If something does not open
| Message | Try |
|---|---|
| `No numeric data variable found` | `--variable NAME` (see the list from inspect) |
| `extra dimension 'band'/'depth'…` | add `read: {sel: {depth: 0}}` to the YAML |
| `Cannot find a date in …` | add `read: {time_regex: "(\\d{4})(\\d{2})"}` |
| `needs 1-D lat coordinates` | curvilinear/swath data: download a gridded (Level 3) version instead |
| HDF4 / GeoTIFF / GRIB errors | `pip install pyhdf` / `rioxarray` / `cfgrib` inside the venv (`pipeline\requirements-optional.txt`) |
| Values look 10 000× too big | add `read: {scale: {multiply: 0.0001}}` |
