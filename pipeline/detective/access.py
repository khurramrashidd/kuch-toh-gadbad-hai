"""Getting raw files onto disk, whatever the source.

Supported access methods (set `access.method` in a source YAML):

* ``http``        - one or many public URLs (with fallbacks and URL templates)
* ``earthaccess`` - NASA Earthdata (CMR) collections via the official
                    ``earthaccess`` library; needs a free Earthdata Login
* ``local``       - files you already have (e.g. the challenge resources
                    downloaded by hand on 13 Nov) - globs allowed
"""
from __future__ import annotations

import gzip
import itertools
import os
import shutil
import time
from pathlib import Path
from typing import Iterable

import requests

from .registry import Config, Source
from .util import PIPELINE_DIR, DetectiveError, LoginRequired, ensure_dir, log

USER_AGENT = "KuchTohGadbadHai/1.0 (NASA Space Apps 2026; Earth System Trend Detective)"


# ----------------------------------------------------------------------------- http
def _download(url: str, dest: Path, retries: int = 3, timeout: tuple = (20, 300)) -> Path:
    if dest.exists() and dest.stat().st_size > 0:
        log.debug("cached %s", dest.name)
        return dest
    ensure_dir(dest.parent)
    tmp = dest.with_suffix(dest.suffix + ".part")
    last_err: Exception | None = None
    for attempt in range(1, retries + 1):
        try:
            log.info("  downloading %s", url)
            with requests.get(url, stream=True, timeout=timeout, headers={"User-Agent": USER_AGENT}) as r:
                if r.status_code == 404:
                    raise FileNotFoundError(f"404 Not Found: {url}")
                r.raise_for_status()
                with open(tmp, "wb") as f:
                    for chunk in r.iter_content(chunk_size=1 << 20):
                        if chunk:
                            f.write(chunk)
            if tmp.stat().st_size == 0:
                raise IOError(f"empty download: {url}")
            os.replace(tmp, dest)
            return dest
        except FileNotFoundError as e:
            last_err = e
            break
        except Exception as e:  # network hiccup -> retry
            last_err = e
            log.warning("  attempt %d/%d failed: %s", attempt, retries, e)
            time.sleep(2 * attempt)
    if tmp.exists():
        tmp.unlink()
    raise DetectiveError(f"Could not download {url}: {last_err}")


def _maybe_decompress(path: Path, mode: str | None) -> Path:
    if mode == "gzip" or (mode in (None, "auto") and path.suffix == ".gz"):
        out = path.with_suffix("")
        if not out.exists() or out.stat().st_mtime < path.stat().st_mtime:
            log.info("  decompressing %s", path.name)
            with gzip.open(path, "rb") as fin, open(out, "wb") as fout:
                shutil.copyfileobj(fin, fout)
        return out
    return path


def _name_from_url(url: str) -> str:
    name = url.split("?")[0].rstrip("/").split("/")[-1]
    return name or "download.dat"


def _expand_template(template: str, variables: dict) -> list[tuple[dict, str]]:
    keys = list(variables)
    out = []
    for combo in itertools.product(*[list(variables[k]) for k in keys]):
        vals = dict(zip(keys, combo))
        out.append((vals, template.format(**vals)))
    return out


def fetch_http(src: Source, cfg: Config) -> list[Path]:
    a = src.access
    raw_dir = ensure_dir(cfg.path_raw(src.id))
    decompress = a.get("decompress", "auto")
    paths: list[Path] = []

    def get_with_fallbacks(urls: list[str], name: str | None = None) -> Path:
        errors = []
        for u in urls:
            try:
                p = _download(u, raw_dir / (name or _name_from_url(u)))
                return _maybe_decompress(p, decompress)
            except DetectiveError as e:
                errors.append(str(e))
                log.warning("  %s -> trying next mirror", e)
        raise DetectiveError(" / ".join(errors))

    if a.get("url"):
        urls = [a["url"]] + list(a.get("fallback_urls", []))
        paths.append(get_with_fallbacks(urls, a.get("filename")))
    for item in a.get("files", []) or []:
        if isinstance(item, str):
            item = {"url": item}
        urls = [item["url"]] + list(item.get("fallback_urls", []))
        paths.append(get_with_fallbacks(urls, item.get("name")))
    if a.get("template"):
        templates = [a["template"]] + list(a.get("template_fallbacks", []))
        variables = a.get("template_vars", {})
        combos = _expand_template(templates[0], variables)
        for vals, _ in combos:
            urls = [t.format(**vals) for t in templates]
            paths.append(get_with_fallbacks(urls))
    if not paths:
        raise DetectiveError(f"{src.id}: http access needs url, files or template")
    return paths


