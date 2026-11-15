import 'package:flutter/material.dart';

import '../app_state.dart';
import '../config.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'cases_screen.dart';
import 'evidence_screen.dart';
import 'explore_screen.dart';
import 'game_screen.dart';
import 'investigate_screen.dart';
import 'lab_screen.dart';
import 'place_screen.dart';

const _monthsEn = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _monthsHi = ['जन', 'फ़र', 'मार्च', 'अप्रैल', 'मई', 'जून', 'जुल', 'अग', 'सित', 'अक्टू', 'नव', 'दिस'];
const _daysEn = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _daysHi = ['सोम', 'मंगल', 'बुध', 'गुरु', 'शुक्र', 'शनि', 'रवि'];

String _date(DateTime t, String lang) => lang == 'hi' ? '${_daysHi[t.weekday - 1]}, ${t.day} ${_monthsHi[t.month - 1]} ${t.year}' : '${_daysEn[t.weekday - 1]}, ${t.day} ${_monthsEn[t.month - 1]} ${t.year}';
String _time(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Responsive frame.
///  phone   (< 700)       header + content + bottom navigation
///  tablet  (700 - 1199)  header + left rail + content + footer
///  desktop (>= 1200)     header + left sidebar + content + right sidebar + footer
class Shell extends StatelessWidget {
  const Shell({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final k = context.k;
    if (app.loading && app.catalog == null) {
      return Scaffold(
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.travel_explore, size: 56, color: k.accent),
            const SizedBox(height: 16),
            Text(context.t('app_name'), style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
            const SizedBox(height: 12),
            Text(context.t('loading'), style: TextStyle(color: k.muted)),
          ]),
        ),
      );
    }
    if (app.catalog == null) {
      return Scaffold(
        appBar: AppBar(title: Text(context.t('app_name')), actions: const [HeaderActions()]),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.folder_off, size: 52, color: k.muted),
              const SizedBox(height: 12),
              Text(context.t('no_data_title'), style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(context.t('no_data_body'), textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(app.error ?? '', textAlign: TextAlign.center, style: TextStyle(color: k.muted, fontSize: 12)),
              const SizedBox(height: 16),
              FilledButton.icon(onPressed: app.load, icon: const Icon(Icons.refresh), label: Text(context.t('retry'))),
            ]),
          ),
        ),
      );
    }
    final tab = app.tab.clamp(0, 4);
    const pages = [InvestigateScreen(), CasesScreen(), PlaceScreen(), ExploreScreen(), LabScreen()];
    final dests = [
      (Icons.search_outlined, Icons.search, tx(context, 'Investigate', 'जाँच'), tx(context, 'Ask, then test', 'पूछें, फिर परखें')),
      (Icons.folder_special_outlined, Icons.folder_special, context.t('tab_cases'), tx(context, 'Opposite trends, one cause?', 'उल्टे रुझान, एक वजह?')),
      (Icons.my_location_outlined, Icons.my_location, context.t('tab_place'), tx(context, '40 years where you live', 'आपकी जगह के 40 साल')),
      (Icons.public_outlined, Icons.public, context.t('tab_explore'), tx(context, 'Map, globe, regions', 'नक़्शा, ग्लोब, क्षेत्र')),
      (Icons.science_outlined, Icons.science, context.t('tab_lab'), tx(context, 'Methods and references', 'तरीक़े और संदर्भ')),
    ];
    final w = MediaQuery.sizeOf(context).width;
    final phone = w < 700, desktop = w >= 1200, wideRight = w >= 1320;
    void go(int i) => AppScope.read(context).goTab(i);

    final content = Column(children: [
      if (app.catalog!.demo) const DemoBanner(),
      Expanded(
        child: Stack(children: [
          Positioned.fill(child: InShell(child: KeyedSubtree(key: ValueKey(app.dataVersion), child: IndexedStack(index: tab, children: pages)))),
          const Positioned(right: 12, bottom: 12, left: 12, child: Align(alignment: Alignment.bottomRight, child: RecapBanner())),
        ]),
      ),
    ]);

    if (phone) {
      return Scaffold(
        drawer: _Menu(dests: [for (final d in dests) (d.$2, d.$3, d.$4)], tab: tab),
        body: ColoredBox(color: k.brand.first, child: SafeArea(bottom: false, child: ColoredBox(color: k.bg, child: Column(children: [const _Header(compact: true), Expanded(child: MediaQuery.removePadding(context: context, removeTop: true, child: content))])))),
        bottomNavigationBar: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: go,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: [for (var i = 0; i < dests.length; i++) NavigationDestination(icon: Icon(dests[i].$1, color: k.tab(i)), selectedIcon: Icon(dests[i].$2), label: dests[i].$3)],
        ),
      );
    }

    final Widget left = desktop
        ? Container(
            width: 236,
            color: k.surface,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const SizedBox(height: 10),
              for (var i = 0; i < dests.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  child: Material(
                    color: i == tab ? k.tab(i) : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => go(i),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Row(children: [
                          Icon(i == tab ? dests[i].$2 : dests[i].$1, color: i == tab ? Colors.white : k.tab(i)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(dests[i].$3, style: TextStyle(fontWeight: FontWeight.w800, fontFamily: kHeadFont, color: i == tab ? Colors.white : k.text)),
                              Text(dests[i].$4, style: TextStyle(fontSize: 11.5, color: i == tab ? Colors.white.withValues(alpha: 0.85) : k.muted)),
                            ]),
                          ),
                        ]),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 6),
              const RecapTile(),
              const ApkButton(tile: true),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Text(tx(context, 'Other tools draw the line.\nWe tell you if it is real.', 'दूसरे टूल रेखा खींचते हैं।\nहम बताते हैं कि वह असली है या नहीं।'), style: TextStyle(color: k.muted, fontSize: 12, height: 1.35)),
              ),
            ]),
          )
        : NavigationRail(
            backgroundColor: k.surface,
            selectedIndex: tab,
            onDestinationSelected: go,
            labelType: NavigationRailLabelType.all,
            destinations: [for (final d in dests) NavigationRailDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: Text(d.$3))],
          );

    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          const _Header(compact: false),
          Divider(height: 1, color: k.line),
          Expanded(
            child: Row(children: [
              left,
              VerticalDivider(width: 1, color: k.line),
              Expanded(child: content),
              if (wideRight) ...[VerticalDivider(width: 1, color: k.line), const _RightBar()],
            ]),
          ),
          Divider(height: 1, color: k.line),
          const _Footer(),
        ]),
      ),
    );
  }
}

