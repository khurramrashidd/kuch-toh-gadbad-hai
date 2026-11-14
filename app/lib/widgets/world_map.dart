import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../theme.dart';

/// A region drawn on the map (mirror-case side, or a highlighted box).
class MapRegion {
  const MapRegion({required this.color, this.cells = const [], this.res, this.bbox, this.pin, this.label});
  final Color color;
  final List<List<double>> cells; // [lat, lon] centres
  final List<double>? res; // [dlat, dlon]
  final List<double>? bbox; // [west, south, east, north]
  final List<double>? pin; // [lat, lon]
  final String? label;
}

class MapMarker {
  const MapMarker(this.lat, this.lon, {this.color, this.label});
  final double lat, lon;
  final Color? color;
  final String? label;
}

/// Equirectangular world map: Natural Earth land, an optional trend-layer image,
/// mirror regions joined by the detective's red string, markers, pinch-zoom and tap.
class WorldMap extends StatefulWidget {
  const WorldMap({
    super.key,
    this.layerUrl,
    this.stippleUrl,
    this.layerBounds,
    this.layerOpacity = 1.0,
    this.regions = const [],
    this.markers = const [],
    this.redString = false,
    this.onTap,
    this.focus,
    this.layerPainter,
  });
  final CustomPainter? layerPainter; // drawn instead of the PNG (filtered cells)
  final String? layerUrl, stippleUrl;
  final List<double>? layerBounds; // west, south, east, north
  final double layerOpacity;
  final List<MapRegion> regions;
  final List<MapMarker> markers;
  final bool redString;
  final void Function(double lat, double lon)? onTap;
  final List<double>? focus; // bbox to zoom to initially

  @override
  State<WorldMap> createState() => _WorldMapState();
}

class _WorldMapState extends State<WorldMap> {
  final _tc = TransformationController();
  Size? _lastSize;
  List<double>? _lastFocus;

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  void _fit(Size size) {
    final f = widget.focus;
    if (f == null || f.length != 4) {
      _tc.value = Matrix4.identity();
      return;
    }
    final w = size.width, h = size.height;
    final bw = math.max(10.0, f[2] - f[0]) * 1.25, bh = math.max(8.0, f[3] - f[1]) * 1.25;
    final s = math.min(w / (bw / 360 * w), h / (bh / 180 * h)).clamp(1.0, 6.0);
    final cx = ((f[0] + f[2]) / 2 + 180) / 360 * w, cy = (90 - (f[1] + f[3]) / 2) / 180 * h;
    var tx = w / 2 - cx * s, ty = h / 2 - cy * s;
    tx = tx.clamp(w - w * s, 0.0);
    ty = ty.clamp(h - h * s, 0.0);
    _tc.value = Matrix4(s, 0, 0, 0, 0, s, 0, 0, 0, 0, 1, 0, tx, ty, 0, 1);
  }

  void _zoom(double factor) {
    final m = _tc.value;
    final s = (m.storage[0] * factor).clamp(1.0, 16.0);
    final size = _lastSize ?? const Size(360, 180);
    final cx = size.width / 2, cy = size.height / 2;
    final sceneC = _tc.toScene(Offset(cx, cy));
    var tx = cx - sceneC.dx * s, ty = cy - sceneC.dy * s;
    tx = tx.clamp(size.width - size.width * s, 0.0);
    ty = ty.clamp(size.height - size.height * s, 0.0);
    _tc.value = Matrix4(s, 0, 0, 0, 0, s, 0, 0, 0, 0, 1, 0, tx, ty, 0, 1);
  }

  @override
  Widget build(BuildContext context) {
    final world = context.app.world;
    final k = context.k;
    return AspectRatio(
      aspectRatio: 2,
      child: LayoutBuilder(builder: (context, cons) {
        final size = Size(cons.maxWidth, cons.maxWidth / 2);
        if (_lastSize != size || _lastFocus != widget.focus) {
          _lastSize = size;
          _lastFocus = widget.focus;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _fit(size);
          });
        }
        final b = widget.layerBounds ?? const [-180.0, -90.0, 180.0, 90.0];
        Rect boundsRect() => Rect.fromLTRB(
              (b[0] + 180) / 360 * size.width,
              (90 - b[3]) / 180 * size.height,
              (b[2] + 180) / 360 * size.width,
              (90 - b[1]) / 180 * size.height,
            );
        final r = boundsRect();
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(children: [
            InteractiveViewer(
              transformationController: _tc,
              minScale: 1,
              maxScale: 16,
              boundaryMargin: EdgeInsets.zero,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: widget.onTap == null
                    ? null
                    : (d) {
                        final p = d.localPosition;
                        final lon = p.dx / size.width * 360 - 180;
                        final lat = 90 - p.dy / size.height * 180;
                        widget.onTap!(lat.clamp(-90.0, 90.0), lon.clamp(-180.0, 180.0));
                      },
                child: SizedBox(
                  width: size.width,
                  height: size.height,
                  child: Stack(children: [
                    Positioned.fill(child: CustomPaint(painter: _LandPainter(world?.rings ?? const [], k))),
                    if (widget.layerPainter != null) Positioned.fill(child: CustomPaint(painter: widget.layerPainter)),
                    if (widget.layerUrl != null && widget.layerPainter == null)
                      Positioned.fromRect(
                        rect: r,
                        child: Opacity(
                          opacity: widget.layerOpacity,
                          child: Image.network(widget.layerUrl!,
                              fit: BoxFit.fill,
                              filterQuality: FilterQuality.none,
                              gaplessPlayback: true,
                              errorBuilder: (_, _, _) => const SizedBox.shrink()),
                        ),
                      ),
                    if (widget.layerUrl != null) Positioned.fill(child: CustomPaint(painter: _CoastPainter(world?.rings ?? const []))),
                    if (widget.stippleUrl != null)
                      Positioned.fromRect(
                        rect: r,
                        child: Image.network(widget.stippleUrl!,
                            fit: BoxFit.fill, filterQuality: FilterQuality.none, gaplessPlayback: true, errorBuilder: (_, _, _) => const SizedBox.shrink()),
                      ),
                    Positioned.fill(child: CustomPaint(painter: _OverlayPainter(widget.regions, widget.markers, widget.redString, k))),
                  ]),
                ),
              ),
            ),
            Positioned(
              right: 6,
              bottom: 6,
              child: Column(children: [
                _ZoomBtn(icon: Icons.add, onTap: () => _zoom(1.6)),
                const SizedBox(height: 4),
                _ZoomBtn(icon: Icons.remove, onTap: () => _zoom(1 / 1.6)),
                const SizedBox(height: 4),
                _ZoomBtn(icon: Icons.public, onTap: () => _tc.value = Matrix4.identity()),
              ]),
            ),
          ]),
        );
      }),
    );
  }
}

