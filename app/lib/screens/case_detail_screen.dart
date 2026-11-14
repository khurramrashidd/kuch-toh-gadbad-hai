import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../models/json.dart';
import '../models/models.dart';
import '../services/ai_service.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/trend_chart.dart';
import '../widgets/world_map.dart';

class CaseDetailScreen extends StatefulWidget {
  const CaseDetailScreen({super.key, required this.summary});
  final CaseSummary summary;
  @override
  State<CaseDetailScreen> createState() => _CaseDetailScreenState();
}

class _CaseDetailScreenState extends State<CaseDetailScreen> {
  late Future<CaseFile> _future;
  Future<LayerMeta?>? _layer;
  Narration? _notes;
  bool _thinking = false;

  @override
  void initState() {
    super.initState();
    final app = AppScope.read(context);
    _future = app.data.caseFile(widget.summary.file).then((c) {
      _layer = _loadLayer(app, c);
      return c;
    });
  }

  Future<LayerMeta?> _loadLayer(AppState app, CaseFile c) async {
    final ds = c.layerSource == null ? null : app.catalog!.dataset(c.layerSource!);
    if (ds == null) return null;
    for (final l in ds.layers) {
      if (l.season == c.layerSeason) {
        try {
          return await app.data.layerMeta(l.path);
        } catch (_) {
          return null;
        }
      }
    }
    return null;
  }

  Future<void> _ask(CaseFile c) async {
    final app = AppScope.read(context);
    setState(() => _thinking = true);
    final n = await app.ai.narrate(c, app.lang);
    if (!mounted) return;
    setState(() {
      _notes = n;
      _thinking = false;
    });
  }

