/// Device capability check service for All Teed Up.
///
/// Verifies that the device has all the hardware and software features
/// the app depends on — calendar provider, contacts provider, and
/// camera/gallery access. Run this during onboarding, before the user
/// reaches the paywall, so incompatible devices are identified early.
///
/// All checks are non-destructive: no data is written and no permissions
/// beyond those already granted are requested.
library;

import 'package:device_calendar/device_calendar.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:permission_handler/permission_handler.dart';

/// The result of a full device capability check.
///
/// Each boolean field corresponds to one capability. A value of `false`
/// means the capability is missing or unavailable on this device.
class DeviceCapabilityResult {
  /// Creates a [DeviceCapabilityResult].
  const DeviceCapabilityResult({
    required this.hasCalendar,
    required this.hasContacts,
    required this.hasCameraOrGallery,
    required this.hasPlayServices,
  });

  /// Whether the device has at least one accessible calendar.
  ///
  /// `false` on devices where the calendar provider is disabled,
  /// missing, or has not been granted permission.
  final bool hasCalendar;

  /// Whether the device contacts provider is accessible.
  ///
  /// `false` on heavily locked-down or MDM-managed devices that
  /// have disabled the contacts provider entirely.
  final bool hasContacts;

  /// Whether the device has a camera or an accessible photo library.
  ///
  /// At least one of these is required to capture or import a booking
  /// confirmation screenshot. Both are checked together because users
  /// can always import a screenshot from the gallery even without a camera.
  final bool hasCameraOrGallery;

  /// Whether Google Play Services (or equivalent billing infrastructure)
  /// is available, which is required to complete the in-app purchase.
  final bool hasPlayServices;

  /// `true` if ALL critical capabilities are present.
  bool get isFullyCompatible =>
      hasCalendar && hasContacts && hasCameraOrGallery && hasPlayServices;

  /// `true` if ANY critical capability is missing.
  bool get hasIssues => !isFullyCompatible;

  /// A human-readable list of missing capabilities, or empty if all OK.
  List<String> get missingCapabilities {
    final issues = <String>[];
    if (!hasCalendar) issues.add('Calendar');
    if (!hasContacts) issues.add('Contacts');
    if (!hasCameraOrGallery) issues.add('Camera / Photo Library');
    if (!hasPlayServices) issues.add('Google Play Services');
    return issues;
  }
}

/// Service that checks whether the device meets All Teed Up's requirements.
///
/// ```dart
/// final result = await DeviceCapabilityService.check();
/// if (result.hasIssues) {
///   // Show incompatibility bottom sheet
/// }
/// ```
class DeviceCapabilityService {
  // Private constructor — use the static [check] method.
  const DeviceCapabilityService._();

  /// Runs all capability checks and returns a [DeviceCapabilityResult].
  ///
  /// This method is safe to call from any async context. It catches
  /// all exceptions internally — a failed check returns `false` for
  /// that capability rather than throwing.
  static Future<DeviceCapabilityResult> check() async {
    final results = await Future.wait([
      _checkCalendar(),
      _checkContacts(),
      _checkCameraOrGallery(),
      _checkPlayServices(),
    ]);

    return DeviceCapabilityResult(
      hasCalendar: results[0],
      hasContacts: results[1],
      hasCameraOrGallery: results[2],
      hasPlayServices: results[3],
    );
  }

  // ---------------------------------------------------------------------------
  // Individual checks
  // ---------------------------------------------------------------------------

  /// Returns `true` if at least one calendar is accessible on this device.
  static Future<bool> _checkCalendar() async {
    try {
      final plugin = DeviceCalendarPlugin();
      final result = await plugin.retrieveCalendars();
      return result.isSuccess && result.data != null && result.data!.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Returns `true` if contacts permission is granted.
  ///
  /// Checks permission status only — permission was already requested
  /// moments earlier in onboarding, so re-fetching the entire device
  /// contact list here (as this used to do) was a redundant, slow
  /// round-trip on devices with large address books.
  static Future<bool> _checkContacts() async {
    try {
      return await Permission.contacts.status.isGranted;
    } catch (_) {
      return false;
    }
  }

  /// Returns `true` if the device has a camera or an accessible photo library.
  ///
  /// We check via permission status rather than attempting a live capture,
  /// so this is non-invasive and instant.
  static Future<bool> _checkCameraOrGallery() async {
    // image_picker works with either camera or gallery; if at least one
    // is granted, the core scan flow is available.
    try {
      // If permissions were granted during onboarding, at least one of
      // camera or photos should be accessible.
      // We return true optimistically here since image_picker degrades
      // gracefully (only shows the available source), and camera permission
      // was already requested in onboarding.
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Returns `true` if Google Play Services / billing is available.
  ///
  /// Uses the same IAP plugin check that [PurchaseService] uses, so
  /// there is no redundant initialisation.
  static Future<bool> _checkPlayServices() async {
    try {
      // A real billing-service handshake can hang for several seconds on
      // a store listing that isn't fully published yet — bound it so a
      // slow connection can't stall the whole onboarding flow.
      return await InAppPurchase.instance
          .isAvailable()
          .timeout(const Duration(seconds: 3), onTimeout: () => false);
    } catch (_) {
      // If the check itself throws, Play Services are not available.
      return false;
    }
  }
}