class _ZoomBtn extends StatelessWidget {
  const _ZoomBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
        color: context.k.bg.withValues(alpha: 0.75),
        shape: const CircleBorder(),
        child: InkWell(customBorder: const CircleBorder(), onTap: onTap, child: Padding(padding: const EdgeInsets.all(5), child: Icon(icon, size: 18, color: context.k.text))),
      );
}

Path _landPath(List<List<List<double>>> rings, Size size) {
  final path = Path();
  for (final ring in rings) {
    if (ring.length < 3) continue;
    for (var i = 0; i < ring.length; i++) {
      final x = (ring[i][0] + 180) / 360 * size.width;
      final y = (90 - ring[i][1]) / 180 * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
  }
  return path;
}

class _LandPainter extends CustomPainter {
  _LandPainter(this.rings, this.p);
  final List<List<List<double>>> rings;
  final Palette p;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = p.ocean);
    final grat = Paint()
      ..color = p.grid.withValues(alpha: 0.7)
      ..strokeWidth = 0.6;
    for (var lon = -150; lon <= 150; lon += 30) {
      final x = (lon + 180) / 360 * size.width;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grat);
    }
    for (var lat = -60; lat <= 60; lat += 30) {
      final y = (90 - lat) / 180 * size.height;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grat);
    }
    final path = _landPath(rings, size);
    canvas.drawPath(path, Paint()..color = p.land);
    canvas.drawPath(path, Paint()
      ..color = p.coast
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7);
  }

  @override
  bool shouldRepaint(covariant _LandPainter old) => old.rings != rings || old.p != p;
}

class _CoastPainter extends CustomPainter {
  _CoastPainter(this.rings);
  final List<List<List<double>>> rings;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(_landPath(rings, size), Paint()
      ..color = Colors.black.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6);
  }

  @override
  bool shouldRepaint(covariant _CoastPainter old) => old.rings != rings;
}

class _OverlayPainter extends CustomPainter {
  _OverlayPainter(this.regions, this.markers, this.redString, this.p);
  final List<MapRegion> regions;
  final List<MapMarker> markers;
  final bool redString;
  final Palette p;

  Offset _xy(Size s, double lat, double lon) => Offset((lon + 180) / 360 * s.width, (90 - lat) / 180 * s.height);

  @override
  void paint(Canvas canvas, Size size) {
    final pins = <Offset>[];
    for (final r in regions) {
      final fill = Paint()..color = r.color.withValues(alpha: 0.42);
      final edge = Paint()
        ..color = r.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8;
      if (r.cells.isNotEmpty && r.res != null && r.res!.length == 2) {
        final dlat = r.res![0], dlon = r.res![1];
        for (final c in r.cells) {
          final tl = _xy(size, c[0] + dlat / 2, c[1] - dlon / 2);
          final br = _xy(size, c[0] - dlat / 2, c[1] + dlon / 2);
          final rect = Rect.fromPoints(tl, br);
          canvas.drawRect(rect, fill);
          canvas.drawRect(rect, edge);
        }
      } else if (r.bbox != null && r.bbox!.length == 4) {
        final b = r.bbox!;
        final rect = Rect.fromPoints(_xy(size, b[3], b[0]), _xy(size, b[1], b[2]));
        canvas.drawRect(rect, fill);
        canvas.drawRect(rect, edge..strokeWidth = 1.5);
      }
      if (r.pin != null) pins.add(_xy(size, r.pin![0], r.pin![1]));
    }
    if (redString && pins.length >= 2) {
      final a = pins[0], b = pins[1];
      final mid = Offset((a.dx + b.dx) / 2, math.min(a.dy, b.dy) - (b - a).distance * 0.25 - 8);
      final path = Path()
        ..moveTo(a.dx, a.dy)
        ..quadraticBezierTo(mid.dx, mid.dy, b.dx, b.dy);
      canvas.drawPath(path, Paint()
        ..color = Colors.black.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5);
      canvas.drawPath(path, Paint()
        ..color = p.string
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2);
    }
    for (var i = 0; i < pins.length; i++) {
      canvas.drawCircle(pins[i], 6, Paint()..color = p.string);
      canvas.drawCircle(pins[i], 2.5, Paint()..color = Colors.white);
    }
    for (final m in markers) {
      final o = _xy(size, m.lat, m.lon);
      canvas.drawCircle(o, 7, Paint()..color = Colors.black.withValues(alpha: 0.5));
      canvas.drawCircle(o, 5.5, Paint()..color = m.color ?? p.accent);
      canvas.drawCircle(o, 2, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant _OverlayPainter old) => old.regions != regions || old.markers != markers || old.p != p;
}