  String _shareText(CaseFile c, String lang) {
    final site = kIsWeb ? Uri.base.toString() : '';
    return '🕵️ ${c.name(lang)}\n${c.verdict.headline(lang)}\n${c.verdict.label(lang)}: ${c.verdict.detail(lang)}\n— Kuch Toh Gadbad Hai · NASA Space Apps 2026 $site';
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.lang;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.summary.name(lang), style: const TextStyle(fontWeight: FontWeight.w800)),
        actions: const [HeaderActions()],
      ),
      body: FutureBuilder<CaseFile>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('${snap.error}'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final c = snap.data!;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980),
              child: ListView(padding: const EdgeInsets.fromLTRB(14, 6, 14, 40), children: [
                _header(context, c, lang),
                const SizedBox(height: 12),
                _map(context, c, lang),
                SectionTitle('${c.sourceShort.isEmpty ? '' : pick(lang, c.sourceShort, c.sourceShortHi)} · ${pick(lang, c.seasonLabel.isNotEmpty ? c.seasonLabel[0] : c.season, c.seasonLabel.length > 1 ? c.seasonLabel[1] : c.season)} · ${c.period.isNotEmpty ? '${c.period.first}-${c.period.last}' : ''}',
                    icon: Icons.insights),
                LayoutBuilder(builder: (context, cons) {
                  final cards = [for (final r in c.regions) _RegionCard(region: r, c: c)];
                  if (cons.maxWidth > 700 && cards.length == 2) {
                    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(child: cards[0]),
                      const SizedBox(width: 12),
                      Expanded(child: cards[1]),
                    ]);
                  }
                  return Column(children: [for (final w in cards) Padding(padding: const EdgeInsets.only(bottom: 12), child: w)]);
                }),
                SectionTitle(context.t('evidence_board'), icon: Icons.push_pin),
                _EvidenceBoard(checks: c.checks),
                if (c.drivers.isNotEmpty) ...[
                  SectionTitle(context.t('the_suspects'), icon: Icons.person_search),
                  for (final d in c.drivers) _SuspectCard(d: d, c: c),
                ],
                SectionTitle(context.t('detective_notes'), icon: Icons.edit_note),
                _notesCard(context, c),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  FilledButton.icon(
                    onPressed: () => AppScope.read(context).device.shareWhatsApp(_shareText(c, lang)),
                    icon: const Icon(Icons.share),
                    label: Text(context.t('share_whatsapp')),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: _shareText(c, lang)));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.t('copied'))));
                      }
                    },
                    icon: const Icon(Icons.copy),
                    label: Text(context.t('share')),
                  ),
                ]),
                SectionTitle(context.t('source_data'), icon: Icons.satellite_alt),
                Text(pick(lang, c.sourceTitle, c.sourceTitleHi), style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('${context.t('mission')}: ${c.mission}', style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 4),
                SelectableText(c.citation, style: Theme.of(context).textTheme.bodySmall),
              ]),
            ),
          );
        },
      ),
    );
  }

  Widget _header(BuildContext context, CaseFile c, String lang) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: context.k.paper, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(context.t('the_question').toUpperCase(),
            style: TextStyle(color: context.k.ink, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.2, fontFamily: 'monospace')),
        const SizedBox(height: 6),
        Text(pick(lang, c.question, c.questionHi), style: TextStyle(color: context.k.ink, fontSize: 16.5, fontWeight: FontWeight.w700, height: 1.3)),
        const SizedBox(height: 14),
        CaseStamp(code: c.verdict.code, label: c.verdict.label(lang)),
        const SizedBox(height: 12),
        Text(c.verdict.headline(lang), style: TextStyle(color: context.k.ink, fontSize: 14.5, height: 1.35)),
        const SizedBox(height: 6),
        Text(c.verdict.detail(lang), style: TextStyle(color: context.k.ink, fontSize: 14, height: 1.35, fontStyle: FontStyle.italic)),
      ]),
    );
  }

  Widget _map(BuildContext context, CaseFile c, String lang) {
    final regions = <MapRegion>[
      for (final r in c.regions)
        if (r.cells.isNotEmpty || (r.bbox != null && r.bbox!.length == 4))
          MapRegion(color: context.k.signColor(r.sign), cells: r.cells, res: r.res, bbox: r.cells.isEmpty ? r.bbox : null, pin: r.pin, label: r.label(lang)),
    ];
    if (regions.isEmpty) return _AltitudePanel(c: c);
    final focus = toDL(c.raw['map_bounds']).whereType<double>().toList();
    return FutureBuilder<LayerMeta?>(
      future: _layer,
      builder: (context, snap) {
        final meta = snap.data;
        final app = context.app;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          WorldMap(
            layerUrl: meta == null ? null : app.data.url('${meta.path}/trend.png'),
            layerBounds: meta?.bounds,
            layerOpacity: 0.55,
            regions: regions,
            redString: true,
            focus: focus.length == 4 ? focus : null,
          ),
          const SizedBox(height: 6),
          Wrap(spacing: 14, runSpacing: 4, children: [
            for (final r in c.regions)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 12, height: 12, color: context.k.signColor(r.sign)),
                const SizedBox(width: 6),
                Text('${r.label(lang)} (${r.sign >= 0 ? context.t('rising') : context.t('falling')})', style: const TextStyle(fontSize: 12)),
              ]),
          ]),
        ]);
      },
    );
  }

  Widget _notesCard(BuildContext context, CaseFile c) {
    final n = _notes;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: context.k.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: context.k.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (n == null && !_thinking)
          FilledButton.tonalIcon(onPressed: () => _ask(c), icon: const Icon(Icons.auto_awesome), label: Text(context.t('ask_ai'))),
        if (_thinking) const LinearProgressIndicator(),
        if (n != null) ...[
          SelectableText(n.text, style: const TextStyle(fontSize: 14.5, height: 1.45)),
          const SizedBox(height: 8),
          Row(children: [
            Icon(n.ai ? Icons.auto_awesome : Icons.description, size: 14, color: context.k.muted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(n.ai ? '${context.t('ai_label')}${n.model != null ? ' (${n.model})' : ''}' : context.t('template_label'),
                  style: Theme.of(context).textTheme.bodySmall),
            ),
          ]),
        ],
      ]),
    );
  }
}

class _AltitudePanel extends StatelessWidget {
  const _AltitudePanel({required this.c});
  final CaseFile c;
  @override
  Widget build(BuildContext context) {
    final lang = context.lang;
    final rows = [...c.regions]..sort((a, b) => (a.levels?.first ?? 0).compareTo(b.levels?.first ?? 0));
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: context.k.card, borderRadius: BorderRadius.circular(14)),
      child: Column(children: [
        for (final r in rows)
          Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: context.k.signColor(r.sign).withValues(alpha: 0.18), borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              Icon(r.sign >= 0 ? Icons.arrow_upward : Icons.arrow_downward, color: context.k.signColor(r.sign)),
              const SizedBox(width: 10),
              Expanded(child: Text(r.label(lang), style: const TextStyle(fontWeight: FontWeight.w700))),
              Text('${fmtSigned(r.trend.slopeDec)} ${c.perDecadeLabel(lang)}', style: TextStyle(color: context.k.signColor(r.sign), fontWeight: FontWeight.w800)),
            ]),
          ),
      ]),
    );
  }
}

