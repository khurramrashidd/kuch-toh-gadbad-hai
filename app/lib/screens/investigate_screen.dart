import 'package:flutter/material.dart';

import '../app_state.dart';
import '../knowledge.dart';
import '../models/models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'evidence_screen.dart';
import 'game_screen.dart';
import 'tour_screen.dart';

/// Home: three short questions lead to the right variables (with plain definitions),
/// plus the doors to "Bring your own evidence", the game and the demo tour.
class InvestigateScreen extends StatefulWidget {
  const InvestigateScreen({super.key});
  @override
  State<InvestigateScreen> createState() => _InvestigateScreenState();
}

class _InvestigateScreenState extends State<InvestigateScreen> {
  Topic? _topic;
  Preset? _preset; // null = my own place
  bool _myPlace = false;
  String _season = 'ANN';
  Future<String?>? _ai;

  List<DatasetInfo> _matches(Catalog cat, Topic t) => [
        for (final d in cat.layerDatasets)
          if (t.words.any((w) => d.id.toLowerCase().contains(w) || d.short.toLowerCase().contains(w))) d
      ];

  void _askAi(BuildContext context) {
    final app = AppScope.read(context);
    final cat = app.catalog!;
    final p = _preset;
    final vars = [for (final d in cat.layerDatasets) '${d.id} = ${d.short}'].join('; ');
    final lang = app.lang == 'hi' ? 'Hindi (Devanagari)' : 'English';
    final prompt = 'You help students choose Earth-science variables to investigate for trends. '
        'Region: ${p == null ? 'the user\'s home area' : '${p.en} (${p.kind})'}. '
        '${_topic == null ? '' : 'They are curious about: ${_topic!.en}. '}'
        'Available variables: $vars; plus for any single place: temperature, very hot days, rainfall, monsoon rainfall, root-zone soil wetness, humidity. '
        'Suggest the 3 most relevant variables for this kind of region, one short line each saying what change scientists have reported there or why it matters. '
        'Use only the listed variables. Do not state numbers. Write in $lang, under 90 words, plain text.';
    setState(() => _ai = app.ai.suggest(prompt));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final lang = app.lang;
    final cat = app.catalog!;
    final k = context.k;
    final t = _topic;
    final ready = t != null && (_myPlace || _preset != null);
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: ListView(padding: const EdgeInsets.fromLTRB(14, 10, 14, 40), children: [
            Row(children: [
              Expanded(child: Text(tx(context, 'Start an investigation', 'जाँच शुरू करें'), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900))),
              const HeaderActions(),
            ]),
            Text(tx(context, 'Other tools draw the line. We tell you if it is real, why it is happening, and how to check us.', 'दूसरे टूल रेखा खींचते हैं। हम बताते हैं कि वह असली है या नहीं, क्यों हो रहा है, और हमें कैसे परखें।'),
                style: TextStyle(color: k.accent, fontWeight: FontWeight.w600, fontSize: 15)),
            const SizedBox(height: 14),

            // ---------------- guided investigation
            _Step(n: 1, text: tx(context, 'What are you curious or worried about?', 'आपको किस बात की जिज्ञासा या चिंता है?')),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final tp in kTopics)
                ChoiceChip(
                  avatar: Icon(tp.icon, size: 18),
                  label: Text(lang == 'hi' ? tp.hi : tp.en),
                  selected: _topic == tp,
                  onSelected: (_) => setState(() {
                    _topic = tp;
                    _ai = null;
                  }),
                ),
            ]),
            const SizedBox(height: 12),
            _Step(n: 2, text: tx(context, 'Where?', 'कहाँ?')),
            Wrap(spacing: 8, runSpacing: 8, children: [
              ChoiceChip(
                avatar: const Icon(Icons.my_location, size: 18),
                label: Text(tx(context, 'My own place', 'मेरी अपनी जगह')),
                selected: _myPlace,
                onSelected: (_) => setState(() {
                  _myPlace = true;
                  _preset = null;
                  _ai = null;
                }),
              ),
              for (final p in kPresets)
                ChoiceChip(
                  label: Text('${lang == 'hi' ? p.hi : p.en} · ${lang == 'hi' ? p.kindHi : p.kind}'),
                  selected: _preset == p,
                  onSelected: (_) => setState(() {
                    _preset = p;
                    _myPlace = false;
                    _ai = null;
                  }),
                ),
            ]),
            const SizedBox(height: 12),
            _Step(n: 3, text: tx(context, 'Which part of the year?', 'साल का कौन-सा हिस्सा?')),
            Wrap(spacing: 8, children: [
              for (final s in const ['ANN', 'JJAS', 'DJF'])
                ChoiceChip(label: Text(cat.seasonLabel(s, lang)), selected: _season == s, onSelected: (_) => setState(() => _season = s)),
            ]),
            const SizedBox(height: 14),

            if (ready) ...[
              SectionTitle(tx(context, 'Variables worth investigating', 'जाँचने लायक़ चीज़ें'), icon: Icons.search),
              if (_myPlace)
                for (final key in t.power)
                  _VarCard(
                    title: _powerTitle(context, key),
                    definition: tx(context, kPowerDefs[key]!.$1, kPowerDefs[key]!.$2),
                    source: 'NASA POWER (MERRA-2)',
                    action: tx(context, 'Test it at my place', 'मेरी जगह पर जाँचें'),
                    onTap: () => AppScope.read(context).goTab(2),
                  )
              else ...[
                for (final d in _matches(cat, t))
                  _VarCard(
                    title: d.name(lang),
                    definition: d.definition(lang),
                    source: d.mission,
                    note: d.qualityNote,
                    action: tx(context, 'Test it in ${_preset!.en}', '${_preset!.hi} में जाँचें'),
                    onTap: () => AppScope.read(context).explore(
                        dataset: d.id,
                        season: d.layers.any((l) => l.season == _season) ? _season : d.layers.first.season,
                        bbox: _preset!.bbox,
                        regionName: lang == 'hi' ? _preset!.hi : _preset!.en),
                  ),
                if (_matches(cat, t).isEmpty)
                  Text(tx(context, 'No map dataset for this topic is loaded yet. Try "My own place", or run the pipeline for more datasets.', 'इस विषय का नक़्शा-डेटा अभी लोड नहीं है। "मेरी अपनी जगह" आज़माएँ, या और डेटा के लिए पाइपलाइन चलाएँ।')),
              ],
              const SizedBox(height: 6),
              if (_ai == null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () => _askAi(context),
                    icon: const Icon(Icons.auto_awesome, size: 18),
                    label: Text(tx(context, 'Ask AI what else to look at here', 'एआई से पूछें: यहाँ और क्या देखें')),
                  ),
                )
              else
                FutureBuilder<String?>(
                  future: _ai,
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) return const LinearProgressIndicator();
                    final text = snap.data;
                    return Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: k.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: k.line)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Icon(Icons.auto_awesome, size: 16, color: k.accent),
                          const SizedBox(width: 6),
                          Text(tx(context, 'AI-generated suggestion (Gemini)', 'एआई का सुझाव (Gemini)'), style: TextStyle(color: k.accent, fontWeight: FontWeight.w700, fontSize: 12.5)),
                        ]),
                        const SizedBox(height: 4),
                        Text(text ?? tx(context, 'AI is not available right now. The list above does not depend on it.', 'एआई अभी उपलब्ध नहीं है। ऊपर की सूची उस पर निर्भर नहीं।')),
                        const SizedBox(height: 4),
                        Text(tx(context, 'AI only suggests where to look. Every verdict in this app is computed from data, never written by AI.', 'एआई सिर्फ़ सुझाता है कि कहाँ देखें। इस ऐप का हर फ़ैसला डेटा से गणना है, एआई का लिखा नहीं।'),
                            style: TextStyle(color: k.muted, fontSize: 11.5)),
                      ]),
                    );
                  },
                ),
            ] else
              Text(tx(context, 'Answer questions 1 and 2 to see what to investigate.', 'क्या जाँचें यह देखने के लिए सवाल 1 और 2 का जवाब दें।'), style: TextStyle(color: k.muted)),

            // ---------------- doors
            SectionTitle(tx(context, 'More detective tools', 'जासूसी के और औज़ार'), icon: Icons.work_outline),
            LayoutBuilder(builder: (context, cons) {
              final cols = cons.maxWidth > 760 ? 3 : 1;
              final w = (cons.maxWidth - (cols - 1) * 10) / cols;
              final top = cat.cases.isNotEmpty ? cat.cases.first : null;
              return Wrap(spacing: 10, runSpacing: 10, children: [
                _Door(
                    width: w,
                    icon: Icons.upload_file,
                    title: tx(context, 'Bring your own evidence', 'अपना सबूत लाएँ'),
                    text: tx(context, 'Drop in a file from NASA Giovanni, AppEEARS or NOAA and get a verdict.', 'NASA Giovanni, AppEEARS या NOAA की फ़ाइल डालें और फ़ैसला पाएँ।'),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const EvidenceScreen()))),
                _Door(
                    width: w,
                    icon: Icons.sports_esports,
                    title: tx(context, 'Can you beat the test?', 'क्या आप जाँच को हरा सकते हैं?'),
                    text: tx(context, '10 charts: real trend or just noise? A one-minute game.', '10 चार्ट: असली रुझान या सिर्फ़ शोर? एक मिनट का खेल।'),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const GameScreen()))),
                if (top != null)
                  _Door(
                      width: w,
                      icon: Icons.play_circle_outline,
                      title: tx(context, 'Watch a demo case', 'डेमो केस देखें'),
                      text: '${top.name(lang)} · ${tx(context, 'plays by itself in one minute', 'एक मिनट में खुद चलता है')}',
                      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TourScreen(summary: top)))),
              ]);
            }),
            const SizedBox(height: 10),
            Wrap(spacing: 8, children: [
              TextButton.icon(onPressed: () => AppScope.read(context).goTab(1), icon: const Icon(Icons.folder_special_outlined, size: 18), label: Text(tx(context, 'All case files', 'सभी केस फ़ाइलें'))),
              TextButton.icon(onPressed: () => AppScope.read(context).goTab(3), icon: const Icon(Icons.public, size: 18), label: Text(tx(context, 'Open the globe', 'ग्लोब खोलें'))),
              TextButton.icon(onPressed: () => AppScope.read(context).goTab(4), icon: const Icon(Icons.menu_book, size: 18), label: Text(tx(context, 'Methods and references', 'तरीक़े और संदर्भ'))),
            ]),
          ]),
        ),
      ),
    );
  }

  String _powerTitle(BuildContext context, String key) => switch (key) {
        'temp' => tx(context, 'Average temperature', 'औसत तापमान'),
        'hotdays' => tx(context, 'Very hot days', 'बहुत गर्म दिन'),
        'rain' => tx(context, 'Rainfall in a year', 'साल भर की बारिश'),
        'monsoon' => tx(context, 'Monsoon rainfall', 'मानसून की बारिश'),
        'soil' => tx(context, 'Soil wetness', 'मिट्टी की नमी'),
        _ => tx(context, 'Humidity', 'नमी'),
      };
}

