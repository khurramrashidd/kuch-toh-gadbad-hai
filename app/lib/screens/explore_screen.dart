import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../knowledge.dart';
import '../l10n/strings.dart';
import '../models/models.dart';
import '../services/place_name_service.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/globe.dart';
import '../widgets/trend_report.dart';
import '../widgets/world_map.dart';

/// Explore: flat map (default) or 3D globe, filters, tap a cell, or box a region.
class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});
  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  String? _dsId, _season;
  String _sphere = 'all';
  Future<(LayerMeta, LayerCells)>? _layer;
  CellInfo? _cell;
  Future<Series?>? _cellSeries;
  bool _stipple = true, _globe = false, _boxMode = false, _showFilters = false;
  int _direction = 0, _minVerdict = 0;
  (double, double)? _corner; // first corner while boxing a region
  List<double>? _bbox; // west, south, east, north
  String? _regionName;
  Future<(Series, int)?>? _regionSeries;
  List<double>? _pendingBox;
  final PlaceNameService _places = PlaceNameService();
  String? _placeLabel;
  Timer? _hoverTimer;
  int _mapPointers = 0; // fingers on the map: page scrolling is paused so pinch and drag reach the map

  void _lookup(double lat, double lon, {bool now = false}) {
    _hoverTimer?.cancel();
    final lang = AppScope.read(context).lang;
    _hoverTimer = Timer(Duration(milliseconds: now ? 0 : 350), () async {
      final name = await _places.name(lat, lon, lang: lang);
      if (mounted && name != _placeLabel) setState(() => _placeLabel = name);
    });
  }

  @override
  void dispose() {
    _hoverTimer?.cancel();
    super.dispose();
  }

  (double, double)? _me; // "zoom to my location"
  List<double>? _meBox, _meCentre;

  Future<void> _goHere() async {
    final app = AppScope.read(context);
    final ll = app.here ?? await app.locate();
    if (!mounted) return;
    if (ll == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tx(
              context,
              'Location is off or not allowed. Turn it on and try again.',
              'लोकेशन बंद है या अनुमति नहीं। चालू करके फिर कोशिश करें।',
            ),
          ),
        ),
      );
      return;
    }
    setState(() {
      _me = ll;
      _meBox = [ll.$2 - 9, ll.$1 - 6, ll.$2 + 9, ll.$1 + 6];
      _meCentre = [ll.$1, ll.$2];
      _bbox = null;
      _regionSeries = null;
    });
  }

  String? _pendingName;

  void _choose(
    DatasetInfo ds,
    String season, {
    List<double>? bbox,
    String? regionName,
  }) {
    final app = AppScope.read(context);
    final ref = ds.layers.firstWhere(
      (l) => l.season == season,
      orElse: () => ds.layers.first,
    );
    setState(() {
      _dsId = ds.id;
      _season = ref.season;
      _cell = null;
      _cellSeries = null;
      _pendingBox =
          bbox ?? _bbox; // keep the chosen region when the variable changes
      _pendingName = bbox != null ? regionName : _regionName;
      _bbox = null;
      _regionSeries = null;
      _layer = () async {
        final meta = await app.data.layerMeta(ref.path);
        final cells = await app.data.layerCells(ref.path);
        return (meta, cells);
      }();
    });
    _layer!
        .then((v) {
          if (!mounted || _pendingBox == null) return;
          final b = _pendingBox!, n = _pendingName;
          _pendingBox = null;
          _setRegion(v.$1, v.$2, b, n);
        })
        .catchError((_) {});
  }

  void _setRegion(
    LayerMeta meta,
    LayerCells cells,
    List<double> bbox,
    String? name,
  ) {
    final app = AppScope.read(context);
    setState(() {
      _bbox = bbox;
      _regionName = name;
      _cell = null;
      _cellSeries = null;
      _corner = null;
      _boxMode = false;
      _regionSeries = app.data.regionSeries(meta, cells, bbox);
    });
  }

  void _tap(LayerMeta meta, LayerCells cells, double lat, double lon) {
    final app = AppScope.read(context);
    _lookup(lat, lon, now: true);
    if (_boxMode) {
      final c = _corner;
      if (c == null) {
        setState(() => _corner = (lat, lon));
        return;
      }
      final s = math.min(c.$1, lat), n = math.max(c.$1, lat);
      var w = math.min(c.$2, lon), e = math.max(c.$2, lon);
      if (e - w > 180) {
        final t = w;
        w = e;
        e = t; // crosses the date line
      }
      if (n - s < meta.dlat || (e - w).abs() < meta.dlon) {
        setState(() => _corner = null);
        return;
      }
      _setRegion(meta, cells, [w, s, e, n], null);
      return;
    }
    final c = cells.cell(meta, lat, lon);
    setState(() {
      _cell = c;
      _bbox = null;
      _regionSeries = null;
      _cellSeries = c == null ? null : app.data.cellSeries(meta, c.i, c.j);
    });
  }

  /// Strongest proven rising / falling spots, kept apart from each other.
  List<MapMarker> _hotspots(
    BuildContext context,
    LayerMeta meta,
    LayerCells cells,
  ) {
    final s = cells.fields['s'], q = cells.fields['q'];
    if (s == null || q == null) return const [];
    final cand = <(double, int)>[];
    void add(int grid, int k) {
      if (k >= s.length || k >= q.length) return;
      final sv = s[k], qv = q[k];
      if (sv == null || qv == null || qv >= 0.10) return;
      final lat = meta.lat0 + (grid ~/ meta.nlon) * meta.dlat;
      if (lat.abs() > 78) return;
      cand.add((sv, grid));
    }

    final pos = cells.position;
    if (pos != null) {
      pos.forEach(add);
    } else {
      for (var g = 0; g < meta.nlat * meta.nlon; g++) {
        add(g, g);
      }
    }
    final out = <MapMarker>[];
    for (final sign in const [1, -1]) {
      final list = cand.where((c) => c.$1 * sign > 0).toList()
        ..sort((a, b) => (b.$1 * sign).compareTo(a.$1 * sign));
      final picked = <(double, double)>[];
      for (final c in list) {
        final lat = meta.lat0 + (c.$2 ~/ meta.nlon) * meta.dlat;
        var lon = meta.lon0 + (c.$2 % meta.nlon) * meta.dlon;
        if (lon > 180) lon -= 360;
        if (picked.any(
          (p) =>
              (p.$1 - lat).abs() < 22 &&
              (((p.$2 - lon).abs() + 180) % 360 - 180).abs() < 30,
        ))
          continue;
        picked.add((lat, lon));
        out.add(
          MapMarker(
            lat,
            lon,
            color: sign > 0 ? context.k.rising : context.k.falling,
            label: '${sign > 0 ? '▲' : '▼'} ${fmtSigned(c.$1)}',
          ),
        );
        if (picked.length >= 3) break;
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final lang = app.lang;
    final k = context.k;
    final all = app.catalog!.layerDatasets;
    if (all.isEmpty) return Center(child: Text(context.t('no_cases')));

    // a request from the guided investigation
    final req = app.exploreRequest;
    if (req != null) {
      app.exploreRequest = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final d = all.firstWhere(
          (x) => x.id == req.dataset,
          orElse: () => all.first,
        );
        _choose(
          d,
          req.season ?? d.layers.first.season,
          bbox: req.bbox,
          regionName: req.regionName,
        );
      });
    } else if (_dsId == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _dsId == null)
          _choose(all.first, all.first.layers.first.season);
      });
    }
    final spheres = <String>{for (final d in all) d.sphere}.toList()..sort();
    final dss = _sphere == 'all'
        ? all
        : all.where((d) => d.sphere == _sphere).toList();
    final ds = all.firstWhere((d) => d.id == _dsId, orElse: () => all.first);
    final filter = CellFilter(direction: _direction, minVerdict: _minVerdict);
    final phone = MediaQuery.sizeOf(context).width < 700;
    final showFilters = !phone || _showFilters;
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    String sphereName(String s) => switch (s) {
      'atmosphere' => tx(context, 'Air', 'हवा'),
      'hydrosphere' => tx(context, 'Water', 'पानी'),
      'cryosphere' => tx(context, 'Ice', 'बर्फ़'),
      'biosphere' => tx(context, 'Life', 'जीवन'),
      'land' => tx(context, 'Land', 'ज़मीन'),
      'anthroposphere' => tx(context, 'People', 'इंसान'),
      'ocean' => tx(context, 'Ocean', 'समुद्र'),
      _ => s,
    };

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: wide ? 1500 : 1100),
          child: ListView(
            physics: _mapPointers > 0 ? const NeverScrollableScrollPhysics() : null,
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 40),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      context.t('explore_title'),
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  const HeaderActions(),
                ],
              ),
              const SizedBox(height: 6),
              if (phone)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () =>
                        setState(() => _showFilters = !_showFilters),
                    icon: Icon(
                      _showFilters ? Icons.expand_less : Icons.tune,
                      size: 18,
                    ),
                    label: Text(
                      '${tx(context, 'Filters', 'फ़िल्टर')}${filter.active || _sphere != 'all' ? ' •' : ''}',
                    ),
                  ),
                ),
              // sphere filter
              if (showFilters)
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    ChoiceChip(
                      label: Text(tx(context, 'All', 'सब')),
                      selected: _sphere == 'all',
                      onSelected: (_) => setState(() => _sphere = 'all'),
                    ),
                    for (final s in spheres)
                      ChoiceChip(
                        avatar: CircleAvatar(radius: 6, backgroundColor: k.sphere(s)),
                        showCheckmark: false,
                        selectedColor: k.sphere(s).withValues(alpha: 0.25),
                        side: BorderSide(color: k.sphere(s).withValues(alpha: _sphere == s ? 0.9 : 0.4)),
                        label: Text(sphereName(s)),
                        selected: _sphere == s,
                        onSelected: (_) => setState(() => _sphere = s),
                      ),
                  ],
                ),
              const SizedBox(height: 6),
              // variable
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final d in dss)
                    ChoiceChip(
                      label: Text(d.shortName(lang)),
                      selected: d.id == ds.id,
                      onSelected: (_) => _choose(
                        d,
                        d.layers.any((l) => l.season == _season)
                            ? _season!
                            : d.layers.first.season,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              // season + view toggles
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final l in ds.layers)
                    ChoiceChip(
                      avatar: const Icon(Icons.calendar_month, size: 16),
                      label: Text(app.catalog!.seasonLabel(l.season, lang)),
                      selected: l.season == _season,
                      onSelected: (_) => _choose(ds, l.season),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              // verdict / direction filters
              if (showFilters)
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Icon(Icons.filter_alt, size: 18, color: k.muted),
                    ChoiceChip(
                      label: Text(tx(context, 'Rising', 'बढ़ता')),
                      selected: _direction == 1,
                      onSelected: (v) => setState(() => _direction = v ? 1 : 0),
                    ),
                    ChoiceChip(
                      label: Text(tx(context, 'Falling', 'घटता')),
                      selected: _direction == -1,
                      onSelected: (v) =>
                          setState(() => _direction = v ? -1 : 0),
                    ),
                    ChoiceChip(
                      label: Text(
                        tx(context, 'Likely or better', 'संभव या बेहतर'),
                      ),
                      selected: _minVerdict == 3,
                      onSelected: (v) =>
                          setState(() => _minVerdict = v ? 3 : 0),
                    ),
                    ChoiceChip(
                      label: Text(
                        tx(context, 'Confirmed only', 'सिर्फ़ पक्का'),
                      ),
                      selected: _minVerdict == 4,
                      onSelected: (v) =>
                          setState(() => _minVerdict = v ? 4 : 0),
                    ),
                    if (!_globe && !filter.active)
                      FilterChip(
                        label: Text(context.t('sig_only')),
                        selected: _stipple,
                        onSelected: (v) => setState(() => _stipple = v),
                      ),
                  ],
                ),
              const SizedBox(height: 8),
              Text(
                ds.name(lang),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              if (ds.definition(lang).isNotEmpty)
                Text(ds.definition(lang), style: const TextStyle(height: 1.3)),
              Text(ds.mission, style: Theme.of(context).textTheme.bodySmall),
              if (ds.qualityNote.isNotEmpty)
                Text(
                  ds.qualityNote,
                  style: TextStyle(color: k.likely, fontSize: 12),
                ),
              const SizedBox(height: 8),
              FutureBuilder<(LayerMeta, LayerCells)>(
                future: _layer,
                builder: (context, snap) {
                  if (snap.hasError) return Text('${snap.error}');
                  if (!snap.hasData)
                    return const AspectRatio(
                      aspectRatio: 2,
                      child: Center(child: CircularProgressIndicator()),
                    );
                  final (meta, cells) = snap.data!;
                  final f = meta.field;
                  final b = _bbox;
                  final markers = <MapMarker>[
                    ..._hotspots(context, meta, cells),
                    if (_cell != null)
                      MapMarker(_cell!.lat, _cell!.lon, color: k.string),
                    if (_me != null)
                      MapMarker(
                        _me!.$1,
                        _me!.$2,
                        color: k.accent,
                        label: tx(context, 'You', 'आप'),
                      ),
                    if (_corner != null)
                      MapMarker(
                        _corner!.$1,
                        _corner!.$2,
                        color: k.accent,
                        label: tx(context, 'corner 1', 'कोना 1'),
                      ),
                  ];
                  final regions = <MapRegion>[
                    if (b != null)
                      MapRegion(
                        color: k.accent,
                        bbox: b,
                        pin: [
                          (b[1] + b[3]) / 2,
                          b[0] <= b[2] ? (b[0] + b[2]) / 2 : b[0],
                        ],
                        label: _regionName,
                      ),
                  ];
                  final mapPart = <Widget>[
                      Container(
                        padding: const EdgeInsets.all(10),
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: k.card,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: '${(f.sigAreaFrac * 100).round()}% ',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: k.accent,
                                  fontSize: 16,
                                ),
                              ),
                              TextSpan(
                                text:
                                    '${context.t('field_sig')} (${meta.period.isNotEmpty ? '${meta.period.first}-${meta.period.last}' : ''}): ',
                              ),
                              TextSpan(
                                text:
                                    '${(f.sigUpFrac * 100).round()}% ${context.t('up')}',
                                style: TextStyle(
                                  color: k.rising,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const TextSpan(text: ' · '),
                              TextSpan(
                                text:
                                    '${(f.sigDownFrac * 100).round()}% ${context.t('down')}',
                                style: TextStyle(
                                  color: k.falling,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // view + region tools
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          SegmentedButton<bool>(
                            segments: [
                              ButtonSegment(
                                value: false,
                                icon: const Icon(Icons.map_outlined, size: 18),
                                label: Text(
                                  tx(context, 'Flat map', 'सपाट नक़्शा'),
                                ),
                              ),
                              ButtonSegment(
                                value: true,
                                icon: const Icon(Icons.public, size: 18),
                                label: Text(
                                  tx(context, '3D globe', '3D ग्लोब'),
                                ),
                              ),
                            ],
                            selected: {_globe},
                            showSelectedIcon: false,
                            onSelectionChanged: (v) =>
                                setState(() => _globe = v.first),
                          ),
                          FilterChip(
                            avatar: const Icon(Icons.crop_free, size: 16),
                            label: Text(
                              _boxMode
                                  ? (_corner == null
                                        ? tx(
                                            context,
                                            'Tap first corner',
                                            'पहला कोना दबाएँ',
                                          )
                                        : tx(
                                            context,
                                            'Tap opposite corner',
                                            'सामने का कोना दबाएँ',
                                          ))
                                  : tx(
                                      context,
                                      'Draw my own region',
                                      'अपना क्षेत्र बनाएँ',
                                    ),
                            ),
                            selected: _boxMode,
                            onSelected: (v) => setState(() {
                              _boxMode = v;
                              _corner = null;
                            }),
                          ),
                          PopupMenuButton<Preset>(
                            tooltip: tx(
                              context,
                              'Jump to a region',
                              'किसी क्षेत्र पर जाएँ',
                            ),
                            onSelected: (p) => _setRegion(
                              meta,
                              cells,
                              p.bbox,
                              lang == 'hi' ? p.hi : p.en,
                            ),
                            itemBuilder: (_) => [
                              for (final p in kPresets)
                                PopupMenuItem(
                                  value: p,
                                  child: Text(
                                    '${lang == 'hi' ? p.hi : p.en} · ${lang == 'hi' ? p.kindHi : p.kind}',
                                  ),
                                ),
                            ],
                            child: Chip(
                              avatar: const Icon(
                                Icons.place_outlined,
                                size: 16,
                              ),
                              label: Text(
                                tx(context, 'Region presets', 'तैयार क्षेत्र'),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(children: [
                          Icon(Icons.place, size: 18, color: k.accent),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _placeLabel ?? tx(context, 'Move over the map or tap it to see the place name', 'जगह का नाम देखने के लिए नक़्शे पर जाएँ या दबाएँ'),
                              style: TextStyle(fontWeight: _placeLabel == null ? FontWeight.w500 : FontWeight.w800, color: _placeLabel == null ? k.muted : k.text),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ]),
                      ),
                      Listener(
                        onPointerDown: (_) => setState(() => _mapPointers++),
                        onPointerUp: (_) => setState(() => _mapPointers = math.max(0, _mapPointers - 1)),
                        onPointerCancel: (_) => setState(() => _mapPointers = math.max(0, _mapPointers - 1)),
                        child: _globe
                        ? GlobeView(
                          meta: meta,
                          cells: cells,
                          filter: filter,
                          markers: markers,
                          regions: regions,
                          focus: b == null
                              ? _meCentre
                              : [
                                  (b[1] + b[3]) / 2,
                                  b[0] <= b[2] ? (b[0] + b[2]) / 2 : b[0],
                                ],
                          focusZoom: b == null && _meCentre != null
                              ? 3.6
                              : null,
                          onLocate: _goHere,
                          onTap: (lat, lon) => _tap(meta, cells, lat, lon),
                          onHover: _lookup,
                        )
                        : WorldMap(
                          layerUrl: app.data.url('${meta.path}/trend.png'),
                          stippleUrl: _stipple && !filter.active
                              ? app.data.url('${meta.path}/sig.png')
                              : null,
                          layerBounds: meta.bounds,
                          layerPainter: filter.active
                              ? FlatCellsPainter(meta, cells, filter)
                              : null,
                          markers: markers,
                          regions: regions,
                          focus: b != null ? (b[0] <= b[2] ? b : null) : _meBox,
                          onLocate: _goHere,
                          onTap: (lat, lon) => _tap(meta, cells, lat, lon),
                          onHover: _lookup,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _Legend(meta: meta),
                      const SizedBox(height: 4),
                      Text(
                        _globe
                            ? tx(
                                context,
                                'Drag to spin, pinch or scroll to zoom. Strong colour = proven change; pale = not proven. Pins mark the strongest proven spots.',
                                'घुमाने के लिए खींचें, ज़ूम के लिए चुटकी या स्क्रॉल। गहरा रंग = साबित बदलाव; हल्का = साबित नहीं। पिन सबसे तेज़ साबित जगहें दिखाते हैं।',
                              )
                            : context.t('dots_mean'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ];
                  final Widget resultPart = b != null
                      ? FutureBuilder<(Series, int)?>(
                          future: _regionSeries,
                          builder: (context, rs) {
                            if (rs.connectionState != ConnectionState.done)
                              return const LinearProgressIndicator();
                            final r = rs.data;
                            if (r == null) {
                              return Text(
                                tx(
                                  context,
                                  'No data in this region for this variable (or the region is too large). Try a smaller box.',
                                  'इस क्षेत्र में इस चीज़ का डेटा नहीं (या क्षेत्र बहुत बड़ा है)। छोटा डिब्बा आज़माएँ।',
                                ),
                              );
                            }
                            final name =
                                _regionName ??
                                '${b[1].toStringAsFixed(1)}° to ${b[3].toStringAsFixed(1)}°, ${b[0].toStringAsFixed(1)}° to ${b[2].toStringAsFixed(1)}°';
                            return TrendReport(
                              series: r.$1,
                              title: '${ds.shortName(lang)} · $name',
                              unit: ds.units,
                              sourceNote:
                                  '${ds.title}; ${tx(context, 'area-weighted mean of', 'क्षेत्र-भारित औसत,')} ${r.$2} ${tx(context, 'map cells, anomalies vs 1991-2020', 'खाने, 1991-2020 की तुलना में')}',
                              sourceUrl: ds.urlInfo,
                            );
                          },
                        )
                      : _cell == null
                      ? Text(
                          tx(
                            context,
                            'Tap the map for one spot, or use "Draw my own region" / "Region presets" for an area.',
                            'एक जगह के लिए नक़्शा दबाएँ, या क्षेत्र के लिए "अपना क्षेत्र बनाएँ" / "तैयार क्षेत्र" चुनें।',
                          ),
                          style: TextStyle(color: k.accent),
                        )
                      : _readout(context, meta, ds);
                  // tablet / desktop: map on the left, verdict beside it; phone: stacked
                  if (wide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 11, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: mapPart)),
                        const SizedBox(width: 16),
                        Expanded(flex: 9, child: resultPart),
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [...mapPart, const SizedBox(height: 10), resultPart],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _readout(BuildContext context, LayerMeta meta, DatasetInfo ds) {
    final c = _cell!;
    final lang = context.lang;
    final code = kVerdictCodes[c.verdictCode] ?? 'insufficient';
    final s = c['s'];
    final col = (s ?? 0) >= 0 ? context.k.rising : context.k.falling;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: context.k.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: col.withValues(alpha: 0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${context.t('value_here')} · ${c.lat.toStringAsFixed(1)}°, ${c.lon.toStringAsFixed(1)}°',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  VerdictChip(code, dense: true),
                ],
              ),
              Text(
                '${fmtSigned(s)} ${meta.units(lang)}',
                style: TextStyle(
                  color: col,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                tx(
                  context,
                  'Map verdict: tested together with every other cell, so thousands of cells cannot fake a result (false-discovery control).',
                  'नक़्शे का फ़ैसला: बाक़ी सभी खानों के साथ परखा गया, ताकि हज़ारों खाने मिलकर झूठा नतीजा न बना सकें।',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (context.app.expert)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      StatTile(
                        label: context.t('significance'),
                        value: fmtP(c['p']),
                      ),
                      StatTile(
                        label: context.t('q_value'),
                        value: fmtP(c['q']),
                      ),
                      StatTile(
                        label: context.t('signal_noise'),
                        value: '${fmtNum(c['snr'], digits: 1)}×',
                      ),
                      if (c['b'] != null)
                        StatTile(
                          label: context.t('normal_level'),
                          value: fmtNum(c['b']),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        FutureBuilder<Series?>(
          future: _cellSeries,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done)
              return const LinearProgressIndicator();
            final ser = snap.data;
            if (ser == null) return const SizedBox.shrink();
            return TrendReport(
              series: ser,
              title:
                  '${ds.shortName(lang)} · ${c.lat.toStringAsFixed(1)}°, ${c.lon.toStringAsFixed(1)}°',
              unit: ds.units,
              sourceNote:
                  '${ds.title}; ${tx(context, 'one map cell, anomalies vs 1991-2020', 'एक खाना, 1991-2020 की तुलना में')}',
              sourceUrl: ds.urlInfo,
            );
          },
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.meta});
  final LayerMeta meta;
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 12,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            gradient: LinearGradient(colors: meta.palette),
          ),
        ),
        const SizedBox(height: 3),
        Row(
          children: [
            Text(fmtSigned(-meta.vmax), style: const TextStyle(fontSize: 11)),
            Expanded(
              child: Center(
                child: Text(
                  '0  ·  ${meta.units(context.lang)}',
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ),
            Text(fmtSigned(meta.vmax), style: const TextStyle(fontSize: 11)),
          ],
        ),
      ],
    );
  }
}
