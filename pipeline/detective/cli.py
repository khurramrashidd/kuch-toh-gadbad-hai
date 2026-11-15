"""Command line: python -m detective <command>     (run inside the pipeline folder)

  run [ids]  everything, or only the given datasets (+ the cases that use them)
  status     what is published, what failed and why, open locks
  list       datasets and cases on disk (cached? enabled?)
  login      save your NASA Earthdata Login (once)
  inspect    look inside ANY file/URL; prints a block to paste to Claude + drafts a YAML
  add        inspect + register + analyse a new file/URL in one go
  cases      rebuild mirror cases          places   rebuild My Place cities
  selftest   Monte Carlo honesty tests     catalog  rebuild catalog.json from what is on disk
  serve      share app + live data on your Wi-Fi (tablet / phone / second laptop)
  unlock     clear locks left by a closed window
  demo       synthetic data in real formats -> labelled DEMO pack (no internet needed)

Several tabs may run at the same time (different datasets): every result is saved in its own
file under data/index/ and catalog.json is re-assembled under a lock after each step.
"""
from __future__ import annotations

import argparse
import os
import shutil
import sys
import time
import traceback
import warnings
from pathlib import Path

from . import __version__, access, places as places_mod, publish, readers, selftest as selftest_mod
from .canonical import pick_variable
from .engine import Context
from .mirror import NoMirror
from .registry import load_cases, load_config, load_places, load_sources
from .util import LOCK_SUFFIX, PIPELINE_DIR, DetectiveError, LoginRequired, dump_yaml, ensure_dir, log, now_iso, read_json, setup_logging, slugify


# ----------------------------------------------------------------------------- setup
def _context(args) -> Context:
    overrides = {}
    if args.demo:
        overrides["cache_dir"] = ".cache-demo"
    if getattr(args, "output", None):
        overrides["output_dir"] = args.output
    cfg = load_config(overrides=overrides)
    folder = PIPELINE_DIR / ("demo/sources" if args.demo else "sources")
    sources = load_sources(folder)
    return Context(cfg, sources, demo=args.demo)


def _cases(args) -> dict:
    cases = load_cases()
    if args.demo:
        cases.update(load_cases(PIPELINE_DIR / "demo" / "cases"))
    return cases


def _case_sources(case: dict) -> list[str]:
    ids = []
    for k in ("source",):
        if case.get(k):
            ids.append(case[k])
    for k in ("series_a", "series_b"):
        if case.get(k):
            ids.append(case[k]["source"])
    return ids


# ----------------------------------------------------------------------------- run
def _selected(args) -> set[str]:
    return set((getattr(args, "ids", None) or []) + (getattr(args, "only", None) or []))


def _walk_strings(obj):
    if isinstance(obj, str):
        yield obj
    elif isinstance(obj, dict):
        for v in obj.values():
            yield from _walk_strings(v)
    elif isinstance(obj, (list, tuple)):
        for v in obj:
            yield from _walk_strings(v)


def _case_refs(case: dict, ctx: Context) -> set[str]:
    """All dataset ids a case touches (its own + local / default drivers)."""
    refs = {v for v in _walk_strings(case) if v in ctx.sources}
    refs |= set(ctx.cfg.raw.get("drivers_default") or []) & set(ctx.sources)
    return refs


def build_datasets(ctx: Context, args, report: dict) -> list[str]:
    only = _selected(args)
    unknown = sorted(only - set(ctx.sources))
    for sid in unknown:
        report["datasets"][sid] = {"status": "error", "reason": "unknown id (typo? disabled? see: python -m detective list)"}
    done = []
    for src in ctx.sources.values():
        if only and src.id not in only:
            continue
        if src.needs_login and getattr(args, "skip_login", False):
            report["datasets"][src.id] = {"status": "skipped", "reason": "needs Earthdata Login (--skip-login)"}
            continue
        t0 = time.time()
        try:
            log.info("[%s] %s", src.id, src.title)
            ctx.cube(src.id, refresh=getattr(args, "refresh", False))
            layers, series = [], None
            if src.kind == "grid" and src.role in ("layer", "both"):
                for season in src.seasons:
                    layers.append(publish.publish_layer(ctx, src, season))
            if src.kind == "index":
                series = publish.publish_series(ctx, src)
            publish.save_index(ctx, "datasets", src.id, publish.dataset_entry(src, layers, series))
            st = {"status": "ok", "seconds": round(time.time() - t0, 1), "layers": [l["season"] for l in layers]}
            done.append(src.id)
        except LoginRequired as e:
            st = {"status": "login", "reason": str(e)}
            log.warning("[%s] %s", src.id, e)
        except Exception as e:
            st = {"status": "error", "reason": f"{type(e).__name__}: {e}"}
            log.error("[%s] FAILED: %s", src.id, e)
            log.debug(traceback.format_exc())
        report["datasets"][src.id] = st
        publish.save_status(ctx, "dataset", src.id, st)
        publish.assemble(ctx, set(_cases(args)))  # the app sees each dataset as soon as it is ready
    return done


