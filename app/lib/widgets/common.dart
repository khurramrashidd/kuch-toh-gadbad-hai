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
        color: c,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: dense ? 12 : 15, color: Colors.white),
        const SizedBox(width: 4),
        Text(verdictText(context.lang, code), style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: dense ? 11 : 12.5)),
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
          color: c.withValues(alpha: 0.14),
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
  const SectionTitle(this.text, {super.key, this.icon, this.color});
  final String text;
  final IconData? icon;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Row(children: [
        if (icon != null) ...[IconBadge(icon!, color: color ?? context.k.accent, size: 30), const SizedBox(width: 10)],
        Expanded(child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 17))),
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
      decoration: BoxDecoration(color: (color ?? context.k.accent).withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: (color ?? context.k.accent).withValues(alpha: 0.25))),
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

/// Marks the area inside the main shell, whose own header already shows the actions.
class InShell extends InheritedWidget {
  const InShell({super.key, required super.child});
  @override
  bool updateShouldNotify(covariant InShell oldWidget) => false;
}

/// Mode + theme + language, used in every pushed screen's app bar (hidden inside the shell).
class HeaderActions extends StatelessWidget {
  const HeaderActions({super.key, this.force = false});
  final bool force;
  @override
  Widget build(BuildContext context) {
    if (!force && context.getInheritedWidgetOfExactType<InShell>() != null) return const SizedBox.shrink();
    final compact = MediaQuery.sizeOf(context).width < 700;
    if (!compact) return const Row(mainAxisSize: MainAxisSize.min, children: [ModeButton(), ThemeButton(), LangButton()]);
    final app = context.app;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      IconButton(
        tooltip: tx(context, app.expert ? 'Scientist mode (tap for Simple)' : 'Simple mode (tap for Scientist)', app.expert ? 'वैज्ञानिक मोड' : 'सरल मोड'),
        onPressed: () => AppScope.read(context).toggleExpert(),
        icon: Icon(app.expert ? Icons.science : Icons.emoji_objects_outlined, color: context.k.accent),
      ),
      const ThemeButton(),
      IconButton(
        tooltip: context.t('language'),
        onPressed: () => AppScope.read(context).toggleLang(),
        icon: Icon(Icons.translate, color: context.k.accent),
      ),
    ]);
  }
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

/// Subtle orbital curves: the only decorative motif in the app (kept faint on purpose).
class OrbitPainter extends CustomPainter {
  OrbitPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = color;
    final c = Offset(size.width * 0.86, size.height * 0.2);
    for (var i = 0; i < 3; i++) {
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(-0.42 + i * 0.16);
      final w = size.height * (1.5 + i * 0.75);
      canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: w * 1.9, height: w * 0.72), paint);
      canvas.restore();
    }
    canvas.drawCircle(c + Offset(-size.height * 0.95, size.height * 0.34), 3.2, Paint()..color = color.withValues(alpha: (color.a * 2.5).clamp(0, 1)));
  }

  @override
  bool shouldRepaint(covariant OrbitPainter old) => old.color != color;
}

/// Top-of-page hero: one sentence of purpose and the three steps.
class HeroPanel extends StatelessWidget {
  const HeroPanel({super.key});
  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final wide = MediaQuery.sizeOf(context).width >= 700;
    Widget step(IconData icon, String label, String sub) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13.5)),
            Text(sub, style: TextStyle(color: Colors.white.withValues(alpha: 0.78), fontSize: 11.5)),
          ]),
        ]);
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [k.brand.first, k.brand.last, k.dark ? const Color(0xFF0F766E) : const Color(0xFF14B8A6)])),
        child: CustomPaint(
          painter: OrbitPainter(Colors.white.withValues(alpha: 0.10)),
          child: Padding(
            padding: EdgeInsets.all(wide ? 22 : 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tx(context, 'EARTH SYSTEM TREND DETECTIVE', 'पृथ्वी तंत्र रुझान जासूस'), style: const TextStyle(color: Color(0xFFFFC078), fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
              const SizedBox(height: 6),
              Text(tx(context, 'Is the change real? Ask the data.', 'क्या बदलाव असली है? डेटा से पूछिए।'), style: TextStyle(color: Colors.white, fontSize: wide ? 30 : 23, fontWeight: FontWeight.w900, height: 1.15, letterSpacing: -0.3, fontFamily: kHeadFont)),
              const SizedBox(height: 6),
              Text(
                  tx(context, 'Other tools draw the line. We tell you if it is real, why it is happening, and how to check us.',
                      'दूसरे टूल रेखा खींचते हैं। हम बताते हैं कि वह असली है या नहीं, क्यों हो रहा है, और हमें कैसे परखें।'),
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.88), fontSize: 14, height: 1.4)),
              const SizedBox(height: 14),
              Wrap(spacing: 18, runSpacing: 10, children: [
                step(Icons.help_outline, tx(context, '1  Ask', '1  पूछें'), tx(context, 'what and where', 'क्या और कहाँ')),
                step(Icons.show_chart, tx(context, '2  Test', '2  परखें'), tx(context, 'rate and significance', 'दर और महत्व')),
                step(Icons.gavel, tx(context, '3  Verdict', '3  फ़ैसला'), tx(context, 'in plain words', 'सरल शब्दों में')),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Coloured rounded square with an icon: the small badge used on section titles and cards.
class IconBadge extends StatelessWidget {
  const IconBadge(this.icon, {super.key, required this.color, this.size = 38, this.solid = false});
  final IconData icon;
  final Color color;
  final double size;
  final bool solid;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: solid ? color : color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(size * 0.3)),
        child: Icon(icon, color: solid ? Colors.white : color, size: size * 0.58),
      );
}

/// Content fades and slides up once when it first appears (skipped when the device asks for less motion).
class FadeSlideIn extends StatelessWidget {
  const FadeSlideIn({super.key, required this.child, this.delayMs = 0, this.dy = 16});
  final Widget child;
  final int delayMs;
  final double dy;
  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) return child;
    final total = 420 + delayMs;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      curve: Interval(delayMs / total, 1, curve: Curves.easeOutCubic),
      builder: (context, v, ch) => Opacity(opacity: v.clamp(0.0, 1.0), child: Transform.translate(offset: Offset(0, (1 - v) * dy), child: ch)),
      child: child,
    );
  }
}

