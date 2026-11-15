import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models/models.dart';
import '../stats/extra.dart';
import '../stats/trend.dart';
import '../theme.dart';
import 'common.dart';
import 'test_info.dart';
import 'trend_chart.dart';

/// The verdict panel used everywhere a time series is judged:
/// stamp, plain sentence, chart, three tests side by side, "years still needed",
/// cherry-pick shield, break warning, and how to reproduce it.
class TrendReport extends StatefulWidget {
  const TrendReport({super.key, required this.series, required this.title, this.unit = '', this.monthly, this.sourceNote, this.sourceUrl, this.percentBase});
  final Series series; // yearly values
  final String title, unit;
  final List<MonthlyPoint>? monthly; // enables the Seasonal Mann-Kendall test
  final String? sourceNote, sourceUrl;
  final double? percentBase;

  @override
  State<TrendReport> createState() => _TrendReportState();
}

class _TrendReportState extends State<TrendReport> {
  RangeValues? _range;

  @override
  void didUpdateWidget(covariant TrendReport old) {
    super.didUpdateWidget(old);
    if (old.series != widget.series) _range = null;
  }

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final expert = context.app.expert;
    final all = widget.series;
    if (all.years.length < 6) {
      return Text(tx(context, 'Not enough years to judge a trend.', 'रुझान परखने के लिए साल कम हैं।'));
    }
    final y0 = all.years.first.toDouble(), y1 = all.years.last.toDouble();
    final rg = _range ?? RangeValues(y0, y1);
    final a = all.years.indexWhere((y) => y >= rg.start.round());
    final b = all.years.lastIndexWhere((y) => y <= rg.end.round());
    final years = all.years.sublist(math.max(0, a), math.max(a, b) + 1);
    final vals = all.values.sublist(math.max(0, a), math.max(a, b) + 1);
    final s = Series(years, vals);
    final mk = mkTrend(vals, years, minYears: 8);
    final ols = olsTTest(vals, years);
    final mon = widget.monthly?.where((p) => p.year >= years.first && p.year <= years.last).toList();
    final smk = (mon != null && mon.length >= 36) ? seasonalMk(mon) : null;
    final pt = pettitt(vals, years);
    final scan = windowScan(vals, years, minLen: math.min(15, math.max(10, years.length ~/ 2)));
    final code = mk.verdict(minYears: 10);
    final up = (mk.slope.isNaN ? 0 : mk.slope) >= 0;
    final col = code == 'not_proven' || code == 'insufficient' ? k.notProven : (up ? k.rising : k.falling);
    final unit = widget.unit;
    final perDec = mk.slope * 10;

    // --- agreement of the tests
    final tests = <(String, String, double?, String)>[
      (
        tx(context, 'Straight-line fit (t-test)', 'सीधी रेखा (t-टेस्ट)'),
        tx(context, 'Fits a line; asks if the slope could be zero. Adjusted for year-to-year memory.', 'रेखा बिठाकर पूछता है: क्या ढलान शून्य हो सकती है? साल-दर-साल की याद के लिए सुधारा गया।'),
        ols.valid ? ols.pAdj : null,
        'ols'
      ),
      (
        tx(context, 'Mann-Kendall', 'मान-केंडल'),
        tx(context, 'Counts ups against downs; not fooled by one extreme year.', 'बढ़त और गिरावट गिनता है; एक अजीब साल से धोखा नहीं खाता।'),
        mk.valid ? mk.p : null,
        'mk'
      ),
      if (smk != null)
        (
          tx(context, 'Seasonal Mann-Kendall', 'मौसमी मान-केंडल'),
          tx(context, 'Compares each month only with the same month, so seasons cannot fake a trend.', 'हर महीने की तुलना उसी महीने से, ताकि मौसम का चक्र धोखा न दे।'),
          smk.p,
          'smk'
        ),
    ];
    final ciExcludesZero = mk.ciLo.isFinite && mk.ciHi.isFinite && (mk.ciLo > 0 || mk.ciHi < 0);
    final passed = tests.where((t) => t.$3 != null && t.$3! < 0.05).length + (ciExcludesZero ? 1 : 0);
    final totalChecks = tests.length + 1;

