"""Small shared helpers: paths, logging, YAML/JSON I/O, number cleaning."""
from __future__ import annotations

import datetime as _dt
import json
import logging
import math
import os
import re
import sys
import time
from contextlib import contextmanager
from pathlib import Path
from typing import Any

import numpy as np
import yaml

PIPELINE_DIR = Path(__file__).resolve().parent.parent

log = logging.getLogger("detective")


def setup_logging(verbose: bool = False) -> None:
    """UTF-8 safe console logging (Windows cmd defaults to cp1252)."""
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")  # type: ignore[attr-defined]
        except Exception:  # pragma: no cover - very old consoles
            pass
    level = logging.DEBUG if verbose else logging.INFO
    logging.basicConfig(level=level, format="%(levelname)-7s %(message)s")
    # third-party libraries are chatty
    for name in ("urllib3", "earthaccess", "fsspec", "asyncio", "PIL", "h5py"):
        logging.getLogger(name).setLevel(logging.WARNING)


def load_yaml(path: Path | str) -> dict:
    with open(path, "r", encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}
    if not isinstance(data, dict):
        raise ValueError(f"{path}: expected a mapping at top level")
    return data


def dump_yaml(data: dict, path: Path | str) -> None:
    with open(path, "w", encoding="utf-8") as f:
        yaml.safe_dump(data, f, allow_unicode=True, sort_keys=False)


def round_sig(x: float, sig: int = 4) -> float:
    if x == 0 or not math.isfinite(x):
        return x
    return round(x, sig - int(math.floor(math.log10(abs(x)))) - 1)


def clean(obj: Any, sig: int | None = 4) -> Any:
    """Recursively convert numpy types to Python, NaN/inf to None and round floats."""
    if isinstance(obj, dict):
        return {str(k): clean(v, sig) for k, v in obj.items()}
    if isinstance(obj, (list, tuple)):
        return [clean(v, sig) for v in obj]
    if isinstance(obj, np.ndarray):
        return [clean(v, sig) for v in obj.tolist()]
    if isinstance(obj, (np.bool_,)):
        return bool(obj)
    if isinstance(obj, (np.integer,)):
        return int(obj)
    if isinstance(obj, (float, np.floating)):
        f = float(obj)
        if not math.isfinite(f):
            return None
        return round_sig(f, sig) if sig else f
    if isinstance(obj, (_dt.date, _dt.datetime)):
        return obj.isoformat()
    if isinstance(obj, np.datetime64):
        return str(obj)
    if isinstance(obj, Path):
        return obj.as_posix()
    return obj


def replace_file(tmp: Path | str, dest: Path | str, tries: int = 25) -> Path:
    """os.replace with retries: on Windows the target may be open for a moment (web server, app, other tab)."""
    tmp, dest = Path(tmp), Path(dest)
    for i in range(tries):
        try:
            os.replace(tmp, dest)
            return dest
        except PermissionError:
            time.sleep(0.05 * (i + 1))
    os.replace(tmp, dest)  # last try raises the real error
    return dest


def tmp_path(dest: Path | str) -> Path:
    """Hidden per-process temp name next to dest (dot-files are never deployed)."""
    dest = Path(dest)
    return dest.with_name(f".{dest.name}.{os.getpid()}.tmp")


def write_bytes_atomic(path: Path | str, data: bytes) -> Path:
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = tmp_path(path)
    with open(tmp, "wb") as f:
        f.write(data)
    return replace_file(tmp, path)


def write_json(path: Path | str, obj: Any, sig: int | None = 4) -> Path:
    """Atomic: readers (the app, the web server, another pipeline tab) never see a half-written file."""
    data = json.dumps(clean(obj, sig), ensure_ascii=False, separators=(",", ":"))
    return write_bytes_atomic(path, data.encode("utf-8"))


def read_json(path: Path | str) -> Any:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def now_iso() -> str:
    return _dt.datetime.now(_dt.timezone.utc).replace(microsecond=0).isoformat()


def slugify(text: str) -> str:
    text = re.sub(r"[^a-zA-Z0-9]+", "-", text.strip().lower()).strip("-")
    return text or "item"


def ensure_dir(path: Path | str) -> Path:
    path = Path(path)
    path.mkdir(parents=True, exist_ok=True)
    return path


class DetectiveError(RuntimeError):
    """An expected, user-facing failure (bad config, missing login, ...)."""


class LoginRequired(DetectiveError):
    pass


# ----------------------------------------------------------------------------- locks (parallel runs in several tabs)
LOCK_SUFFIX = ".lock"


@contextmanager
def file_lock(path: Path | str, what: str, timeout: float = 3600.0):
    """Cross-process lock via an exclusive lock file. Another tab doing the same thing makes us wait.

    A lock left behind by a closed window is removed with:  python -m detective unlock
    """
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    t0 = time.time()
    told = False
    while True:
        try:
            fd = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
            os.write(fd, f"pid {os.getpid()} since {now_iso()} : {what}".encode("utf-8"))
            os.close(fd)
            break
        except FileExistsError:
            if not told:
                try:
                    holder = path.read_text(encoding="utf-8", errors="replace")
                except OSError:
                    holder = "?"
                log.info("waiting: another run is busy with %s (%s). If no other run is open: python -m detective unlock", what, holder)
                told = True
            if time.time() - t0 > timeout:
                raise DetectiveError(f"gave up waiting for {what}; if no other run is active: python -m detective unlock")
            time.sleep(0.5)
    try:
        yield
    finally:
        try:
            path.unlink()
        except OSError:
            pass