def build_cases(ctx: Context, args, report: dict, touched: set[str] | None = None) -> int:
    """touched: only cases that use one of these datasets (None = all / args.cases)."""
    n = 0
    only = set(getattr(args, "cases", None) or [])
    for cid, case in _cases(args).items():
        if only and cid not in only:
            continue
        if touched is not None and not (_case_refs(case, ctx) & touched):
            continue
        missing = [s for s in _case_sources(case) if s not in ctx.sources]
        if missing:
            st = {"status": "skipped", "reason": f"needs source(s) {missing} (enable them in sources/)"}
        else:
            try:
                log.info("[case] %s", cid)
                entry = publish.publish_case(ctx, case)
                publish.save_index(ctx, "cases", cid, entry)
                st = {"status": "ok", "verdict": entry["verdict"].get("en"), "strength": entry["strength"]}
                n += 1
            except NoMirror as e:
                st = {"status": "no_mirror", "reason": str(e)}
                log.warning("[case] %s: %s", cid, e)
            except Exception as e:
                st = {"status": "error", "reason": f"{type(e).__name__}: {e}"}
                log.error("[case] %s FAILED: %s", cid, e)
                log.debug(traceback.format_exc())
        report["cases"][cid] = st
        publish.save_status(ctx, "case", cid, st)
    return n


def build_places(ctx: Context, args, report: dict) -> None:
    pl = load_places()
    if args.demo:
        from .demo import make_power_demo

        for p in pl[:6]:
            m, d = make_power_demo(p["lat"], p["lon"])
            doc = {"slug": slugify(p["name"]), "name": "[DEMO] " + p["name"], "name_hi": "[डेमो] " + p.get("name_hi", p["name"]),
                   "country": p.get("country", ""), "lat": p["lat"], "lon": p["lon"], "source": "SYNTHETIC DEMO in NASA POWER format",
                   "demo": True, "fetched_at": now_iso(), "variables": places_mod.analyse_power(m, d, ctx.cfg)}
            publish.write_json(ctx.cfg.output_dir / "places" / f"{doc['slug']}.json", doc)
        report["places"] = {"status": "ok", "count": min(6, len(pl)), "demo": True}
        return
    try:
        out = places_mod.build_places(ctx, pl, getattr(args, "places", None) or None)
        report["places"] = {"status": "ok" if out else "error", "count": len(out)}
    except Exception as e:
        report["places"] = {"status": "error", "reason": str(e)}


def finish(ctx: Context, args, report: dict) -> None:
    catalog = publish.assemble(ctx, set(_cases(args)))
    print()
    print("=" * 76)
    print(f" Kuch Toh Gadbad Hai pipeline v{__version__}  ->  {ctx.cfg.output_dir}")
    print("=" * 76)
    for k, v in report["datasets"].items():
        print(f"  dataset {k:24s} {v['status']:9s} {str(v.get('reason', ''))[:78]}")
    for k, v in report["cases"].items():
        extra = f"{v.get('verdict', '')} ({v.get('strength')})" if v["status"] == "ok" else str(v.get("reason", ""))
        print(f"  case    {k:24s} {v['status']:9s} {extra[:78]}")
    if report.get("places"):
        pl = report["places"]
        print(f"  places  {'':24s} {pl.get('status', ''):9s} {pl.get('count', '')} {str(pl.get('reason', ''))[:60]}")
    print("-" * 76)
    print(f"  catalog now: {len(catalog['datasets'])} datasets, {len(catalog['cases'])} cases, {len(catalog['places'])} places"
          + ("   [DEMO DATA]" if ctx.demo else ""))
    print("  app: browser -> refresh;  flutter run tab -> press R;  APK -> Lab tab -> Reload data")
    print("=" * 76)


