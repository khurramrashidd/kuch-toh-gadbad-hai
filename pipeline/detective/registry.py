"""Loads pipeline settings, dataset sources (sources/*.yaml) and cases (cases/*.yaml).

A *source* is any dataset described by a small YAML file. Adding a new NASA
resource = dropping one YAML file into sources/ (or running
`python -m detective add <file-or-url>` which drafts it for you).
"""
from __future__ import annotations

import copy
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from .util import PIPELINE_DIR, DetectiveError, load_yaml, log

DEFAULT_CONFIG: dict[str, Any] = {
    "output_dir": "../app/web/data",
    "cache_dir": ".cache",
    "analysis": {
        "baseline": [1991, 2020],
        "min_years": 15,
        "min_valid_frac": 0.8,
        "alpha": 0.05,
        "fdr_alpha": 0.10,
        "grid_method": "lag1",
        "series_method": "lag1",
        "snr_confirm": 1.0,
    },
    "mirror": {"min_cells": 4, "max_clusters": 8, "driver_p": 0.10, "explained_min": 0.25},
    "drivers_default": ["gistemp_global", "nino34"],
    "publish": {"series_block": 16, "png_scale": 4},
    "app": {"ai_models": ["gemini-3.5-flash-lite", "gemini-flash-lite-latest", "gemini-2.5-flash-lite"]},
}

KINDS = {"grid", "index", "levels"}
SPHERES = {"atmosphere", "hydrosphere", "cryosphere", "biosphere", "anthroposphere", "geosphere"}


def _deep_merge(base: dict, extra: dict) -> dict:
    out = copy.deepcopy(base)
    for k, v in (extra or {}).items():
        if isinstance(v, dict) and isinstance(out.get(k), dict):
            out[k] = _deep_merge(out[k], v)
        else:
            out[k] = v
    return out


@dataclass
class Config:
    raw: dict
    root: Path

    @property
    def output_dir(self) -> Path:
        return (self.root / self.raw["output_dir"]).resolve()

    @property
    def cache_dir(self) -> Path:
        return (self.root / self.raw["cache_dir"]).resolve()

    @property
    def analysis(self) -> dict:
        return self.raw["analysis"]

    @property
    def mirror(self) -> dict:
        return self.raw["mirror"]

    def path_raw(self, source_id: str) -> Path:
        return self.cache_dir / "raw" / source_id

    def path_cube(self, source_id: str) -> Path:
        return self.cache_dir / "cube" / f"{source_id}.nc"

    def path_result(self, source_id: str, season: str) -> Path:
        return self.cache_dir / "results" / source_id / f"{season}.nc"


def load_config(path: Path | None = None, overrides: dict | None = None) -> Config:
    path = path or PIPELINE_DIR / "config.yaml"
    raw = _deep_merge(DEFAULT_CONFIG, load_yaml(path) if Path(path).exists() else {})
    if overrides:
        raw = _deep_merge(raw, overrides)
    return Config(raw=raw, root=Path(path).resolve().parent)


@dataclass
class Source:
    id: str
    title: str
    kind: str
    access: dict
    read: dict = field(default_factory=dict)
    title_hi: str = ""
    short: str = ""
    short_hi: str = ""
    gender_hi: str = "m"           # grammatical gender of short_hi (m/f) for Hindi verbs
    sphere: str = "atmosphere"
    mission: str = ""
    role: str = "layer"            # layer | driver | both
    units: str = ""
    convert: Any = None
    aggregate: str = "mean"        # monthly -> season: mean | sum
    period: dict = field(default_factory=lambda: {"start": 1981, "end": "auto"})
    seasons: list = field(default_factory=lambda: ["ANN"])
    analysis_grid: float | None = None
    min_coverage: float = 0.75
    trend_units: str = "absolute"  # absolute | percent (percent of baseline mean)
    known_transitions: list = field(default_factory=list)
    palette: str = "generic"
    good_direction: str = "none"   # up | down | none (only used for wording)
    citation: str = ""
    url_info: str = ""
    notes: str = ""
    explain: str = ""              # one-line plain-language definition (shown in the app)
    explain_hi: str = ""
    quality_note: str = ""         # e.g. "quick-look product, not the original science data"
    enabled: bool = True
    benchmarks: list = field(default_factory=list)
    file: Path | None = None

    @property
    def needs_login(self) -> bool:
        return bool(self.access.get("login", self.access.get("method") == "earthaccess"))

    @property
    def is_driver(self) -> bool:
        return self.role in ("driver", "both")

    @property
    def is_layer(self) -> bool:
        return self.role in ("layer", "both") and self.kind in ("grid",)

    def label(self, lang: str = "en") -> str:
        if lang == "hi" and self.title_hi:
            return self.title_hi
        return self.title


def source_from_dict(d: dict, file: Path | None = None) -> Source:
    missing = [k for k in ("id", "title", "kind", "access") if k not in d]
    if missing:
        raise DetectiveError(f"{file}: missing required keys {missing}")
    if d["kind"] not in KINDS:
        raise DetectiveError(f"{file}: kind must be one of {sorted(KINDS)}")
    if "method" not in d["access"]:
        raise DetectiveError(f"{file}: access.method is required")
    known = {f for f in Source.__dataclass_fields__}  # type: ignore[attr-defined]
    extra = set(d) - known
    if extra:
        log.debug("%s: ignoring unknown keys %s", file, sorted(extra))
    kwargs = {k: v for k, v in d.items() if k in known}
    src = Source(**kwargs)
    src.file = file
    if not src.short:
        src.short = src.title
    if src.sphere not in SPHERES:
        log.debug("%s: unusual sphere %r", src.id, src.sphere)
    if isinstance(src.seasons, str):
        src.seasons = [src.seasons]
    return src


def load_sources(folder: Path | None = None, include_disabled: bool = False) -> dict[str, Source]:
    folder = folder or PIPELINE_DIR / "sources"
    out: dict[str, Source] = {}
    for f in sorted(Path(folder).glob("*.yaml")):
        if f.name.startswith("_"):
            continue
        src = source_from_dict(load_yaml(f), f)
        if src.id in out:
            raise DetectiveError(f"Duplicate source id {src.id!r} in {f} and {out[src.id].file}")
        if src.enabled or include_disabled:
            out[src.id] = src
    return out


def load_cases(folder: Path | None = None, include_disabled: bool = False) -> dict[str, dict]:
    folder = folder or PIPELINE_DIR / "cases"
    out: dict[str, dict] = {}
    for f in sorted(Path(folder).glob("*.yaml")):
        if f.name.startswith("_"):
            continue
        c = load_yaml(f)
        for k in ("id", "title", "type"):
            if k not in c:
                raise DetectiveError(f"{f}: case missing {k!r}")
        c["_file"] = str(f)
        if c.get("enabled", True) or include_disabled:
            out[c["id"]] = c
    return out


def load_places(path: Path | None = None) -> list[dict]:
    path = path or PIPELINE_DIR / "places.yaml"
    if not Path(path).exists():
        return []
    return list(load_yaml(path).get("places", []))
