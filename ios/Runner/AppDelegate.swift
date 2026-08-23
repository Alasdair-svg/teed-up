import Flutter
import UIKit
import workmanager_apple

// Uses the classic (pre-implicit-engine) registration pattern deliberately —
// this app has no Scene manifest and needs no multi-window support, and the
// newer `didInitializeImplicitFlutterEngine` hook fires before `window` is
// guaranteed to exist. flutter_contacts 1.1.9+2's plugin registration force-
// unwraps `UIApplication.shared.delegate!.window!!.rootViewController!`,
// which crashed on launch under that timing (fatal error at
// SwiftFlutterContactsPlugin.swift:435, reproduced in the iOS Simulator).
// This is the pattern flutter_contacts (and most older plugins) assume.
@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // BGTaskScheduler requires this identifier to be registered natively
    // before the app finishes launching — the Dart-side Workmanager().
    // initialize()/registerPeriodicTask() calls in RsvpMonitor happen well
    // after that window, so without this call BGTaskScheduler.submit()
    // hits an unrecoverable NSAssertion ("submission without registration")
    // and crashes the whole app on launch the moment the identifier here
    // actually matches Info.plist's BGTaskSchedulerPermittedIdentifiers.
    // Identifier and frequency must match RsvpMonitor.taskName and
    // _intervalMinutes in lib/services/rsvp_monitor.dart exactly.
    SwiftWorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "com.teedup.rsvp_monitor",
      frequency: NSNumber(value: 15 * 60)
    )

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