class _Step extends StatelessWidget {
  const _Step({required this.n, required this.text});
  final int n;
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          CircleAvatar(radius: 12, backgroundColor: context.k.accent, child: Text('$n', style: TextStyle(color: context.k.onAccent, fontWeight: FontWeight.w800, fontSize: 13))),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5))),
        ]),
      );
}

class _VarCard extends StatelessWidget {
  const _VarCard({required this.title, required this.definition, required this.source, required this.action, required this.onTap, this.note = ''});
  final String title, definition, source, action, note;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return Card(
      color: k.card,
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          if (definition.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(definition, style: const TextStyle(height: 1.3))),
          const SizedBox(height: 4),
          Text(source, style: TextStyle(color: k.muted, fontSize: 12)),
          if (note.isNotEmpty) Text(note, style: TextStyle(color: k.likely, fontSize: 12)),
          Align(alignment: Alignment.centerRight, child: FilledButton.tonalIcon(onPressed: onTap, icon: const Icon(Icons.arrow_forward, size: 18), label: Text(action))),
        ]),
      ),
    );
  }
}

class _Door extends StatelessWidget {
  const _Door({required this.width, required this.icon, required this.title, required this.text, required this.onTap});
  final double width;
  final IconData icon;
  final String title, text;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return SizedBox(
      width: width,
      child: Material(
        color: k.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: k.line)),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Icon(icon, color: k.accent, size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text(text, style: TextStyle(color: k.muted, fontSize: 12.5)),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
