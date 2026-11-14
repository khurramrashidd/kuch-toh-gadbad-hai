import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models/models.dart';
import '../theme.dart';
import 'world_map.dart';

/// Which map cells are shown (verdict / direction filters).
class CellFilter {
  const CellFilter({this.direction = 0, this.minVerdict = 0});
  final int direction; // 0 all, 1 rising only, -1 falling only
  final int minVerdict; // 0 all, 3 likely+confirmed, 4 confirmed only
  bool get active => direction != 0 || minVerdict != 0;

  bool pass(double? s, double? v) {
    if (s == null) return false;
    if (direction > 0 && s <= 0) return false;
    if (direction < 0 && s >= 0) return false;
    if (minVerdict > 0) {
      final code = (v ?? 1).round();
      if (code == 5 || code < minVerdict) return false;
    }
    return true;
  }

  @override
  bool operator ==(Object other) => other is CellFilter && other.direction == direction && other.minVerdict == minVerdict;
  @override
  int get hashCode => Object.hash(direction, minVerdict);
}

class GeoLabel {
  const GeoLabel(this.en, this.hi, this.lat, this.lon, this.rank, {this.ocean = false});
  final String en, hi;
  final double lat, lon;
  final int rank; // 0 = always, 1 = zoom >= 1.6, 2 = zoom >= 2.6
  final bool ocean;
}