def cmd_run(args) -> int:
    ctx = _context(args)
    ensure_dir(ctx.cfg.output_dir)
    publish.migrate_index(ctx)
    report = {"datasets": {}, "cases": {}}
    partial = bool(_selected(args))
    done = build_datasets(ctx, args, report)
    if partial:
        if done:
            build_cases(ctx, args, report, touched=set(done))
    else:
        build_cases(ctx, args, report)
    if (not partial and not args.no_places) or args.with_places:
        build_places(ctx, args, report)
    if (not partial and not args.no_selftest) or args.selftest:
        selftest_mod.run_selftest(ctx, quick=args.quick)
    finish(ctx, args, report)
    return 0 if all(v["status"] in ("ok", "skipped", "no_mirror") for v in [*report["datasets"].values(), *report["cases"].values()]) else 1


def cmd_cases(args) -> int:
    ctx = _context(args)
    report = {"datasets": {}, "cases": {}}
    build_cases(ctx, args, report)
    finish(ctx, args, report)
    return 0


def cmd_places(args) -> int:
    ctx = _context(args)
    report = {"datasets": {}, "cases": {}}
    build_places(ctx, args, report)
    finish(ctx, args, report)
    return 0


def cmd_selftest(args) -> int:
    ctx = _context(args)
    selftest_mod.run_selftest(ctx, quick=args.quick)
    finish(ctx, args, {"datasets": {}, "cases": {}})
    return 0


def cmd_catalog(args) -> int:
    ctx = _context(args)
    finish(ctx, args, {"datasets": {}, "cases": {}})
    return 0


def cmd_status(args) -> int:
    ctx = _context(args)
    publish.migrate_index(ctx)
    datasets, cases, places, statuses = publish.current_items(ctx, set(_cases(args)))
    stat = {(x["kind"], x["id"]): x for x in statuses}
    pub = {d["id"] for d in datasets}
    cat = ctx.cfg.output_dir / "catalog.json"
    when = read_json(cat).get("app", {}).get("generated_at") if cat.exists() else "never"
    print(f"\nOutput  {ctx.cfg.output_dir}\nCatalog {when}   mode: {'DEMO' if ctx.demo else 'real data'}\n")
    print(f"  {'dataset':24s} {'in app':6s} {'last run':9s} {'when (UTC)':20s} reason")
    for sid in ctx.sources:
        x = stat.get(("dataset", sid), {})
        print(f"  {sid:24s} {'yes' if sid in pub else '-':6s} {x.get('status', 'not run'):9s} {str(x.get('at', ''))[:19]:20s} {str(x.get('reason', ''))[:70]}")
    print(f"\n  {'case':24s} {'in app':6s} {'last run':9s} result")
    shown = {c["id"]: c for c in cases}
    for cid in _cases(args):
        x = stat.get(("case", cid), {})
        res = f"{shown[cid]['verdict'].get('en', '')} (strength {shown[cid]['strength']})" if cid in shown else str(x.get("reason", ""))
        print(f"  {cid:24s} {'yes' if cid in shown else '-':6s} {x.get('status', 'not run'):9s} {res[:80]}")
    print(f"\n  places: {len(places)}")
    locks = _locks(ctx)
    if locks:
        print("\n  busy / locks:")
        for l in locks:
            try:
                txt = l.read_text(encoding="utf-8", errors="replace")
            except OSError:
                txt = ""
            print(f"    {l.name:30s} {txt}")
        print("  (if no other run is open: python -m detective unlock)")
    print()
    return 0


def _locks(ctx: Context) -> list[Path]:
    out = []
    for d in {ctx.cfg.cache_dir, PIPELINE_DIR / ".cache", PIPELINE_DIR / ".cache-demo", ctx.cfg.output_dir}:
        if Path(d).exists():
            out += sorted(Path(d).glob(f"*{LOCK_SUFFIX}"))
    return out


def cmd_unlock(args) -> int:
    ctx = _context(args)
    n = 0
    for l in _locks(ctx):
        try:
            l.unlink()
            n += 1
            print(f"removed {l}")
        except OSError as e:
            print(f"could not remove {l}: {e}")
    for d in (ctx.cfg.output_dir, ctx.cfg.cache_dir):
        if Path(d).exists():
            for t in Path(d).rglob(".*.tmp"):
                try:
                    t.unlink()
                except OSError:
                    pass
    print(f"{n} lock(s) removed. Only do this when no other pipeline window is running.")
    return 0


def cmd_serve(args) -> int:
    from .serve import serve

    cfg = load_config()
    return serve(cfg.output_dir, port=args.port, web_root=args.web, quiet=not args.verbose)