    String sentence() {
      final dir = up ? tx(context, 'rising', 'बढ़ रहा है') : tx(context, 'falling', 'घट रहा है');
      final rate = '${fmtNum(perDec.abs())} $unit ${tx(context, 'per decade', 'प्रति दशक')}';
      switch (code) {
        case 'confirmed':
          return tx(context, 'Yes, it is $dir: about $rate. This is very unlikely to be chance.', 'हाँ, यह $dir: लगभग $rate। यह संयोग होने की संभावना बहुत कम है।');
        case 'likely':
          return tx(context, 'Probably $dir (about $rate), but the change is still small next to the normal ups and downs.',
              'शायद $dir (लगभग $rate), पर बदलाव अभी सामान्य उतार-चढ़ाव के मुक़ाबले छोटा है।');
        case 'not_proven':
          return tx(context, 'Not proven. The line tilts ($rate) but ordinary ups and downs could produce this by chance.',
              'साबित नहीं। रेखा झुकी है ($rate) पर सामान्य उतार-चढ़ाव से भी ऐसा संयोग से हो सकता है।');
        default:
          return tx(context, 'Not enough data to judge.', 'परखने के लिए डेटा कम है।');
      }
    }

    final needs = (code == 'not_proven' || code == 'likely') && mk.yearsNeeded.isFinite ? math.max(0, mk.yearsNeeded.ceil() - mk.n) : null;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: k.card, borderRadius: BorderRadius.circular(18), border: Border.all(color: k.line), boxShadow: k.dark ? null : [BoxShadow(color: k.accent.withValues(alpha: 0.08), blurRadius: 14, offset: const Offset(0, 4))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        VerdictBanner(code: code, sentence: sentence(), rate: mk.valid ? '${fmtSigned(perDec)} $unit ${tx(context, 'per decade', 'प्रति दशक')}' : null),
        const SizedBox(height: 10),
        TrendChart(series: s, color: col, height: 170, unitLabel: unit, emergedLabel: context.t('emerged_in'), breakLabel: context.t('break_in')),
        Row(children: [
          Text('${rg.start.round()}', style: Theme.of(context).textTheme.bodySmall),
          Expanded(
            child: RangeSlider(
              values: rg,
              min: y0,
              max: y1,
              divisions: math.max(1, (y1 - y0).round()),
              labels: RangeLabels('${rg.start.round()}', '${rg.end.round()}'),
              onChanged: (v) {
                if (v.end - v.start >= 9) setState(() => _range = v);
              },
            ),
          ),
          Text('${rg.end.round()}', style: Theme.of(context).textTheme.bodySmall),
        ]),
        Text(tx(context, 'Drag to change the years: does the verdict survive?', 'साल बदलकर देखें: क्या फ़ैसला टिकता है?'), style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 10),

        // ---- tests side by side
        Text('${tx(context, 'Tests that agree', 'सहमत जाँचें')}: $passed / $totalChecks', style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        for (final t in tests) _TestRow(name: t.$1, hint: t.$2, pass: t.$3 == null ? null : t.$3! < 0.05, detail: expert ? 'p = ${fmtP(t.$3)}' : null, info: t.$4),
        _TestRow(
          name: tx(context, '95% confidence interval', '95% विश्वास अंतराल'),
          hint: tx(context, 'The range the true rate most likely lies in. If it includes zero, "no change" is still possible.',
              'वह दायरा जिसमें असली दर होने की सबसे ज़्यादा संभावना है। अगर इसमें शून्य है, तो "कोई बदलाव नहीं" भी संभव है।'),
          info: 'ci',
          pass: mk.ciLo.isFinite ? ciExcludesZero : null,
          detail: mk.ciLo.isFinite ? '${fmtSigned(mk.ciLo * 10)} … ${fmtSigned(mk.ciHi * 10)} $unit/${tx(context, 'decade', 'दशक')}' : null,
        ),
        const SizedBox(height: 4),
        const TestInfoChips(ids: ['sen', 'p']),
        const SizedBox(height: 8),

        // ---- needs more years / emerged
        if (needs != null && needs > 0)
          _Note(
            icon: Icons.hourglass_bottom,
            color: k.likely,
            text: tx(context, 'If this rate continues, about $needs more years of data would be needed to prove it.',
                'अगर यही दर रही, तो इसे साबित करने के लिए लगभग $needs और साल का डेटा चाहिए।'),
          ),
        if (mk.emerged)
          _Note(
            icon: Icons.flag,
            color: k.confirmed,
            text: tx(context, 'The change grew bigger than normal year-to-year swings around ${mk.toe1.round()}.',
                'बदलाव लगभग ${mk.toe1.round()} में सामान्य सालाना उतार-चढ़ाव से बड़ा हो गया।'),
          ),
        if (mk.valid && mk.pRaw < 0.05 && mk.p >= 0.05)
          _Note(
            icon: Icons.gpp_maybe,
            color: k.likely,
            text: tx(context, 'A naive test would call this significant (p = ${fmtP(mk.pRaw)}). But each year here resembles the one before, and such "memory" makes fake trends. After correcting for it: p = ${fmtP(mk.p)}.',
                'सीधी-सादी जाँच इसे साबित कह देती (p = ${fmtP(mk.pRaw)})। पर यहाँ हर साल पिछले साल जैसा है, और ऐसी "याद" झूठे रुझान बनाती है। इसे सुधारने के बाद: p = ${fmtP(mk.p)}।'),
          ),
        if (pt != null && pt.p < 0.05)
          _Note(
            icon: Icons.warning_amber,
            color: k.artifact,
            text: tx(context, 'Sudden jump near ${pt.year}. Check whether an instrument or method changed then; a jump is not a trend.',
                '${pt.year} के पास अचानक उछाल। देखें कि तब कोई यंत्र या तरीक़ा तो नहीं बदला; उछाल रुझान नहीं होता।'),
          ),

        // ---- cherry-pick shield
        if (scan != null && scan.total >= 6) ...[
          const SizedBox(height: 6),
          _Note(
            icon: Icons.shield,
            color: scan.agree >= 0.8 ? k.confirmed : (scan.agree >= 0.6 ? k.likely : k.artifact),
            text: tx(
                context,
                'Cherry-pick shield: the direction stays the same in ${(scan.agree * 100).round()}% of ${scan.total} start/end-year choices'
                    '${scan.oppositeSig > 0 ? '; ${scan.oppositeSig} choices even prove the opposite' : ''}.',
                'चुनिंदा-साल कवच: ${scan.total} शुरू/अंत साल के चुनावों में से ${(scan.agree * 100).round()}% में दिशा वही रहती है'
                    '${scan.oppositeSig > 0 ? '; ${scan.oppositeSig} चुनाव तो उल्टा साबित करते हैं' : ''}।'),
          ),
          if (expert) ...[
            const SizedBox(height: 6),
            SizedBox(height: 150, child: CustomPaint(painter: _ScanPainter(scan, k), size: Size.infinite)),
            Text(tx(context, 'Each square = one start year (across) and end year (down). Strong colour = significant; grey = opposite direction.',
                'हर चौकोर = एक शुरू साल (आड़ा) और अंत साल (खड़ा)। गहरा रंग = साबित; धूसर = उल्टी दिशा।'),
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ],

        // ---- scientist details
        if (expert && mk.valid) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            StatTile(label: 'Sen slope /yr', value: fmtSigned(mk.slope, digits: 3)),
            StatTile(label: 'OLS slope /yr', value: fmtSigned(ols.slope, digits: 3)),
            StatTile(label: 'MK p (lag-1)', value: fmtP(mk.p)),
            StatTile(label: 'MK p (raw)', value: fmtP(mk.pRaw)),
            StatTile(label: 't-test p (raw)', value: fmtP(ols.p)),
            StatTile(label: 'r1', value: fmtNum(mk.r1)),
            StatTile(label: 'n / n_eff', value: '${mk.n} / ${ols.nEff.isFinite ? ols.nEff.round() : '–'}'),
            StatTile(label: 'R²', value: fmtNum(ols.r2)),
            StatTile(label: tx(context, 'signal / noise', 'सिग्नल / शोर'), value: '${fmtNum(mk.snr, digits: 1)}×'),
            if (smk != null) StatTile(label: 'Seasonal Sen /yr', value: fmtSigned(smk.slopePerYear, digits: 3)),
          ]),
        ],
        const SizedBox(height: 4),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 8),
            leading: Icon(Icons.replay, color: k.accent, size: 20),
            title: Text(tx(context, 'Reproduce this', 'इसे खुद दोहराएँ'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            children: [
              SelectableText(
                [
                  if (widget.sourceNote != null) '${tx(context, 'Data', 'डेटा')}: ${widget.sourceNote}',
                  '${tx(context, 'Years', 'साल')}: ${years.first}-${years.last} (n = ${mk.n})',
                  tx(context, 'Rate: Sen\'s slope (median of all pairwise slopes), 95% interval after Gilbert (1987).', 'दर: सेन ढलान (सभी जोड़ों की ढलानों की माध्यिका), 95% अंतराल गिल्बर्ट (1987) के अनुसार।'),
                  tx(context, 'Tests: Mann-Kendall with lag-1 variance correction; least-squares t-test with effective sample size (Santer et al. 2008); Seasonal Kendall (Hirsch & Slack 1984) when monthly data exist.',
                      'जाँच: lag-1 सुधार के साथ मान-केंडल; प्रभावी नमूना आकार के साथ t-टेस्ट (Santer 2008); मासिक डेटा हो तो मौसमी केंडल (Hirsch-Slack 1984)।'),
                  tx(context, 'Verdict: Confirmed = p < 0.05 and change larger than year-to-year noise; Likely = p < 0.10; otherwise Not proven.',
                      'फ़ैसला: पक्का = p < 0.05 और बदलाव सालाना शोर से बड़ा; संभव = p < 0.10; वरना साबित नहीं।'),
                  'Python: pymannkendall.yue_wang_modification_test(values) / scipy.stats.linregress(years, values)',
                ].join('\n'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (widget.sourceUrl != null && widget.sourceUrl!.isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => AppScope.read(context).device.openUrl(widget.sourceUrl!),
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: Text(tx(context, 'Open the data source', 'डेटा स्रोत खोलें')),
                  ),
                ),
            ],
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => AppScope.read(context).device.shareWhatsApp(
                '${widget.title}: ${fmtSigned(perDec)} $unit ${tx(context, 'per decade', 'प्रति दशक')} (${years.first}-${years.last}). ${sentence()} - Kuch Toh Gadbad Hai'),
            icon: const Icon(Icons.share, size: 16),
            label: Text(tx(context, 'Share verdict', 'फ़ैसला भेजें')),
          ),
        ),
      ]),
    );
  }
}