# ----------------------------------------------------------------------------- local
def fetch_local(src: Source, cfg: Config) -> list[Path]:
    a = src.access
    patterns: list[str] = []
    if a.get("path"):
        patterns.append(a["path"])
    patterns += list(a.get("paths", []) or [])
    out: list[Path] = []
    for pat in patterns:
        p = Path(os.path.expanduser(pat))
        if not p.is_absolute():
            p = PIPELINE_DIR / p
        if any(ch in str(p) for ch in "*?["):
            matches = sorted(p.parent.glob(p.name))
            out += matches
        elif p.exists():
            out.append(p)
    if not out:
        raise DetectiveError(f"{src.id}: no local files matched {patterns}")
    return [_maybe_decompress(p, a.get("decompress", "auto")) if p.is_file() else p for p in out]


# ----------------------------------------------------------------------------- earthaccess
_EA_AUTH = None


def earthdata_login(interactive: bool = False):
    """Log in to NASA Earthdata. Non-interactive tries ~/.netrc (or _netrc) then env vars."""
    global _EA_AUTH
    try:
        import earthaccess  # noqa: F401
    except ImportError as e:  # pragma: no cover
        raise DetectiveError("earthaccess is not installed - run: pip install -r requirements.txt") from e
    import earthaccess

    if _EA_AUTH is not None and getattr(_EA_AUTH, "authenticated", False):
        return _EA_AUTH
    strategies = ["interactive"] if interactive else ["netrc", "environment"]
    for strat in strategies:
        try:
            kwargs = {"strategy": strat}
            if strat == "interactive":
                kwargs["persist"] = True
            auth = earthaccess.login(**kwargs)
            if auth is not None and getattr(auth, "authenticated", False):
                _EA_AUTH = auth
                return auth
        except Exception as e:
            log.debug("earthaccess login via %s failed: %s", strat, e)
    raise LoginRequired(
        "NASA Earthdata Login needed. Run: python -m detective login  once "
        "(free account: https://urs.earthdata.nasa.gov/users/new)"
    )


def _granule_date(g) -> str:
    try:
        return g["umm"]["TemporalExtent"]["RangeDateTime"]["BeginningDateTime"][:10]
    except Exception:
        try:
            return g["umm"]["TemporalExtent"]["SingleDateTime"][:10]
        except Exception:
            return ""


def _filter_granules(granules: list, sample: dict | None) -> list:
    if not sample:
        return granules
    months = set(sample.get("months", []) or [])
    days = set(sample.get("days", []) or [])
    keep = []
    for g in granules:
        d = _granule_date(g)
        if not d:
            keep.append(g)
            continue
        m, dd = int(d[5:7]), int(d[8:10])
        if months and m not in months:
            continue
        if days and dd not in days:
            continue
        keep.append(g)
    return keep


