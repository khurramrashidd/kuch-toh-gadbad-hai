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
  final GlobalKey _stepsKey = GlobalKey();
  Topic? _topic;
  Preset? _preset; // null = my own place
  bool _myPlace = false;
  String _season = 'ANN';

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
          constraints: const BoxConstraints(maxWidth: 1040),
          child: ListView(padding: const EdgeInsets.fromLTRB(14, 10, 14, 40), children: [
            const FadeSlideIn(child: HeroPanel()),
            const SizedBox(height: 14),
            LayoutBuilder(builder: (context, cons) {
              final cols = cons.maxWidth > 760 ? 3 : 1;
              final w = (cons.maxWidth - (cols - 1) * 12) / cols;
              return Wrap(spacing: 12, runSpacing: 10, children: [
                FadeSlideIn(
                  delayMs: 80,
                  child: ActionCard(
                      width: w,
                      color: k.tab(0),
                      icon: Icons.search_rounded,
                      title: tx(context, 'Investigate', 'जाँच करें'),
                      text: tx(context, 'Three questions, then a verdict.', 'तीन सवाल, फिर फ़ैसला।'),
                      onTap: () {
                        final c = _stepsKey.currentContext;
                        if (c != null) Scrollable.ensureVisible(c, duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic, alignment: 0.02);
                      }),
                ),
                FadeSlideIn(
                  delayMs: 160,
                  child: ActionCard(
                      width: w,
                      color: k.tab(3),
                      icon: Icons.public,
                      title: tx(context, 'Explore the map', 'नक़्शा देखें'),
                      text: tx(context, 'Tap anywhere on Earth and test it.', 'पृथ्वी पर कहीं भी दबाएँ और परखें।'),
                      onTap: () => AppScope.read(context).goTab(3)),
                ),
                FadeSlideIn(
                  delayMs: 240,
                  child: ActionCard(
                      width: w,
                      color: k.tab(1),
                      icon: Icons.folder_special,
                      title: tx(context, 'Open a case', 'केस खोलें'),
                      text: tx(context, 'Opposite trends: one cause or two?', 'उल्टे रुझान: एक वजह या दो?'),
                      onTap: () => AppScope.read(context).goTab(1)),
                ),
              ]);
            }),
            SectionTitle(tx(context, 'Start an investigation', 'जाँच शुरू करें'), icon: Icons.search_rounded, key: _stepsKey),

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
                }),
              ),
              ChoiceChip(
                avatar: const Icon(Icons.public, size: 18),
                label: Text(_preset == null ? tx(context, 'Choose a region…', 'क्षेत्र चुनें…') : '${lang == 'hi' ? _preset!.hi : _preset!.en} · ${lang == 'hi' ? _preset!.kindHi : _preset!.kind}'),
                selected: _preset != null,
                onSelected: (_) async {
                  final picked = await showModalBottomSheet<Preset>(
                    context: context,
                    showDragHandle: true,
                    isScrollControlled: true,
                    builder: (ctx) => DraggableScrollableSheet(
                      expand: false,
                      initialChildSize: 0.7,
                      maxChildSize: 0.92,
                      builder: (ctx, sc) => ListView(controller: sc, children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                          child: Text(tx(context, 'Choose a region', 'क्षेत्र चुनें'), style: Theme.of(ctx).textTheme.titleLarge),
                        ),
                        for (final p in kPresets)
                          ListTile(
                            leading: Icon(Icons.place_outlined, color: k.accent),
                            title: Text(lang == 'hi' ? p.hi : p.en, style: const TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: Text(lang == 'hi' ? p.kindHi : p.kind),
                            trailing: _preset == p ? Icon(Icons.check, color: k.accent) : null,
                            onTap: () => Navigator.pop(ctx, p),
                          ),
                      ]),
                    ),
                  );
                  if (picked != null) {
                    setState(() {
                      _preset = picked;
                      _myPlace = false;
                    });
                  }
                },
              ),
            ]),
            const SizedBox(height: 12),
            _Step(n: 3, text: tx(context, 'Which part of the year?', 'साल का कौन-सा हिस्सा?')),
            Wrap(spacing: 8, children: [
              for (final s in const ['ANN', 'JJAS', 'DJF'])
                ChoiceChip(label: Text(cat.seasonLabel(s, lang)), selected: _season == s, onSelected: (_) => setState(() => _season = s)),
            ]),
            const SizedBox(height: 14),

            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: !ready
                    ? null
                    : () => showModalBottomSheet<void>(
                          context: context,
                          showDragHandle: true,
                          isScrollControlled: true,
                          useSafeArea: true,
                          builder: (_) => _ResultsSheet(topic: t, preset: _preset, myPlace: _myPlace, season: _season),
                        ),
                icon: const Icon(Icons.search),
                label: Text(ready ? tx(context, 'Show what to investigate', 'दिखाएँ: क्या जाँचें') : tx(context, 'Answer questions 1 and 2 first', 'पहले सवाल 1 और 2 का जवाब दें')),
              ),
            ),
            const SizedBox(height: 8),

            // ---------------- doors
            SectionTitle(tx(context, 'More detective tools', 'जासूसी के और औज़ार'), icon: Icons.work_outline),
            LayoutBuilder(builder: (context, cons) {
              final cols = cons.maxWidth > 760 ? 3 : 1;
              final w = (cons.maxWidth - (cols - 1) * 10) / cols;
              return Wrap(spacing: 10, runSpacing: 10, children: [
                _Door(
                    width: w,
                    icon: Icons.upload_file,
                    color: k.sun,
                    title: tx(context, 'Bring your own evidence', 'अपना सबूत लाएँ'),
                    text: tx(context, 'Drop in a file from NASA Giovanni, AppEEARS or NOAA and get a verdict.', 'NASA Giovanni, AppEEARS या NOAA की फ़ाइल डालें और फ़ैसला पाएँ।'),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const EvidenceScreen()))),
                _Door(
                    width: w,
                    icon: Icons.sports_esports,
                    color: k.violet,
                    title: tx(context, 'Can you beat the test?', 'क्या आप जाँच को हरा सकते हैं?'),
                    text: tx(context, '10 charts: real trend or just noise? A one-minute game.', '10 चार्ट: असली रुझान या सिर्फ़ शोर? एक मिनट का खेल।'),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const GameScreen()))),
                for (final cs in cat.cases.take(2))
                  _Door(
                      width: w,
                      icon: Icons.play_circle_outline,
                      color: k.falling,
                      title: '${tx(context, 'Watch a demo', 'डेमो देखें')}: ${cs.name(lang)}',
                      text: tx(context, 'A real case that plays by itself in one minute.', 'एक असली केस जो एक मिनट में खुद चलता है।'),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TourScreen(summary: cs)))),
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

}

