import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../models/models.dart';
import '../services/evidence_parser.dart';
import '../stats/extra.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/trend_report.dart';

/// "Bring your own evidence": drop in a file from Giovanni, AppEEARS, NOAA CDO,
/// KNMI Climate Explorer or any CSV with dates and numbers, and get a verdict.
class EvidenceScreen extends StatefulWidget {
  const EvidenceScreen({super.key});
  @override
  State<EvidenceScreen> createState() => _EvidenceScreenState();
}

class _EvidenceScreenState extends State<EvidenceScreen> {
  static const _samples = [
    ('sample_giovanni_rain.csv', 'Giovanni layout: monsoon-coast rainfall', 'Giovanni ढाँचा: तटीय बारिश'),
    ('sample_noaa_station_temperature.csv', 'NOAA CDO layout: station temperature', 'NOAA CDO ढाँचा: स्टेशन तापमान'),
    ('sample_appeears_ndvi.csv', 'AppEEARS layout: farm greenness (NDVI)', 'AppEEARS ढाँचा: खेत की हरियाली (NDVI)'),
    ('sample_trap_looks_like_trend.csv', 'The trap: looks like a trend, is it?', 'जाल: रुझान जैसा दिखता है, है क्या?'),
  ];

  String? _text, _name;
  Evidence? _ev;
  EvidenceError? _err;
  bool _sample = false;
  final _paste = TextEditingController();

  void _load(String text, String name, {String? column, bool sample = false}) {
    setState(() {
      _text = text;
      _name = name;
      _sample = sample;
      try {
        _ev = parseEvidence(text, column: column, fileName: name);
        _err = null;
      } on EvidenceError catch (e) {
        _ev = null;
        _err = e;
      } catch (e) {
        _ev = null;
        _err = EvidenceError('Could not read this file ($e).', 'यह फ़ाइल पढ़ी नहीं जा सकी।');
      }
    });
  }

  Future<void> _pick() async {
    try {
      XFile? f;
      try {
        f = await openFile(acceptedTypeGroups: const [
          XTypeGroup(label: 'data', extensions: ['csv', 'txt', 'tsv', 'dat'], mimeTypes: ['text/csv', 'text/plain', 'text/comma-separated-values', 'text/tab-separated-values'])
        ]);
      } catch (_) {
        f = await openFile();
      }
      if (f == null) return;
      final text = await f.readAsString();
      if (!mounted) return;
      _load(text, tx(context, 'uploaded file', 'अपलोड की गई फ़ाइल'));
    } catch (e) {
      setState(() => _err = EvidenceError('The file could not be opened. Try "Paste text" instead.', 'फ़ाइल नहीं खुली। "टेक्स्ट चिपकाएँ" आज़माएँ।'));
    }
  }

  @override
  void dispose() {
    _paste.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final ev = _ev;
    Widget? report;
    if (ev != null) {
      final (years, vals) = ev.isMonthly ? yearlyFromMonthly(ev.points) : (<int>[for (final p in ev.points) p.year], <double?>[for (final p in ev.points) p.value]);
      report = TrendReport(
        series: Series(years, vals),
        title: ev.column,
        unit: '',
        monthly: ev.isMonthly ? ev.points : null,
        sourceNote: '${_name ?? ''} (${ev.format})',
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(tx(context, 'Bring your own evidence', 'अपना सबूत लाएँ')), actions: const [HeaderActions()]),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(padding: const EdgeInsets.fromLTRB(14, 10, 14, 40), children: [
            Text(
                tx(context, 'NASA tools like Giovanni, AppEEARS and Data Rods draw a time series. Download it as CSV, drop it here, and the detective tells you whether the trend is real.',
                    'Giovanni, AppEEARS और Data Rods जैसे NASA टूल टाइम-सीरीज़ बनाते हैं। उसे CSV में उतारें, यहाँ डालें, और जासूस बताएगा कि रुझान असली है या नहीं।'),
                style: const TextStyle(height: 1.35)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(onPressed: _pick, icon: const Icon(Icons.upload_file), label: Text(tx(context, 'Choose a file', 'फ़ाइल चुनें'))),
              OutlinedButton.icon(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(tx(context, 'Paste the file text', 'फ़ाइल का टेक्स्ट चिपकाएँ')),
                    content: SizedBox(width: 520, child: TextField(controller: _paste, maxLines: 12, decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'date,value\n2001-01,12.3\n...'))),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tx(context, 'Cancel', 'रद्द'))),
                      FilledButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            if (_paste.text.trim().isNotEmpty) _load(_paste.text, tx(context, 'pasted text', 'चिपकाया टेक्स्ट'));
                          },
                          child: Text(tx(context, 'Test it', 'जाँचें'))),
                    ],
                  ),
                ),
                icon: const Icon(Icons.content_paste),
                label: Text(tx(context, 'Paste text', 'टेक्स्ट चिपकाएँ')),
              ),
            ]),
            const SizedBox(height: 12),
            Text(tx(context, 'Or try a sample (synthetic numbers in the real file layouts):', 'या नमूना आज़माएँ (असली फ़ाइल ढाँचों में बनावटी आँकड़े):'), style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final s in _samples)
                ActionChip(
                  avatar: const Icon(Icons.description_outlined, size: 16),
                  label: Text(tx(context, s.$2, s.$3)),
                  onPressed: () async {
                    final t = await rootBundle.loadString('assets/samples/${s.$1}');
                    _load(t, s.$1, sample: true);
                  },
                ),
            ]),
            const SizedBox(height: 12),
            if (_err != null)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: k.artifact.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                child: Text(tx(context, _err!.en, _err!.hi)),
              ),
            if (ev != null) ...[
              if (_sample)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: k.likely.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                  child: Text(tx(context, 'Sample file: synthetic numbers for demonstration, not real measurements.', 'नमूना फ़ाइल: दिखाने के लिए बनावटी आँकड़े, असली माप नहीं।'), style: const TextStyle(fontSize: 12.5)),
                ),
              Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Pill('${tx(context, 'Recognised as', 'पहचाना गया')}: ${ev.format}', color: k.accent),
                Pill('${ev.points.length} ${ev.isMonthly ? tx(context, 'months', 'महीने') : tx(context, 'years', 'साल')}'),
                if (ev.dropped > 0) Pill('${ev.dropped} ${tx(context, 'missing values skipped', 'ग़ायब मान छोड़े')}'),
                if (ev.isMonthly) Pill(tx(context, 'seasonal cycle removed', 'मौसमी चक्र हटाया गया'), color: k.confirmed),
              ]),
              if (ev.columns.length > 1) ...[
                const SizedBox(height: 8),
                Row(children: [
                  Text('${tx(context, 'Column', 'कॉलम')}: '),
                  Expanded(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: ev.column,
                      items: [for (final c in ev.columns) DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis))],
                      onChanged: (c) {
                        if (c != null && _text != null) _load(_text!, _name ?? '', column: c, sample: _sample);
                      },
                    ),
                  ),
                ]),
              ],
              if (ev.title.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4, bottom: 6), child: Text(ev.title, style: Theme.of(context).textTheme.bodySmall)),
              const SizedBox(height: 6),
              report!,
            ],
          ]),
        ),
      ),
    );
  }
}