def fetch_earthaccess(src: Source, cfg: Config) -> list[Path]:
    import earthaccess

    a = src.access
    raw_dir = ensure_dir(cfg.path_raw(a.get("raw_as") or src.id))  # raw_as: several sources share one download
    if os.environ.get("KTGH_OFFLINE") == "1":  # --offline: build from the files already on disk, no network at all
        stream = a.get("mode", "download") == "stream"
        cached = sorted(p for p in raw_dir.iterdir() if p.is_file() and not p.name.startswith("_") and not p.name.endswith(".part")
                        and not _is_sidecar(p) and (p.name.endswith(".subset.nc") == stream))
        if not stream:
            _remove_broken(cached)
            cached = [p for p in cached if p.exists()]
        if not cached:
            raise DetectiveError(f"{src.id}: --offline but nothing is cached yet")
        log.info("  %s: offline - using %d cached file(s)", src.id, len(cached))
        return cached
    earthdata_login()
    names = a.get("short_name")
    names = [names] if isinstance(names, str) else list(names or [])
    if not names and not a.get("concept_id"):
        raise DetectiveError(f"{src.id}: earthaccess needs short_name or concept_id")
    start = a.get("temporal", [None, None])[0] or f"{src.period.get('start', 1979)}-01-01"
    end = a.get("temporal", [None, None])[1] or None
    query: dict = {"temporal": (str(start), str(end) if end else None)}
    if a.get("version"):
        query["version"] = str(a["version"])
    if a.get("bounding_box"):
        query["bounding_box"] = tuple(a["bounding_box"])
    if a.get("max_granules"):
        query["count"] = int(a["max_granules"])

    granules: list = []
    used = None
    if a.get("concept_id"):
        granules = earthaccess.search_data(concept_id=a["concept_id"], **query)
        used = a["concept_id"]
    for name in names:
        if granules:
            break
        try:
            granules = earthaccess.search_data(short_name=name, **query)
            used = name
        except Exception as e:
            log.warning("  search %s failed: %s", name, e)
    if not granules:
        hint = ""
        try:
            kw = a.get("keyword") or (names[0] if names else src.title)
            found = earthaccess.search_datasets(keyword=kw, count=8)
            hint = "; candidates: " + ", ".join(c["umm"]["ShortName"] for c in found)
        except Exception:
            pass
        raise DetectiveError(f"{src.id}: no granules found for {names}{hint}")
    granules = _filter_granules(granules, a.get("sample"))
    log.info("  %s: %d granules from %s", src.id, len(granules), used)

    if a.get("mode", "download") == "stream":
        return _stream_subset(granules, raw_dir, a.get("subset", {}))
    def data_files() -> list[Path]:
        return sorted(p for p in raw_dir.iterdir() if p.is_file() and not p.name.endswith(".part") and not _is_sidecar(p)
                      and not p.name.endswith(".subset.nc") and not p.name.startswith("_"))

    # A dropped connection leaves half-written files behind; earthaccess would then skip them as "already there".
    # So: delete broken files, download, check again - up to 4 rounds - and never hand a broken file to the reader.
    want = len(granules)
    for attempt in range(1, 5):
        removed = _remove_broken(data_files())
        if removed:
            log.info("  %s: removed %d incomplete file(s) from an interrupted download", src.id, removed)
        have = len(data_files())
        if have >= want and not removed:
            break
        log.info("  %s: download round %d (%d of %d files on disk)", src.id, attempt, have, want)
        try:
            earthaccess.download(granules, local_path=str(raw_dir), threads=int(a.get("threads", 4)))
        except Exception as e:  # network down etc. - keep what we have, try again
            log.warning("  %s: download round %d stopped: %s", src.id, attempt, str(e)[:160])
            time.sleep(20)
    _remove_broken(data_files())
    paths = data_files()
    if not paths:
        raise DetectiveError(f"{src.id}: nothing could be downloaded (check the internet connection), then run it again")
    if len(paths) < want:
        log.warning("  %s: %d of %d files downloaded; missing months are left empty. Run again with --refresh to fetch the rest.", src.id, len(paths), want)
    return paths


def _file_ok(p: Path) -> bool:
    """True unless the file is a truncated HDF5 / NetCDF-4 (the usual result of a dropped connection)."""
    try:
        with open(p, "rb") as f:
            head = f.read(8)
        if head[:8] == b"\x89HDF\r\n\x1a\n":
            import h5py

            with h5py.File(p, "r") as h:
                h.visit(lambda _name: None)  # walks every group: fails on a cut-off file
            return True
        return p.stat().st_size > 0
    except Exception:
        return False