class _Step extends StatelessWidget {
  const _Step({required this.n, required this.text});
  final int n;
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [context.k.accent, context.k.falling])),
            child: Text('$n', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14)),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, fontFamily: kHeadFont))),
        ]),
      );
}

class _VarCard extends StatelessWidget {
  const _VarCard({required this.title, required this.definition, required this.source, required this.action, required this.onTap, this.note = '', this.color});
  final Color? color;
  final String title, definition, source, action, note;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final c = color ?? k.accent;
    return Card(
      color: k.card,
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: BoxDecoration(border: Border(left: BorderSide(color: c, width: 5))),
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, fontFamily: kHeadFont, color: c)),
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
  const _Door({required this.width, required this.icon, required this.title, required this.text, required this.onTap, this.color});
  final Color? color;
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
        elevation: k.dark ? 0 : 2,
        shadowColor: (color ?? k.accent).withValues(alpha: 0.25),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: (color ?? k.accent).withValues(alpha: 0.30))),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              IconBadge(icon, color: color ?? k.accent, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontFamily: kHeadFont, fontSize: 15)),
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

/// The answer to the three questions, shown in its own sheet so the home page stays short.
class _ResultsSheet extends StatefulWidget {
  const _ResultsSheet({required this.topic, required this.preset, required this.myPlace, required this.season});
  final Topic? topic;
  final Preset? preset;
  final bool myPlace;
  final String season;
  @override
  State<_ResultsSheet> createState() => _ResultsSheetState();
}

