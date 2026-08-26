/// Small, always-visible build stamp.
///
/// Exists because a whole test cycle was wasted on a stale build: the Play
/// Store served an older version than the track advertised, and neither the
/// user nor I could tell which code was actually running without digging
/// into Settings. A build number on the first screen makes that a glance
/// rather than an investigation.
library;

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../theme/app_theme.dart';

/// Renders "v1.4.0 (32)" from the running bundle. Shows nothing until the
/// platform responds, so it can never display a wrong or stale value.
class BuildStamp extends StatefulWidget {
  /// Creates a [BuildStamp].
  const BuildStamp({super.key, this.align = TextAlign.center});

  /// Text alignment, for callers placing it in a row or a footer.
  final TextAlign align;

  @override
  State<BuildStamp> createState() => _BuildStampState();
}

class _BuildStampState extends State<BuildStamp> {
  String? _label;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (!mounted) return;
      setState(() => _label = 'v${info.version} (${info.buildNumber})');
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final label = _label;
    if (label == null) return const SizedBox.shrink();
    return Text(
      label,
      textAlign: widget.align,
      style: const TextStyle(
        fontFamily: 'Inter',
        fontSize: 11,
        letterSpacing: 0.4,
        color: AppColors.textMuted,
      ),
    );
  }
}