/// Date, time, place and current weather. Tap the place to (re)locate.
class _HereNow extends StatelessWidget {
  const _HereNow({this.dense = false});
  final bool dense;
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final k = context.k;
    final lang = app.lang;
    final wx = app.weather;
    final style = TextStyle(color: k.muted, fontSize: dense ? 12 : 13, fontWeight: FontWeight.w600);
    final place = app.hereName ?? (app.here == null ? null : '${app.here!.$1.toStringAsFixed(1)}°, ${app.here!.$2.toStringAsFixed(1)}°');
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.calendar_today, size: dense ? 13 : 15, color: k.muted),
        const SizedBox(width: 5),
        Text('${_date(app.now, lang)} · ${_time(app.now)}', style: style),
        const SizedBox(width: 10),
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => AppScope.read(context).locate(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(app.locating ? Icons.gps_not_fixed : Icons.place, size: dense ? 14 : 16, color: k.accent),
              const SizedBox(width: 3),
              Text(place ?? (app.locating ? tx(context, 'Finding you…', 'आपको खोज रहे हैं…') : tx(context, 'Use my location', 'मेरी जगह इस्तेमाल करें')),
                  style: style.copyWith(color: k.accent)),
            ]),
          ),
        ),
        if (wx != null) ...[
          const SizedBox(width: 8),
          Icon(wx.icon, size: dense ? 15 : 17, color: k.rising),
          const SizedBox(width: 4),
          Text('${wx.tempC.round()}°C · ${lang == 'hi' ? wx.words.$2 : wx.words.$1}', style: style.copyWith(color: k.text)),
        ],
      ]),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.compact});
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final base = context.k;
    // Everything inside the bar is drawn in white on the blue-to-teal gradient.
    return Theme(
      data: Theme.of(context).copyWith(extensions: [base.onBrand()]),
      child: Builder(builder: (context) {
        final title = Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: compact ? 32 : 36,
            height: compact ? 32 : 36,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(11)),
            child: Icon(Icons.travel_explore, color: const Color(0xFFFFC078), size: compact ? 20 : 23),
          ),
          const SizedBox(width: 9),
          Flexible(child: Text(kAppName, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w900, fontSize: compact ? 18 : 20, color: Colors.white, fontFamily: kHeadFont))),
        ]);
        final deco = BoxDecoration(
          gradient: LinearGradient(begin: Alignment.centerLeft, end: Alignment.centerRight, colors: base.brand),
          boxShadow: [BoxShadow(color: base.brand.first.withValues(alpha: 0.25), blurRadius: 10, offset: const Offset(0, 3))],
        );
        if (compact) {
          return Container(
            decoration: deco,
            padding: const EdgeInsets.fromLTRB(2, 4, 4, 8),
            child: CustomPaint(
              painter: OrbitPainter(Colors.white.withValues(alpha: 0.08)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  IconButton(
                    tooltip: tx(context, 'Menu', 'मेनू'),
                    onPressed: () => Scaffold.of(context).openDrawer(),
                    icon: const Icon(Icons.menu_rounded, color: Colors.white),
                  ),
                  Expanded(child: title),
                  const ThemeButton(),
                ]),
                const Padding(padding: EdgeInsets.only(left: 12), child: _HereNow(dense: true)),
              ]),
            ),
          );
        }
        return Container(
          decoration: deco,
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: CustomPaint(
            painter: OrbitPainter(Colors.white.withValues(alpha: 0.08)),
            child: Row(children: [
              title,
              const SizedBox(width: 20),
              const Expanded(child: _HereNow()),
              const HeaderActions(force: true),
            ]),
          ),
        );
      }),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final k = context.k;
    final cat = app.catalog!;
    final style = TextStyle(color: k.muted, fontSize: 11.5);
    final g = cat.generatedAt.length >= 16 ? cat.generatedAt.substring(0, 16).replaceAll('T', ' ') : cat.generatedAt;
    return Container(
      color: k.surface,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      child: Row(children: [
        Expanded(
          child: Text(
              '${cat.datasets.length} ${tx(context, 'NASA and partner datasets', 'NASA व साझेदार डेटासेट')} · ${cat.cases.length} ${tx(context, 'cases', 'केस')} · ${tx(context, 'data updated', 'डेटा अपडेट')} $g UTC · '
              '${tx(context, 'AI-assisted; verdicts are computed, not AI-written', 'एआई-सहायित; फ़ैसले गणना से, एआई से नहीं')} · Team $kTeamName, NASA Space Apps 2026',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style),
        ),
        InkWell(onTap: () => AppScope.read(context).goTab(4), child: Text(tx(context, 'References', 'संदर्भ'), style: style.copyWith(color: k.accent, fontWeight: FontWeight.w700))),
      ]),
    );
  }
}

