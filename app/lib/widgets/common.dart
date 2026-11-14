import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../l10n/strings.dart';
import '../theme.dart';

/// Inline two-language text.
String tx(BuildContext context, String en, String hi) => context.lang == 'hi' ? hi : en;

String fmtNum(double? x, {int digits = 2}) {
  if (x == null || !x.isFinite) return '–';
  final a = x.abs();
  if (a >= 100) return x.toStringAsFixed(0);
  if (a >= 10) return x.toStringAsFixed(1);
  if (a >= 1) return x.toStringAsFixed(digits);
  if (a == 0) return '0';
  final d = math.max(digits, 1 - (math.log(a) / math.ln10).floor());
  return x.toStringAsFixed(math.min(d, 6));
}

String fmtSigned(double? x, {int digits = 2}) {
  if (x == null || !x.isFinite) return '–';
  return (x > 0 ? '+' : '') + fmtNum(x, digits: digits);
}

String fmtP(double? p) {
  if (p == null || !p.isFinite) return '–';
  if (p < 0.001) return '< 0.001';
  return p.toStringAsFixed(3);
}

class VerdictChip extends StatelessWidget {
  const VerdictChip(this.code, {super.key, this.dense = false});
  final String code;
  final bool dense;
  @override
  Widget build(BuildContext context) {
    final c = context.k.verdict(code);
    final icon = switch (code) {
      'confirmed' => Icons.verified,
      'likely' => Icons.help,
      'artifact' => Icons.flag,
      'not_proven' => Icons.hourglass_empty,
      _ => Icons.remove_circle_outline,
    };
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 6 : 9, vertical: dense ? 2 : 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: 0.8)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: dense ? 12 : 15, color: c),
        const SizedBox(width: 4),
        Text(verdictText(context.lang, code), style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: dense ? 11 : 12.5)),
      ]),
    );
  }
}

/// Rubber stamp for a whole case.
class CaseStamp extends StatelessWidget {
  const CaseStamp({super.key, required this.code, required this.label, this.size = 1.0});
  final String code, label;
  final double size;
  @override
  Widget build(BuildContext context) {
    final c = context.k.caseVerdict(code);
    return Transform.rotate(
      angle: -0.05,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12 * size, vertical: 6 * size),
        decoration: BoxDecoration(
          border: Border.all(color: c, width: 2.5 * size),
          borderRadius: BorderRadius.circular(6),
          color: c.withValues(alpha: 0.08),
        ),
        child: Text(
          label.toUpperCase(),
          style: TextStyle(color: c, fontWeight: FontWeight.w900, letterSpacing: 1.2, fontSize: 13 * size, fontFamily: 'monospace'),
        ),
      ),
    );
  }
}

class DemoBanner extends StatelessWidget {
  const DemoBanner({super.key});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: context.k.artifact,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Text(context.t('demo_banner'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.icon});
  final String text;
  final IconData? icon;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Row(children: [
        if (icon != null) ...[Icon(icon, size: 18, color: context.k.accent), const SizedBox(width: 8)],
        Expanded(child: Text(text, style: Theme.of(context).textTheme.titleMedium)),
      ]),
    );
  }
}

class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value, this.color});
  final String label, value;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: context.k.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: context.k.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: TextStyle(color: context.k.muted, fontSize: 11)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(color: color ?? context.k.text, fontWeight: FontWeight.w800, fontSize: 15)),
      ]),
    );
  }
}

/// Two normalised mini-lines (rising side vs falling side).
class TwinSparkline extends StatelessWidget {
  const TwinSparkline({super.key, required this.a, required this.b, required this.signA, required this.signB, this.height = 46});
  final List<double?> a, b;
  final int signA, signB;
  final double height;
  @override
  Widget build(BuildContext context) {
    return SizedBox(height: height, child: CustomPaint(painter: _SparkPainter(a, b, context.k.signColor(signA), context.k.signColor(signB)), size: Size.infinite));
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.a, this.b, this.ca, this.cb);
  final List<double?> a, b;
  final Color ca, cb;

  void _line(Canvas canvas, Size size, List<double?> v, Color c) {
    final vals = v.whereType<double>().where((e) => e.isFinite).toList();
    if (vals.length < 2) return;
    final lo = vals.reduce(math.min), hi = vals.reduce(math.max);
    final span = (hi - lo).abs() < 1e-12 ? 1.0 : hi - lo;
    final path = Path();
    var started = false;
    for (var i = 0; i < v.length; i++) {
      final y = v[i];
      if (y == null || !y.isFinite) {
        started = false;
        continue;
      }
      final px = v.length == 1 ? 0.0 : i / (v.length - 1) * size.width;
      final py = size.height - 3 - (y - lo) / span * (size.height - 6);
      if (!started) {
        path.moveTo(px, py);
        started = true;
      } else {
        path.lineTo(px, py);
      }
    }
    canvas.drawPath(path, Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round);
  }

  @override
  void paint(Canvas canvas, Size size) {
    _line(canvas, size, a, ca);
    _line(canvas, size, b, cb);
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) => old.a != a || old.b != b;
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color});
  final String text;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final c = color ?? context.k.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
      child: Text(text, style: TextStyle(color: c, fontSize: 11.5, fontWeight: FontWeight.w600)),
    );
  }
}

class LangButton extends StatelessWidget {
  const LangButton({super.key});
  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () => AppScope.read(context).toggleLang(),
      icon: Icon(Icons.translate, size: 18, color: context.k.accent),
      label: Text(context.t('language'), style: TextStyle(color: context.k.accent, fontWeight: FontWeight.w700)),
    );
  }
}

class ThemeButton extends StatelessWidget {
  const ThemeButton({super.key});
  @override
  Widget build(BuildContext context) {
    final dark = context.app.dark;
    return IconButton(
      tooltip: context.t(dark ? 'theme_light' : 'theme_dark'),
      onPressed: () => AppScope.read(context).toggleTheme(),
      icon: Icon(dark ? Icons.light_mode : Icons.dark_mode, color: context.k.accent),
    );
  }
}

/// Theme toggle + language toggle, used in every screen header.
class HeaderActions extends StatelessWidget {
  const HeaderActions({super.key});
  @override
  Widget build(BuildContext context) => const Row(mainAxisSize: MainAxisSize.min, children: [ModeButton(), ThemeButton(), LangButton()]);
}

/// Simple (plain words) <-> Scientist (all numbers) switch.
class ModeButton extends StatelessWidget {
  const ModeButton({super.key});
  @override
  Widget build(BuildContext context) {
    final expert = context.app.expert;
    return Tooltip(
      message: tx(context, expert ? 'Scientist mode: all numbers shown. Tap for Simple.' : 'Simple mode. Tap for Scientist mode (all numbers).',
          expert ? 'वैज्ञानिक मोड: सारे आँकड़े। सरल के लिए दबाएँ।' : 'सरल मोड। वैज्ञानिक मोड (सारे आँकड़े) के लिए दबाएँ।'),
      child: TextButton.icon(
        onPressed: () => AppScope.read(context).toggleExpert(),
        icon: Icon(expert ? Icons.science : Icons.emoji_objects_outlined, size: 18, color: context.k.accent),
        label: Text(tx(context, expert ? 'Scientist' : 'Simple', expert ? 'वैज्ञानिक' : 'सरल'), style: TextStyle(color: context.k.accent, fontWeight: FontWeight.w700)),
      ),
    );
  }
}