def cmd_list(args) -> int:
    ctx = _context(args)
    print(f"{'id':22s} {'kind':7s} {'access':12s} {'login':5s} {'cached':6s} title")
    for f in sorted((PIPELINE_DIR / ("demo/sources" if args.demo else "sources")).glob("*.yaml")):
        if f.name.startswith("_"):
            continue
        from .registry import source_from_dict
        from .util import load_yaml

        s = source_from_dict(load_yaml(f), f)
        cached = ctx.cfg.path_cube(s.id).exists()
        flag = "" if s.enabled else "  (disabled)"
        print(f"{s.id:22s} {s.kind:7s} {s.access.get('method'):12s} {'yes' if s.needs_login else 'no':5s} {'yes' if cached else 'no':6s} {s.title}{flag}")
    print()
    for cid, c in _cases(args).items():
        miss = [x for x in _case_sources(c) if x not in ctx.sources]
        print(f"case {cid:28s} {c['type']:15s} {'needs ' + ','.join(miss) if miss else 'ready'}")
    return 0


def cmd_login(args) -> int:
    access.earthdata_login(interactive=True)
    print("Earthdata Login saved. You can now run the full pipeline.")
    return 0


# ----------------------------------------------------------------------------- inspect / add
def _resolve_input(target: str) -> Path:
    if target.startswith("http://") or target.startswith("https://"):
        inbox = ensure_dir(PIPELINE_DIR / "inbox")
        name = target.split("?")[0].rstrip("/").split("/")[-1] or "download.dat"
        p = access._download(target, inbox / name)
        return access._maybe_decompress(p, "auto")
    p = Path(target).expanduser()
    if not p.is_absolute():
        p = (Path.cwd() / p).resolve()
    if not p.exists():
        raise DetectiveError(f"{target} not found")
    return p


def _draft(path: Path, sid: str | None, title: str | None) -> tuple[dict, dict, object]:
    fmt = readers.sniff(path)
    files = access.iter_files([path])
    ds = readers.open_one(files[0], {}) if len(files) == 1 or fmt != "dir" else readers.open_raw(files, {})
    info = readers.describe(ds)
    info["format"] = fmt
    var = pick_variable(ds, None)
    da = ds[var]
    dims = [d.lower() for d in da.dims]
    has_ll = any(d in dims for d in ("lat", "latitude", "y", "ydim", "nlat")) and any(d in dims for d in ("lon", "longitude", "x", "xdim", "nlon"))
    kind = "levels" if has_ll and any(d in dims for d in ("lev", "level", "plev", "pressure")) else ("grid" if has_ll or da.ndim >= 3 else "index")
    sid = sid or slugify(path.stem).replace("-", "_")[:40]
    rel = path
    try:
        rel = path.relative_to(PIPELINE_DIR)
    except ValueError:
        pass
    draft = {
        "id": sid,
        "title": title or str(da.attrs.get("long_name") or var).strip()[:80],
        "title_hi": title or str(da.attrs.get("long_name") or var).strip()[:80],
        "short": str(var),
        "short_hi": str(var),
        "sphere": "atmosphere",
        "mission": "Space Apps 2026 challenge resource",
        "kind": kind,
        "role": "layer" if kind == "grid" else "driver",
        "access": {"method": "local", "path": rel.as_posix()},
        "read": {"variable": str(var)},
        "units": str(da.attrs.get("units", "")),
        "period": {"start": "auto", "end": "auto"},
        "seasons": ["ANN"],
        "min_coverage": 0.6,
        "palette": "generic",
        "citation": "TODO: paste the citation from the resource page",
        "url_info": "",
    }
    return draft, info, ds