/// Desktop right sidebar: here and now, how to read a verdict, the top case, data status.
class _RightBar extends StatelessWidget {
  const _RightBar();
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final k = context.k;
    final lang = app.lang;
    final cat = app.catalog!;
    final wx = app.weather;
    Widget card(String title, IconData icon, List<Widget> children) => Container(
          margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: k.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: k.line)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Icon(icon, size: 18, color: k.accent), const SizedBox(width: 6), Text(title, style: const TextStyle(fontWeight: FontWeight.w800))]),
            const SizedBox(height: 8),
            ...children,
          ]),
        );
    final top = cat.cases.isNotEmpty ? cat.cases.first : null;
    return Container(
      width: 300,
      color: k.bg,
      child: ListView(padding: const EdgeInsets.only(bottom: 16), children: [
        card(tx(context, 'Here and now', 'यहाँ और अभी'), Icons.place, [
          Text(_date(app.now, lang), style: TextStyle(color: k.muted, fontSize: 12.5)),
          Text(_time(app.now), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          if (app.here == null)
            OutlinedButton.icon(
                onPressed: app.locating ? null : () => AppScope.read(context).locate(),
                icon: const Icon(Icons.my_location, size: 18),
                label: Text(app.locating ? tx(context, 'Finding you…', 'खोज रहे हैं…') : tx(context, 'Use my location', 'मेरी जगह इस्तेमाल करें')))
          else ...[
            Text(app.hereName ?? '${app.here!.$1.toStringAsFixed(2)}°, ${app.here!.$2.toStringAsFixed(2)}°', style: const TextStyle(fontWeight: FontWeight.w700)),
            if (wx != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(children: [
                  Icon(wx.icon, color: k.rising, size: 30),
                  const SizedBox(width: 8),
                  Text('${wx.tempC.round()}°C', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  const SizedBox(width: 8),
                  Expanded(child: Text('${lang == 'hi' ? wx.words.$2 : wx.words.$1}\n${tx(context, 'humidity', 'नमी')} ${wx.humidity}% · ${tx(context, 'wind', 'हवा')} ${wx.wind.round()} km/h', style: TextStyle(color: k.muted, fontSize: 12))),
                ]),
              ),
            const SizedBox(height: 6),
            Text(tx(context, 'Today is weather. The trend is climate:', 'आज का हाल मौसम है। रुझान जलवायु है:'), style: TextStyle(color: k.muted, fontSize: 12)),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                  onPressed: () => AppScope.read(context).goTab(2), icon: const Icon(Icons.timeline, size: 18), label: Text(tx(context, 'See 40 years at this place', 'इस जगह के 40 साल देखें'))),
            ),
          ],
        ]),
        card(tx(context, 'How to read a verdict', 'फ़ैसला कैसे पढ़ें'), Icons.gavel, [
          for (final v in [
            ('confirmed', tx(context, 'Real change, bigger than normal ups and downs.', 'असली बदलाव, सामान्य उतार-चढ़ाव से बड़ा।')),
            ('likely', tx(context, 'Probably real, still small.', 'शायद असली, अभी छोटा।')),
            ('not_proven', tx(context, 'Could be chance. May need more years.', 'संयोग हो सकता है। और साल चाहिए।')),
            ('artifact', tx(context, 'A jump when an instrument changed.', 'यंत्र बदलने पर आया उछाल।')),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 108, child: Align(alignment: Alignment.centerLeft, child: VerdictChip(v.$1, dense: true))),
                Expanded(child: Text(v.$2, style: const TextStyle(fontSize: 12))),
              ]),
            ),
        ]),
        if (top != null)
          card(tx(context, 'Strongest case', 'सबसे मज़बूत केस'), Icons.folder_special, [
            Text(top.name(lang), style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(top.verdict.label(lang), style: TextStyle(color: k.caseVerdict(top.verdict.code), fontWeight: FontWeight.w700, fontSize: 12.5)),
            Align(
                alignment: Alignment.centerLeft,
                child: TextButton(onPressed: () => AppScope.read(context).goTab(1), child: Text(tx(context, 'Open the case files', 'केस फ़ाइलें खोलें')))),
          ]),
        card(tx(context, 'Data status', 'डेटा की स्थिति'), Icons.storage, [
          Text('${cat.datasets.length} ${tx(context, 'datasets', 'डेटासेट')} · ${cat.cases.length} ${tx(context, 'cases', 'केस')} · ${cat.places.length} ${tx(context, 'cities', 'शहर')}', style: const TextStyle(fontSize: 12.5)),
          Text('${tx(context, 'Live refresh', 'लाइव रिफ़्रेश')}: ${app.live ? tx(context, 'on', 'चालू') : tx(context, 'off', 'बंद')}', style: TextStyle(color: k.muted, fontSize: 12)),
          Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(onPressed: () => AppScope.read(context).reload(), icon: const Icon(Icons.refresh, size: 18), label: Text(context.t('reload_data')))),
        ]),
      ]),
    );
  }
}

