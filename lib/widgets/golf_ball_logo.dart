/// Animated golf ball on a tee — the All Teed Up brand logo.
///
/// Rendered entirely via [CustomPainter] with a dimple pattern that
/// rotates around the Y-axis, giving a spinning globe effect. Uses
/// TAG brand colours from [AppColors].
///
/// Usage:
/// ```dart
/// const GolfBallLogo(size: 160, animate: true)
/// ```
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A golf ball on a tee rendered with [CustomPainter].
///
/// Set [animate] to `true` for the spinning effect, or `false` for a
/// static logo (e.g. in an app bar).
class GolfBallLogo extends StatefulWidget {
  /// Creates a [GolfBallLogo].
  const GolfBallLogo({
    super.key,
    this.size = 160,
    this.animate = true,
    this.showTee = true,
    this.showGlow = true,
  });

  /// Overall widget size (the ball diameter is roughly 70% of this).
  final double size;

  /// Whether the ball should spin.
  final bool animate;

  /// Whether to render the tee below the ball.
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
      duration: const Duration(seconds: 8),
    );
    if (widget.animate) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(GolfBallLogo oldWidget) {
    super.didUpdateWidget(oldWidget);
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
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          size: Size(widget.size, widget.size * (widget.showTee ? 1.35 : 1.0)),
          painter: _GolfBallPainter(
            rotation: _controller.value * math.pi * 2,
            showTee: widget.showTee,
            showGlow: widget.showGlow,
          ),
        );
      },
    );
  }
}

/// Custom painter that draws a golf ball with dimples and an optional tee.
class _GolfBallPainter extends CustomPainter {
  _GolfBallPainter({
    required this.rotation,
    required this.showTee,
    required this.showGlow,
  });

  final double rotation;
  final bool showTee;
  final bool showGlow;

