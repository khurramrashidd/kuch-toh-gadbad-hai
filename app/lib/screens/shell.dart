import 'package:flutter/material.dart';

import '../app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'cases_screen.dart';
import 'explore_screen.dart';
import 'investigate_screen.dart';
import 'lab_screen.dart';
import 'place_screen.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    if (app.loading && app.catalog == null) {
      return Scaffold(
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.travel_explore, size: 56, color: context.k.accent),
            const SizedBox(height: 16),
            Text(context.t('app_name'), style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
            const SizedBox(height: 12),
            Text(context.t('loading'), style: TextStyle(color: context.k.muted)),
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
              Icon(Icons.folder_off, size: 52, color: context.k.muted),
              const SizedBox(height: 12),
              Text(context.t('no_data_title'), style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(context.t('no_data_body'), textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(app.error ?? '', textAlign: TextAlign.center, style: TextStyle(color: context.k.muted, fontSize: 12)),
              const SizedBox(height: 16),
              FilledButton.icon(onPressed: app.load, icon: const Icon(Icons.refresh), label: Text(context.t('retry'))),
            ]),
          ),
        ),
      );
    }
    final tab = app.tab.clamp(0, 4);
    final pages = [
      const InvestigateScreen(),
      const CasesScreen(),
      const PlaceScreen(),
      const ExploreScreen(),
      const LabScreen(),
    ];
    final dests = [
      (Icons.search_outlined, Icons.search, tx(context, 'Investigate', 'जाँच')),
      (Icons.folder_special_outlined, Icons.folder_special, context.t('tab_cases')),
      (Icons.my_location_outlined, Icons.my_location, context.t('tab_place')),
      (Icons.public_outlined, Icons.public, context.t('tab_explore')),
      (Icons.science_outlined, Icons.science, context.t('tab_lab')),
    ];
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final body = Column(children: [
      if (app.catalog!.demo) const DemoBanner(),
      Expanded(child: KeyedSubtree(key: ValueKey(app.dataVersion), child: IndexedStack(index: tab, children: pages))),
    ]);
    if (wide) {
      return Scaffold(
        body: Row(children: [
          NavigationRail(
            backgroundColor: context.k.surface,
            selectedIndex: tab,
            onDestinationSelected: (i) => AppScope.read(context).goTab(i),
            labelType: NavigationRailLabelType.all,
            leading: Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Icon(Icons.travel_explore, color: context.k.accent, size: 32)),
            destinations: [
              for (final d in dests) NavigationRailDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: Text(d.$3)),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: body),
        ]),
      );
    }
    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => AppScope.read(context).goTab(i),
        destinations: [for (final d in dests) NavigationDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: d.$3)],
      ),
    );
  }
}
