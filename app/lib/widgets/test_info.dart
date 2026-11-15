import 'package:flutter/material.dart';

import '../app_state.dart';
import '../theme.dart';
import 'common.dart';

/// Plain-language explanation of each statistical test, shown in a small pop-up
/// wherever the test is named in the app.
class TestInfo {
  const TestInfo(this.icon, this.en, this.hi, this.whatEn, this.whatHi, this.howEn, this.howHi, this.readEn, this.readHi, this.ref);
  final IconData icon;
  final String en, hi, whatEn, whatHi, howEn, howHi, readEn, readHi, ref;
}

const kTestInfo = <String, TestInfo>{
  'ols': TestInfo(
    Icons.show_chart,
    'Straight-line fit (t-test)',
    'सीधी रेखा (t-टेस्ट)',
    'Draws the best straight line through the yearly values and asks: could the true slope be zero?',
    'सालाना आँकड़ों में से सबसे अच्छी सीधी रेखा खींचता है और पूछता है: क्या असली ढलान शून्य हो सकती है?',
    'The slope is divided by its uncertainty to get a t value. Because one year often resembles the next, we count fewer "independent" years (effective sample size), which makes the test stricter.',
    'ढलान को उसकी अनिश्चितता से भाग देकर t मान निकलता है। चूँकि एक साल अक्सर अगले जैसा होता है, हम कम "स्वतंत्र" साल गिनते हैं, जिससे जाँच और सख़्त हो जाती है।',
    'p below 0.05 means a slope this large would appear by chance less than 1 time in 20. Works best when the change is steady and the scatter is bell-shaped.',
    'p 0.05 से कम हो तो इतनी ढलान संयोग से 20 में 1 बार से भी कम दिखेगी। जब बदलाव एक-सा हो तब सबसे अच्छा काम करता है।',
    'Santer et al. (2008), Int. J. Climatology',
  ),
  'mk': TestInfo(
    Icons.swap_vert,
    'Mann-Kendall test',
    'मान-केंडल जाँच',
    'Asks only one thing: do later years tend to be higher (or lower) than earlier years?',
    'सिर्फ़ एक बात पूछता है: क्या बाद के साल पहले के सालों से ज़्यादा (या कम) रहते हैं?',
    'It compares every pair of years and counts ups minus downs. It uses only the order of values, not their size, so one freak year cannot fool it. We also correct for year-to-year memory (lag-1).',
    'यह सालों की हर जोड़ी की तुलना करके बढ़त घटा गिरावट गिनता है। यह सिर्फ़ क्रम देखता है, आकार नहीं, इसलिए एक अजीब साल इसे धोखा नहीं दे सकता। साल-दर-साल की याद के लिए सुधार भी किया जाता है।',
    'p below 0.05 means the ups (or downs) win too often to be chance. It is the standard trend test for rainfall, rivers and other "messy" data.',
    'p 0.05 से कम हो तो बढ़त (या गिरावट) इतनी बार जीतती है कि यह संयोग नहीं। बारिश, नदियों जैसे उबड़-खाबड़ डेटा के लिए यह मानक जाँच है।',
    'Mann (1945), Econometrica; Kendall (1975), Rank Correlation Methods',
  ),
  'smk': TestInfo(
    Icons.calendar_month,
    'Seasonal Mann-Kendall test',
    'मौसमी मान-केंडल जाँच',
    'The Mann-Kendall test done month by month, so the yearly cycle of seasons cannot fake or hide a trend.',
    'मान-केंडल जाँच, महीने-दर-महीने, ताकि मौसमों का सालाना चक्र रुझान को झूठा न बनाए और न छिपाए।',
    'January is compared only with other Januaries, July only with other Julys, and so on. The twelve answers are then added up.',
    'जनवरी की तुलना सिर्फ़ दूसरी जनवरियों से, जुलाई की सिर्फ़ जुलाइयों से, और इसी तरह। फिर बारह जवाब जोड़े जाते हैं।',
    'p below 0.05 means the change shows up across the months. Shown only when monthly data are available.',
    'p 0.05 से कम हो तो बदलाव कई महीनों में दिखता है। सिर्फ़ तब दिखता है जब मासिक डेटा हो।',
    'Hirsch, Slack & Smith (1982); Hirsch & Slack (1984)',
  ),
  'ci': TestInfo(
    Icons.straighten,
    '95% confidence interval',
    '95% विश्वास अंतराल',
    'Not one number but a range: the true rate of change most likely lies between these two values.',
    'एक संख्या नहीं, एक दायरा: बदलाव की असली दर इन दो मानों के बीच होने की सबसे ज़्यादा संभावना है।',
    'We compute the slope between every pair of years, sort them, and take the middle 95%.',
    'हम सालों की हर जोड़ी के बीच ढलान निकालते हैं, उन्हें क्रम में लगाते हैं, और बीच के 95% लेते हैं।',
    'If the range does not include zero, "no change" is ruled out. A narrow range means we know the rate well; a wide range means more years are needed.',
    'अगर दायरे में शून्य नहीं है, तो "कोई बदलाव नहीं" ख़ारिज। संकरा दायरा = दर अच्छी तरह पता है; चौड़ा दायरा = और साल चाहिए।',
    'Gilbert (1987), Statistical Methods for Environmental Pollution Monitoring',
  ),
  'sen': TestInfo(
    Icons.trending_up,
    "Sen's slope (the rate)",
    'सेन ढलान (दर)',
    'Our estimate of how fast the value changes per year or per decade.',
    'हमारा अनुमान कि मान हर साल या हर दशक कितनी तेज़ी से बदलता है।',
    'It is the middle value (median) of the slopes between all pairs of years, so a few extreme years barely move it.',
    'यह सालों की सभी जोड़ियों के बीच की ढलानों का बीच वाला मान (माध्यिका) है, इसलिए कुछ अजीब साल इसे मुश्किल से हिलाते हैं।',
    'A plus sign means rising, a minus sign means falling. Always read it together with the confidence interval.',
    'धन चिह्न = बढ़ रहा है, ऋण चिह्न = घट रहा है। इसे हमेशा विश्वास अंतराल के साथ पढ़ें।',
    'Sen (1968), J. American Statistical Association',
  ),
  'p': TestInfo(
    Icons.casino_outlined,
    'p-value',
    'p-मान',
    'How often pure chance alone would produce a trend at least this strong.',
    'सिर्फ़ संयोग से इतना या इससे तेज़ रुझान कितनी बार बन सकता है।',
    'Each test imagines a world with no real trend and counts how rarely our result would happen there.',
    'हर जाँच एक ऐसी दुनिया सोचती है जिसमें कोई असली रुझान नहीं, और गिनती है कि वहाँ हमारा नतीजा कितना दुर्लभ होता।',
    'Below 0.05 (1 in 20) is the usual bar for "significant". It is not the chance that the trend is false, and a small p does not mean a big change.',
    '0.05 (20 में 1) से कम को आम तौर पर "महत्वपूर्ण" माना जाता है। यह रुझान के ग़लत होने की संभावना नहीं है, और छोटा p बड़े बदलाव का मतलब नहीं।',
    'Wasserstein & Lazar (2016), The American Statistician',
  ),
};