class _RegionCard extends StatelessWidget {
  const _RegionCard({required this.region, required this.c});
  final CaseRegion region;
  final CaseFile c;
  @override
  Widget build(BuildContext context) {
    final lang = context.lang;
    final t = region.trend;
    final col = context.k.signColor(region.sign);
    final per = c.perDecadeLabel(lang);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: context.k.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: col.withValues(alpha: 0.5))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: col, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(child: Text(region.label(lang), style: Theme.of(context).textTheme.titleMedium)),
          VerdictChip(t.verdict, dense: true),
        ]),
        const SizedBox(height: 8),
        Text('${fmtSigned(t.slopeDec)} $per', style: TextStyle(color: col, fontSize: 22, fontWeight: FontWeight.w900)),
        Text('${context.t('ci95')}: ${fmtNum(t.ciLoDec)} … ${fmtNum(t.ciHiDec)}', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        TrendChart(
          series: region.series,
          color: col,
          height: 150,
          unitLabel: c.units,
          emergedLabel: context.t('emerged_in'),
          breakLabel: context.t('break_in'),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          StatTile(label: context.t('significance'), value: fmtP(t.p)),
          StatTile(label: context.t('signal_noise'), value: '${fmtNum(t.snr, digits: 1)}×'),
          StatTile(
            label: t.emerged ? context.t('emerged_in') : context.t('needs_years'),
            value: t.emerged ? '${t.toe1?.round() ?? '–'}' : (t.yearsNeeded == null ? '–' : '~${t.yearsNeeded!.ceil()} ${context.t('years')}'),
            color: t.emerged ? context.k.confirmed : context.k.likely,
          ),
          if (region.areaKm2 != null) StatTile(label: 'km²', value: fmtNum(region.areaKm2)),
        ]),
      ]),
    );
  }
}

class _EvidenceBoard extends StatelessWidget {
  const _EvidenceBoard({required this.checks});
  final List<Check> checks;
  @override
  Widget build(BuildContext context) {
    final lang = context.lang;
    return Column(children: [
      for (final ch in checks)
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: context.k.paper,
            borderRadius: BorderRadius.circular(10),
            boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(1, 2))],
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: context.k.check(ch.status), width: 2.5)),
              child: Icon(
                switch (ch.status) { 'pass' => Icons.check, 'warn' => Icons.priority_high, 'fail' => Icons.close, _ => Icons.remove },
                color: context.k.check(ch.status),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(ch.title(lang).toUpperCase(),
                    style: TextStyle(color: context.k.ink, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1, fontFamily: 'monospace')),
                const SizedBox(height: 3),
                Text(ch.text(lang), style: TextStyle(color: context.k.ink, fontSize: 13.5, height: 1.3)),
              ]),
            ),
          ]),
        ),
    ]);
  }
}

class _SuspectCard extends StatelessWidget {
  const _SuspectCard({required this.d, required this.c});
  final DriverTest d;
  final CaseFile c;
  @override
  Widget build(BuildContext context) {
    final lang = context.lang;
    final col = switch (d.verdict) { 'strong' => context.k.confirmed, 'weak' => context.k.likely, _ => context.k.notProven };
    final label = switch (d.verdict) { 'strong' => context.t('suspect_strong'), 'weak' => context.t('suspect_weak'), _ => context.t('suspect_none') };
    String expl(Fingerprint f) {
      final e = f.explained;
      if (e == null || !e.isFinite) return '–';
      if (e > 1.5) return '>100%';
      return '${(e * 100).round()}%';
    }

    final series = d.series ?? d.a.series;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: context.k.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: col.withValues(alpha: 0.6))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(d.kind == 'local' ? Icons.location_searching : Icons.public, size: 18, color: col),
          const SizedBox(width: 8),
          Expanded(child: Text(d.name(lang), style: Theme.of(context).textTheme.titleMedium)),
          Pill(label, color: col),
        ]),
        const SizedBox(height: 2),
        Text(d.kind == 'local' ? context.t('suspect_local') : context.t('suspect_global'), style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final (i, f) in [d.a, d.b].indexed)
            if (i < c.regions.length)
              StatTile(
                label: '${c.regions[i].label(lang)} · ${context.t('fingerprint')}',
                value: '${context.t('explains')} ${expl(f)} · p ${fmtP(f.p)}',
                color: context.k.signColor(c.regions[i].sign),
              ),
        ]),
        if (series != null && !series.isEmpty) ...[
          const SizedBox(height: 8),
          Text(context.t('driver_series'), style: Theme.of(context).textTheme.bodySmall),
          TrendChart(series: series, color: col, height: 110, unitLabel: d.units, emergedLabel: context.t('emerged_in'), breakLabel: context.t('break_in')),
        ],
      ]),
    );
  }
}