/// Large gradient card that leads somewhere; shrinks slightly while pressed.
class ActionCard extends StatefulWidget {
  const ActionCard({super.key, required this.color, required this.icon, required this.title, required this.text, required this.onTap, this.width});
  final Color color;
  final IconData icon;
  final String title, text;
  final VoidCallback onTap;
  final double? width;
  @override
  State<ActionCard> createState() => _ActionCardState();
}

class _ActionCardState extends State<ActionCard> {
  bool _down = false;
  @override
  Widget build(BuildContext context) {
    final c = widget.color;
    return SizedBox(
      width: widget.width,
      child: AnimatedScale(
        scale: _down ? 0.97 : 1,
        duration: const Duration(milliseconds: 110),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [c, Color.lerp(c, const Color(0xFF0B1F3A), 0.32)!]),
            boxShadow: [BoxShadow(color: c.withValues(alpha: 0.30), blurRadius: 14, offset: const Offset(0, 6))],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: widget.onTap,
              onHighlightChanged: (v) => setState(() => _down = v),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.20), borderRadius: BorderRadius.circular(14)),
                    child: Icon(widget.icon, color: Colors.white, size: 26),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text(widget.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17, fontFamily: kHeadFont)),
                      const SizedBox(height: 2),
                      Text(widget.text, style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 12.5, height: 1.3)),
                    ]),
                  ),
                  const Icon(Icons.arrow_forward_rounded, color: Colors.white),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The main result: a full-width coloured banner with icon, verdict, rate, one plain sentence and a stamp.
class VerdictBanner extends StatelessWidget {
  const VerdictBanner({super.key, required this.code, required this.sentence, this.rate});
  final String code, sentence;
  final String? rate;
  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final c = k.verdict(code);
    final hi = context.lang == 'hi';
    final icon = switch (code) {
      'confirmed' => Icons.verified_rounded,
      'likely' => Icons.thumb_up_alt_rounded,
      'artifact' => Icons.flag_rounded,
      'not_proven' => Icons.hourglass_top_rounded,
      _ => Icons.help_rounded,
    };
    final stamp = switch (code) {
      'confirmed' => hi ? 'असली' : 'REAL',
      'likely' => hi ? 'संभावित' : 'LIKELY',
      'artifact' => hi ? 'झूठा अलार्म' : 'FALSE ALARM',
      'not_proven' => hi ? 'साबित नहीं' : 'NOT PROVEN',
      _ => hi ? 'डेटा कम' : 'NO DATA',
    };
    final still = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final stampBox = Transform.rotate(
      angle: -0.09,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 2.4), borderRadius: BorderRadius.circular(6), color: Colors.white.withValues(alpha: 0.14)),
        child: Text(stamp, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 1.1, fontSize: 12.5, fontFamily: 'monospace')),
      ),
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [c, Color.lerp(c, const Color(0xFF0B1F3A), 0.30)!]),
        boxShadow: [BoxShadow(color: c.withValues(alpha: 0.28), blurRadius: 12, offset: const Offset(0, 5))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(verdictText(context.lang, code), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 20, height: 1.15, fontFamily: kHeadFont))),
          const SizedBox(width: 8),
          if (still)
            stampBox
          else
            TweenAnimationBuilder<double>(
              key: ValueKey(code),
              tween: Tween(begin: 2.2, end: 1),
              duration: const Duration(milliseconds: 520),
              curve: Curves.easeOutBack,
              builder: (context, v, ch) => Opacity(opacity: (2.2 - v).clamp(0.0, 1.0), child: Transform.scale(scale: v, child: ch)),
              child: stampBox,
            ),
        ]),
        if (rate != null) ...[
          const SizedBox(height: 10),
          Text(rate!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 22, fontFamily: kHeadFont)),
        ],
        const SizedBox(height: 4),
        Text(sentence, style: const TextStyle(color: Colors.white, height: 1.35, fontSize: 14)),
      ]),
    );
  }
}