const kGeoLabels = <GeoLabel>[
  GeoLabel('Pacific Ocean', 'प्रशांत महासागर', 0, -150, 0, ocean: true),
  GeoLabel('Atlantic Ocean', 'अटलांटिक महासागर', 5, -32, 0, ocean: true),
  GeoLabel('Indian Ocean', 'हिंद महासागर', -22, 78, 0, ocean: true),
  GeoLabel('Arctic Ocean', 'आर्कटिक महासागर', 82, 0, 0, ocean: true),
  GeoLabel('Southern Ocean', 'दक्षिणी महासागर', -62, 20, 0, ocean: true),
  GeoLabel('Arabian Sea', 'अरब सागर', 15, 64, 1, ocean: true),
  GeoLabel('Bay of Bengal', 'बंगाल की खाड़ी', 14, 89, 1, ocean: true),
  GeoLabel('India', 'भारत', 22, 79, 0),
  GeoLabel('China', 'चीन', 35, 103, 0),
  GeoLabel('Russia', 'रूस', 62, 95, 0),
  GeoLabel('USA', 'अमेरिका', 39, -99, 0),
  GeoLabel('Canada', 'कनाडा', 58, -105, 0),
  GeoLabel('Brazil', 'ब्राज़ील', -10, -53, 0),
  GeoLabel('Australia', 'ऑस्ट्रेलिया', -25, 134, 0),
  GeoLabel('Antarctica', 'अंटार्कटिका', -80, 30, 0),
  GeoLabel('Greenland', 'ग्रीनलैंड', 73, -41, 0),
  GeoLabel('Sahara', 'सहारा', 23, 10, 0),
  GeoLabel('Pakistan', 'पाकिस्तान', 29.5, 69, 1),
  GeoLabel('Bangladesh', 'बांग्लादेश', 24, 90, 1),
  GeoLabel('Nepal', 'नेपाल', 28.3, 84, 2),
  GeoLabel('Sri Lanka', 'श्रीलंका', 7.8, 80.7, 2),
  GeoLabel('Afghanistan', 'अफ़ग़ानिस्तान', 34, 66, 1),
  GeoLabel('Iran', 'ईरान', 32, 54, 1),
  GeoLabel('Saudi Arabia', 'सऊदी अरब', 24, 45, 1),
  GeoLabel('Turkey', 'तुर्की', 39, 35, 1),
  GeoLabel('Kazakhstan', 'कज़ाख़स्तान', 48, 67, 1),
  GeoLabel('Mongolia', 'मंगोलिया', 46.5, 104, 1),
  GeoLabel('Japan', 'जापान', 36.5, 138, 1),
  GeoLabel('Indonesia', 'इंडोनेशिया', -2, 114, 1),
  GeoLabel('Myanmar', 'म्यांमार', 21, 96, 2),
  GeoLabel('Thailand', 'थाईलैंड', 15.5, 101, 2),
  GeoLabel('Vietnam', 'वियतनाम', 14.5, 108.5, 2),
  GeoLabel('Philippines', 'फ़िलीपींस', 12.5, 122.5, 2),
  GeoLabel('Egypt', 'मिस्र', 26.5, 30, 1),
  GeoLabel('Nigeria', 'नाइजीरिया', 9.5, 8, 1),
  GeoLabel('Ethiopia', 'इथियोपिया', 8.5, 39.5, 1),
  GeoLabel('DR Congo', 'कांगो', -2.5, 23.5, 1),
  GeoLabel('South Africa', 'दक्षिण अफ़्रीका', -30, 24.5, 1),
  GeoLabel('Kenya', 'केन्या', 0.5, 38, 2),
  GeoLabel('Sudan', 'सूडान', 15.5, 30, 2),
  GeoLabel('Algeria', 'अल्जीरिया', 28, 2.5, 2),
  GeoLabel('Angola', 'अंगोला', -12, 17.5, 2),
  GeoLabel('Senegal', 'सेनेगल', 14.5, -14.5, 2),
  GeoLabel('UK', 'ब्रिटेन', 54, -2, 1),
  GeoLabel('France', 'फ़्रांस', 46.5, 2.5, 1),
  GeoLabel('Spain', 'स्पेन', 40, -3.5, 1),
  GeoLabel('Germany', 'जर्मनी', 51, 10, 1),
  GeoLabel('Italy', 'इटली', 42.8, 12.5, 2),
  GeoLabel('Netherlands', 'नीदरलैंड', 52.3, 5.5, 2),
  GeoLabel('Ukraine', 'यूक्रेन', 49, 31.5, 2),
  GeoLabel('Scandinavia', 'स्कैंडिनेविया', 63, 15, 1),
  GeoLabel('Mexico', 'मेक्सिको', 23.5, -102, 1),
  GeoLabel('Argentina', 'अर्जेंटीना', -35, -65, 1),
  GeoLabel('Peru', 'पेरू', -9.5, -75, 2),
  GeoLabel('Colombia', 'कोलंबिया', 4, -73, 2),
  GeoLabel('Paraguay', 'पैराग्वे', -23.3, -58, 2),
  GeoLabel('Chile', 'चिली', -33, -71, 2),
  GeoLabel('Amazon', 'अमेज़न', -4, -62, 1),
  GeoLabel('Alaska', 'अलास्का', 64.5, -152, 1),
  GeoLabel('Siberia', 'साइबेरिया', 66, 125, 1),
  GeoLabel('Tibet', 'तिब्बत', 32.5, 88, 2),
  GeoLabel('New Zealand', 'न्यूज़ीलैंड', -42, 172.5, 1),
  GeoLabel('UAE', 'यूएई', 24, 54, 2),
  GeoLabel('Bahrain', 'बहरीन', 26.1, 50.5, 2),
  GeoLabel('Korea', 'कोरिया', 37, 127.8, 2),
];

/// Interactive orthographic globe: drag to spin, pinch / wheel / buttons to zoom, tap to pick a place.
class GlobeView extends StatefulWidget {
  const GlobeView({super.key, this.meta, this.cells, this.filter = const CellFilter(), this.markers = const [], this.regions = const [], this.redString = false, this.onTap, this.focus, this.height, this.onLocate, this.focusZoom});
  final VoidCallback? onLocate;
  final double? focusZoom;
  final LayerMeta? meta;
  final LayerCells? cells;
  final CellFilter filter;
  final List<MapMarker> markers;
  final List<MapRegion> regions;
  final bool redString;
  final void Function(double lat, double lon)? onTap;
  final List<double>? focus; // [lat, lon] to face
  final double? height;

  @override
  State<GlobeView> createState() => _GlobeViewState();
}

