import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../l10n/strings.dart';
import '../models/models.dart';
import '../services/device_service.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../knowledge.dart';
import '../widgets/trend_chart.dart';
import '../widgets/trend_report.dart';
import '../widgets/world_map.dart';
import 'case_detail_screen.dart';

class _Spot {
  _Spot(this.lat, this.lon, this.name, [this.nameHi = '']);
  final double lat, lon;
  final String name, nameHi;
}

class _SatSample {
  _SatSample(this.ds, this.meta, this.cell);
  final DatasetInfo ds;
  final LayerMeta meta;
  final CellInfo cell;
}

class PlaceScreen extends StatefulWidget {
  const PlaceScreen({super.key});
  @override
  State<PlaceScreen> createState() => _PlaceScreenState();
}

class _PlaceScreenState extends State<PlaceScreen> {
  _Spot? _spot;
  Future<PlaceReport?>? _report;
  Future<List<_SatSample>>? _sat;
  Future<List<(CaseSummary, CaseRegion)>>? _mirrors;
  String? _status;
  bool _powerFailed = false;

  void _select(_Spot s) {
    final app = AppScope.read(context);
    setState(() {
      _spot = s;
      _status = null;
      _powerFailed = false;
      _report = _loadReport(app, s);
      _sat = _loadSatellite(app, s);
      _mirrors = _findMirrors(app, s);
    });
  }

  Future<PlaceReport?> _loadReport(AppState app, _Spot s) async {
    final cat = app.catalog!;
    PlaceInfo? best;
    var bestD = 1e9;
    for (final p in cat.places) {
      final d = math.sqrt(math.pow(p.lat - s.lat, 2) + math.pow(p.lon - s.lon, 2));
      if (d < bestD) {
        bestD = d;
        best = p;
      }
    }
    if (best != null && bestD < 0.3) {
      try {
        return await app.data.place(best.file);
      } catch (_) {}
    }
    try {
      return await app.power.analyse(s.lat, s.lon, name: s.name, nameHi: s.nameHi);
    } catch (_) {
      if (mounted) setState(() => _powerFailed = true);
      return null;
    }
  }

  Future<List<_SatSample>> _loadSatellite(AppState app, _Spot s) async {
    final out = <_SatSample>[];
    for (final ds in app.catalog!.layerDatasets) {
      final ref = ds.layers.firstWhere((l) => l.season == 'ANN', orElse: () => ds.layers.first);
      try {
        final meta = await app.data.layerMeta(ref.path);
        final cells = await app.data.layerCells(ref.path);
        final cell = cells.cell(meta, s.lat, s.lon);
        if (cell != null) out.add(_SatSample(ds, meta, cell));
      } catch (_) {}
    }
    return out;
  }

  Future<List<(CaseSummary, CaseRegion)>> _findMirrors(AppState app, _Spot s) async {
    final out = <(CaseSummary, CaseRegion)>[];
    for (final cs in app.catalog!.cases) {
      try {
        final c = await app.data.caseFile(cs.file);
        for (final r in c.regions) {
          if (r.cells.isNotEmpty && r.contains(s.lat, s.lon)) out.add((cs, r));
        }
      } catch (_) {}
    }
    return out;
  }

  Future<void> _gps() async {
    final app = AppScope.read(context);
    setState(() => _status = '…');
    try {
      final (lat, lon) = await app.device.currentLocation();
      if (!mounted) return;
      _select(_Spot(lat, lon, 'My location', 'मेरी लोकेशन'));
    } on LocationFailure catch (e) {
      if (mounted) setState(() => _status = tr(app.lang, e.key));
    } catch (e) {
      if (mounted) setState(() => _status = '$e');
    }
  }

