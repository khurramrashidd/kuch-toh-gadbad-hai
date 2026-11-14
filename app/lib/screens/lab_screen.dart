import 'package:flutter/material.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../app_state.dart';
import '../config.dart';
import '../knowledge.dart';
import '../models/json.dart';
import '../theme.dart';
import '../widgets/common.dart';

class LabScreen extends StatefulWidget {
  const LabScreen({super.key});
  @override
  State<LabScreen> createState() => _LabScreenState();
}

class _LabScreenState extends State<LabScreen> {
  Future<Map<String, dynamic>>? _selftest;
  Future<Map<String, dynamic>>? _report;

  @override
  void initState() {
    super.initState();
    final app = AppScope.read(context);
    final st = app.catalog!.selftest;
    _selftest = st == null ? null : app.data.map(st);
    _report = app.data.map('report.json');
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.lang;
    final checks = const ['witnesses', 'signal', 'alibi', 'timeline', 'motive'];
    final names = {
      'witnesses': ('Witnesses', 'गवाह', Icons.groups),
      'signal': ('Signal vs noise', 'सिग्नल बनाम शोर', Icons.graphic_eq),
      'alibi': ('Alibi check', 'बहाने की जाँच', Icons.satellite_alt),
      'timeline': ('Timeline', 'समय-रेखा', Icons.timeline),
      'motive': ('Motive', 'मक़सद (वजह)', Icons.psychology_alt),
    };
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(padding: const EdgeInsets.fromLTRB(14, 10, 14, 40), children: [
            Row(children: [
              Expanded(child: Text(context.t('lab_title'), style: Theme.of(context).textTheme.headlineSmall)),
              const HeaderActions(),
            ]),
            SectionTitle(context.t('five_checks'), icon: Icons.checklist),
            for (final k in checks)
              Card(
                color: context.k.card,
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  leading: Icon(names[k]!.$3, color: context.k.accent),
                  title: Text(lang == 'hi' ? names[k]!.$2 : names[k]!.$1, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(context.t('check_${k}_d')),
                ),
              ),
            if (_selftest != null)
              FutureBuilder<Map<String, dynamic>>(
                future: _selftest,
                builder: (context, snap) => snap.hasData ? _SelftestView(data: snap.data!) : const LinearProgressIndicator(),
              ),
            SectionTitle(context.t('limits_title'), icon: Icons.gavel),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: context.k.paper, borderRadius: BorderRadius.circular(10)),
              child: Text(context.t('limits_body'), style: TextStyle(color: context.k.ink, height: 1.4)),
            ),
            SectionTitle(tx(context, 'References: everything we used, from where, and why', 'संदर्भ: हमने क्या, कहाँ से और क्यों इस्तेमाल किया'), icon: Icons.menu_book),
            Text(tx(context, 'Datasets inside our results', 'हमारे नतीजों में शामिल डेटा'), style: TextStyle(fontWeight: FontWeight.w800, color: context.k.accent)),
            const SizedBox(height: 4),
            for (final d in context.app.catalog!.datasets)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(d.name(lang), style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(d.mission, style: Theme.of(context).textTheme.bodySmall),
                  if (d.definition(lang).isNotEmpty) Text('${tx(context, 'Why', 'क्यों')}: ${d.definition(lang)}', style: Theme.of(context).textTheme.bodySmall),
                  if (d.qualityNote.isNotEmpty) Text(d.qualityNote, style: TextStyle(color: context.k.likely, fontSize: 12)),
                  SelectableText(d.citation, style: Theme.of(context).textTheme.bodySmall),
                  if (d.urlInfo.isNotEmpty) _Link(d.urlInfo),
                ]),
              ),
            for (final g in const ['NASA tools', 'Space agency partners', 'Methods', 'Software']) ...[
              const SizedBox(height: 6),
              Text(
                  switch (g) {
                    'NASA tools' => tx(context, 'NASA and US agency tools', 'NASA और अमेरिकी एजेंसियों के टूल'),
                    'Space agency partners' => tx(context, 'Space agency partners (non-US)', 'अंतरिक्ष एजेंसी साझेदार (गैर-अमेरिकी)'),
                    'Methods' => tx(context, 'Methods and reading', 'तरीक़े और पठन'),
                    _ => tx(context, 'Software', 'सॉफ़्टवेयर'),
                  },
                  style: TextStyle(fontWeight: FontWeight.w800, color: context.k.accent)),
              const SizedBox(height: 4),
              for (final r in kReferences.where((r) => r.group == g))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(r.name, style: const TextStyle(fontWeight: FontWeight.w700))),
                      Pill(r.used ? tx(context, 'used in results', 'नतीजों में शामिल') : tx(context, 'consulted / linked', 'परामर्श / लिंक'), color: r.used ? context.k.confirmed : context.k.muted),
                    ]),
                    Text(r.org, style: Theme.of(context).textTheme.bodySmall),
                    Text('${tx(context, 'Why', 'क्यों')}: ${tx(context, r.why, r.whyHi)}', style: Theme.of(context).textTheme.bodySmall),
                    _Link(r.url),
                  ]),
                ),
            ],
            SectionTitle(tx(context, 'Use of AI', 'एआई का उपयोग'), icon: Icons.auto_awesome),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: context.k.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: context.k.line)),
              child: Text(
                  tx(context,
                      'AI-assisted project. (1) Code, documentation and the synthetic sample/demo files were written with the help of an AI assistant (Anthropic Claude) and reviewed by the team. '
                          '(2) Inside the app, Google Gemini (Firebase AI Logic) writes the "Detective\'s notes" and the "what else to look at" suggestions; these are always labelled as AI. '
                          'No verdict, number, map or chart is produced by AI: they are computed from the cited data with the published methods above. No NASA logos or mission emblems are used.',
                      'एआई-सहायित परियोजना। (1) कोड, दस्तावेज़ और बनावटी नमूना/डेमो फ़ाइलें एआई सहायक (Anthropic Claude) की मदद से लिखी गईं और टीम ने जाँचीं। '
                          '(2) ऐप में Google Gemini (Firebase AI Logic) "जासूस के नोट्स" और "और क्या देखें" सुझाव लिखता है; इन पर हमेशा एआई का लेबल रहता है। '
                          'कोई फ़ैसला, आँकड़ा, नक़्शा या चार्ट एआई नहीं बनाता: वे ऊपर दिए प्रकाशित तरीक़ों से उद्धृत डेटा पर गणना हैं। NASA के लोगो या मिशन चिह्न इस्तेमाल नहीं किए गए।'),
                  style: const TextStyle(height: 1.4, fontSize: 13)),
            ),
            SectionTitle(tx(context, 'Team', 'टीम'), icon: Icons.groups),
            const Text('$kTeamName · $kTeamMembers · NASA Space Apps Challenge 2026, $kLocalEvent'),
            const _AdminPanel(),
            SectionTitle(context.t('pipeline_status'), icon: Icons.precision_manufacturing),
            Card(
              color: context.k.card,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SelectableText('${context.t('data_url')}: ${context.app.dataBaseUrl}', style: Theme.of(context).textTheme.bodySmall),
                  Row(children: [
                    FilledButton.tonalIcon(
                      onPressed: () => AppScope.read(context).reload(),
                      icon: const Icon(Icons.refresh, size: 18),
                      label: Text(context.t('reload_data')),
                    ),
                    const Spacer(),
                    Text(context.t('live_data'), style: Theme.of(context).textTheme.bodySmall),
                    Switch(value: context.app.live, onChanged: (v) => AppScope.read(context).setLive(v)),
                  ]),
                ]),
              ),
            ),
            FutureBuilder<Map<String, dynamic>>(
              future: _report,
              builder: (context, snap) {
                if (!snap.hasData) return const SizedBox.shrink();
                final ds = toM(snap.data!['datasets']);
                final cs = toM(snap.data!['cases']);
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${context.t('generated')}: ${context.app.catalog!.generatedAt}', style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 6),
                  for (final e in [...ds.entries, ...cs.entries])
                    Row(children: [
                      Icon(toM(e.value)['status'] == 'ok' ? Icons.check_circle : Icons.info, size: 16,
                          color: toM(e.value)['status'] == 'ok' ? context.k.confirmed : context.k.likely),
                      const SizedBox(width: 6),
                      Expanded(child: Text('${e.key} – ${toS(toM(e.value)['status'])} ${toS(toM(e.value)['reason'])}', style: const TextStyle(fontSize: 12))),
                    ]),
                ]);
              },
            ),
            const Divider(),
            Text(context.t('about'), style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
      ),
    );
  }
}