/// Phone menu (hamburger): every section, the tools and the settings in one place.
class _Menu extends StatelessWidget {
  const _Menu({required this.dests, required this.tab});
  final List<(IconData, String, String)> dests;
  final int tab;
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final k = context.k;
    void close() => Navigator.of(context).pop();
    Widget label(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
          child: Text(t.toUpperCase(), style: TextStyle(color: k.muted, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
        );
    return Drawer(
      backgroundColor: k.surface,
      child: SafeArea(
        child: ListView(padding: EdgeInsets.zero, children: [
          Container(
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: k.brand)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.travel_explore, color: Color(0xFFFFC078), size: 30),
                SizedBox(width: 10),
                Expanded(child: Text(kAppName, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 19, color: Colors.white, fontFamily: kHeadFont))),
              ]),
              const SizedBox(height: 6),
              Text(tx(context, 'The Earth trend detective', 'पृथ्वी के रुझानों का जासूस'), style: TextStyle(color: Colors.white.withValues(alpha: 0.88), fontSize: 13)),
            ]),
          ),
          label(tx(context, 'Sections', 'अनुभाग')),
          for (var i = 0; i < dests.length; i++)
            ListTile(
              leading: IconBadge(dests[i].$1, color: k.tab(i), size: 36, solid: i == tab),
              title: Text(dests[i].$2, style: TextStyle(fontWeight: FontWeight.w800, fontFamily: kHeadFont, color: i == tab ? k.tab(i) : k.text)),
              subtitle: Text(dests[i].$3, style: TextStyle(fontSize: 12, color: k.muted)),
              selected: i == tab,
              onTap: () {
                close();
                AppScope.read(context).goTab(i);
              },
            ),
          label(tx(context, 'Tools', 'औज़ार')),
          ListTile(
            leading: IconBadge(Icons.upload_file, color: k.sun, size: 36),
            title: Text(tx(context, 'Bring your own evidence', 'अपना सबूत लाएँ')),
            onTap: () {
              close();
              Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const EvidenceScreen()));
            },
          ),
          ListTile(
            leading: IconBadge(Icons.sports_esports, color: k.violet, size: 36),
            title: Text(tx(context, 'Can you beat the test?', 'क्या आप जाँच को हरा सकते हैं?')),
            onTap: () {
              close();
              Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const GameScreen()));
            },
          ),
          const RecapTile(),
          const ApkButton(tile: true),
          label(tx(context, 'Settings', 'सेटिंग')),
          SwitchListTile(
            secondary: Icon(Icons.science_outlined, color: k.muted),
            title: Text(tx(context, 'Scientist mode', 'वैज्ञानिक मोड')),
            subtitle: Text(tx(context, 'Show every number', 'सारे आँकड़े दिखाएँ'), style: const TextStyle(fontSize: 12)),
            value: app.expert,
            onChanged: (_) => AppScope.read(context).toggleExpert(),
          ),
          SwitchListTile(
            secondary: Icon(Icons.dark_mode_outlined, color: k.muted),
            title: Text(tx(context, 'Dark mode', 'डार्क मोड')),
            value: app.dark,
            onChanged: (_) => AppScope.read(context).toggleTheme(),
          ),
          ListTile(
            leading: Icon(Icons.translate, color: k.muted),
            title: Text(tx(context, 'Language', 'भाषा')),
            trailing: Text(app.lang == 'hi' ? 'हिन्दी' : 'English', style: TextStyle(color: k.accent, fontWeight: FontWeight.w700)),
            onTap: () => AppScope.read(context).toggleLang(),
          ),
          ListTile(
            leading: Icon(Icons.my_location, color: k.muted),
            title: Text(tx(context, 'Use my location', 'मेरी जगह इस्तेमाल करें')),
            subtitle: app.hereName == null ? null : Text(app.hereName!, style: const TextStyle(fontSize: 12)),
            onTap: () => AppScope.read(context).locate(),
          ),
          ListTile(
            leading: Icon(Icons.refresh, color: k.muted),
            title: Text(context.t('reload_data')),
            onTap: () {
              close();
              AppScope.read(context).reload();
            },
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Text('Team $kTeamName · NASA Space Apps 2026\n${tx(context, 'AI-assisted; verdicts are computed, not AI-written.', 'एआई-सहायित; फ़ैसले गणना से, एआई से नहीं।')}', style: TextStyle(color: k.muted, fontSize: 11.5, height: 1.4)),
          ),
        ]),
      ),
    );
  }
}