class _GlobeViewState extends State<GlobeView> {
  double _lat = 18, _lon = 78, _zoom = 1.0;
  double _startZoom = 1.0, _pinch0 = 0, _moved = 0;
  DateTime _downAt = DateTime.now();
  final Map<int, Offset> _pts = {};
  List<double>? _lastFocus;

  @override
  void initState() {
    super.initState();
    _applyFocus();
  }

  @override
  void didUpdateWidget(covariant GlobeView old) {
    super.didUpdateWidget(old);
    _applyFocus();
  }

  void _applyFocus() {
    final f = widget.focus;
    if (f != null && f.length == 2 && (_lastFocus == null || _lastFocus![0] != f[0] || _lastFocus![1] != f[1])) {
      _lastFocus = f;
      _lat = f[0].clamp(-85.0, 85.0);
      _lon = f[1];
      if (widget.focusZoom != null) _zoom = widget.focusZoom!.clamp(0.8, 9.0);
    }
  }

  void _setZoom(double z) => setState(() => _zoom = z.clamp(0.8, 9.0));

  /// Screen point -> (lat, lon) or null when outside the disc.
  (double, double)? _unproject(Offset p, Size size) {
    final r = math.min(size.width, size.height) / 2 * 0.94 * _zoom;
    final x = (p.dx - size.width / 2) / r, y = -(p.dy - size.height / 2) / r;
    final rho2 = x * x + y * y;
    if (rho2 > 1) return null;
    final z = math.sqrt(1 - rho2);
    final p0 = _lat * math.pi / 180, l0 = _lon * math.pi / 180;
    final lat = math.asin((z * math.sin(p0) + y * math.cos(p0)).clamp(-1.0, 1.0));
    final lon = l0 + math.atan2(x, z * math.cos(p0) - y * math.sin(p0));
    var d = lon * 180 / math.pi;
    d = ((d + 540) % 360) - 180;
    return (lat * 180 / math.pi, d);
  }

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final app = context.app;
    return LayoutBuilder(builder: (context, cons) {
      final w = cons.maxWidth;
      final h = widget.height ?? math.min(w, 560.0);
      final size = Size(w, h);
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          color: k.surface,
          width: w,
          height: h,
          child: Stack(children: [
            // Raw pointer handling: the globe wins every drag (a page scroll must not steal it).
            RawGestureDetector(
              behavior: HitTestBehavior.opaque,
              gestures: {
                EagerGestureRecognizer: GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(() => EagerGestureRecognizer(), (_) {}),
              },
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerSignal: (e) {
                  if (e is PointerScrollEvent) _setZoom(_zoom * (e.scrollDelta.dy < 0 ? 1.12 : 1 / 1.12));
                },
                onPointerDown: (e) {
                  _pts[e.pointer] = e.localPosition;
                  _moved = 0;
                  _downAt = DateTime.now();
                  if (_pts.length == 2) {
                    final v = _pts.values.toList();
                    _pinch0 = (v[0] - v[1]).distance;
                    _startZoom = _zoom;
                  }
                },
                onPointerMove: (e) {
                  final prev = _pts[e.pointer];
                  if (prev == null) return;
                  _pts[e.pointer] = e.localPosition;
                  final d = e.localPosition - prev;
                  _moved += d.distance;
                  setState(() {
                    if (_pts.length >= 2) {
                      final v = _pts.values.toList();
                      final dist = (v[0] - v[1]).distance;
                      if (_pinch0 > 10) _zoom = (_startZoom * dist / _pinch0).clamp(0.8, 9.0);
                    } else {
                      final r = math.min(size.width, size.height) / 2 * 0.94 * _zoom;
                      final deg = 180 / math.pi / r;
                      _lon = ((_lon - d.dx * deg + 540) % 360) - 180;
                      _lat = (_lat + d.dy * deg).clamp(-88.0, 88.0);
                    }
                  });
                },
                onPointerUp: (e) {
                  final single = _pts.length == 1;
                  _pts.remove(e.pointer);
                  if (single && _moved < 8 && DateTime.now().difference(_downAt).inMilliseconds < 500 && widget.onTap != null) {
                    final ll = _unproject(e.localPosition, size);
                    if (ll != null) widget.onTap!(ll.$1, ll.$2);
                  }
                },
                onPointerCancel: (e) => _pts.remove(e.pointer),
                child: CustomPaint(
                  size: size,
                  painter: _GlobePainter(
                    lat0: _lat,
                    lon0: _lon,
                    zoom: _zoom,
                    rings: app.world?.rings ?? const [],
                    cities: app.world?.cities ?? const [],
                    meta: widget.meta,
                    cells: widget.cells,
                    filter: widget.filter,
                    markers: widget.markers,
                    regions: widget.regions,
                    redString: widget.redString,
                    lang: app.lang,
                    p: k,
                  ),
                ),
              ),
            ),
            Positioned(
              right: 6,
              bottom: 6,
              child: Column(children: [
                _Btn(Icons.add, () => _setZoom(_zoom * 1.5)),
                const SizedBox(height: 4),
                _Btn(Icons.remove, () => _setZoom(_zoom / 1.5)),
                const SizedBox(height: 4),
                _Btn(Icons.public, () => setState(() {
                      _lat = 18;
                      _lon = 78;
                      _zoom = 1;
                    })),
                if (widget.onLocate != null) ...[const SizedBox(height: 4), _Btn(Icons.my_location, widget.onLocate!)],
              ]),
            ),
          ]),
        ),
      );
    });
  }
}

