import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../stats/trend.dart';
import '../theme.dart';
import 'common.dart';

/// Yearly values + Sen trend line + 95% fan + "signal emerged" and "sudden shift" markers.
/// The chart fits its own trend from the plotted numbers, so the line always matches the dots.
class TrendChart extends StatelessWidget {
  const TrendChart({
    super.key,
    required this.series,
    this.color,
    this.height = 170,
    this.unitLabel = '',
    this.emergedLabel = 'signal',
    this.breakLabel = 'shift',
  });
  final Series series;
  final Color? color;
  final double height;
  final String unitLabel, emergedLabel, breakLabel;

  @override
  Widget build(BuildContext context) {
    final fit = series.isEmpty ? null : mkTrend(series.values, series.years, minYears: 8);
    final pt = series.isEmpty ? null : pettitt(series.values, series.years);
    final k = context.k;
    return SizedBox(
      height: height,
      child: CustomPaint(
        size: Size.infinite,
        painter: _ChartPainter(series, fit, pt, color ?? k.accent, unitLabel, emergedLabel, breakLabel, k),
      ),
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter(this.s, this.fit, this.pt, this.color, this.unit, this.emLabel, this.brLabel, this.p);
  final Series s;
  final TrendResult? fit;
  final PettittResult? pt;
  final Color color;
  final String unit, emLabel, brLabel;
  final Palette p;

  static const _left = 46.0, _right = 10.0, _top = 12.0, _bottom = 22.0;

  void _text(Canvas c, String t, Offset at, {Color? col, double size = 10, bool alignRight = false, bool center = false}) {
    final tp = TextPainter(text: TextSpan(text: t, style: TextStyle(color: col ?? p.muted, fontSize: size)), textDirection: TextDirection.ltr)
      ..layout();
    var o = at;
    if (alignRight) o = Offset(at.dx - tp.width, at.dy);
    if (center) o = Offset(at.dx - tp.width / 2, at.dy);
    tp.paint(c, o);
  }

  void _dashed(Canvas c, Offset a, Offset b, Paint p, {double dash = 4, double gap = 3}) {
    final d = (b - a);
    final len = d.distance;
    if (len == 0) return;
    final dir = d / len;
    var pos = 0.0;
    while (pos < len) {
      final e = math.min(pos + dash, len);
      c.drawLine(a + dir * pos, a + dir * e, p);
      pos = e + gap;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final pts = <(int, double)>[];
    for (var i = 0; i < s.years.length && i < s.values.length; i++) {
      final v = s.values[i];
      if (v != null && v.isFinite) pts.add((s.years[i], v));
    }
    final w = size.width - _left - _right, h = size.height - _top - _bottom;
    if (pts.length < 2 || w <= 0 || h <= 0) {
      _text(canvas, '–', Offset(size.width / 2, size.height / 2), center: true);
      return;
    }
    final x0 = s.years.first.toDouble(), x1 = s.years.last.toDouble();
    var lo = pts.map((e) => e.$2).reduce(math.min), hi = pts.map((e) => e.$2).reduce(math.max);
    final f = fit;
    if (f != null && f.slope.isFinite) {
      final a = f.intercept + f.slope * x0, b = f.intercept + f.slope * x1;
      lo = math.min(lo, math.min(a, b));
      hi = math.max(hi, math.max(a, b));
    }
    final pad = (hi - lo).abs() < 1e-12 ? 1.0 : (hi - lo) * 0.08;
    lo -= pad;
    hi += pad;
    double px(num yr) => _left + (yr - x0) / math.max(1, x1 - x0) * w;
    double py(double v) => _top + (1 - (v - lo) / (hi - lo)) * h;

    final grid = Paint()
      ..color = p.line
      ..strokeWidth = 1;
    for (var k = 0; k <= 3; k++) {
      final v = lo + (hi - lo) * k / 3;
      final y = py(v);
      canvas.drawLine(Offset(_left, y), Offset(size.width - _right, y), grid);
      _text(canvas, fmtNum(v), Offset(_left - 4, y - 6), alignRight: true);
    }
    if (lo < 0 && hi > 0) {
      canvas.drawLine(Offset(_left, py(0)), Offset(size.width - _right, py(0)), Paint()
        ..color = p.muted.withValues(alpha: 0.5)
        ..strokeWidth = 1);
    }
    final span = (x1 - x0).round();
    final step = span > 60 ? 20 : (span > 30 ? 10 : 5);
    for (var yr = ((x0 / step).ceil() * step); yr <= x1; yr += step) {
      _text(canvas, '$yr', Offset(px(yr), size.height - _bottom + 5), center: true);
    }
    if (unit.isNotEmpty) _text(canvas, unit, const Offset(2, 0), size: 9.5);

    // trend fan + line
    if (f != null && f.slope.isFinite) {
      final tm = (x0 + x1) / 2;
      final ym = f.intercept + f.slope * tm;
      if (f.ciLo.isFinite && f.ciHi.isFinite) {
        final fan = Path()
          ..moveTo(px(x0), py(ym + f.ciLo * (x0 - tm)))
          ..lineTo(px(x1), py(ym + f.ciLo * (x1 - tm)))
          ..lineTo(px(x1), py(ym + f.ciHi * (x1 - tm)))
          ..lineTo(px(x0), py(ym + f.ciHi * (x0 - tm)))
          ..close();
        canvas.drawPath(fan, Paint()..color = color.withValues(alpha: 0.10));
      }
      canvas.drawLine(
        Offset(px(x0), py(f.intercept + f.slope * x0)),
        Offset(px(x1), py(f.intercept + f.slope * x1)),
        Paint()
          ..color = color.withValues(alpha: 0.95)
          ..strokeWidth = 2.2,
      );
      if (f.emerged) {
        final x = px(f.toe1);
        _dashed(canvas, Offset(x, _top), Offset(x, _top + h), Paint()
          ..color = p.confirmed
          ..strokeWidth = 1.4);
        _text(canvas, '$emLabel ${f.toe1.round()}', Offset(x + 3, _top), col: p.confirmed, size: 9.5);
      }
    }
    final brk = pt;
    if (brk != null && brk.p < 0.05) {
      final x = px(brk.year);
      _dashed(canvas, Offset(x, _top + 12), Offset(x, _top + h), Paint()
        ..color = p.string
        ..strokeWidth = 1.2, dash: 2, gap: 3);
      _text(canvas, '$brLabel ${brk.year}', Offset(x + 3, _top + h - 12), col: p.string, size: 9.5);
    }

    // data
    final line = Path();
    var started = false;
    var prevYear = -9999;
    for (final (yr, v) in pts) {
      final o = Offset(px(yr), py(v));
      if (!started || yr - prevYear > 1) {
        line.moveTo(o.dx, o.dy);
        started = true;
      } else {
        line.lineTo(o.dx, o.dy);
      }
      prevYear = yr;
    }
    canvas.drawPath(line, Paint()
      ..color = p.text.withValues(alpha: 0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3);
    final dot = Paint()..color = p.text;
    for (final (yr, v) in pts) {
      canvas.drawCircle(Offset(px(yr), py(v)), pts.length > 80 ? 1.4 : 2.2, dot);
    }
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) => old.s != s || old.color != color || old.p != p;
}