class _ResultsSheetState extends State<_ResultsSheet> {
  Future<(String, String)?>? _ai;
  Topic? get _topic => widget.topic;
  Preset? get _preset => widget.preset;

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
    final t = widget.topic!;
    final matches = _matches(cat, t);
    void close() => Navigator.of(context).pop();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, sc) => ListView(controller: sc, padding: const EdgeInsets.fromLTRB(16, 0, 16, 28), children: [
        Text(tx(context, 'Variables worth investigating', 'जाँचने लायक़ चीज़ें'), style: Theme.of(context).textTheme.titleLarge),
        Text('${lang == 'hi' ? t.hi : t.en} · ${widget.myPlace ? tx(context, 'my own place', 'मेरी अपनी जगह') : (lang == 'hi' ? _preset!.hi : _preset!.en)}', style: TextStyle(color: k.muted)),
        const SizedBox(height: 10),
        if (widget.myPlace)
          for (final key in t.power)
            _VarCard(
              title: _powerTitle(context, key),
              definition: tx(context, kPowerDefs[key]!.$1, kPowerDefs[key]!.$2),
              source: 'NASA POWER (MERRA-2)',
              action: tx(context, 'Test it at my place', 'मेरी जगह पर जाँचें'),
              onTap: () {
                close();
                AppScope.read(context).goTab(2);
              },
            )
        else ...[
          for (final d in matches)
            _VarCard(
              title: d.name(lang),
              definition: d.definition(lang),
              source: d.mission,
              color: k.sphere(d.sphere),
              note: d.qualityNote,
              action: tx(context, 'Test it in ${_preset!.en}', '${_preset!.hi} में जाँचें'),
              onTap: () {
                close();
                AppScope.read(context).explore(
                    dataset: d.id,
                    season: d.layers.any((l) => l.season == widget.season) ? widget.season : d.layers.first.season,
                    bbox: _preset!.bbox,
                    regionName: lang == 'hi' ? _preset!.hi : _preset!.en);
              },
            ),
          if (matches.isEmpty) Text(tx(context, 'No map dataset for this topic is loaded. Try "My own place".', 'इस विषय का नक़्शा-डेटा लोड नहीं है। "मेरी अपनी जगह" आज़माएँ।')),
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
          FutureBuilder<(String, String)?>(
            future: _ai,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) return const LinearProgressIndicator();
              final text = snap.data?.$1;
              final by = snap.data?.$2;
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: k.bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: k.line)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(Icons.auto_awesome, size: 16, color: k.accent),
                    const SizedBox(width: 6),
                    Expanded(child: Text('${tx(context, 'AI-generated suggestion', 'एआई का सुझाव')}${by == null ? '' : ' ($by)'}', style: TextStyle(color: k.accent, fontWeight: FontWeight.w700, fontSize: 12.5))),
                  ]),
                  const SizedBox(height: 4),
                  Text(text ?? tx(context, 'AI is not available right now. The list above does not depend on it.', 'एआई अभी उपलब्ध नहीं है। ऊपर की सूची उस पर निर्भर नहीं।')),
                  if (text == null && app.expert) Text(app.ai.lastError, style: TextStyle(color: k.muted, fontSize: 11)),
                  if (text == null) TextButton(onPressed: () => _askAi(context), child: Text(tx(context, 'Try again', 'फिर कोशिश करें'))),
                  Text(tx(context, 'AI only suggests where to look. Every verdict in this app is computed from data, never written by AI.', 'एआई सिर्फ़ सुझाता है कि कहाँ देखें। इस ऐप का हर फ़ैसला डेटा से गणना है, एआई का लिखा नहीं।'),
                      style: TextStyle(color: k.muted, fontSize: 11.5)),
                ]),
              );
            },
          ),
      ]),
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