class _Btn extends StatelessWidget {
  const _Btn(this.icon, this.onTap);
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
        color: context.k.bg.withValues(alpha: 0.8),
        shape: const CircleBorder(),
        child: InkWell(customBorder: const CircleBorder(), onTap: onTap, child: Padding(padding: const EdgeInsets.all(6), child: Icon(icon, size: 18, color: context.k.text))),
      );
}

class _GlobePainter extends CustomPainter {
  _GlobePainter({required this.lat0, required this.lon0, required this.zoom, required this.rings, required this.cities, required this.meta, required this.cells, required this.filter, required this.markers, required this.regions, required this.redString, required this.lang, required this.p});
  final double lat0, lon0, zoom;
  final List<List<List<double>>> rings;
  final List<City> cities;
  final LayerMeta? meta;
  final LayerCells? cells;
  final CellFilter filter;
  final List<MapMarker> markers;
  final List<MapRegion> regions;
  final bool redString;
  final String lang;
  final Palette p;

  static const _d2r = math.pi / 180;
  late double _sp0, _cp0, _r;
  late Offset _c;

  /// Returns the screen point, or null when on the far side.
  Offset? _proj(double lat, double lon) {
    final ph = lat * _d2r, dl = (lon - lon0) * _d2r;
    final sp = math.sin(ph), cp = math.cos(ph), cdl = math.cos(dl);
    if (_sp0 * sp + _cp0 * cp * cdl < 0) return null;
    return Offset(_c.dx + _r * cp * math.sin(dl), _c.dy - _r * (_cp0 * sp - _sp0 * cp * cdl));
  }

  void _text(Canvas canvas, String s, Offset o, {Color? color, double size = 11, bool bold = false, bool italic = false, bool center = true, bool halo = true}) {
    final style = TextStyle(
        color: color ?? p.text,
        fontSize: size,
        fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
        fontStyle: italic ? FontStyle.italic : FontStyle.normal,
        shadows: halo ? [Shadow(color: p.bg, blurRadius: 3), Shadow(color: p.bg, blurRadius: 3)] : null);
    final tp = TextPainter(text: TextSpan(text: s, style: style), textDirection: TextDirection.ltr)..layout();
    tp.paint(canvas, center ? o - Offset(tp.width / 2, tp.height / 2) : o);
  }