class _TestRow extends StatelessWidget {
  const _TestRow({required this.name, required this.hint, required this.pass, this.detail, this.info});
  final String name, hint;
  final String? info; // key into kTestInfo: shows the (i) pop-up
  final bool? pass;
  final String? detail;
  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final c = pass == null ? k.muted : (pass! ? k.confirmed : k.notProven);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(pass == null ? Icons.remove_circle_outline : (pass! ? Icons.check_circle : Icons.cancel_outlined), color: c, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text.rich(TextSpan(children: [
              TextSpan(text: name, style: const TextStyle(fontWeight: FontWeight.w700)),
              TextSpan(
                  text: pass == null ? '' : '  ${pass! ? tx(context, 'says: real', 'कहता है: असली') : tx(context, 'says: not proven', 'कहता है: साबित नहीं')}',
                  style: TextStyle(color: c, fontWeight: FontWeight.w600, fontSize: 12.5)),
              if (detail != null) TextSpan(text: '  ($detail)', style: TextStyle(color: k.muted, fontSize: 12)),
            ])),
            Text(hint, style: TextStyle(color: k.muted, fontSize: 12)),
          ]),
        ),
        if (info != null) InfoDot(info!),
      ]),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.color, required this.text});
  final IconData icon;
  final Color color;
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 4),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(8)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13, height: 1.3))),
        ]),
      );
}