void showTestInfo(BuildContext context, String id) {
  final t = kTestInfo[id];
  if (t == null) return;
  final hi = context.lang == 'hi';
  showDialog<void>(
    context: context,
    builder: (ctx) {
      final k = ctx.k;
      Widget part(String head, String body, Color c) => Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(head.toUpperCase(), style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
              const SizedBox(height: 2),
              Text(body, style: const TextStyle(height: 1.4)),
            ]),
          );
      return AlertDialog(
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
        title: Row(children: [
          IconBadge(t.icon, color: k.accent),
          const SizedBox(width: 10),
          Expanded(child: Text(hi ? t.hi : t.en, style: Theme.of(ctx).textTheme.titleLarge)),
        ]),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              part(hi ? 'यह क्या है' : 'What it is', hi ? t.whatHi : t.whatEn, k.accent),
              part(hi ? 'कैसे काम करता है' : 'How it works', hi ? t.howHi : t.howEn, k.falling),
              part(hi ? 'कैसे पढ़ें' : 'How to read it', hi ? t.readHi : t.readEn, k.rising),
              const SizedBox(height: 12),
              Text('${hi ? 'स्रोत' : 'Source'}: ${t.ref}', style: TextStyle(color: k.muted, fontSize: 12)),
            ]),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(hi ? 'समझ गया' : 'Got it'))],
      );
    },
  );
}

/// Small (i) button that opens the explanation of a test.
class InfoDot extends StatelessWidget {
  const InfoDot(this.id, {super.key, this.size = 18});
  final String id;
  final double size;
  @override
  Widget build(BuildContext context) => InkResponse(
        radius: 20,
        onTap: () => showTestInfo(context, id),
        child: Tooltip(
          message: tx(context, 'What is this test?', 'यह जाँच क्या है?'),
          child: Padding(padding: const EdgeInsets.all(4), child: Icon(Icons.info_outline, size: size, color: context.k.accent)),
        ),
      );
}

/// Row of chips, one per test, each opening its explanation.
class TestInfoChips extends StatelessWidget {
  const TestInfoChips({super.key, this.ids = const ['ols', 'mk', 'smk', 'ci', 'sen', 'p']});
  final List<String> ids;
  @override
  Widget build(BuildContext context) {
    final hi = context.lang == 'hi';
    return Wrap(spacing: 6, runSpacing: 6, children: [
      for (final id in ids)
        ActionChip(
          avatar: Icon(Icons.info_outline, size: 16, color: context.k.accent),
          label: Text(hi ? kTestInfo[id]!.hi : kTestInfo[id]!.en),
          onPressed: () => showTestInfo(context, id),
        ),
    ]);
  }
}