def _summary_lines(path: Path, info: dict, ds, draft: dict) -> list[str]:
    """Compact, paste-able description of a file (for Claude / for the team)."""
    import numpy as np

    out = [f"FILE   {path.name}  ({path.stat().st_size / 1e6:.1f} MB)" if path.is_file() else f"FOLDER {path}",
           f"FORMAT {info['format']}   DIMS {info['dims']}"]
    for v in info["variables"][:25]:
        line = f"  var {v['name']:30s} {str(v['dims']):34s} units={v['units']!r} {v['long_name'][:50]}"
        try:
            da = ds[v["name"]]
            if da.size <= 5e7 and np.issubdtype(da.dtype, np.number):
                a = np.asarray(da.values, dtype="float64")
                fin = np.isfinite(a)
                if fin.any():
                    line += f"  [min {np.nanmin(a):.4g} mean {np.nanmean(a):.4g} max {np.nanmax(a):.4g} nan {100 * (1 - fin.mean()):.0f}%]"
        except Exception:
            pass
        out.append(line)
    if len(info["variables"]) > 25:
        out.append(f"  ... {len(info['variables']) - 25} more variables")
    for c, rng in list(info["coords"].items())[:8]:
        out.append(f"  coord {c}: {rng[0]} .. {rng[1]} ({rng[2]} values)")
    if "time" in ds.coords and ds["time"].size > 1:
        try:
            t = ds["time"].values
            step = np.median(np.diff(t.astype("datetime64[D]")).astype("float64"))
            out.append(f"  time step ~{step:.0f} days ({'monthly' if 27 <= step <= 32 else 'daily' if step <= 1.5 else 'yearly' if step > 300 else 'other'})")
        except Exception:
            pass
    if ds.attrs:
        keys = [k for k in ("title", "institution", "source", "references", "product_version", "ShortName", "VersionID") if k in ds.attrs]
        for k in keys[:5]:
            out.append(f"  attr {k}: {str(ds.attrs[k])[:100]}")
    out.append(f"GUESS  kind={draft['kind']} variable={draft['read']['variable']} units={draft['units']!r}")
    return out


def cmd_inspect(args) -> int:
    path = _resolve_input(args.target)
    draft, info, ds = _draft(path, args.id, args.title)
    lines = _summary_lines(path, info, ds, draft)
    out = PIPELINE_DIR / "sources" / f"_draft_{draft['id']}.yaml"
    dump_yaml(draft, out)
    report = ensure_dir(PIPELINE_DIR / "inbox") / f"{draft['id']}_inspect.txt"
    report.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("\n----- copy from here (paste to Claude) " + "-" * 36)
    print("\n".join(lines))
    print("----- to here " + "-" * 61)
    print(f"\nSaved: {report}\nDraft YAML: {out}\nNext: python -m detective add \"{args.target}\" --id {draft['id']}   (or wait for Claude's YAML)")
    return 0


def cmd_add(args) -> int:
    path = _resolve_input(args.target)
    draft, info, _ = _draft(path, args.id, args.title)
    if args.kind:
        draft["kind"] = args.kind
        draft["role"] = "layer" if args.kind == "grid" else "driver"
    if args.variable:
        draft["read"]["variable"] = args.variable
    if args.units:
        draft["units"] = args.units
    out = PIPELINE_DIR / "sources" / f"{draft['id']}.yaml"
    if out.exists() and not args.force:
        raise DetectiveError(f"{out.name} already exists (use --force to overwrite)")
    dump_yaml(draft, out)
    log.info("registered %s as %s (%s)", path.name, draft["id"], draft["kind"])
    case_file = None
    if draft["kind"] == "grid" and not args.no_case:
        case_file = PIPELINE_DIR / "cases" / f"auto-{draft['id']}.yaml"
        if not case_file.exists():
            dump_yaml({
                "id": f"auto-{draft['id']}",
                "title": f"Mirror hunt: {draft['title']}",
                "title_hi": f"उल्टे रुझान की खोज: {draft['title_hi']}",
                "tagline": "Where does this variable rise - and where does it fall?",
                "tagline_hi": "यह चीज़ कहाँ बढ़ रही है - और कहाँ घट रही है?",
                "question": f"Is {draft['short']} rising in one region and falling in another - and does one driver explain both?",
                "question_hi": f"क्या {draft['short_hi']} एक क्षेत्र में बढ़ और दूसरे में घट रहा है - और क्या एक ही वजह दोनों को समझाती है?",
                "spotlight": "global",
                "type": "auto_mirror",
                "source": draft["id"],
                "season": "ANN",
                "region_a": {"auto": "positive"},
                "region_b": {"auto": "negative"},
            }, case_file)
            log.info("drafted mirror case %s", case_file.name)
    args.ids = [draft["id"]]
    args.only = None
    args.demo = False
    ctx = _context(args)
    report = {"datasets": {}, "cases": {}}
    done = build_datasets(ctx, args, report)
    if case_file is not None and done:
        args.cases = [f"auto-{draft['id']}"]
        build_cases(ctx, args, report)
    finish(ctx, args, report)
    print(f"\nEdit {out} (title, Hindi name, citation, palette), then:  python -m detective run {draft['id']}")
    return 0


