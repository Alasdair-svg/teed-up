// The build stamp exists so a stale install is obvious at a glance. If it
// silently renders nothing, it is worse than useless — it looks like the
// build is old when it may not be.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:all_teed_up/widgets/build_stamp.dart';

void main() {
  testWidgets('renders version and build number from the bundle',
      (tester) async {
    PackageInfo.setMockInitialValues(
      appName: 'All Teed Up',
      packageName: 'com.teedup.golf',
      version: '1.4.1',
      buildNumber: '33',
      buildSignature: '',
    );

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: BuildStamp())),
    );
    await tester.pumpAndSettle();

    expect(find.text('v1.4.1 (33)'), findsOneWidget);
  });
}