  @override
  void paint(Canvas canvas, Size size) {
    final ballDiameter = size.width * 0.7;
    final ballRadius = ballDiameter / 2;
    final ballCenter = Offset(
      size.width / 2,
      showTee ? size.height * 0.38 : size.height / 2,
    );

    // ── Glow ──────────────────────────────────────────────────
    if (showGlow) {
      final glowPaint = Paint()
        ..shader = RadialGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.15),
            AppColors.primary.withValues(alpha: 0.05),
            AppColors.primary.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.6, 1.0],
        ).createShader(
          Rect.fromCircle(center: ballCenter, radius: ballRadius * 1.6),
        );
      canvas.drawCircle(ballCenter, ballRadius * 1.6, glowPaint);
    }

    // ── Tee ───────────────────────────────────────────────────
    if (showTee) {
      _drawTee(canvas, size, ballCenter, ballRadius);
    }

    // ── Ball body ─────────────────────────────────────────────
    final ballPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.3, -0.3),
        radius: 0.9,
        colors: [
          const Color(0xFFFFFFFF),
          const Color(0xFFF0F0F0),
          const Color(0xFFD8D8D8),
        ],
        stops: const [0.0, 0.65, 1.0],
      ).createShader(
        Rect.fromCircle(center: ballCenter, radius: ballRadius),
      );

    canvas.drawCircle(ballCenter, ballRadius, ballPaint);

    // ── Dimples ───────────────────────────────────────────────
    _drawDimples(canvas, ballCenter, ballRadius);

    // ── Specular highlight ────────────────────────────────────
    final highlightPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.4, -0.5),
        radius: 0.4,
        colors: [
          Colors.white.withValues(alpha: 0.7),
          Colors.white.withValues(alpha: 0.0),
        ],
      ).createShader(
        Rect.fromCircle(center: ballCenter, radius: ballRadius),
      );
    canvas.drawCircle(ballCenter, ballRadius, highlightPaint);

    // ── Rim outline ───────────────────────────────────────────
    final rimPaint = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(ballCenter, ballRadius, rimPaint);
  }

  void _drawTee(Canvas canvas, Size size, Offset ballCenter, double ballRadius) {
    final teeTopY = ballCenter.dy + ballRadius - 2;
    final teeBottomY = size.height - 4;
    final teeCenterX = ballCenter.dx;

    // Tee cup (curved top that holds the ball)
    final cupPath = Path();
    final cupWidth = ballRadius * 0.6;
    final cupHeight = ballRadius * 0.15;
    cupPath.moveTo(teeCenterX - cupWidth, teeTopY);
    cupPath.quadraticBezierTo(
      teeCenterX,
      teeTopY + cupHeight,
      teeCenterX + cupWidth,
      teeTopY,
    );

    final cupPaint = Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(cupPath, cupPaint);

    // Tee shaft (tapered)
    final shaftTopWidth = ballRadius * 0.08;
    final shaftBottomWidth = ballRadius * 0.18;

    final shaftPath = Path()
      ..moveTo(teeCenterX - shaftTopWidth, teeTopY + cupHeight - 1)
      ..lineTo(teeCenterX - shaftBottomWidth, teeBottomY)
      ..lineTo(teeCenterX + shaftBottomWidth, teeBottomY)
      ..lineTo(teeCenterX + shaftTopWidth, teeTopY + cupHeight - 1)
      ..close();

    final shaftPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          AppColors.primary,
          AppColors.deepPurple,
        ],
      ).createShader(
        Rect.fromLTRB(
          teeCenterX - shaftBottomWidth,
          teeTopY,
          teeCenterX + shaftBottomWidth,
          teeBottomY,
        ),
      );
    canvas.drawPath(shaftPath, shaftPaint);

    // Tee base
    final basePaint = Paint()
      ..color = AppColors.deepPurple
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(teeCenterX - shaftBottomWidth * 1.3, teeBottomY),
      Offset(teeCenterX + shaftBottomWidth * 1.3, teeBottomY),
      basePaint,
    );
  }

  void _drawDimples(Canvas canvas, Offset center, double radius) {
    // Generate dimples using a Fibonacci sphere distribution
    const dimpleCount = 92;
    final dimpleRadius = radius * 0.065;

    final dimpleShadowPaint = Paint()..style = PaintingStyle.fill;

    for (var i = 0; i < dimpleCount; i++) {
      // Fibonacci sphere point distribution
      final phi = math.acos(1 - 2 * (i + 0.5) / dimpleCount);
      final theta = math.pi * (1 + math.sqrt(5)) * i + rotation;

      // 3D → 2D orthographic projection (Y-axis rotation)
      final x3d = math.sin(phi) * math.cos(theta);
      final y3d = math.cos(phi);
      final z3d = math.sin(phi) * math.sin(theta);

      // Only draw front-facing dimples
      if (z3d < -0.05) continue;

      final screenX = center.dx + x3d * radius * 0.85;
      final screenY = center.dy - y3d * radius * 0.85;

      // Scale dimple by depth — closer = larger
      final depthScale = 0.5 + z3d * 0.5;
      final scaledRadius = dimpleRadius * depthScale;

      if (scaledRadius < 0.8) continue;

      // Dimple colour: TAG purple shadow with depth-based alpha
      final alpha = (0.08 + z3d * 0.12).clamp(0.0, 0.25);
      dimpleShadowPaint.color = AppColors.primary.withValues(alpha: alpha);

      // Dimple indent effect — slightly offset inner shadow
      canvas.drawCircle(
        Offset(screenX + 0.3, screenY + 0.5),
        scaledRadius,
        dimpleShadowPaint,
      );

      // Bright rim on upper-left edge for 3D indent illusion
      if (scaledRadius > 1.5) {
        final rimAlpha = (0.06 + z3d * 0.08).clamp(0.0, 0.15);
        final rimHighlight = Paint()
          ..color = Colors.white.withValues(alpha: rimAlpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.6;
        canvas.drawArc(
          Rect.fromCircle(
            center: Offset(screenX, screenY),
            radius: scaledRadius,
          ),
          -math.pi * 0.8, // Start angle (upper-left)
          math.pi * 0.6, // Sweep angle
          false,
          rimHighlight,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_GolfBallPainter oldDelegate) =>
      rotation != oldDelegate.rotation;
}