def cmd_demo(args) -> int:
    from .demo import make_demo

    make_demo()
    args.demo = True
    if args.clean:
        ctx = _context(args)
        if ctx.cfg.cache_dir.exists():
            shutil.rmtree(ctx.cfg.cache_dir)
    args.ids, args.only, args.cases, args.places = [], None, None, None
    args.skip_login = False
    args.refresh = True
    args.no_places = args.no_selftest = args.with_places = args.selftest = False
    return cmd_run(args)


# ----------------------------------------------------------------------------- main
def main(argv=None) -> int:
    p = argparse.ArgumentParser(prog="python -m detective", description="Kuch Toh Gadbad Hai - Earth System Trend Detective pipeline",
                                formatter_class=argparse.RawDescriptionHelpFormatter, epilog=__doc__)
    p.add_argument("-v", "--verbose", action="store_true")
    p.add_argument("--demo", action="store_true", help="use the synthetic demo datasets")
    p.add_argument("--output", help="override output folder (default ../app/web/data)")
    p.add_argument("--offline", action="store_true", help="NASA Earthdata datasets: use only files already downloaded, no network")
    sub = p.add_subparsers(dest="cmd")

    r = sub.add_parser("run", help="everything, or only the given dataset ids")
    r.add_argument("ids", nargs="*", help="dataset ids (default: all enabled)")
    r.add_argument("--only", nargs="*", help="same as giving ids")
    r.add_argument("--skip-login", action="store_true", help="skip datasets that need Earthdata Login")
    r.add_argument("--refresh", action="store_true", help="re-download and rebuild cubes")
    r.add_argument("--no-places", action="store_true", help="full run: keep existing My Place files")
    r.add_argument("--no-selftest", action="store_true", help="full run: skip the honesty tests")
    r.add_argument("--with-places", action="store_true", help="partial run: also rebuild My Place cities")
    r.add_argument("--selftest", action="store_true", help="partial run: also run the honesty tests")
    r.add_argument("--quick", action="store_true", help="faster (smaller) selftest")
    r.add_argument("--cases", nargs="*", help="only these cases")
    r.add_argument("--places", nargs="*", help="only these place slugs")

    sub.add_parser("list", help="list datasets and cases")
    sub.add_parser("status", help="what is published / failed / locked")
    sub.add_parser("catalog", help="rebuild catalog.json from disk")
    sub.add_parser("unlock", help="remove locks left by a closed window")
    sub.add_parser("login", help="save NASA Earthdata Login")

    c = sub.add_parser("cases", help="rebuild mirror cases")
    c.add_argument("cases", nargs="*")
    pl = sub.add_parser("places", help="rebuild My Place cities")
    pl.add_argument("places", nargs="*")
    st = sub.add_parser("selftest", help="honesty tests")
    st.add_argument("--quick", action="store_true")

    sv = sub.add_parser("serve", help="share the app + live data on your network")
    sv.add_argument("--port", type=int, default=8090)
    sv.add_argument("--web", help="built web app folder (default ../app/build/web)")

    for name in ("inspect", "add"):
        q = sub.add_parser(name, help=f"{name} a new file or URL")
        q.add_argument("target")
        q.add_argument("--id")
        q.add_argument("--title")
        if name == "add":
            q.add_argument("--kind", choices=["grid", "index", "levels"])
            q.add_argument("--variable")
            q.add_argument("--units")
            q.add_argument("--force", action="store_true")
            q.add_argument("--refresh", action="store_true")
            q.add_argument("--no-case", action="store_true", help="do not draft an automatic mirror case")

    d = sub.add_parser("demo", help="synthetic demo pack")
    d.add_argument("--quick", action="store_true")
    d.add_argument("--clean", action="store_true")

    args = p.parse_args(argv)
    if args.offline:
        os.environ["KTGH_OFFLINE"] = "1"
    setup_logging(args.verbose)
    warnings.filterwarnings("ignore", category=RuntimeWarning)
    if not args.cmd:
        p.print_help()
        return 0
    try:
        return {
            "run": cmd_run, "list": cmd_list, "login": cmd_login, "cases": cmd_cases, "places": cmd_places,
            "selftest": cmd_selftest, "inspect": cmd_inspect, "add": cmd_add, "demo": cmd_demo,
            "status": cmd_status, "catalog": cmd_catalog, "unlock": cmd_unlock, "serve": cmd_serve,
        }[args.cmd](args)
    except DetectiveError as e:
        log.error("%s", e)
        return 2
    except KeyboardInterrupt:
        print("\nstopped (Ctrl+C)")
        return 130


if __name__ == "__main__":
    sys.exit(main())
