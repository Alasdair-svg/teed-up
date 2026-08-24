/// Animated golf-globe-on-a-tee — the All Teed Up brand logo.
///
/// Live-rendered, matching the technique of the reference D3 globe this
/// brand mark comes from: an orthographic projection of real coastline
/// data on a dimpled sphere, spun continuously.
///
/// ## Why live rendering, not a baked frame sequence
///
/// A pre-rendered sprite sequence was tried and removed. The arithmetic
/// kills it: a slow 40s rotation at 60fps needs 2,400 frames. With a
/// affordable 72 frames you get 1.8 frames/sec — a slideshow — and
/// cross-fading between them doesn't rescue it, because adjacent frames
/// are 5deg apart, which is ~24px of surface movement at display size.
/// Dissolving between two positions 24px apart reads as a ghosted double
/// image, not rotation. Sprites fundamentally cannot produce sharp *slow*
/// rotation without absurd asset weight.
///
/// Live rendering has none of those tradeoffs: true 60fps at any speed,
/// sharp at every angle, and the coastline data costs 73KB instead of
/// 3.9MB of frames.
///
/// ## Fidelity
///
/// [_landPolygons] is loaded from `assets/data/land.json` — the real
/// Natural Earth 110m land boundaries (via world-atlas), the same dataset
/// the reference globe uses: 119 polygons, ~5,000 points. An earlier
/// version of this widget hand-simplified that to 16 blobs (~400 points),
/// which is what made it read as crude next to the reference.
///
/// ## Performance
///
/// Two things keep this at 60fps:
///   * Dimple gradient shaders are built once per depth-bucket per frame
///     and reused across all 392 dimples via canvas translation, instead
///     of building a fresh shader per dimple (~700 shader builds/frame,
///     which is what made an earlier version stutter).
///   * Dimple count tiers down with render size.
///
/// Usage:
/// ```dart
/// const GolfBallLogo(size: 160, animate: true)
/// ```
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../theme/app_theme.dart';

/// Real coastline polygons as [[lon,lat], ...] rings, loaded once.
List<List<List<double>>>? _landPolygons;

/// Internal country borders (deduplicated arcs — the topojson "mesh"), so
/// shared borders stroke once rather than twice. The reference draws these
/// and they're a visible part of its texture.
List<List<List<double>>>? _borderArcs;

Future<void>? _geoLoad;

List<List<List<double>>> _parseRings(String s) {
  final raw = jsonDecode(s) as List<dynamic>;
  return raw
      .map<List<List<double>>>((ring) => (ring as List<dynamic>)
          .map<List<double>>((p) => <double>[
                (p as List<dynamic>)[0].toDouble(),
                p[1].toDouble(),
              ])
          .toList(growable: false))
      .toList(growable: false);
}

Future<void> _ensureLandLoaded() {
  return _geoLoad ??= Future.wait([
    rootBundle.loadString('assets/data/land.json'),
    rootBundle.loadString('assets/data/borders.json'),
  ]).then((r) {
    _landPolygons = _parseRings(r[0]);
    _borderArcs = _parseRings(r[1]);
  });
}

/// A golf ball on a tee rendered with [CustomPainter].
///
/// Set [animate] to `true` for the spinning effect. Set [showTee] to `false`
/// for a compact logo without the tee (e.g. in an app bar or badge).
class GolfBallLogo extends StatefulWidget {
  /// Creates a [GolfBallLogo].
  const GolfBallLogo({
    super.key,
    this.size = 160,
    this.animate = true,
    this.showTee = true,
    this.showGlow = true,
  });

  /// Overall widget width. Height is ~1.3x when [showTee] is true.
  final double size;

  /// Whether the globe should spin continuously.
  final bool animate;

  /// Whether to render the wooden tee below the ball.
  final bool showTee;

  /// Whether to render a soft purple glow behind the ball.
  final bool showGlow;