  _Spot? _parseLatLon(String s) {
    final m = RegExp(r'^\s*(-?\d+(?:\.\d+)?)\s*[, ]\s*(-?\d+(?:\.\d+)?)\s*$').firstMatch(s);
    if (m == null) return null;
    final lat = double.parse(m.group(1)!), lon = double.parse(m.group(2)!);
    if (lat.abs() > 90 || lon.abs() > 180) return null;
    return _Spot(lat, lon, '${lat.toStringAsFixed(2)}, ${lon.toStringAsFixed(2)}');
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final lang = app.lang;
    final world = app.world;
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: ListView(padding: const EdgeInsets.fromLTRB(14, 10, 14, 40), children: [
            Row(children: [
              Expanded(child: Text(context.t('place_title'), style: Theme.of(context).textTheme.headlineSmall)),
              const HeaderActions(),
            ]),
            const SizedBox(height: 4),
            Text(context.t('place_intro')),
            const SizedBox(height: 12),
            Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
              FilledButton.icon(onPressed: _gps, icon: const Icon(Icons.gps_fixed), label: Text(context.t('use_gps'))),
              SizedBox(
                width: math.min(340.0, MediaQuery.sizeOf(context).width - 28),
                child: Autocomplete<City>(
                  optionsBuilder: (v) {
                    final q = v.text.trim().toLowerCase();
                    if (q.length < 2 || world == null) return const Iterable<City>.empty();
                    return world.cities.where((c) => c.name.toLowerCase().startsWith(q)).take(8);
                  },
                  displayStringForOption: (c) => '${c.name}, ${c.country}',
                  onSelected: (c) => _select(_Spot(c.lat, c.lon, c.name)),
                  fieldViewBuilder: (context, controller, focus, submit) => TextField(
                    controller: controller,
                    focusNode: focus,
                    decoration: InputDecoration(
                      isDense: true,
                      prefixIcon: const Icon(Icons.search),
                      hintText: context.t('search_city'),
                      border: const OutlineInputBorder(),
                    ),
                    onSubmitted: (s) {
                      final p = _parseLatLon(s);
                      if (p != null) {
                        _select(p);
                      } else {
                        submit();
                      }
                    },
                  ),
                ),
              ),
            ]),
            if (_status != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_status!, style: TextStyle(color: context.k.likely))),
            const SizedBox(height: 10),
            Text(context.t('tap_map'), style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            WorldMap(
              markers: [if (_spot != null) MapMarker(_spot!.lat, _spot!.lon, color: context.k.string)],
              onTap: (lat, lon) => _select(_Spot(lat, lon, '${lat.toStringAsFixed(2)}, ${lon.toStringAsFixed(2)}')),
            ),
            if (app.catalog!.places.isNotEmpty) ...[
              SectionTitle(context.t('showcase'), icon: Icons.star_outline),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final p in app.catalog!.places)
                  ActionChip(label: Text(p.label(lang)), onPressed: () => _select(_Spot(p.lat, p.lon, p.name, p.nameHi))),
              ]),
            ],
            if (_spot != null) ..._results(context),
          ]),
        ),
      ),
    );
  }

  List<Widget> _results(BuildContext context) {
    final lang = context.lang;
    final s = _spot!;
    return [
      const Divider(),
      Text(pick(lang, s.name, s.nameHi), style: Theme.of(context).textTheme.headlineSmall),
      Text('${s.lat.toStringAsFixed(2)}°, ${s.lon.toStringAsFixed(2)}°', style: Theme.of(context).textTheme.bodySmall),
      FutureBuilder<List<(CaseSummary, CaseRegion)>>(
        future: _mirrors,
        builder: (context, snap) {
          final list = snap.data ?? const [];
          if (list.isEmpty) return const SizedBox.shrink();
          return Column(children: [
            for (final (cs, r) in list)
              Card(
                color: context.k.string.withValues(alpha: 0.15),
                margin: const EdgeInsets.only(top: 10),
                child: ListTile(
                  leading: Icon(Icons.link, color: context.k.string),
                  title: Text(context.t('mirror_link')),
                  subtitle: Text('${cs.name(lang)} · ${r.label(lang)} (${r.sign >= 0 ? context.t('rising') : context.t('falling')})'),
                  trailing: TextButton(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CaseDetailScreen(summary: cs))),
                    child: Text(context.t('open_case')),
                  ),
                ),
              ),
          ]);
        },
      ),
      FutureBuilder<PlaceReport?>(
        future: _report,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(children: [
                const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 12),
                Expanded(child: Text(context.t('fetching_power'))),
              ]),
            );
          }
          final r = snap.data;
          if (r == null) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(_powerFailed ? context.t('power_failed') : context.t('no_data_here'), style: TextStyle(color: context.k.likely)),
            );
          }
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(height: 8),
            Text('${r.source}${r.live ? '' : ' · ${r.fetchedAt.split('T').first}'}', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            LayoutBuilder(builder: (context, cons) {
              final cols = cons.maxWidth > 700 ? 2 : 1;
              final w = (cons.maxWidth - (cols - 1) * 12) / cols;
              return Wrap(spacing: 12, runSpacing: 12, children: [
                for (final v in r.variables) SizedBox(width: w, child: _VariableCard(v: v)),
              ]);
            }),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => AppScope.read(context).device.shareWhatsApp(_shareText(r, lang)),
              icon: const Icon(Icons.share),
              label: Text(context.t('share_whatsapp')),
            ),
          ]);
        },
      ),
      SectionTitle(context.t('from_satellites'), icon: Icons.satellite_alt),
      FutureBuilder<List<_SatSample>>(
        future: _sat,
        builder: (context, snap) {
          if (!snap.hasData) return const LinearProgressIndicator();
          if (snap.data!.isEmpty) return Text(context.t('no_data_here'));
          return Column(children: [for (final sm in snap.data!) _SatTile(sample: sm)]);
        },
      ),
    ];
  }

  String _shareText(PlaceReport r, String lang) {
    final lines = <String>['📍 ${r.label(lang)} (${r.lat.toStringAsFixed(2)}, ${r.lon.toStringAsFixed(2)})'];
    for (final v in r.variables) {
      lines.add('• ${v.name(lang)}: ${fmtSigned(v.trend.slopeDec)} ${v.units}/${lang == 'hi' ? 'दशक' : 'decade'} – ${verdictText(lang, v.trend.verdict)}');
    }
    lines.add('— Kuch Toh Gadbad Hai · NASA POWER data · NASA Space Apps 2026');
    return lines.join('\n');
  }
}

