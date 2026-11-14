# Datasets

All enabled by default unless marked *optional*. Each lives in `pipeline/sources/<id>.yaml`.

| id | What | Mission / product | Access | Login | Used in |
|---|---|---|---|---|---|
| `gistemp_grid` | Surface temperature anomaly, 2°, monthly, 1951– | NASA GISS GISTEMP v4 (GHCNv4 + ERSSTv5) | http (data.giss.nasa.gov, NOAA PSL mirror) | no | Explore, Cold Spot case |
| `gpcp_precip` | Precipitation, 2.5°, monthly, 1979– | GPCP v2.3 (NASA GSFC) via NOAA PSL | http | no | Explore, Monsoon's Two Faces, Wet Gets Wetter, Thirsty North (local suspect) |
| `grace_mascon` | Terrestrial water storage, 0.5° → 1°, monthly, 2002– | NASA JPL GRACE/GRACE-FO RL06.3Mv04 CRI mascons (PO.DAAC) | earthaccess | **yes** | Explore, Thirsty North |
| `seaice_arctic` / `seaice_antarctic` | Monthly sea-ice extent, 1979– | NSIDC Sea Ice Index v4 (passive microwave: Nimbus-7, DMSP, GCOM-W) | http | no | Opposite Poles, benchmark |
| `gistemp_global` | Global mean temperature | NASA GISTEMP v4 table | http | no | suspect (driver) |
| `nino34` | El Niño (Oceanic Niño Index) | NOAA CPC / ERSSTv5 | http | no | suspect |
| `dmi_iod` | Indian Ocean Dipole | NOAA PSL (HadISST) | http | no | suspect |
| `co2_mlo` | CO₂ at Mauna Loa | NOAA GML | http | no | suspect |
| `merra2_temp_levels` *(optional)* | Air temperature by pressure level | NASA GMAO MERRA-2 M2TMNPASM | earthaccess, streamed subset | yes | Warm Below, Cold Above |
| `omi_no2` *(optional)* | Tropospheric NO₂ | NASA Aura OMI OMNO2d | earthaccess, 3 days/month | yes | Same Fuel, Opposite Air |
| — | "My Place" point data, 1981– | NASA POWER (MERRA-2 meteorology, GPM IMERG / MERRA-2 precipitation) | live API in the app + `places.yaml` | no | My Place |

To turn on an optional dataset: set `enabled: true` in its YAML, then `python -m detective run merra2_temp_levels`
and `python -m detective cases` (from `pipeline\` with the venv active). Both are large downloads; start them early
(they resume where they stopped).

## Adding a dataset
1. `python -m detective add <file|folder|url>` — inspects it, writes `sources/<id>.yaml`, builds a map layer and drafts
   `cases/auto-<id>.yaml` (an automatic mirror hunt).
2. Open the YAML and fill in `title`, `title_hi`, `short`, `short_hi` (+ `gender_hi: f` if the Hindi noun is feminine),
   `sphere`, `mission`, `units`, `palette`, `citation`, `url_info`.
3. Re-run `python -m detective run <id>` and `flutter build web + firebase deploy --only hosting`.

See `sources/_TEMPLATE.yaml` for every option (HDF groups, fill values, scaling, time-in-filename, coarsening,
Earthdata short names, streaming subsets, known instrument transitions for the alibi check).

## Writing a mirror case by hand
```yaml
id: my-case
title: A Catchy Title
title_hi: हिंदी शीर्षक
tagline: one line
question: What the judges should wonder about?
spotlight: india            # india | global
type: mirror_regions        # mirror_regions | auto_mirror | mirror_series | mirror_levels
source: gpcp_precip
season: JJAS
region_a: {name: Somewhere, name_hi: कहीं, bbox: [lon_min, lat_min, lon_max, lat_max]}
region_b: {auto: negative, within: [60, 5, 100, 40]}    # strongest falling cluster inside the box
drivers: [nino34, dmi_iod, gistemp_global]             # global suspects
local_drivers: [{source: gpcp_precip, label: Rainfall, label_hi: बारिश}]
witnesses: [{source: another_dataset}]                 # optional second dataset
```
Then `python -m detective cases` (or the full pipeline) and redeploy.