  @override
  State<GolfBallLogo> createState() => _GolfBallLogoState();
}

class _GolfBallLogoState extends State<GolfBallLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // Matches the reference's pace: 0.15deg per frame at ~60fps = 9deg/s
    // = 40s per revolution. A slow, stately spin.
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 40),
    );
    if (widget.animate) _controller.repeat();

    if (_landPolygons == null) {
      _ensureLandLoaded().then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void didUpdateWidget(GolfBallLogo old) {
    super.didUpdateWidget(old);
    if (widget.animate && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.animate && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final teeExtra = widget.showTee ? widget.size * 0.28 : 0.0;
    final teeSpace = widget.showTee ? (widget.size / 2 - 2) * 0.2 : 0.0;

    // Ball drop-shadow as a static BoxShadow (painted once by the framework,
    // not re-blurred on every animation frame inside CustomPainter.paint).
    return Stack(
      alignment: Alignment.topCenter,
      children: [
        Positioned(
          top: teeSpace + 3,
          child: Container(
            width: widget.size - 4,
            height: widget.size - 4,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 8,
                  offset: const Offset(3, 4),
                ),
              ],
            ),
          ),
        ),
        // Isolates the continuously-animating painter into its own
        // compositor layer so a repaint here never forces sibling widgets
        // to repaint alongside it.
        RepaintBoundary(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => CustomPaint(
              size: Size(widget.size, widget.size + teeExtra),
              painter: _GolfGlobePainter(
                rotation: _controller.value * math.pi * 2,
                showTee: widget.showTee,
                showGlow: widget.showGlow,
                widgetSize: widget.size,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// Painter
// =============================================================================

class _GolfGlobePainter extends CustomPainter {
  _GolfGlobePainter({
    required this.rotation,
    required this.showTee,
    required this.showGlow,
    required this.widgetSize,
  });

  final double rotation;
  final bool showTee;
  final bool showGlow;
  final double widgetSize;

  // Fibonacci dimple distributions, tiered by render size — full detail
  // only earns its cost at large sizes.
  static final List<_LatLon> _dimplesFull = _buildDimples(392);
  static final List<_LatLon> _dimplesMed = _buildDimples(180);
  static final List<_LatLon> _dimplesSmall = _buildDimples(80);

  List<_LatLon> get _dimples {
    if (widgetSize <= 64) return _dimplesSmall;
    if (widgetSize <= 150) return _dimplesMed;
    return _dimplesFull;
  }

  static List<_LatLon> _buildDimples(int count) {
    final pts = <_LatLon>[];
    final goldenAngle = math.pi * (3 - math.sqrt(5));
    for (var i = 0; i < count; i++) {
      final y = 1 - (i / (count - 1)) * 2;
      final theta = goldenAngle * i;
      final lat = math.asin(y.clamp(-1.0, 1.0)) * 180 / math.pi;
      final lon = (theta * 180 / math.pi) % 360 - 180;
      pts.add(_LatLon(lon, lat));
    }
    return pts;
  }

  // ---------------------------------------------------------------------------
  // Projection (orthographic, matching d3.geoOrthographic with rotate
  // [lambda, -15, 0] — the reference's fixed -15deg tilt plus the spin)
  // ---------------------------------------------------------------------------

  static const double _axialTilt = -15 * math.pi / 180;

  /// Sphere point for [lon]/[lat] after the animated spin and fixed tilt.
  (double, double, double) _rotatedPoint(double lon, double lat) {
    final lonR = lon * math.pi / 180;
    final latR = lat * math.pi / 180;
    // d3.geoOrthographic().rotate([lambda,...]) adds lambda to longitude;
    // frames captured from the reference confirmed the visible face sweeps
    // westward, so this matches it exactly.
    final rotLon = lonR + rotation;

    final x = math.cos(latR) * math.sin(rotLon);
    final y = math.sin(latR);
    final z = math.cos(latR) * math.cos(rotLon);

    final tiltedY = y * math.cos(_axialTilt) - z * math.sin(_axialTilt);
    final tiltedZ = y * math.sin(_axialTilt) + z * math.cos(_axialTilt);

    return (x, tiltedY, tiltedZ);
  }

  /// Projects [lon]/[lat] to screen, or null if on the far side.
  Offset? _project(double lon, double lat, Offset center, double radius) {
    final (x, y, z) = _rotatedPoint(lon, lat);
    if (z < 0) return null; // back-facing — cull
    return Offset(center.dx + x * radius, center.dy - y * radius);
  }

  /// How "front-facing" a point is: 1.0 = dead-centre, 0.0 = edge.
  double _frontFactor(double lon, double lat) {
    final (_, _, z) = _rotatedPoint(lon, lat);
    return z.clamp(0.0, 1.0);
  }

  // ---------------------------------------------------------------------------
  // Paint
  // ---------------------------------------------------------------------------

  @override
  void paint(Canvas canvas, Size size) {
    final ballRadius = widgetSize / 2 - 2;
    final teeSpace = showTee ? ballRadius * 0.2 : 0.0;
    final center = Offset(size.width / 2, widgetSize / 2 - teeSpace / 2);
    final sc = widgetSize / 600;

    // ── Glow ────────────────────────────────────────────────────────────────
    if (showGlow) {
      final gPaint = Paint()
        ..shader = RadialGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.18),
            AppColors.primary.withValues(alpha: 0.06),
            AppColors.primary.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(
          Rect.fromCircle(center: center, radius: ballRadius * 1.7),
        );
      canvas.drawCircle(center, ballRadius * 1.7, gPaint);
    }

    // ── Tee (behind the ball) ───────────────────────────────────────────────
    if (showTee) _drawTee(canvas, center, ballRadius, sc);

    // ── Ball body ───────────────────────────────────────────────────────────
    final ballPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.25, -0.25),
        radius: 1.0,
        colors: const [
          Color(0xFFFFFFFF),
          Color(0xFFF8F8FA),
          Color(0xFFECECF0),
          Color(0xFFDDDDE5),
        ],
        stops: const [0.0, 0.6, 0.85, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: ballRadius));
    canvas.drawCircle(center, ballRadius, ballPaint);

    // ── Clip to sphere for all overlays ─────────────────────────────────────
    canvas.save();
    canvas.clipPath(Path()
      ..addOval(Rect.fromCircle(center: center, radius: ballRadius)));

    // Draw order matters and matches the reference exactly. The matte
    // white wash goes UNDER the seams and dimples — painting it over them
    // (as an earlier version did) washes the dimples out by 15% and is
    // what made this read flat next to the reference.
    _drawGraticule(canvas, center, ballRadius, sc);
    _drawLandmasses(canvas, center, ballRadius, sc);
    _drawBorders(canvas, center, ballRadius, sc);

    // Matte white ocean overlay — urethane golf-ball surface.
    canvas.drawCircle(
      center,
      ballRadius,
      Paint()..color = const Color(0x26FFFFFF),
    );

    _drawSeams(canvas, center, ballRadius, sc);
    _drawDimples(canvas, center, ballRadius, sc);

    canvas.restore();

    // ── Specular highlight ──────────────────────────────────────────────────
    if (widgetSize > 64) {
      canvas.drawCircle(
        center,
        ballRadius,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.35, -0.35),
            radius: 0.55,
            colors: [
              Colors.white.withValues(alpha: 0.30),
              Colors.white.withValues(alpha: 0.06),
              Colors.white.withValues(alpha: 0.0),
            ],
          ).createShader(Rect.fromCircle(center: center, radius: ballRadius)),
      );
    }

    // ── Rim outline ─────────────────────────────────────────────────────────
    canvas.drawCircle(
      center,
      ballRadius,
      Paint()
        ..color = const Color(0xFFD0D0DA)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5 * sc.clamp(0.5, 2.0),
    );
  }

  // ── Tee ───────────────────────────────────────────────────────────────────

  void _drawTee(Canvas canvas, Offset ballCenter, double ballRadius, double sc) {
    final teeTop = ballCenter.dy + ballRadius - 1;
    final teeWidth = math.max(4.0, 12 * sc);
    final teeStemW = math.max(2.0, 4 * sc);
    final teeStemH = math.max(6.0, ballRadius * 0.35);
    final teeBaseH = math.max(2.0, 4 * sc);
    final cx = ballCenter.dx;

    final teeGrad = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFFC49A6C), Color(0xFFB8895C), Color(0xFF8B6914)],
      stops: [0.0, 0.3, 1.0],
    ).createShader(Rect.fromLTWH(
        cx - teeWidth / 2, teeTop, teeWidth, teeStemH + teeBaseH + 4));

    final path = Path()
      ..moveTo(cx - teeWidth / 2, teeTop + 2 * sc)
      ..quadraticBezierTo(cx - teeWidth / 2, teeTop, cx - teeWidth * 0.3, teeTop)
      ..quadraticBezierTo(cx, teeTop - 2 * sc, cx + teeWidth * 0.3, teeTop)
      ..quadraticBezierTo(cx + teeWidth / 2, teeTop, cx + teeWidth / 2, teeTop + 2 * sc)
      ..lineTo(cx + teeStemW / 2, teeTop + 2 * sc)
      ..lineTo(cx + teeStemW / 2, teeTop + 2 * sc + teeStemH)
      ..lineTo(cx - teeStemW / 2, teeTop + 2 * sc + teeStemH)
      ..lineTo(cx - teeStemW / 2, teeTop + 2 * sc)
      ..close();

    canvas.drawPath(path, Paint()..shader = teeGrad);
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF8B6914)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5 * sc,
    );

    final baseY = teeTop + 2 * sc + teeStemH;
    final tipPath = Path()
      ..moveTo(cx - teeStemW / 2, baseY)
      ..lineTo(cx, baseY + teeBaseH)
      ..lineTo(cx + teeStemW / 2, baseY)
      ..close();
    canvas.drawPath(tipPath, Paint()..color = const Color(0xFF8B6914));
  }

  // ── Landmasses (real coastline data) ──────────────────────────────────────

  void _drawLandmasses(
      Canvas canvas, Offset center, double ballRadius, double sc) {
    final polys = _landPolygons;
    if (polys == null) return; // asset still loading — ball renders bare

    final landPaint = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.92)
      ..isAntiAlias = true;
    final shore = _hairline(0.3 * sc, 0.30);
    final shorePaint = Paint()
      ..color = AppColors.deepPurple.withValues(alpha: shore.alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = shore.width
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    final r = ballRadius * 0.995;
    for (final ring in polys) {
      final path = _clipRingToPath(ring, center, r);
      if (path == null) continue;
      canvas.drawPath(path, landPaint);
      if (widgetSize > 64) canvas.drawPath(path, shorePaint);
    }
  }

  /// Where segment a->b crosses the limb (z = 0), pushed back onto the
  /// unit sphere so the point sits exactly on the visible edge.
  (double, double) _limbCrossing(
      (double, double, double) a, (double, double, double) b) {
    final t = a.$3 / (a.$3 - b.$3);
    var x = a.$1 + (b.$1 - a.$1) * t;
    var y = a.$2 + (b.$2 - a.$2) * t;
    final m = math.sqrt(x * x + y * y);
    if (m > 1e-9) {
      x /= m;
      y /= m;
    }
    return (x, y);
  }

  /// Clips a lon/lat ring to the visible hemisphere, returning a closed
  /// screen-space path — or null if nothing of it is front-facing.
  ///
  /// Naively skipping back-facing points (what this used to do) is wrong in
  /// two ways that together made landmasses render flaky: it splits a ring
  /// straddling the horizon into disconnected subpaths, so `close()` only
  /// seals the last one and the fill comes out as ragged fragments; and it
  /// jumps straight from the last visible vertex to the next, cutting a
  /// chord and popping as vertices cross the threshold during rotation.
  ///
  /// This instead does Sutherland–Hodgman clipping against the z >= 0
  /// half-space, interpolating the exact point each edge crosses the limb,
  /// then walks along the limb arc between an exit and the following entry
  /// so the filled shape hugs the horizon — the same result
  /// d3.geoOrthographic's clipAngle(90) produces in the reference.
  Path? _clipRingToPath(List<List<double>> ring, Offset center, double r) {
    final n = ring.length;
    if (n < 3) return null;

    final v = List<(double, double, double)>.generate(
        n, (i) => _rotatedPoint(ring[i][0], ring[i][1]));

    var anyVisible = false;
    for (final p in v) {
      if (p.$3 >= 0) {
        anyVisible = true;
        break;
      }
    }
    if (!anyVisible) return null;

    Offset toScreen(double x, double y) =>
        Offset(center.dx + x * r, center.dy - y * r);

    final pts = <Offset>[];
    final onLimb = <bool>[];
    for (var i = 0; i < n; i++) {
      final a = v[i];
      final b = v[(i + 1) % n];
      final aIn = a.$3 >= 0;
      final bIn = b.$3 >= 0;
      if (aIn) {
        pts.add(toScreen(a.$1, a.$2));
        onLimb.add(false);
        if (!bIn) {
          final c = _limbCrossing(a, b);
          pts.add(toScreen(c.$1, c.$2));
          onLimb.add(true);
        }
      } else if (bIn) {
        final c = _limbCrossing(a, b);
        pts.add(toScreen(c.$1, c.$2));
        onLimb.add(true);
      }
    }
    if (pts.length < 3) return null;

    final path = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (var i = 0; i < pts.length; i++) {
      final j = (i + 1) % pts.length;
      // Between an exit point and the next entry point, follow the limb
      // instead of cutting a chord across the visible face.
      if (onLimb[i] && onLimb[j]) {
        final a0 = math.atan2(-(pts[i].dy - center.dy), pts[i].dx - center.dx);
        final a1 = math.atan2(-(pts[j].dy - center.dy), pts[j].dx - center.dx);
        var d = a1 - a0;
        while (d > math.pi) {
          d -= 2 * math.pi;
        }
        while (d < -math.pi) {
          d += 2 * math.pi;
        }
        final steps = math.max(2, (d.abs() / 0.12).ceil());
        for (var k = 1; k < steps; k++) {
          final ang = a0 + d * k / steps;
          path.lineTo(
              center.dx + math.cos(ang) * r, center.dy - math.sin(ang) * r);
        }
      }
      if (j != 0) path.lineTo(pts[j].dx, pts[j].dy);
    }
    path.close();
    return path;
  }

  // ── Country borders (internal, deduplicated) ──────────────────────────────

  void _drawBorders(
      Canvas canvas, Offset center, double ballRadius, double sc) {
    final arcsData = _borderArcs;
    if (arcsData == null || widgetSize <= 100) return;

    final b = _hairline(0.3 * sc, 0.30);
    final paint = Paint()
      ..color = AppColors.deepPurple.withValues(alpha: b.alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = b.width
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    final r = ballRadius * 0.995;
    final path = Path();
    for (final arc in arcsData) {
      // Strokes (unlike fills) SHOULD break at the horizon rather than
      // wrap around it — but the break must land exactly on the limb, not
      // at the last vertex that happened to be front-facing, or the ends
      // stop short and fray as the globe turns.
      var started = false;
      (double, double, double)? prev;
      for (final pt in arc) {
        final cur = _rotatedPoint(pt[0], pt[1]);
        final visible = cur.$3 >= 0;
        if (visible) {
          if (!started && prev != null) {
            // Entering view — begin exactly at the limb crossing.
            final c = _limbCrossing(prev, cur);
            path.moveTo(center.dx + c.$1 * r, center.dy - c.$2 * r);
            path.lineTo(center.dx + cur.$1 * r, center.dy - cur.$2 * r);
            started = true;
          } else if (!started) {
            path.moveTo(center.dx + cur.$1 * r, center.dy - cur.$2 * r);
            started = true;
          } else {
            path.lineTo(center.dx + cur.$1 * r, center.dy - cur.$2 * r);
          }
        } else if (started && prev != null) {
          // Leaving view — end exactly at the limb crossing.
          final c = _limbCrossing(prev, cur);
          path.lineTo(center.dx + c.$1 * r, center.dy - c.$2 * r);
          started = false;
        }
        prev = cur;
      }
    }
    canvas.drawPath(path, paint);
  }

  // ── Graticule ─────────────────────────────────────────────────────────────

  void _drawGraticule(
      Canvas canvas, Offset center, double ballRadius, double sc) {
    if (widgetSize <= 100) return;
    final g = _hairline(0.3 * sc, 0.25);
    final paint = Paint()
      ..color = const Color(0xFFC8C8DC).withValues(alpha: g.alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = g.width;

    final r = ballRadius * 0.995;
    // Meridians every 15deg
    for (var lon = -180; lon < 180; lon += 15) {
      _strokeArc(canvas, paint, center, r,
          (t) => (lon.toDouble(), -80 + t * 160), 24);
    }
    // Parallels every 15deg
    for (var lat = -75; lat <= 75; lat += 15) {
      _strokeArc(canvas, paint, center, r,
          (t) => (-180 + t * 360, lat.toDouble()), 48);
    }
  }

  void _strokeArc(Canvas canvas, Paint paint, Offset center, double r,
      (double, double) Function(double) at, int steps) {
    final path = Path();
    var started = false;
    for (var i = 0; i <= steps; i++) {
      final (lon, lat) = at(i / steps);
      final p = _project(lon, lat, center, r);
      if (p == null) {
        started = false;
        continue;
      }
      if (!started) {
        path.moveTo(p.dx, p.dy);
        started = true;
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(path, paint);
  }

  // ── Seam lines (equator + meridian) ───────────────────────────────────────

  void _drawSeams(Canvas canvas, Offset center, double ballRadius, double sc) {
    if (widgetSize <= 64) return;
    final seamPaint = Paint()
      ..color = const Color(0xFF5C1D6E).withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.6, 1.2 * sc)
      ..strokeCap = StrokeCap.round;

    final r = ballRadius * 0.995;
    _strokeArc(canvas, seamPaint, center, r, (t) => (-180 + t * 360, 0.0), 90);
    _strokeArc(canvas, seamPaint, center, r, (t) => (0.0, -90 + t * 180), 90);
  }

  // ── Dimples ───────────────────────────────────────────────────────────────

  /// Depth buckets the concave-gradient shader is pre-built for. Building
  /// one shader per dimple per frame (~700/frame) is what made an earlier
  /// version stutter; 12 steps is visually indistinguishable here.
  static const int _dimpleShaderBuckets = 12;

  void _drawDimples(Canvas canvas, Offset center, double ballRadius, double sc) {
    final dimpleR = widgetSize <= 64
        ? 1.4
        : widgetSize <= 150
            ? 2.6
            : 4.5 * sc * 1.2;
    final r = ballRadius * 0.97;

    if (widgetSize <= 64) {
      final dotPaint = Paint()..color = Colors.black.withValues(alpha: 0.14);
      final dotHlPaint = Paint()..color = Colors.white.withValues(alpha: 0.12);
      for (final d in _dimples) {
        final p = _project(d.lon, d.lat, center, r);
        if (p == null) continue;
        canvas.drawCircle(p, dimpleR, dotPaint);
        canvas.drawCircle(
          Offset(p.dx - dimpleR * 0.2, p.dy - dimpleR * 0.2),
          dimpleR * 0.35,
          dotHlPaint,
        );
      }
      return;
    }

    // Shaders depend only on depth (bucketed) and are position-independent
    // when built against an origin-centred rect — so translate the canvas
    // to each dimple and draw at the origin, reusing a handful of shaders
    // across all of them.
    final hlR = dimpleR * (widgetSize >= 150 ? 0.55 : 0.45);
    final hlCenter = Offset(-dimpleR * 0.25, -dimpleR * 0.25);
    final localRect = Rect.fromCircle(center: Offset.zero, radius: dimpleR);
    final hlRect = Rect.fromCircle(center: hlCenter, radius: hlR);

    final bodyShaders = List<Shader?>.filled(_dimpleShaderBuckets, null);
    final hlShaders = List<Shader?>.filled(_dimpleShaderBuckets, null);

    Shader bodyShaderFor(int bucket) => bodyShaders[bucket] ??= () {
          final depth = bucket / (_dimpleShaderBuckets - 1);
          final a = 0.12 + depth * 0.18;
          return RadialGradient(
            center: const Alignment(0.15, 0.15),
            radius: 1.0,
            colors: [
              Colors.black.withValues(alpha: a * 0.08),
              Colors.black.withValues(alpha: a * 0.2),
              Colors.black.withValues(alpha: a * 0.55),
              Colors.black.withValues(alpha: a * 1.0),
              Colors.black.withValues(alpha: a * 0.8),
              Colors.black.withValues(alpha: a * 0.1),
            ],
            stops: const [0.0, 0.35, 0.55, 0.75, 0.9, 1.0],
          ).createShader(localRect);
        }();

    Shader hlShaderFor(int bucket) => hlShaders[bucket] ??= () {
          final depth = bucket / (_dimpleShaderBuckets - 1);
          final a = (0.18 + depth * 0.25).clamp(0.0, 0.45);
          return RadialGradient(
            colors: [
              Colors.white.withValues(alpha: a),
              Colors.white.withValues(alpha: a * 0.4),
              Colors.white.withValues(alpha: 0.0),
            ],
          ).createShader(hlRect);
        }();

    final bodyPaint = Paint();
    final hlPaint = Paint();

    for (final d in _dimples) {
      final p = _project(d.lon, d.lat, center, r);
      if (p == null) continue;
      final depth = _frontFactor(d.lon, d.lat);
      final bucket = (depth * (_dimpleShaderBuckets - 1))
          .round()
          .clamp(0, _dimpleShaderBuckets - 1);

      canvas.save();
      canvas.translate(p.dx, p.dy);
      bodyPaint.shader = bodyShaderFor(bucket);
      canvas.drawCircle(Offset.zero, dimpleR, bodyPaint);
      if (depth > 0.15) {
        hlPaint.shader = hlShaderFor(bucket);
        canvas.drawCircle(hlCenter, hlR, hlPaint);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_GolfGlobePainter old) => rotation != old.rotation;
}

class _LatLon {
  const _LatLon(this.lon, this.lat);
  final double lon;
  final double lat;
}

/// A stroke thinner than one device pixel can't actually be drawn thinner —
/// clamping the width alone makes fine lines read ~4x too heavy at small
/// render sizes, which turned the ball into a wireframe. So clamp the width
/// to something drawable and scale the alpha down by however much we had to
/// over-draw, preserving the line's intended visual weight.
({double width, double alpha}) _hairline(double idealWidth, double baseAlpha) {
  const minDrawable = 0.35;
  if (idealWidth >= minDrawable) {
    return (width: idealWidth, alpha: baseAlpha);
  }
  final ratio = (idealWidth / minDrawable).clamp(0.15, 1.0);
  return (width: minDrawable, alpha: baseAlpha * ratio);
}