class _ScanPainter extends CustomPainter {
  _ScanPainter(this.scan, this.p);
  final WindowScan scan;
  final Palette p;
  @override
  void paint(Canvas canvas, Size size) {
    final n = scan.years.length;
    if (n < 2) return;
    final cw = size.width / n, ch = size.height / n;
    final step = scan.cells.length > 1 ? math.max(1, (scan.cells[1].$2 - scan.cells[0].$2).abs()) : 1;
    final base = scan.fullSign > 0 ? p.rising : p.falling;
    for (final c in scan.cells) {
      final col = switch (c.$3) { 2 => base, 1 => base.withValues(alpha: 0.35), 0 => p.muted.withValues(alpha: 0.30), _ => p.muted };
      canvas.drawRect(Rect.fromLTWH(c.$1 * cw, c.$2 * ch, cw * step + 0.5, ch * step + 0.5), Paint()..color = col);
    }
    void label(String t, Offset o) {
      final tp = TextPainter(text: TextSpan(text: t, style: TextStyle(color: p.muted, fontSize: 10)), textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, o);
    }

    label('${scan.years.first} →', const Offset(2, 2));
    label('↓ ${scan.years.last}', Offset(2, size.height - 14));
  }

  @override
  bool shouldRepaint(covariant _ScanPainter old) => old.scan != scan || old.p != p;
}