  @override
  void paint(Canvas canvas, Size size) {
    _sp0 = math.sin(lat0 * _d2r);
    _cp0 = math.cos(lat0 * _d2r);
    _r = math.min(size.width, size.height) / 2 * 0.94 * zoom;
    _c = Offset(size.width / 2, size.height / 2);
    canvas.clipRect(Offset.zero & size);

    // soft halo + ocean disc
    canvas.drawCircle(_c, _r * 1.03, Paint()..color = p.grid.withValues(alpha: 0.35));
    canvas.drawCircle(_c, _r, Paint()..color = p.ocean);

    // land fill (rings broken where they leave the visible side)
    final land = Path();
    for (final ring in rings) {
      if (ring.length < 3) continue;
      var any = false, allVis = true;
      final pts = <Offset>[];
      for (final q in ring) {
        final o = _proj(q[1], q[0]);
        if (o == null) {
          allVis = false;
          // clamp far-side points onto the limb so partly visible continents still fill
          final ph = q[1] * _d2r, dl = (q[0] - lon0) * _d2r;
          final x = math.cos(ph) * math.sin(dl), y = _cp0 * math.sin(ph) - _sp0 * math.cos(ph) * math.cos(dl);
          final n = math.sqrt(x * x + y * y);
          pts.add(n == 0 ? _c : Offset(_c.dx + _r * x / n, _c.dy - _r * y / n));
        } else {
          any = true;
          pts.add(o);
        }
      }
      if (!any) continue;
      if (allVis || ring.length > 8) land.addPolygon(pts, true);
    }
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: _c, radius: _r)));
    canvas.drawPath(land, Paint()..color = p.land);

    // data cells
    final m = meta, cs = cells;
    if (m != null && cs != null) _paintCells(canvas, m, cs);

    // coast lines on top
    canvas.drawPath(
        land,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = p.coast);

    // graticule
    final gp = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = p.grid.withValues(alpha: 0.7);
    for (var lat = -60; lat <= 60; lat += 30) {
      _polyline(canvas, [for (var lon = -180; lon <= 180; lon += 4) (lat.toDouble(), lon.toDouble())], gp);
    }
    for (var lon = -180; lon < 180; lon += 30) {
      _polyline(canvas, [for (var lat = -88; lat <= 88; lat += 4) (lat.toDouble(), lon.toDouble())], gp);
    }

    // case regions
    final pins = <Offset>[];
    for (final rg in regions) {
      final fill = Paint()..color = rg.color.withValues(alpha: 0.28);
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = rg.color;
      final res = rg.res;
      if (rg.cells.isNotEmpty && res != null && res.length == 2) {
        for (final c in rg.cells) {
          final q = _quad(c[0] - res[0] / 2, c[0] + res[0] / 2, c[1] - res[1] / 2, c[1] + res[1] / 2);
          if (q != null) canvas.drawPath(q, fill);
        }
      } else if (rg.bbox != null && rg.bbox!.length == 4) {
        final b = rg.bbox!;
        final path = _box(b[1], b[3], b[0], b[2]);
        if (path != null) {
          canvas.drawPath(path, fill);
          canvas.drawPath(path, stroke);
        }
      }
      final pin = rg.pin;
      if (pin != null) {
        final o = _proj(pin[0], pin[1]);
        if (o != null) {
          pins.add(o);
          canvas.drawCircle(o, 5, Paint()..color = rg.color);
          canvas.drawCircle(o, 5, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.5..color = p.bg);
          if (rg.label != null) _text(canvas, rg.label!, o + const Offset(0, -14), bold: true, size: 12);
        }
      }
    }
    if (redString && pins.length >= 2) {
      canvas.drawLine(pins[0], pins[1], Paint()..color = p.string..strokeWidth = 2);
    }

    // labels
    for (final g in kGeoLabels) {
      if (g.rank == 1 && zoom < 1.6) continue;
      if (g.rank == 2 && zoom < 2.6) continue;
      final o = _proj(g.lat, g.lon);
      if (o == null) continue;
      _text(canvas, lang == 'hi' ? g.hi : g.en, o, color: g.ocean ? p.coast : p.text.withValues(alpha: 0.85), size: g.ocean ? 11 : 11.5, italic: g.ocean, bold: !g.ocean && g.rank == 0);
    }
    if (zoom >= 2.2) {
      final minPop = zoom >= 5 ? 1000000 : (zoom >= 3.4 ? 3000000 : 7000000);
      var shown = 0;
      for (final c in cities) {
        if (c.pop < minPop) continue;
        final o = _proj(c.lat, c.lon);
        if (o == null || (o - _c).distance > _r * 0.97) continue;
        if (o.dx < 0 || o.dy < 0 || o.dx > size.width || o.dy > size.height) continue;
        canvas.drawCircle(o, 2.2, Paint()..color = p.text);
        _text(canvas, c.name, o + const Offset(5, -6), size: 10.5, center: false);
        if (++shown > 90) break;
      }
    }

    // markers
    for (final mk in markers) {
      final o = _proj(mk.lat, mk.lon);
      if (o == null) continue;
      final col = mk.color ?? p.accent;
      canvas.drawCircle(o, 6.5, Paint()..color = p.bg);
      canvas.drawCircle(o, 5, Paint()..color = col);
      if (mk.label != null) _text(canvas, mk.label!, o + const Offset(0, -15), bold: true, size: 11.5, color: col);
    }
    canvas.restore();
    // limb
    canvas.drawCircle(
        _c,
        _r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = p.coast);
  }

  void _polyline(Canvas canvas, List<(double, double)> ll, Paint paint) {
    final path = Path();
    var pen = false;
    for (final q in ll) {
      final o = _proj(q.$1, q.$2);
      if (o == null) {
        pen = false;
        continue;
      }
      if (pen) {
        path.lineTo(o.dx, o.dy);
      } else {
        path.moveTo(o.dx, o.dy);
        pen = true;
      }
    }
    canvas.drawPath(path, paint);
  }

  Path? _quad(double s, double n, double w, double e) {
    final a = _proj(s, w), b = _proj(s, e), c = _proj(n, e), d = _proj(n, w);
    if (a == null || b == null || c == null || d == null) return null;
    return Path()..addPolygon([a, b, c, d], true);
  }

  Path? _box(double s, double n, double w, double e) {
    final pts = <Offset>[];
    void edge(double la0, double lo0, double la1, double lo1) {
      for (var i = 0; i < 12; i++) {
        final o = _proj(la0 + (la1 - la0) * i / 12, lo0 + (lo1 - lo0) * i / 12);
        if (o != null) pts.add(o);
      }
    }

    edge(s, w, s, e);
    edge(s, e, n, e);
    edge(n, e, n, w);
    edge(n, w, s, w);
    if (pts.length < 6) return null;
    return Path()..addPolygon(pts, true);
  }

  void _paintCells(Canvas canvas, LayerMeta m, LayerCells cs) {
    final sArr = cs.fields['s'], vArr = cs.fields['v'], qArr = cs.fields['q'];
    if (sArr == null) return;
    final nlat = m.nlat, nlon = m.nlon;
    // edge trigonometry once per frame
    final sinLat = Float64List(nlat + 1), cosLat = Float64List(nlat + 1);
    for (var i = 0; i <= nlat; i++) {
      final ph = (m.lat0 + (i - 0.5) * m.dlat).clamp(-90.0, 90.0) * _d2r;
      sinLat[i] = math.sin(ph);
      cosLat[i] = math.cos(ph);
    }
    final sinDl = Float64List(nlon + 1), cosDl = Float64List(nlon + 1);
    for (var j = 0; j <= nlon; j++) {
      final dl = (m.lon0 + (j - 0.5) * m.dlon - lon0) * _d2r;
      sinDl[j] = math.sin(dl);
      cosDl[j] = math.cos(dl);
    }
    final pos = cs.position;
    final count = pos?.length ?? nlat * nlon;
    final xy = Float32List(count * 12);
    final colors = Int32List(count * 6);
    var nv = 0;
    void cell(int grid, int k) {
      if (k >= sArr.length) return;
      final s = sArr[k];
      final v = vArr != null && k < vArr.length ? vArr[k] : null;
      if (!filter.pass(s, v)) return;
      final i = grid ~/ nlon, j = grid % nlon;
      // all four corners must be on the near side
      double cx(int ii, int jj) => _c.dx + _r * cosLat[ii] * sinDl[jj];
      double cy(int ii, int jj) => _c.dy - _r * (_cp0 * sinLat[ii] - _sp0 * cosLat[ii] * cosDl[jj]);
      bool vis(int ii, int jj) => _sp0 * sinLat[ii] + _cp0 * cosLat[ii] * cosDl[jj] > 0.02;
      if (!(vis(i, j) && vis(i, j + 1) && vis(i + 1, j) && vis(i + 1, j + 1))) return;
      final q = qArr != null && k < qArr.length ? qArr[k] : null;
      final sig = q != null && q < 0.10;
      final col = m.colorFor(s!).withValues(alpha: sig ? 0.92 : 0.40).toARGB32();
      final o = nv * 2;
      final x00 = cx(i, j), y00 = cy(i, j), x01 = cx(i, j + 1), y01 = cy(i, j + 1);
      final x10 = cx(i + 1, j), y10 = cy(i + 1, j), x11 = cx(i + 1, j + 1), y11 = cy(i + 1, j + 1);
      xy[o] = x00;
      xy[o + 1] = y00;
      xy[o + 2] = x01;
      xy[o + 3] = y01;
      xy[o + 4] = x11;
      xy[o + 5] = y11;
      xy[o + 6] = x00;
      xy[o + 7] = y00;
      xy[o + 8] = x11;
      xy[o + 9] = y11;
      xy[o + 10] = x10;
      xy[o + 11] = y10;
      for (var t = 0; t < 6; t++) {
        colors[nv + t] = col;
      }
      nv += 6;
    }

    if (pos != null) {
      pos.forEach(cell);
    } else {
      for (var g = 0; g < nlat * nlon; g++) {
        cell(g, g);
      }
    }
    if (nv == 0) return;
    final verts = ui.Vertices.raw(ui.VertexMode.triangles, Float32List.sublistView(xy, 0, nv * 2), colors: Int32List.sublistView(colors, 0, nv));
    canvas.drawVertices(verts, BlendMode.dst, Paint());
  }

  @override
  bool shouldRepaint(covariant _GlobePainter o) =>
      o.lat0 != lat0 || o.lon0 != lon0 || o.zoom != zoom || o.cells != cells || o.meta != meta || o.filter != filter || o.markers != markers || o.regions != regions || o.lang != lang || o.p != p || o.rings != rings;
}

