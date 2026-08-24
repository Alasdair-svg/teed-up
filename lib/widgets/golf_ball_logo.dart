/// Animated golf-globe-on-a-tee — the All Teed Up brand logo.
///
/// The spinning ball is a pre-rendered 72-frame WebP sequence
/// (assets/images/golf_ball_frames/), not a live CustomPainter. Two earlier
/// rounds of tuning a real-time Dart renderer (rotation speed, dimple-count
/// tiering, shader caching) still wasn't smooth or detailed enough on real
/// Android hardware, and its hand-simplified 16-continent coastline data was
/// visibly cruder than the reference. The frames here are captured directly
/// from that reference technique (real 110m-resolution world-atlas coastline
/// data, full graticule, same dimple/specular treatment) via a one-off
/// generation harness — see scratchpad history for that script — so this
/// guarantees the same visual quality regardless of device, since Flutter is
/// just blitting a cached image rather than computing sphere geometry every
/// frame. The tee, glow, and drop-shadow don't rotate, so they stay as cheap
/// static Flutter draws layered under/behind the frame sequence.
///
/// Usage:
/// ```dart
/// const GolfBallLogo(size: 160, animate: true)
/// ```
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Total frames in the baked rotation sequence (5deg apart, 360deg total).
const int _kFrameCount = 72;

/// Native resolution of each source frame — decode requests are capped here.
const int _kFrameSourceSize = 900;

String _frameAsset(int index) {
  final i = index.toString().padLeft(3, '0');
  return 'assets/images/golf_ball_frames/frame_$i.webp';
}

/// A golf ball on a tee — spinning frame sequence + static tee/glow/shadow.
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
    // Matches the reference's own pace (0.15deg/frame at ~60fps = 9deg/s =
    // 40s/revolution) — a deliberate, verified match, not a guess.
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 40),
    );
    if (widget.animate) _controller.repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Frame images decode asynchronously (unlike the old CustomPainter,
    // which drew synchronously) — precache frame 0 so the very first
    // build doesn't show a blank gap before it's ready.
    precacheImage(AssetImage(_frameAsset(0)), context);
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
    // The ball fills exactly `size` — the source frames were generated
    // edge-to-edge in their canvas, so displaying at `size` makes `size`
    // the ball's actual diameter. The tee overlaps up into the ball's
    // bottom slightly so it reads as "seated in the cup" rather than
    // floating below it.
    final teeOverlap = widget.showTee ? widget.size * 0.05 : 0.0;
    final teeExtra = widget.showTee ? widget.size * 0.28 : 0.0;

    // Decode each frame only as large as it'll ever actually be displayed
    // at, capped at the source resolution — keeps the whole 72-frame
    // sequence's decoded memory footprint proportional to on-screen size
    // instead of always paying for a 900x900 decode.
    final dpr = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 2.0;
    final decodeSize = (widget.size * dpr).round().clamp(1, _kFrameSourceSize);

    return SizedBox(
      width: widget.size,
      height: widget.size + teeExtra,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          // Glow — static, position-fixed, cheap, centered on the ball.
          if (widget.showGlow)
            Positioned(
              top: widget.size / 2 - widget.size * 0.85,
              child: Container(
                width: widget.size * 1.7,
                height: widget.size * 1.7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.primary.withValues(alpha: 0.18),
                      AppColors.primary.withValues(alpha: 0.06),
                      AppColors.primary.withValues(alpha: 0.0),
                    ],
                    stops: const [0.0, 0.55, 1.0],
                  ),
                ),
              ),
            ),

          // Drop-shadow — static BoxShadow, painted once by the framework,
          // not re-blurred on every animation frame. Centered on the ball.
          Positioned(
            top: 2,
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

          // Tee — static, drawn once, doesn't rotate. Overlaps up into the
          // ball's bottom by teeOverlap.
          if (widget.showTee)
            Positioned(
              top: widget.size - teeOverlap,
              child: CustomPaint(
                size: Size(widget.size, teeExtra + teeOverlap),
                painter: _TeePainter(
                  ballCenterX: widget.size / 2,
                  sc: widget.size / 600,
                ),
              ),
            ),

          // The spinning ball — cached WebP frame sequence.
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final frame =
                  (_controller.value * _kFrameCount).floor() % _kFrameCount;
              return Image.asset(
                _frameAsset(frame),
                width: widget.size,
                height: widget.size,
                cacheWidth: decodeSize,
                cacheHeight: decodeSize,
                gaplessPlayback: true,
                filterQuality: FilterQuality.medium,
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Wooden tee (warm brown gradient) — the only part of the logo that never
/// rotates, so it stays a lightweight direct paint rather than baked frames.
class _TeePainter extends CustomPainter {
  _TeePainter({required this.ballCenterX, required this.sc});

  final double ballCenterX;
  final double sc;

  @override
  void paint(Canvas canvas, Size size) {
    const teeTop = 0.0;
    final teeWidth = math.max(4.0, 12 * sc);
    final teeStemW = math.max(2.0, 4 * sc);
    final teeStemH = math.max(6.0, size.height * 0.55);
    final teeBaseH = math.max(2.0, 4 * sc);
    final cx = ballCenterX;

    final teeGrad = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFFC49A6C), Color(0xFFB8895C), Color(0xFF8B6914)],
      stops: [0.0, 0.3, 1.0],
    ).createShader(Rect.fromLTWH(cx - teeWidth / 2, teeTop, teeWidth, teeStemH + teeBaseH + 4));

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

  @override
  bool shouldRepaint(_TeePainter old) => false;
}
