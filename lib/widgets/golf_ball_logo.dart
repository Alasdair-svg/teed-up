/// Animated golf-globe-on-a-tee — the All Teed Up brand logo.
///
/// Ported from `golf-globe-brand.js` v3.0. Renders a white golf ball with:
///   - TAG-purple landmass silhouettes (simplified continent outlines)
///   - 392-dimple Fibonacci distribution with concave gradient + specular highlight
///   - Equator and meridian seam lines
///   - "TAG 4" text that rotates with the globe (Atlantic-area anchor)
///   - Wooden tee (warm brown gradient) below the ball
///
/// Usage:
/// ```dart
/// const GolfBallLogo(size: 160, animate: true)
/// ```
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

// =============================================================================
// Simplified continent outlines (lon/lat pairs, closed polygons)
// Approximated from world-atlas-110m — enough to be recognisable as landmasses
// =============================================================================

/// A list of continent outlines, each as a list of [lon, lat] pairs.
const List<List<List<double>>> _kContinents = [
  // North America
  [
    [-168, 72], [-140, 70], [-100, 73], [-85, 72], [-65, 47], [-80, 25],
    [-90, 16], [-105, 20], [-120, 30], [-125, 48], [-168, 72],
  ],
  // South America
  [
    [-80, 12], [-65, 10], [-50, 5], [-35, -5], [-35, -20], [-55, -35],
    [-70, -55], [-75, -50], [-80, -30], [-80, 0], [-80, 12],
  ],
  // Europe
  [
    [-10, 36], [30, 36], [40, 42], [30, 60], [25, 70], [10, 58],
    [0, 52], [-10, 44], [-10, 36],
  ],
  // Africa
  [
    [-18, 15], [40, 12], [50, 10], [42, -12], [35, -35], [18, -35],
    [10, -18], [10, 5], [-18, 15],
  ],
  // Asia
  [
    [40, 42], [60, 36], [90, 22], [120, 22], [140, 40], [140, 55],
    [100, 70], [60, 70], [30, 60], [40, 42],
  ],
  // Australia
  [
    [114, -22], [130, -14], [145, -18], [150, -36], [148, -42],
    [130, -40], [114, -34], [114, -22],
  ],
  // Greenland
  [
    [-45, 58], [-20, 62], [-18, 76], [-40, 83], [-65, 76], [-60, 65], [-45, 58],
  ],
];