/// Flat-map version of the data cells (used instead of the PNG when a filter is on).
class FlatCellsPainter extends CustomPainter {
  FlatCellsPainter(this.meta, this.cells, this.filter);
  final LayerMeta meta;
  final LayerCells cells;
  final CellFilter filter;

  @override
  void paint(Canvas canvas, Size size) {
    final sArr = cells.fields['s'], vArr = cells.fields['v'], qArr = cells.fields['q'];
    if (sArr == null) return;
    final w = size.width / 360, h = size.height / 180;
    final paint = Paint();
    void cell(int grid, int k) {
      if (k >= sArr.length) return;
      final s = sArr[k];
      final v = vArr != null && k < vArr.length ? vArr[k] : null;
      if (!filter.pass(s, v)) return;
      final i = grid ~/ meta.nlon, j = grid % meta.nlon;
      final lat = meta.lat0 + i * meta.dlat;
      var lon = meta.lon0 + j * meta.dlon;
      if (lon > 180) lon -= 360;
      final q = qArr != null && k < qArr.length ? qArr[k] : null;
      paint.color = meta.colorFor(s!).withValues(alpha: (q != null && q < 0.10) ? 0.92 : 0.40);
      canvas.drawRect(Rect.fromLTWH((lon - meta.dlon / 2 + 180) * w, (90 - lat - meta.dlat / 2) * h, meta.dlon * w + 0.4, meta.dlat * h + 0.4), paint);
    }

    final pos = cells.position;
    if (pos != null) {
      pos.forEach(cell);
    } else {
      for (var g = 0; g < meta.nlat * meta.nlon; g++) {
        cell(g, g);
      }
    }
  }

  @override
  bool shouldRepaint(covariant FlatCellsPainter o) => o.meta != meta || o.cells != cells || o.filter != filter;
}
