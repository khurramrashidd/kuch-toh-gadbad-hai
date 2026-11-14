"""Colour palettes and PNG rendering of trend maps (equirectangular, north up)."""
from __future__ import annotations

import io

import numpy as np
from PIL import Image

from .util import write_bytes_atomic


def _save_png(img: "Image.Image", path) -> None:
    buf = io.BytesIO()
    img.save(buf, format="PNG", optimize=True)
    write_bytes_atomic(path, buf.getvalue())

PALETTES = {
    # negative ... zero ... positive
    "temp": ["#053061", "#2166ac", "#4393c3", "#92c5de", "#d1e5f0", "#f7f7f7", "#fddbc7", "#f4a582", "#d6604d", "#b2182b", "#67001f"],
    "precip": ["#543005", "#8c510a", "#bf812d", "#dfc27d", "#f6e8c3", "#f5f5f5", "#c7eae5", "#80cdc1", "#35978f", "#01665e", "#003c30"],
    "water": ["#67001f", "#b2182b", "#d6604d", "#f4a582", "#fddbc7", "#f7f7f7", "#d1e5f0", "#92c5de", "#4393c3", "#2166ac", "#053061"],
    "ice": ["#67001f", "#b2182b", "#d6604d", "#f4a582", "#fddbc7", "#f7f7f7", "#d1e5f0", "#92c5de", "#4393c3", "#2166ac", "#053061"],
    "green": ["#8e0152", "#c51b7d", "#de77ae", "#f1b6da", "#fde0ef", "#f7f7f7", "#e6f5d0", "#b8e186", "#7fbc41", "#4d9221", "#276419"],
    "air": ["#2d004b", "#542788", "#8073ac", "#b2abd2", "#d8daeb", "#f7f7f7", "#fee0b6", "#fdb863", "#e08214", "#b35806", "#7f3b08"],
    "generic": ["#2d004b", "#542788", "#8073ac", "#b2abd2", "#d8daeb", "#f7f7f7", "#fee0b6", "#fdb863", "#e08214", "#b35806", "#7f3b08"],
}


def _hex(h: str) -> tuple[int, int, int]:
    h = h.lstrip("#")
    return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)


def palette(name: str) -> list[str]:
    return PALETTES.get(name, PALETTES["generic"])


def colorize(values: np.ndarray, vmax: float, name: str) -> np.ndarray:
    stops = np.array([_hex(c) for c in palette(name)], dtype="float64")
    nstop = len(stops)
    with np.errstate(invalid="ignore"):
        x = np.clip((values / (vmax if vmax > 0 else 1.0) + 1.0) / 2.0, 0.0, 1.0)
    pos = np.nan_to_num(x, nan=0.5) * (nstop - 1)
    i0 = np.clip(np.floor(pos).astype(int), 0, nstop - 2)
    frac = (pos - i0)[..., None]
    rgb = stops[i0] * (1 - frac) + stops[i0 + 1] * frac
    return rgb.astype("uint8")


def robust_vmax(values: np.ndarray, pct: float = 98.0) -> float:
    v = np.abs(values[np.isfinite(values)])
    if v.size == 0:
        return 1.0
    vm = float(np.percentile(v, pct))
    if vm <= 0:
        vm = float(v.max()) or 1.0
    # round to a "nice" legend number
    exp = 10 ** np.floor(np.log10(vm))
    for m in (1, 1.5, 2, 2.5, 3, 4, 5, 6, 8, 10):
        if m * exp >= vm:
            return float(m * exp)
    return float(10 * exp)


def trend_png(slope: np.ndarray, sig: np.ndarray, vmax: float, name: str, scale: int, path) -> None:
    """slope/sig: (nlat ascending, nlon). Significant cells are opaque, others faded."""
    rgb = colorize(slope, vmax, name)
    alpha = np.where(np.isfinite(slope), np.where(sig, 235, 95), 0).astype("uint8")
    rgba = np.dstack([rgb, alpha])[::-1]  # north up
    img = Image.fromarray(rgba, mode="RGBA")
    if scale > 1:
        img = img.resize((img.width * scale, img.height * scale), Image.NEAREST)
    _save_png(img, path)


def stipple_png(sig: np.ndarray, scale: int, path) -> None:
    """Small dark dots on significant cells (the classic 'stippling' of trend maps)."""
    s = max(scale, 3)
    h, w = sig.shape
    img = np.zeros((h * s, w * s, 4), dtype="uint8")
    d = max(1, s // 3)
    c = (s - d) // 2
    rows, cols = np.nonzero(sig[::-1])
    for r, q in zip(rows, cols):
        y, x = r * s + c, q * s + c
        img[y:y + d, x:x + d] = (20, 20, 20, 210)
    _save_png(Image.fromarray(img, mode="RGBA"), path)
