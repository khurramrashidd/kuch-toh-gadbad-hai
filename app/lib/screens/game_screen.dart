import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../stats/trend.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/trend_chart.dart';

class _Round {
  _Round(this.series, this.truth);
  final Series series;
  final int truth; // +1 real rise, -1 real fall, 0 nothing planted
  int? guess;
  late final TrendResult test = mkTrend(series.values, series.years, minYears: 8);
  int get testSays => test.valid && test.p < 0.05 ? (test.slope > 0 ? 1 : -1) : 0;
}

/// "Can you beat the test?" - ten charts, real trend or just noise?
/// Teaches in a minute why a significance test is needed: eyes love to see trends in noise.
class GameScreen extends StatefulWidget {
  const GameScreen({super.key});
  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late List<_Round> _rounds;
  int _i = 0;

  @override
  void initState() {
    super.initState();
    _new();
  }

  double _gauss(math.Random r) {
    final u = math.max(r.nextDouble(), 1e-12), v = r.nextDouble();
    return math.sqrt(-2 * math.log(u)) * math.cos(2 * math.pi * v);
  }

  void _new() {
    final r = math.Random();
    final kinds = [1, -1, 1, -1, 1, 0, 0, 0, 0, 0]..shuffle(r);
    _rounds = [
      for (final kind in kinds)
        () {
          final n = 28 + r.nextInt(14);
          final phi = kind == 0 ? 0.35 + 0.4 * r.nextDouble() : 0.5 * r.nextDouble(); // noise with memory wanders like a trend
          final strength = (1.3 + 1.6 * r.nextDouble()) / n; // total change of 1.3 to 2.9 noise widths
          var x = _gauss(r);
          final vals = <double?>[];
          for (var t = 0; t < n; t++) {
            x = phi * x + math.sqrt(1 - phi * phi) * _gauss(r);
            vals.add(x + kind * strength * t);
          }
          return _Round(Series([for (var t = 0; t < n; t++) 2025 - n + t], vals), kind);
        }()
    ];
    _i = 0;
  }

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final done = _i >= _rounds.length;
    final answered = _rounds.where((r) => r.guess != null).toList();
    final you = answered.where((r) => r.guess == r.truth).length;
    final test = answered.where((r) => r.testSays == r.truth).length;
    return Scaffold(
      appBar: AppBar(title: Text(tx(context, 'Can you beat the test?', 'क्या आप जाँच को हरा सकते हैं?')), actions: const [HeaderActions()]),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(padding: const EdgeInsets.fromLTRB(14, 10, 14, 40), children: [
            Text(
                tx(context, 'Half of these 10 charts hide a real trend. The rest are only random ups and downs. Look, decide, then see what the Mann-Kendall test says.',
                    'इन 10 चार्ट में से आधों में असली रुझान छिपा है। बाक़ी सिर्फ़ बेतरतीब उतार-चढ़ाव हैं। देखिए, तय कीजिए, फिर देखिए मान-केंडल जाँच क्या कहती है।'),
                style: const TextStyle(height: 1.35)),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: StatTile(label: tx(context, 'You', 'आप'), value: '$you / ${answered.length}', color: k.accent)),
              const SizedBox(width: 8),
              Expanded(child: StatTile(label: tx(context, 'The test', 'जाँच'), value: '$test / ${answered.length}', color: k.confirmed)),
              const SizedBox(width: 8),
              Expanded(child: StatTile(label: tx(context, 'Chart', 'चार्ट'), value: '${math.min(_i + 1, _rounds.length)} / ${_rounds.length}')),
            ]),
            const SizedBox(height: 12),
            if (!done) _round(context, _rounds[_i]) else _summary(context, you, test),
          ]),
        ),
      ),
    );
  }

  Widget _round(BuildContext context, _Round r) {
    final k = context.k;
    final shown = r.guess != null;
    String name(int v) => v > 0 ? tx(context, 'Really rising', 'सच में बढ़ रहा') : (v < 0 ? tx(context, 'Really falling', 'सच में घट रहा') : tx(context, 'Just noise', 'सिर्फ़ शोर'));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: k.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: k.line)),
        child: shown ? TrendChart(series: r.series, height: 210) : SizedBox(height: 210, child: CustomPaint(painter: _RawPainter(r.series, k), size: Size.infinite)),
      ),
      const SizedBox(height: 10),
      if (!shown)
        Row(children: [
          for (final g in const [1, 0, -1])
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: FilledButton.tonal(
                  onPressed: () => setState(() => r.guess = g),
                  child: Text(name(g), textAlign: TextAlign.center),
                ),
              ),
            ),
        ])
      else ...[
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: (r.guess == r.truth ? k.confirmed : k.artifact).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${tx(context, 'Truth', 'सच')}: ${name(r.truth)}', style: const TextStyle(fontWeight: FontWeight.w800)),
            Text('${tx(context, 'You said', 'आपने कहा')}: ${name(r.guess!)}  ${r.guess == r.truth ? '✓' : '✗'}'),
            Text('${tx(context, 'The test said', 'जाँच ने कहा')}: ${name(r.testSays)}  ${r.testSays == r.truth ? '✓' : '✗'}   (p = ${fmtP(r.test.p)})'),
            if (r.truth == 0 && r.guess != 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(tx(context, 'Noise with "memory" wanders, and the eye reads the wander as a trend.', '"याद" वाला शोर भटकता है, और आँख उस भटकाव को रुझान समझ लेती है।'), style: TextStyle(color: k.muted, fontSize: 12.5)),
              ),
          ]),
        ),
        const SizedBox(height: 8),
        FilledButton(onPressed: () => setState(() => _i++), child: Text(_i + 1 >= _rounds.length ? tx(context, 'See result', 'नतीजा देखें') : tx(context, 'Next chart', 'अगला चार्ट'))),
      ],
    ]);
  }

  Widget _summary(BuildContext context, int you, int test) {
    final k = context.k;
    final msg = you > test
        ? tx(context, 'You beat the test this time. It happens: the test is honest, not magic. That is why we also publish its error rate.', 'इस बार आपने जाँच को हरा दिया। ऐसा होता है: जाँच ईमानदार है, जादू नहीं। इसीलिए हम उसकी ग़लती की दर भी छापते हैं।')
        : (you == test
            ? tx(context, 'A tie. On noisy charts most people do worse than this.', 'बराबरी। शोर वाले चार्ट पर ज़्यादातर लोग इससे कम करते हैं।')
            : tx(context, 'The test won. Eyes see patterns in noise; a test counts how often chance alone would do this.', 'जाँच जीती। आँखें शोर में भी पैटर्न देख लेती हैं; जाँच गिनती है कि संयोग से ऐसा कितनी बार होता।'));
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: k.paper, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${tx(context, 'You', 'आप')} $you / 10   ·   ${tx(context, 'The test', 'जाँच')} $test / 10', style: TextStyle(color: k.ink, fontSize: 20, fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        Text(msg, style: TextStyle(color: k.ink, height: 1.35)),
        const SizedBox(height: 10),
        FilledButton.icon(onPressed: () => setState(_new), icon: const Icon(Icons.refresh), label: Text(tx(context, 'Play again', 'फिर खेलें'))),
      ]),
    );
  }
}

/// The bare line with no fitted trend, so the player is not helped.
class _RawPainter extends CustomPainter {
  _RawPainter(this.s, this.p);
  final Series s;
  final Palette p;
  @override
  void paint(Canvas canvas, Size size) {
    final v = s.values.whereType<double>().toList();
    if (v.length < 2) return;
    final lo = v.reduce(math.min), hi = v.reduce(math.max);
    final span = (hi - lo).abs() < 1e-9 ? 1.0 : hi - lo;
    final path = Path();
    for (var i = 0; i < s.values.length; i++) {
      final x = 8 + i / (s.values.length - 1) * (size.width - 16);
      final y = size.height - 10 - (s.values[i]! - lo) / span * (size.height - 20);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
      canvas.drawCircle(Offset(x, y), 2.2, Paint()..color = p.text);
    }
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = p.muted);
  }

  @override
  bool shouldRepaint(covariant _RawPainter old) => old.s != s || old.p != p;
}
