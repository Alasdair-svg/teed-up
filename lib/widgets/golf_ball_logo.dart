/// Animated golf-globe-on-a-tee — the All Teed Up brand logo.
///
/// Ported from `golf-globe-brand.js` v3.0. Renders a white golf ball with:
///   - TAG-purple landmass silhouettes (simplified continent outlines)
///   - 392-dimple Fibonacci distribution with concave gradient + specular highlight
///   - Equator and meridian seam lines
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
// Landmass outlines (lon/lat pairs, closed polygons)
//
// Real coastline data — simplified (Douglas-Peucker) from Natural Earth's
// 110m-resolution land boundaries via the world-atlas dataset (public
// domain), not hand-drawn approximations. The 16 largest landmasses by
// bounding-box area are kept (~400 points total, comparable budget to the
// existing 392-dimple field) — enough detail to read as real continents at
// the globe's render sizes without adding per-frame projection cost.
// =============================================================================

/// A list of landmass outlines, each as a list of [lon, lat] pairs.
const List<List<List<double>>> _kContinents = [
  [
    [-180.0, 69.0], [180.0, 65.0], [156.8, 51.0], [164.5, 62.6], [135.1, 54.7], [141.4, 52.2],
    [129.1, 35.1], [118.0, 39.2], [121.7, 28.2], [105.9, 19.8], [105.2, 8.6], [100.1, 13.4],
    [104.2, 1.3], [91.4, 22.8], [77.5, 8.0], [66.4, 25.4], [48.0, 30.0], [59.8, 22.3],
    [43.5, 12.6], [32.4, 29.9], [51.0, 10.6], [35.5, -24.1], [19.6, -34.8], [9.4, 3.7],
    [-9.0, 4.8], [-17.0, 21.9], [-5.9, 35.8], [33.8, 31.0], [26.2, 39.5], [41.7, 42.0],
    [30.7, 46.6], [22.5, 36.4], [13.1, 45.7], [16.1, 38.0], [8.9, 44.4], [-8.9, 36.9],
    [8.5, 57.1], [29.1, 60.0], [5.9, 62.6], [24.5, 71.0], [37.0, 63.9], [72.6, 72.8],
    [72.4, 66.2], [104.4, 77.7], [178.6, 69.4], [-180.0, 69.0],
  ],
  [
    [-90.5, 69.5], [-81.3, 67.6], [-93.2, 62.0], [-92.3, 57.1], [-79.9, 51.2], [-78.1, 62.3],
    [-73.8, 62.4], [-55.7, 52.1], [-71.1, 46.8], [-59.8, 45.9], [-76.4, 39.1], [-80.4, 25.2],
    [-84.1, 30.1], [-96.6, 28.3], [-96.3, 19.3], [-87.1, 21.5], [-88.9, 15.9], [-83.4, 15.3],
    [-81.4, 8.8], [-61.9, 10.7], [-34.7, -7.3], [-40.9, -21.9], [-58.4, -33.9], [-71.0, -53.8],
    [-75.6, -46.6], [-70.2, -19.8], [-81.3, -6.1], [-78.2, 8.3], [-103.5, 18.3], [-114.8, 31.8],
    [-109.4, 23.2], [-112.2, 24.7], [-124.4, 40.3], [-122.8, 49.0], [-134.1, 58.1], [-150.6, 61.3],
    [-164.8, 54.4], [-157.0, 58.9], [-168.1, 65.7], [-156.6, 71.4], [-90.5, 69.5],
  ],
  [
    [-180.0, -84.7], [-68.9, -73.0], [-57.8, -63.3], [-78.0, -79.2], [135.1, -65.3], [171.2, -71.7],
    [159.8, -80.9], [178.3, -84.5], [-180.0, -84.7],
  ],
  [
    [-27.1, 83.5], [-20.8, 82.7], [-31.9, 82.2], [-12.2, 81.3], [-20.0, 80.2], [-17.7, 80.1],
    [-19.7, 78.8], [-18.5, 77.0], [-21.7, 76.6], [-19.4, 74.3], [-24.8, 72.3], [-21.8, 70.7],
    [-25.5, 71.4], [-26.4, 70.2], [-22.3, 70.1], [-39.8, 65.5], [-43.4, 60.1], [-48.3, 60.9],
    [-51.6, 63.6], [-54.0, 67.2], [-50.9, 69.9], [-54.7, 69.6], [-51.4, 70.6], [-55.8, 71.7],
    [-54.7, 72.6], [-58.6, 75.5], [-68.5, 76.1], [-71.4, 77.0], [-66.8, 77.4], [-73.3, 78.0],
    [-65.7, 79.4], [-68.0, 80.1], [-62.6, 81.8], [-27.1, 83.5],
  ],
  [
    [143.6, -13.8], [145.4, -15.0], [146.4, -19.0], [148.8, -20.4], [153.1, -26.1], [153.1, -30.9],
    [150.0, -37.4], [146.3, -39.0], [145.0, -37.9], [143.6, -38.8], [140.6, -38.0], [138.1, -35.6],
    [138.2, -34.4], [136.8, -35.3], [137.8, -32.9], [136.0, -34.9], [134.3, -32.6], [131.3, -31.5],
    [118.0, -35.1], [115.0, -34.2], [115.7, -31.6], [113.3, -26.1], [114.2, -26.3], [113.4, -24.4],
    [114.1, -21.8], [114.2, -22.5], [120.9, -19.7], [125.7, -14.2], [129.6, -15.0], [130.6, -12.5],
    [132.6, -12.1], [132.4, -11.1], [136.5, -11.9], [135.5, -15.0], [140.2, -17.7], [142.5, -10.7],
    [143.6, -13.8],
  ],
  [
    [-180.0, -16.6], [179.4, -16.4], [-180.0, -16.6],
  ],
  [
    [-86.6, 73.2], [-85.8, 72.5], [-82.3, 73.8], [-80.6, 72.7], [-80.8, 72.1], [-77.8, 72.8],
    [-74.1, 71.3], [-72.2, 71.6], [-67.0, 69.2], [-68.8, 68.7], [-61.9, 66.9], [-63.9, 65.0],
    [-68.0, 66.3], [-68.1, 65.7], [-64.7, 63.4], [-65.0, 62.7], [-68.8, 63.7], [-66.2, 61.9],
    [-71.0, 62.9], [-74.8, 64.7], [-77.7, 64.2], [-78.6, 64.6], [-77.9, 65.3], [-74.0, 65.5],
    [-72.9, 67.7], [-79.0, 70.2], [-84.9, 70.0], [-89.9, 71.2], [-90.2, 72.2], [-89.4, 73.1],
    [-85.8, 73.8], [-86.6, 73.2],
  ],
  [
    [-180.0, 71.5], [180.0, 70.8], [-180.0, 71.5],
  ],
  [
    [-68.5, 83.1], [-61.9, 82.6], [-67.7, 81.5], [-65.5, 81.5], [-71.2, 79.8], [-76.9, 79.3],
    [-75.4, 78.5], [-79.8, 77.2], [-77.9, 76.8], [-80.6, 76.2], [-89.5, 76.5], [-87.8, 77.2],
    [-88.3, 77.9], [-85.0, 77.5], [-88.0, 78.4], [-85.1, 79.3], [-86.9, 80.3], [-81.8, 80.5],
    [-87.6, 80.5], [-91.6, 81.9], [-79.3, 83.1], [-68.5, 83.1],
  ],
  [
    [134.1, -1.2], [134.4, -2.8], [135.5, -3.4], [136.3, -2.3], [138.3, -1.7], [144.6, -3.9],
    [146.0, -5.5], [147.6, -6.1], [147.9, -6.6], [147.0, -6.7], [147.2, -7.4], [150.7, -10.6],
    [147.9, -10.1], [146.0, -8.1], [144.7, -7.6], [143.3, -8.2], [143.4, -9.0], [142.6, -9.3],
    [139.1, -8.1], [137.6, -8.4], [138.7, -7.3], [137.9, -5.4], [133.7, -3.5], [133.0, -4.1],
    [132.0, -2.8], [133.7, -2.2], [132.2, -2.2], [130.5, -0.9], [132.4, -0.4], [134.1, -1.2],
  ],
  [
    [141.0, 37.1], [140.6, 36.3], [140.8, 35.8], [140.3, 35.1], [139.0, 34.7], [137.2, 34.6],
    [135.8, 33.5], [135.1, 33.8], [135.1, 34.6], [131.0, 33.9], [132.0, 33.1], [131.3, 31.5],
    [130.7, 31.0], [130.2, 31.4], [130.4, 32.3], [129.4, 33.3], [130.4, 33.6], [132.6, 35.4],
    [134.6, 35.7], [135.7, 35.5], [136.7, 37.3], [137.4, 36.8], [139.4, 38.2], [140.1, 39.4],
    [139.9, 40.6], [140.3, 41.2], [141.4, 41.4], [141.9, 39.2], [141.0, 38.2], [141.0, 37.1],
  ],
  [
    [105.8, -5.9], [104.7, -5.9], [102.6, -4.2], [99.3, 0.2], [98.6, 1.8], [95.4, 5.0],
    [95.3, 5.5], [97.5, 5.2], [100.6, 2.1], [101.7, 2.1], [103.8, 0.1], [103.4, -0.7],
    [104.4, -1.1], [104.9, -2.3], [105.6, -2.4], [106.1, -3.1], [105.8, -5.9],
  ],
  [
    [117.9, 1.8], [119.0, 0.9], [117.8, 0.8], [117.5, 0.1], [117.5, -0.8], [116.6, -1.5],
    [116.1, -4.0], [116.0, -3.7], [114.9, -4.1], [114.5, -3.5], [113.3, -3.1], [112.1, -3.5],
    [111.7, -3.0], [110.2, -2.9], [110.1, -1.6], [109.1, -0.5], [109.1, 1.3], [109.7, 2.0],
    [110.4, 1.7], [111.2, 1.9], [111.4, 2.7], [113.0, 3.1], [116.7, 6.9], [117.1, 6.9],
    [117.7, 6.0], [119.2, 5.4], [119.1, 5.0], [118.4, 5.0], [118.6, 4.5], [117.9, 4.1],
    [117.3, 3.2], [118.0, 2.3], [117.9, 1.8],
  ],
  [
    [57.5, 70.7], [53.7, 70.8], [53.4, 71.2], [51.6, 71.5], [51.5, 72.0], [54.4, 73.6],
    [53.5, 73.8], [55.9, 74.6], [55.6, 75.1], [66.2, 76.8], [68.2, 76.9], [68.9, 76.5],
    [58.5, 74.3], [55.4, 72.4], [55.6, 71.5], [57.5, 70.7],
  ],
  [
    [50.1, -13.6], [50.4, -15.7], [50.2, -16.0], [49.9, -15.4], [49.7, -15.7], [49.8, -16.9],
    [47.1, -24.9], [45.4, -25.6], [44.0, -25.0], [43.3, -22.1], [44.4, -20.1], [44.0, -17.4],
    [44.4, -16.2], [46.3, -15.8], [47.7, -14.6], [47.9, -13.7], [48.3, -13.8], [49.2, -12.0],
    [50.1, -13.6],
  ],
  [
    [-114.2, 73.1], [-114.7, 72.7], [-112.4, 73.0], [-111.1, 72.5], [-109.9, 73.0], [-108.2, 71.7],
    [-107.7, 72.1], [-108.4, 73.1], [-106.5, 73.1], [-105.4, 72.7], [-104.5, 71.0], [-101.0, 70.0],
    [-101.1, 69.6], [-102.7, 69.5], [-102.1, 69.1], [-102.4, 68.8], [-106.0, 69.2], [-113.3, 68.5],
    [-113.9, 69.0], [-116.1, 69.2], [-117.3, 70.0], [-112.4, 70.4], [-117.9, 70.5], [-118.4, 70.9],
    [-116.1, 71.3], [-119.4, 71.6], [-117.9, 72.7], [-114.2, 73.1],
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
    final teeSpace = widget.showTee ? (widget.size / 2 - 2) * 0.2 : 0.0;

    // Ball drop-shadow as a static BoxShadow (painted once by the framework,
    // not re-blurred on every animation frame inside CustomPainter.paint —
    // spec C6's performance note: avoid live per-frame blur passes).
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
        AnimatedBuilder(
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

  // Fixed axial tilt applied on top of the animated spin, matching the TAG
  // brand globe's orientation (its D3 rotation is [lambda, phi, 0] with
  // phi=-15deg fixed while lambda spins) so the ball reads as a globe on a
  // tilted axis rather than spinning flat.
  static const double _axialTilt = -18 * math.pi / 180;

  /// Projects [lon]/[lat] (degrees) to screen [Offset] given ball [center] and
  /// [radius]. Returns null if the point is on the back face.
  Offset? _project(double lon, double lat, Offset center, double radius) {
    final (x, y, z) = _rotatedPoint(lon, lat);

    if (z < -0.05) return null; // back-facing — cull

    return Offset(
      center.dx + x * radius,
      center.dy - y * radius,
    );
  }

  /// Returns how "front-facing" a point is: 1.0 = dead-centre, 0.0 = edge.
  double _frontFactor(double lon, double lat) {
    final (_, _, z) = _rotatedPoint(lon, lat);
    return z.clamp(0.0, 1.0);
  }

  /// Sphere point for [lon]/[lat] after the animated spin and fixed tilt.
  (double, double, double) _rotatedPoint(double lon, double lat) {
    final lonR = lon * math.pi / 180;
    final latR = lat * math.pi / 180;
    final rotLon = lonR + rotation;

    final x = math.cos(latR) * math.cos(rotLon);
    final y = math.sin(latR);
    final z = math.cos(latR) * math.sin(rotLon);

    final tiltedY = y * math.cos(_axialTilt) - z * math.sin(_axialTilt);
    final tiltedZ = y * math.sin(_axialTilt) + z * math.cos(_axialTilt);

    return (x, tiltedY, tiltedZ);
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

    // Ball drop-shadow is painted once by the framework as a static BoxShadow
    // in GolfBallLogo.build — deliberately NOT a MaskFilter.blur here, since
    // that would re-run the blur on every animation frame (spec C6).

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

    // ── Fresnel rim-light ────────────────────────────────────────────────────
    // A stroked ring whose gradient is brightest along the illuminated
    // (top-left) edge and fades elsewhere, approximating the way light grazes
    // a sphere's silhouette. A single precomputed sweep gradient — no blur.
    if (widgetSize > 64) {
      final rimWidth = math.max(1.2, ballRadius * 0.045);
      final rimPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = rimWidth
        ..shader = SweepGradient(
          startAngle: 0,
          endAngle: math.pi * 2,
          transform: const GradientRotation(-2.6),
          colors: [
            Colors.white.withValues(alpha: 0.55),
            Colors.white.withValues(alpha: 0.0),
            Colors.white.withValues(alpha: 0.0),
            AppColors.primary.withValues(alpha: 0.12),
            Colors.white.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.22, 0.55, 0.78, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: ballRadius));
      canvas.drawCircle(center, ballRadius - rimWidth / 2, rimPaint);
    }
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
      ..color = AppColors.primary.withValues(alpha: 0.92)
      ..isAntiAlias = true;

    // Two-pass shoreline stroke: a wider, softer dark-purple pass underneath
    // gives the coastline a bit of depth, then a crisp thin purple pass on
    // top keeps the edge sharp — no blur filter involved (spec C6).
    final shoreSoft = Paint()
      ..color = AppColors.deepPurple.withValues(alpha: 0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    final shoreCrisp = Paint()
      ..color = AppColors.deepPurple.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.4
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

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
      canvas.drawPath(path, shoreSoft);
      canvas.drawPath(path, shoreCrisp);
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
