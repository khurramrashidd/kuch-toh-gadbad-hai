import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models/models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/trend_chart.dart';
import '../widgets/world_map.dart';
import 'case_detail_screen.dart';

/// A watchable walk-through of one real case: plays by itself, step by step.
class TourScreen extends StatefulWidget {
  const TourScreen({super.key, required this.summary});
  final CaseSummary summary;
  @override
  State<TourScreen> createState() => _TourScreenState();
}

class _TourScreenState extends State<TourScreen> {
  static const _steps = 6;
  static const _seconds = 9;
  late Future<CaseFile> _case;
  int _step = 0;
  bool _playing = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _case = AppScope.read(context).data.caseFile(widget.summary.file);
    _timer = Timer.periodic(const Duration(seconds: _seconds), (_) {
      if (!_playing || !mounted) return;
      if (_step < _steps - 1) {
        setState(() => _step++);
      } else {
        setState(() => _playing = false);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.lang;
    final k = context.k;
    return Scaffold(
      appBar: AppBar(title: Text(tx(context, 'Watch a demo case', 'डेमो केस देखें')), actions: const [HeaderActions()]),
      body: FutureBuilder<CaseFile>(
        future: _case,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('${snap.error}'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final c = snap.data!;
          final a = c.regions.isNotEmpty ? c.regions[0] : null;
          final b = c.regions.length > 1 ? c.regions[1] : null;
          final titles = [
            tx(context, '1. The question', '1. सवाल'),
            tx(context, '2. Where: two regions', '2. कहाँ: दो क्षेत्र'),
            tx(context, '3. What and how much', '3. क्या और कितना'),
            tx(context, '4. Is it real? The evidence board', '4. क्या यह असली है? सबूत बोर्ड'),
            tx(context, '5. Same cause? The suspects', '5. एक ही वजह? संदिग्ध'),
            tx(context, '6. The verdict', '6. फ़ैसला'),
          ];
          Widget body;
          switch (_step) {
            case 0:
              body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.name(lang), style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: k.paper, borderRadius: BorderRadius.circular(12)),
                  child: Text(pick(lang, c.question, c.questionHi), style: TextStyle(color: k.ink, fontSize: 18, height: 1.35, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 10),
                Text('${tx(context, 'Data', 'डेटा')}: ${pick(lang, c.sourceTitle, c.sourceTitleHi)} · ${c.period.isNotEmpty ? '${c.period.first}-${c.period.last}' : ''}'),
                Text(c.mission, style: Theme.of(context).textTheme.bodySmall),
              ]);
            case 1:
              body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                WorldMap(
                  regions: [
                    for (final r in c.regions)
                      if (r.cells.isNotEmpty || (r.bbox != null && r.bbox!.length == 4))
                        MapRegion(color: k.signColor(r.sign), cells: r.cells, res: r.res, bbox: r.cells.isEmpty ? r.bbox : null, pin: r.pin, label: r.label(lang)),
                  ],
                  redString: true,
                ),
                const SizedBox(height: 8),
                Text(tx(context, 'The detective found two regions moving in opposite directions and tied them with a red string.', 'जासूस ने उल्टी दिशा में चलते दो क्षेत्र खोजे और उन्हें लाल धागे से जोड़ा।')),
              ]);
            case 2:
              body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final r in [a, b].whereType<CaseRegion>()) ...[
                  Text('${r.label(lang)}: ${fmtSigned(r.trend.slopeDec)} ${c.perDecadeLabel(lang)}', style: TextStyle(color: k.signColor(r.sign), fontWeight: FontWeight.w800, fontSize: 16)),
                  TrendChart(series: r.series, color: k.signColor(r.sign), height: 130),
                  const SizedBox(height: 6),
                ],
              ]);
            case 3:
              body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final ch in c.checks)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(ch.status == 'pass' ? Icons.check_circle : (ch.status == 'fail' ? Icons.cancel : Icons.help), color: k.check(ch.status), size: 20),
                      const SizedBox(width: 8),
                      Expanded(child: Text.rich(TextSpan(children: [TextSpan(text: '${ch.title(lang)}: ', style: const TextStyle(fontWeight: FontWeight.w800)), TextSpan(text: ch.text(lang))]))),
                    ]),
                  ),
              ]);
            case 4:
              body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tx(context, 'For each suspect we ask: when it goes up, does region A go one way and region B the other, year after year?', 'हर संदिग्ध से हम पूछते हैं: जब वह बढ़ता है, तो क्या क्षेत्र A एक ओर और क्षेत्र B दूसरी ओर जाता है, साल-दर-साल?')),
                const SizedBox(height: 8),
                for (final d in c.drivers)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(d.id == c.bestDriver ? Icons.person_search : Icons.person_outline, color: d.id == c.bestDriver ? k.string : k.muted),
                    title: Text(d.name(lang), style: const TextStyle(fontWeight: FontWeight.w700)),
                    trailing: Pill(d.verdict, color: d.verdict == 'strong' ? k.confirmed : (d.verdict == 'weak' ? k.likely : k.notProven)),
                  ),
              ]);
            default:
              body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Center(child: CaseStamp(code: c.verdict.code, label: c.verdict.label(lang), size: 1.4)),
                const SizedBox(height: 14),
                Text(c.verdict.headline(lang), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, height: 1.3)),
                const SizedBox(height: 6),
                Text(c.verdict.detail(lang)),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => CaseDetailScreen(summary: widget.summary))),
                  icon: const Icon(Icons.folder_open),
                  label: Text(tx(context, 'Open the full case file', 'पूरी केस फ़ाइल खोलें')),
                ),
              ]);
          }
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: Column(children: [
                LinearProgressIndicator(value: (_step + 1) / _steps),
                Expanded(
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 16), children: [
                    Text(titles[_step], style: TextStyle(color: k.accent, fontWeight: FontWeight.w800, fontSize: 15)),
                    const SizedBox(height: 10),
                    AnimatedSwitcher(duration: const Duration(milliseconds: 350), child: KeyedSubtree(key: ValueKey(_step), child: body)),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    IconButton(onPressed: _step > 0 ? () => setState(() => _step--) : null, icon: const Icon(Icons.skip_previous)),
                    FilledButton.tonalIcon(
                      onPressed: () => setState(() {
                        if (_step >= _steps - 1 && !_playing) _step = 0;
                        _playing = !_playing;
                      }),
                      icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                      label: Text(_playing ? tx(context, 'Pause', 'रोकें') : tx(context, 'Play', 'चलाएँ')),
                    ),
                    IconButton(onPressed: _step < _steps - 1 ? () => setState(() => _step++) : null, icon: const Icon(Icons.skip_next)),
                  ]),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }
}