class _SelftestView extends StatelessWidget {
  const _SelftestView({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final fa = toML(data['false_alarms']);
    final mirror = toM(data['mirror']);
    final bench = toML(data['benchmarks']);
    final rec = toM(data['slope_recovery']);
    final methods = [('none', context.t('method_none'), context.k.artifact), ('lag1', context.t('method_lag1'), context.k.confirmed), ('hamed_rao', context.t('method_hr'), context.k.likely)];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionTitle(context.t('false_alarms'), icon: Icons.notification_important),
      Text(context.t('false_alarms_note'), style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 8),
      Wrap(spacing: 14, children: [
        for (final m in methods)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 12, height: 12, color: m.$3),
            const SizedBox(width: 4),
            Text(m.$2, style: const TextStyle(fontSize: 12)),
          ]),
      ]),
      const SizedBox(height: 8),
      for (final row in fa)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${toI(row['n_years'])} ${context.t('years')} · ${context.t('autocorr')} ${toD(row['autocorr'])?.toStringAsFixed(1)}',
                style: TextStyle(fontSize: 12, color: context.k.muted)),
            for (final m in methods) _Bar(value: toD(row['false_alarm_${m.$1}']) ?? 0, color: m.$3, max: 0.35),
          ]),
        ),
      SectionTitle(context.t('mirror_test'), icon: Icons.compare_arrows),
      Wrap(spacing: 8, runSpacing: 8, children: [
        StatTile(label: context.t('mirror_found'), value: '${((toD(mirror['shared_driver_detected']) ?? 0) * 100).round()}%', color: context.k.confirmed),
        StatTile(label: context.t('mirror_false'), value: '${((toD(mirror['false_shared_driver']) ?? 0) * 100).round()}%', color: context.k.falling),
        if (rec.isNotEmpty)
          StatTile(label: 'Sen slope 95% CI coverage', value: '${((toD(rec['ci95_coverage']) ?? 0) * 100).round()}%'),
      ]),
      if (bench.isNotEmpty) ...[
        SectionTitle(context.t('benchmarks'), icon: Icons.fact_check),
        for (final b in bench)
          Card(
            color: context.k.card,
            child: ListTile(
              leading: Icon(b['pass'] == true ? Icons.check_circle : (b['pass'] == false ? Icons.cancel : Icons.help), color: b['pass'] == true ? context.k.confirmed : context.k.likely),
              title: Text(toS(b['title'])),
              subtitle: Text('${context.t('ours')}: ${fmtNum(toD(b['ours']))} · ${context.t('published')}: ${fmtNum(toD(b['expected']))} ± ${fmtNum(toD(b['tolerance']))} ${toS(b['units'])}\n${toS(b['reference'])}'),
              isThreeLine: true,
            ),
          ),
      ],
    ]);
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.value, required this.color, required this.max});
  final double value, max;
  final Color color;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(children: [
        Expanded(
          child: LayoutBuilder(builder: (context, cons) {
            final w = cons.maxWidth;
            return Stack(children: [
              Container(height: 12, width: w, decoration: BoxDecoration(color: context.k.surface, borderRadius: BorderRadius.circular(6))),
              Container(height: 12, width: (value / max).clamp(0.0, 1.0) * w, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6))),
              Positioned(left: (0.05 / max) * w, child: Container(width: 2, height: 12, color: context.k.text.withValues(alpha: 0.6))),
            ]);
          }),
        ),
        const SizedBox(width: 8),
        SizedBox(width: 40, child: Text('${(value * 100).round()}%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
      ]),
    );
  }
}