// =============================================================================
// Widget
// =============================================================================

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

  /// Overall widget width. Height is ~1.3× when [showTee] is true.
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
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    );
    if (widget.animate) _controller.repeat();
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
    return AnimatedBuilder(
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

  // Pre-computed Fibonacci dimple distribution (392 points)
  static final List<_LatLon> _dimples = _buildDimples(392);

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
  // Projection helpers (orthographic, Y-axis rotation)
  // ---------------------------------------------------------------------------

  /// Projects [lon]/[lat] (degrees) to screen [Offset] given ball [center] and
  /// [radius]. Returns null if the point is on the back face.
  Offset? _project(double lon, double lat, Offset center, double radius) {
    final lonR = lon * math.pi / 180;
    final latR = lat * math.pi / 180;

    // Rotate longitude by current animation rotation
    final rotLon = lonR + rotation;

    final x = math.cos(latR) * math.cos(rotLon);
    final y = math.sin(latR);
    final z = math.cos(latR) * math.sin(rotLon);

    if (z < -0.05) return null; // back-facing — cull

    return Offset(
      center.dx + x * radius,
      center.dy - y * radius,
    );
  }

  /// Returns how "front-facing" a point is: 1.0 = dead-centre, 0.0 = edge.
  double _frontFactor(double lon, double lat) {
    final lonR = lon * math.pi / 180;
    final latR = lat * math.pi / 180;
    final rotLon = lonR + rotation;
    return (math.cos(latR) * math.sin(rotLon)).clamp(0.0, 1.0);
  }

  // ---------------------------------------------------------------------------
  // Paint
  // ---------------------------------------------------------------------------

  @override
  void paint(Canvas canvas, Size size) {
    final ballRadius = widgetSize / 2 - 2;
    final teeSpace = showTee ? ballRadius * 0.2 : 0.0;
    final center = Offset(size.width / 2, widgetSize / 2 - teeSpace / 2);
    final sc = widgetSize / 600; // scale factor matching golf-globe-brand.js

    // ── Glow ──────────────────────────────────────────────────────────────────
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

    // ── Tee ───────────────────────────────────────────────────────────────────
    if (showTee) _drawTee(canvas, center, ballRadius, sc);

    // ── Ball drop-shadow ──────────────────────────────────────────────────────
    final shadowPaint = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8)
      ..color = Colors.black.withValues(alpha: 0.15);
    canvas.drawCircle(
      center + Offset(3 * sc, 4 * sc),
      ballRadius,
      shadowPaint,
    );

    // ── Ball body (white golf-ball gradient) ──────────────────────────────────
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

    // ── Clip to sphere for all overlays ───────────────────────────────────────
    canvas.save();
    canvas.clipPath(Path()..addOval(
      Rect.fromCircle(center: center, radius: ballRadius),
    ));

    // ── Landmasses (TAG purple) ───────────────────────────────────────────────
    _drawLandmasses(canvas, center, ballRadius);

    // ── Seam lines ────────────────────────────────────────────────────────────
    _drawSeams(canvas, center, ballRadius, sc);

    // ── Dimples ───────────────────────────────────────────────────────────────
    _drawDimples(canvas, center, ballRadius, sc);

    // ── "TAG 4" globe label ───────────────────────────────────────────────────
    if (widgetSize >= 100) _drawTag4(canvas, center, ballRadius, sc);

    // ── Matte white ocean overlay ─────────────────────────────────────────────
    canvas.drawCircle(
      center,
      ballRadius,
      Paint()..color = const Color(0x26FFFFFF),
    );

    canvas.restore(); // end sphere clip

    // ── Specular highlight (top-left shine) ───────────────────────────────────
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

    // ── Rim outline ───────────────────────────────────────────────────────────
    canvas.drawCircle(
      center,
      ballRadius,
      Paint()
        ..color = const Color(0xFFD0D0DA)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5 * sc.clamp(0.5, 2.0),
    );
  }

  // ---------------------------------------------------------------------------
  // Tee (wooden — warm brown gradient, matching golf-globe-brand.js)
  // ---------------------------------------------------------------------------

  void _drawTee(Canvas canvas, Offset ballCenter, double ballRadius, double sc) {
    final teeTop = ballCenter.dy + ballRadius - 1;
    final teeWidth = math.max(4.0, 12 * sc);
    final teeStemW = math.max(2.0, 4 * sc);
    final teeStemH = math.max(6.0, ballRadius * 0.35);
    final teeBaseH = math.max(2.0, 4 * sc);
    final cx = ballCenter.dx;

    final teeGrad = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: const [Color(0xFFC49A6C), Color(0xFFB8895C), Color(0xFF8B6914)],
      stops: const [0.0, 0.3, 1.0],
    ).createShader(Rect.fromLTWH(cx - teeWidth / 2, teeTop, teeWidth, teeStemH + teeBaseH + 4));

    // Cup + shaft path
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

    // Tee point
    final baseY = teeTop + 2 * sc + teeStemH;
    final tipPath = Path()
      ..moveTo(cx - teeStemW / 2, baseY)
      ..lineTo(cx, baseY + teeBaseH)
      ..lineTo(cx + teeStemW / 2, baseY)
      ..close();
    canvas.drawPath(tipPath, Paint()..color = const Color(0xFF8B6914));
  }

  // ---------------------------------------------------------------------------
  // Landmasses
  // ---------------------------------------------------------------------------

  void _drawLandmasses(Canvas canvas, Offset center, double ballRadius) {
    final landPaint = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.92);

    for (final continent in _kContinents) {
      final path = Path();
      bool first = true;
      for (final pt in continent) {
        final projected = _project(pt[0], pt[1], center, ballRadius * 0.97);
        if (projected == null) {
          first = true;
          continue;
        }
        if (first) {
          path.moveTo(projected.dx, projected.dy);
          first = false;
        } else {
          path.lineTo(projected.dx, projected.dy);
        }
      }
      path.close();
      canvas.drawPath(path, landPaint);

      // Country border outline
      canvas.drawPath(
        path,
        Paint()
          ..color = AppColors.deepPurple.withValues(alpha: 0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.3,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Seam lines (equator + meridian)
  // ---------------------------------------------------------------------------

  void _drawSeams(Canvas canvas, Offset center, double ballRadius, double sc) {
    if (widgetSize <= 64) return;

    final seamPaint = Paint()
      ..color = const Color(0xFF5C1D6E).withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.6, 1.2 * sc)
      ..strokeCap = StrokeCap.round;

    // Equator (lat = 0, all longitudes)
    _drawGreatCircle(canvas, center, ballRadius, seamPaint, isEquator: true);
    // Meridian (lon = 0, all latitudes)
    _drawGreatCircle(canvas, center, ballRadius, seamPaint, isEquator: false);
  }

  void _drawGreatCircle(
    Canvas canvas,
    Offset center,
    double ballRadius,
    Paint paint, {
    required bool isEquator,
  }) {
    final path = Path();
    bool first = true;
    for (var i = -180; i <= 180; i += 3) {
      final lon = isEquator ? i.toDouble() : 0.0;
      final lat = isEquator ? 0.0 : i.toDouble();
      final projected = _project(lon, lat, center, ballRadius * 0.97);
      if (projected == null) {
        first = true;
        continue;
      }
      if (first) {
        path.moveTo(projected.dx, projected.dy);
        first = false;
      } else {
        path.lineTo(projected.dx, projected.dy);
      }
    }
    canvas.drawPath(path, paint);
  }

  // ---------------------------------------------------------------------------
  // Dimples
  // ---------------------------------------------------------------------------

  void _drawDimples(Canvas canvas, Offset center, double ballRadius, double sc) {
    for (final dimple in _dimples) {
      final projected = _project(dimple.lon, dimple.lat, center, ballRadius * 0.97);
      if (projected == null) continue;

      final depth = _frontFactor(dimple.lon, dimple.lat);
      final dimpleR = widgetSize <= 64
          ? 1.4
          : widgetSize <= 150
              ? 2.6
              : 4.5 * sc * 1.2;

      if (widgetSize > 64) {
        // Concave gradient
        final baseAlpha = 0.12 + depth * 0.18;
        final dGrad = RadialGradient(
          center: const Alignment(0.15, 0.15),
          radius: 1.0,
          colors: [
            Colors.black.withValues(alpha: baseAlpha * 0.08),
            Colors.black.withValues(alpha: baseAlpha * 0.2),
            Colors.black.withValues(alpha: baseAlpha * 0.55),
            Colors.black.withValues(alpha: baseAlpha * 1.0),
            Colors.black.withValues(alpha: baseAlpha * 0.8),
            Colors.black.withValues(alpha: baseAlpha * 0.1),
          ],
          stops: const [0.0, 0.35, 0.55, 0.75, 0.9, 1.0],
        ).createShader(Rect.fromCircle(center: projected, radius: dimpleR));

        canvas.drawCircle(
          projected,
          dimpleR,
          Paint()..shader = dGrad,
        );

        // Specular highlight (white crescent upper-left)
        if (depth > 0.15) {
          final hlR = dimpleR * (widgetSize >= 150 ? 0.55 : 0.45);
          final hlCenter = Offset(projected.dx - dimpleR * 0.25, projected.dy - dimpleR * 0.25);
          final hlAlpha = (0.18 + depth * 0.25).clamp(0.0, 0.45);
          canvas.drawCircle(
            hlCenter,
            hlR,
            Paint()
              ..shader = RadialGradient(
                colors: [
                  Colors.white.withValues(alpha: hlAlpha),
                  Colors.white.withValues(alpha: hlAlpha * 0.4),
                  Colors.white.withValues(alpha: 0.0),
                ],
              ).createShader(Rect.fromCircle(center: hlCenter, radius: hlR)),
          );
        }
      } else {
        // Small sizes — simple dots
        canvas.drawCircle(
          projected,
          dimpleR,
          Paint()..color = Colors.black.withValues(alpha: 0.14),
        );
        canvas.drawCircle(
          Offset(projected.dx - dimpleR * 0.2, projected.dy - dimpleR * 0.2),
          dimpleR * 0.35,
          Paint()..color = Colors.white.withValues(alpha: 0.12),
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // "TAG 4" label — rotates with the globe (Atlantic anchor lon=-160, lat=0)
  // ---------------------------------------------------------------------------

  void _drawTag4(Canvas canvas, Offset center, double ballRadius, double sc) {
    const anchorLon = -160.0;
    const anchorLat = 0.0;

    final projected = _project(anchorLon, anchorLat, center, ballRadius * 0.75);
    if (projected == null) return;

    final ff = _frontFactor(anchorLon, anchorLat);
    if (ff < 0.25) return;

    final tagFontSize = math.max(8.0, widgetSize * 0.09 * ff);
    final numFontSize = math.max(10.0, widgetSize * 0.14 * ff);

    // "TAG" in primary purple
    final tagPainter = TextPainter(
      text: TextSpan(
        text: 'TAG',
        style: TextStyle(
          fontFamily: 'Outfit',
          fontWeight: FontWeight.w700,
          fontSize: tagFontSize,
          color: AppColors.primary.withValues(alpha: 0.85 * ff),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    // "4" in dark
    final numPainter = TextPainter(
      text: TextSpan(
        text: '4',
        style: TextStyle(
          fontFamily: 'Outfit',
          fontWeight: FontWeight.w700,
          fontSize: numFontSize,
          color: AppColors.textDark.withValues(alpha: 0.85 * ff),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    canvas.save();
    canvas.translate(projected.dx, projected.dy);
    canvas.scale(math.max(0.3, ff), 1.0); // perspective squish

    tagPainter.paint(canvas, Offset(-tagPainter.width / 2, -tagPainter.height - 1));
    numPainter.paint(canvas, Offset(-numPainter.width / 2, 1));

    canvas.restore();
  }

  @override
  bool shouldRepaint(_GolfGlobePainter old) => rotation != old.rotation;
}

// =============================================================================
// Helper types
// =============================================================================

class _LatLon {
  const _LatLon(this.lon, this.lat);
  final double lon;
  final double lat;
}