def _remove_broken(paths: list[Path]) -> int:
    n = 0
    for p in paths:
        if not _file_ok(p):
            try:
                p.unlink()
                n += 1
            except OSError:
                pass
    return n


_SIDECARS = (".md5", ".sha256", ".sha512", ".xml", ".cmr.json", ".dmrpp", ".txt", ".html", ".png", ".jpg")


def _is_sidecar(p: Path) -> bool:
    return p.name.lower().endswith(_SIDECARS)


def fetch_http_index(src: Source, cfg: Config) -> list[Path]:
    """Download every file linked from a plain web folder listing (e.g. NASA NEO archive).

    access: {method: http_index, url: https://.../folder/, match: 'regex on file name', sample: {months: [...]}}
    """
    import re as _re

    a = src.access
    base = a["url"].rstrip("/") + "/"
    raw_dir = ensure_dir(cfg.path_raw(a.get("raw_as") or src.id))
    rx = _re.compile(a.get("match", r"\.(tiff?|nc4?|csv|hdf|h5)(\.gz)?$"), _re.I)
    listing = raw_dir / "_index.html"
    try:
        if listing.exists():
            listing.unlink()
        _download(base, listing)
        html = listing.read_text(encoding="utf-8", errors="replace")
    except Exception as e:
        cached = sorted(p for p in raw_dir.iterdir() if p.is_file() and rx.search(p.name))
        if cached:
            log.warning("  %s: listing failed (%s) - using %d cached files", src.id, e, len(cached))
            return cached
        raise DetectiveError(f"{src.id}: cannot read folder listing {base}: {e}") from e
    from urllib.parse import urljoin

    from .readers import time_from_filename

    hrefs = _re.findall(r"""href\s*=\s*["']([^"'#]+)["']""", html, flags=_re.I)
    links = sorted({urljoin(base, h.split("?")[0]) for h in hrefs if rx.search(h.split("?")[0])})
    if not links:  # some listings print bare file names without links
        links = sorted({urljoin(base, m) for m in _re.findall(r"[\w.\-]+\.(?:FLOAT\.)?TIFF?", html, flags=_re.I)})
    if not links:
        sample = [h for h in hrefs if not h.startswith(("?", "#"))][:8]
        raise DetectiveError(f"{src.id}: no files matching {rx.pattern!r} at {base}; the page has {len(hrefs)} links, e.g. {sample}. "
                             f"Send Claude the saved page: {listing}")
    start = int(src.period.get("start", 0) or 0) if str(src.period.get("start", "")).isdigit() else 0
    months = set((a.get("sample") or {}).get("months") or [])
    todo = []
    for u in links:
        n = u.rstrip("/").split("/")[-1]
        t = time_from_filename(n)
        if t is not None:
            y, mth = int(str(t)[:4]), int(str(t)[5:7])
            if y < start or (months and mth not in months):
                continue
        todo.append(u)
    if not todo:
        raise DetectiveError(f"{src.id}: no files matching {rx.pattern!r} at {base}")
    log.info("  %s: %d files listed at %s", src.id, len(todo), base)
    out = []
    for i, n in enumerate(todo, 1):
        try:
            out.append(_maybe_decompress(_download(n, raw_dir / n.rstrip("/").split("/")[-1]), a.get("decompress", "auto")))
        except Exception as e:
            log.warning("    skip %s (%s)", n, e)
        if i % 50 == 0:
            log.info("    %d/%d", i, len(todo))
    return out