class _Link extends StatelessWidget {
  const _Link(this.url);
  final String url;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () => AppScope.read(context).device.openUrl(url),
        child: Text(url, style: TextStyle(color: context.k.falling, fontSize: 12, decoration: TextDecoration.underline)),
      );
}

/// Team sign-in (Google). The admin account may clear the shared caches.
class _AdminPanel extends StatefulWidget {
  const _AdminPanel();
  @override
  State<_AdminPanel> createState() => _AdminPanelState();
}

class _AdminPanelState extends State<_AdminPanel> {
  String? _msg;
  bool _busy = false;

  User? get _user {
    try {
      return FirebaseAuth.instance.currentUser;
    } catch (_) {
      return null;
    }
  }

  Future<void> _signIn() async {
    setState(() => _busy = true);
    try {
      final provider = GoogleAuthProvider();
      if (kIsWeb) {
        await FirebaseAuth.instance.signInWithPopup(provider);
      } else {
        await FirebaseAuth.instance.signInWithProvider(provider);
      }
      _msg = null;
    } catch (e) {
      _msg = '$e';
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _clear(String collection) async {
    setState(() => _busy = true);
    var n = 0;
    try {
      final snap = await FirebaseFirestore.instance.collection(collection).limit(300).get();
      for (final d in snap.docs) {
        await d.reference.delete();
        n++;
      }
      _msg = '$collection: $n deleted';
    } catch (e) {
      _msg = '$e';
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!context.app.firebaseReady) return const SizedBox.shrink();
    final u = _user;
    final email = u?.email;
    final admin = email != null && email.toLowerCase() == kAdminEmail;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (email == null)
          TextButton.icon(onPressed: _busy ? null : _signIn, icon: const Icon(Icons.admin_panel_settings_outlined, size: 18), label: Text(tx(context, 'Team sign-in', 'टीम साइन-इन')))
        else ...[
          Text('${tx(context, 'Signed in', 'साइन-इन')}: $email${admin ? ' (admin)' : ''}', style: Theme.of(context).textTheme.bodySmall),
          Wrap(spacing: 8, children: [
            if (admin) OutlinedButton(onPressed: _busy ? null : () => _clear('place_cache'), child: Text(tx(context, 'Clear place cache', 'जगह का कैश साफ़ करें'))),
            if (admin) OutlinedButton(onPressed: _busy ? null : () => _clear('narrations'), child: Text(tx(context, 'Clear AI notes cache', 'एआई नोट्स कैश साफ़ करें'))),
            TextButton(
                onPressed: () async {
                  await FirebaseAuth.instance.signOut();
                  if (mounted) setState(() {});
                },
                child: Text(tx(context, 'Sign out', 'साइन-आउट'))),
          ]),
        ],
        if (_msg != null) Text(_msg!, style: Theme.of(context).textTheme.bodySmall),
      ]),
    );
  }
}