class _VariableCard extends StatelessWidget {
  const _VariableCard({required this.v});
  final PlaceVariable v;
  @override
  Widget build(BuildContext context) {
    final lang = context.lang;
    final def = kPowerDefs[v.key];
    String tn(List<double?> x) => x.length < 3 || x[2] == null ? '–' : '${x[0]?.round()}-${x[1]?.round()}: ${fmtNum(x[2])} ${v.units}';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (def != null) Padding(padding: const EdgeInsets.only(bottom: 4, left: 2), child: Text(tx(context, def.$1, def.$2), style: TextStyle(color: context.k.muted, fontSize: 12.5))),
      Padding(padding: const EdgeInsets.only(bottom: 4, left: 2), child: Text('${context.t('then_now')}: ${tn(v.early)}  →  ${tn(v.late)}', style: const TextStyle(fontSize: 12.5))),
      TrendReport(
        series: v.series,
        title: v.name(lang),
        unit: v.units,
        sourceNote: 'NASA POWER (MERRA-2 / CERES), power.larc.nasa.gov',
        sourceUrl: 'https://power.larc.nasa.gov/data-access-viewer/',
      ),
    ]);
  }
}

class _SatTile extends StatefulWidget {
  const _SatTile({required this.sample});
  final _SatSample sample;
  @override
  State<_SatTile> createState() => _SatTileState();
}

class _SatTileState extends State<_SatTile> {
  Future<Series?>? _series;
  @override
  Widget build(BuildContext context) {
    final lang = context.lang;
    final sm = widget.sample;
    final code = kVerdictCodes[sm.cell.verdictCode] ?? 'insufficient';
    final s = sm.cell['s'];
    return Card(
      color: context.k.card,
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(children: [
        ListTile(
          title: Text(sm.ds.name(lang)),
          subtitle: Text('${fmtSigned(s)} ${sm.meta.units(lang)} · p ${fmtP(sm.cell['p'])} · q ${fmtP(sm.cell['q'])}'),
          trailing: VerdictChip(code, dense: true),
          onTap: () => setState(() => _series ??= AppScope.read(context).data.cellSeries(sm.meta, sm.cell.i, sm.cell.j)),
        ),
        if (_series != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: FutureBuilder<Series?>(
              future: _series,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) return const LinearProgressIndicator();
                final ser = snap.data;
                if (ser == null) return Text(context.t('no_data_here'));
                return TrendChart(series: ser, height: 130, color: (s ?? 0) >= 0 ? context.k.rising : context.k.falling, emergedLabel: context.t('emerged_in'), breakLabel: context.t('break_in'));
              },
            ),
          ),
      ]),
    );
  }
}