def _stream_subset(granules: list, raw_dir: Path, subset: dict) -> list[Path]:
    """Open remote netCDF4/HDF5 files lazily and keep only what we need (saves GBs)."""
    import earthaccess
    import xarray as xr

    out: list[Path] = []
    variables = subset.get("variables")
    sel = subset.get("sel", {}) or {}
    coarsen = int(subset.get("coarsen", 1) or 1)
    todo = []
    for g in granules:
        try:
            name = Path(g.data_links()[0]).name
        except Exception:
            name = f"granule_{len(todo)}"
        target = raw_dir / (Path(name).stem + ".subset.nc")
        if target.exists() and target.stat().st_size > 0:
            out.append(target)
        else:
            todo.append((g, target))
    log.info("  streaming %d granules (%d cached)", len(todo), len(out))
    import logging as _logging

    _logging.getLogger("earthaccess").setLevel(_logging.CRITICAL)  # its long tracebacks hide our own messages

    def one(g, target) -> None:
        fobj = earthaccess.open([g])[0]
        with xr.open_dataset(fobj, engine="h5netcdf", decode_times=True, **({"group": subset["group"]} if subset.get("group") else {})) as ds:
            if variables:
                ds = ds[[v for v in variables if v in ds]]
            for dim, val in sel.items():
                if dim in ds.dims or dim in ds.coords:
                    ds = ds.sel({dim: val}, method="nearest") if not isinstance(val, list) else ds.sel({dim: val})
            if coarsen > 1:
                dims = {d: coarsen for d in ds.dims if d.lower() in ("lat", "lon", "latitude", "longitude", "y", "x")}
                if dims:
                    ds = ds.coarsen(dims, boundary="trim").mean()
            tmp = target.with_name(f"_{target.name}.{time.time_ns()}.part")
            ds.load().to_netcdf(tmp)
        if not target.exists():
            os.replace(tmp, target)

    # Two passes over what is missing; inside a pass every file gets 3 tries with a pause,
    # and after 5 failures in a row we wait for the connection to come back instead of skipping everything.
    import concurrent.futures as _cf

    pool = _cf.ThreadPoolExecutor(max_workers=1)
    failed_in_row = 0
    for rnd in (1, 2):
        left = [(g, t) for g, t in todo if not t.exists()]
        if not left:
            break
        if rnd == 2:
            log.info("  second pass for %d skipped file(s)", len(left))
        for i, (g, target) in enumerate(left, 1):
            ok = False
            for attempt in range(3):
                try:
                    fut = pool.submit(one, g, target)
                    fut.result(timeout=240)  # a silent, hung connection must not freeze the whole run
                    ok = True
                    break
                except _cf.TimeoutError:
                    last = "no answer for 4 minutes"
                    pool = _cf.ThreadPoolExecutor(max_workers=1)  # leave the hung worker behind
                except Exception as e:
                    last = str(e)[:140]
                    time.sleep(8 * (attempt + 1))
            if ok:
                out.append(target)
                failed_in_row = 0
            else:
                failed_in_row += 1
                log.warning("    could not read %s (%s)", target.name.replace(".subset.nc", ""), last)
                if failed_in_row >= 5:
                    log.warning("    5 failures in a row: the connection looks down. Waiting 2 minutes, then carrying on...")
                    time.sleep(120)
                    failed_in_row = 0
            if i % 20 == 0:
                log.info("    %d/%d", i, len(left))
    missing = [t for _, t in todo if not t.exists()]
    if missing:
        log.warning("  %d file(s) still missing; run the same command again to fetch only those", len(missing))
    return sorted(out)


# ----------------------------------------------------------------------------- dispatcher
def fetch(src: Source, cfg: Config) -> list[Path]:
    method = src.access.get("method")
    if method == "http":
        return fetch_http(src, cfg)
    if method == "http_index":
        return fetch_http_index(src, cfg)
    if method == "earthaccess":
        return fetch_earthaccess(src, cfg)
    if method in ("local", "demo"):
        return fetch_local(src, cfg)
    raise DetectiveError(f"{src.id}: unknown access.method {method!r}")


def iter_files(paths: Iterable[Path]) -> list[Path]:
    """Expand directories (except Zarr stores) into their files."""
    out: list[Path] = []
    for p in paths:
        p = Path(p)
        if p.is_dir() and not (p / ".zgroup").exists() and not (p / "zarr.json").exists() and not (p / ".zarray").exists():
            out += sorted(q for q in p.iterdir() if q.is_file() and not q.name.endswith(".part"))
        else:
            out.append(p)
    return out
