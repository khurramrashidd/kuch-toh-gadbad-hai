"""Verdict codes and the plain-language (English + Hindi) wording of the evidence."""
from __future__ import annotations

import math

# per-trend verdicts (also used as integer codes in map cells)
TREND = {
    "confirmed":    {"code": 4, "en": "Confirmed",          "hi": "पक्का सबूत",       "emoji": "✅"},
    "likely":       {"code": 3, "en": "Likely",             "hi": "शक गहरा है",       "emoji": "🟡"},
    "not_proven":   {"code": 2, "en": "Not proven yet",     "hi": "अभी साबित नहीं",   "emoji": "⚪"},
    "artifact":     {"code": 5, "en": "Artifact suspected", "hi": "नकली सुराग?",      "emoji": "🚩"},
    "insufficient": {"code": 1, "en": "Not enough data",    "hi": "डेटा कम है",        "emoji": "▫️"},
}
CODE_TO_TREND = {v["code"]: k for k, v in TREND.items()}

# mirror-case verdicts
CASE = {
    "shared_strong": {"en": "Same cause, opposite effects", "hi": "एक ही वजह, उल्टा असर"},
    "shared_weak":   {"en": "Probably the same cause",      "hi": "शायद एक ही वजह"},
    "other_cause":   {"en": "Different culprit at work",    "hi": "असली वजह कुछ और है"},
    "not_mirror":    {"en": "Mirror not proven",             "hi": "उल्टा रुझान साबित नहीं"},
    "open":          {"en": "Case still open",               "hi": "केस अभी खुला है"},
}

CHECKS = {
    "witnesses": {"en": "Witnesses", "hi": "गवाह"},
    "signal":    {"en": "Signal vs noise", "hi": "सिग्नल बनाम शोर"},
    "alibi":     {"en": "Alibi check", "hi": "बहाने की जाँच"},
    "timeline":  {"en": "Timeline", "hi": "समय-रेखा"},
    "motive":    {"en": "Motive", "hi": "मक़सद (वजह)"},
}


def trend_verdict(p: float, snr: float, n: float, cfg: dict, artifact: bool = False, q: float | None = None) -> str:
    if n is None or not math.isfinite(n) or n < cfg.get("min_years", 15) or p is None or not math.isfinite(p):
        return "insufficient"
    if artifact:
        return "artifact"
    test = q if (q is not None and math.isfinite(q)) else p
    alpha = cfg.get("fdr_alpha", 0.10) if q is not None else cfg.get("alpha", 0.05)
    if test < alpha and snr is not None and math.isfinite(snr) and snr >= cfg.get("snr_confirm", 1.0):
        return "confirmed"
    if test < alpha or p < 0.10:
        return "likely"
    return "not_proven"


def fmt(x: float | None, digits: int = 2) -> str:
    if x is None or not isinstance(x, (int, float)) or not math.isfinite(x):
        return "-"
    ax = abs(x)
    if ax >= 100:
        return f"{x:,.0f}"
    if ax >= 10:
        return f"{x:.1f}"
    if ax >= 1:
        return f"{x:.{digits}f}"
    if ax == 0:
        return "0"
    return f"{x:.{max(digits, 1 - int(math.floor(math.log10(ax))))}f}"


def fmt_p(p: float | None) -> str:
    if p is None or not math.isfinite(p):
        return "-"
    if p < 0.001:
        return "< 0.001"
    return f"{p:.3f}"


def direction_words(slope: float, gender_hi: str = "m") -> tuple[str, str]:
    f = gender_hi == "f"
    if slope is None or not math.isfinite(slope) or slope == 0:
        return "flat", "स्थिर है"
    if slope > 0:
        return "rising", "बढ़ रही है" if f else "बढ़ रहा है"
    return "falling", "घट रही है" if f else "घट रहा है"
