import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models/models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'case_detail_screen.dart';

class CasesScreen extends StatefulWidget {
  const CasesScreen({super.key});
  @override
  State<CasesScreen> createState() => _CasesScreenState();
}

class _CasesScreenState extends State<CasesScreen> {
  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final lang = app.lang;
    final cat = app.catalog!;
    final cases = cat.cases.where((c) => _filter == 'all' || c.spotlight == _filter).toList();
    return SafeArea(
      child: CustomScrollView(slivers: [
        SliverAppBar(
          pinned: true,
          title: Text(context.t('app_name'), style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.3)),
          actions: const [HeaderActions()],
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(context.t('app_tagline'), style: TextStyle(color: context.k.accent, fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(context.t('what_where_howmuch'), style: TextStyle(color: context.k.muted, fontSize: 12.5)),
              const SizedBox(height: 14),
              Text(context.t('cases_intro')),
              const SizedBox(height: 12),
              Wrap(spacing: 8, children: [
                for (final f in const ['all', 'india', 'global'])
                  ChoiceChip(
                    label: Text(context.t('filter_$f')),
                    selected: _filter == f,
                    onSelected: (_) => setState(() => _filter = f),
                  ),
              ]),
            ]),
          ),
        ),
        if (cases.isEmpty)
          SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(24), child: Text(context.t('no_cases'))))
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
            sliver: SliverLayoutBuilder(builder: (context, cons) {
              final cols = cons.crossAxisExtent > 1100 ? 3 : (cons.crossAxisExtent > 700 ? 2 : 1);
              return SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  mainAxisExtent: 292,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) => CaseCard(summary: cases[i], lang: lang),
                  childCount: cases.length,
                ),
              );
            }),
          ),
      ]),
    );
  }
}

class CaseCard extends StatelessWidget {
  const CaseCard({super.key, required this.summary, required this.lang});
  final CaseSummary summary;
  final String lang;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final a = s.regions.isNotEmpty ? s.regions[0] : null;
    final b = s.regions.length > 1 ? s.regions[1] : null;
    final per = pick(lang, s.perDecade, s.perDecadeHi);
    return Material(
      color: context.k.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CaseDetailScreen(summary: s))),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(s.spotlight == 'india' ? Icons.location_on : Icons.public, size: 16, color: context.k.accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(s.name(lang), maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium),
              ),
            ]),
            const SizedBox(height: 4),
            Text(s.tag(lang), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.k.muted, fontSize: 12.5)),
            const SizedBox(height: 10),
            if (a != null && b != null) TwinSparkline(a: a.spark, b: b.spark, signA: a.sign, signB: b.sign),
            const SizedBox(height: 8),
            for (final r in [a, b])
              if (r != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Row(children: [
                    Icon(r.sign >= 0 ? Icons.trending_up : Icons.trending_down, size: 16, color: context.k.signColor(r.sign)),
                    const SizedBox(width: 6),
                    Expanded(child: Text(pick(lang, r.name, r.nameHi), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5))),
                    Text('${fmtSigned(r.slopeDec)} $per', style: TextStyle(color: context.k.signColor(r.sign), fontSize: 12, fontWeight: FontWeight.w700)),
                  ]),
                ),
            const Spacer(),
            Row(children: [
              Expanded(child: Align(alignment: Alignment.centerLeft, child: CaseStamp(code: s.verdict.code, label: s.verdict.label(lang), size: 0.8))),
              const SizedBox(width: 8),
              _StrengthMeter(value: s.strength),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _StrengthMeter extends StatelessWidget {
  const _StrengthMeter({required this.value});
  final int value;
  @override
  Widget build(BuildContext context) {
    final c = value >= 70 ? context.k.confirmed : (value >= 45 ? context.k.likely : context.k.notProven);
    return Tooltip(
      message: context.t('strength'),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < 5; i++)
          Container(
            width: 8,
            height: 14,
            margin: const EdgeInsets.only(left: 2),
            decoration: BoxDecoration(color: value >= (i + 1) * 20 - 5 ? c : context.k.line, borderRadius: BorderRadius.circular(2)),
          ),
        const SizedBox(width: 6),
        Text('$value', style: TextStyle(color: c, fontWeight: FontWeight.w800)),
      ]),
    );
  }
}
