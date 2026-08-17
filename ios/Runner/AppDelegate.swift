import Flutter
import UIKit

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
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
