# HANDOVER TO CLAUDE CODE — All Teed Up (iOS & Android)

## Overview & Architecture Context
This handover document is created for **Claude Code** to fix underlying code bugs, state management gaps, service integrations, and performance issues in the **All Teed Up** Flutter app (`com.teedup.golf`).

### Environment & Repositories
* **Git Repository:** `https://github.com/Alasdair-svg/teed-up.git`
* **Active Branch:** `redesign/all-teed-up-v2`
* **Flutter SDK:** Flutter 3.44.9 / 3.x stable (Dart 3.x)
* **Local State / Persistence:** `sqflite` + `shared_preferences` + `provider` (`AppState`). No cloud backend / no Firebase — 100% device-local storage.
* **CI/CD Pipeline:** Fully automated GitHub Actions workflow (`.github/workflows/ios-publish.yml` and `.github/workflows/android-publish.yml`).

---

## 1. Technical Bug Fixes & Action Plan

### 1.1 Multi-Calendar Account Linking & Primary Selection (`lib/services/calendar_service.dart` & `lib/providers/app_state.dart`)
* **Problem:** The app currently reads calendar IDs using `device_calendar`, but does not provide multi-account selection, account grouping (Google vs iCloud vs Outlook), or a explicit Primary Calendar routing mechanism.
* **Technical Fix:**
  1. Update `CalendarService.getAvailableCalendars()` to group returned `Calendar` objects by `accountName` and `accountType` (e.g. `com.google`, `com.apple.icns`, `com.microsoft.office`).
  2. Extend `AppState` with:
     - `List<String> linkedCalendarIds` — All calendars enabled for event scanning / RSVP monitoring.
     - `String? primaryCalendarId` — The single default calendar used when `createGolfEvent` is called.
  3. Update `createGolfEvent` to write to `primaryCalendarId`, and update `getUpcomingRounds` / `findExistingEvent` to query all `linkedCalendarIds`.

---

### 1.2 Friends & Family Search & Freeze Fix (`lib/widgets/family_setup_section.dart` & `lib/services/contacts_service.dart`)
* **Problem:** Adding family/friends causes occasional UI freezes and unhandled state locks when typing in the contact autocomplete field.
* **Technical Fix:**
  1. In `ContactsService`, wrap all contact queries in an `compute` isolate or async stream with strict debounce (300ms) to prevent blocking the Flutter main UI thread (`UI thread lock`).
  2. Add exception handling for `PlatformException` when contact permissions are partially granted or restricted by device policy.
  3. Ensure `FamilySetupSection` uses an isolated `TextEditingController` with proper state disposal and non-blocking contact resolution.

---

### 1.3 Scan Booking OCR Pipeline & Timeout Recovery (`lib/screens/scan_screen.dart`, `lib/services/scan_service.dart`, `lib/services/booking_parser.dart`)
* **Problem:** Uploading a booking screenshot causes the app to hang indefinitely on the loading screen if Google MLKit / regex parsing stalls or throws an uncaught error.
* **Technical Fix:**
  1. In `ScanService.parseScreenshotFromFile()`, wrap the MLKit text recognition call in a strict **8-second timeout**:
     ```dart
     final RecognizedText text = await _textRecognizer
         .processImage(inputImage)
         .timeout(const Duration(seconds: 8));
     ```
  2. Catch `TimeoutException` and `ScanException`, properly dispose `inputImage` and `_textRecognizer` references, and return a structured fallback response.
  3. In `ScanScreen._processImage()`, handle errors cleanly: dismiss the processing overlay, show a clear Toast/SnackBar ("Couldn't auto-detect booking details"), and present the Manual Booking Entry form pre-filled with whatever fields were extracted before timeout.

---

### 1.4 Settings Screen Complete Implementation (`lib/screens/settings_screen.dart`)
* **Problem:** Settings screen tiles are currently placeholders or lack persistent state bindings.
* **Technical Fix:**
  1. **Default & Primary Calendar Picker:** Bind to `AppState.primaryCalendarId` and `AppState.linkedCalendarIds`.
  2. **Decline Alerts Toggle:** Ensure `AppState.setDeclineAlerts(v)` properly toggles background `RsvpMonitor` polling service.
  3. **Contact Cache Management:** Verify `_confirmClearCache()` and `_showCachedContacts()` update state reactively.
  4. **Friends & Family Persistent List:** Bind `FamilySetupSection` directly to `AppState.familyMembers` with instant SQLite/SharedPreferences persistence.
  5. **In-App Purchase / Restore:** Verify `PurchaseService.restorePurchases()` handles test/production receipts cleanly without crashing on empty store responses.

---

## 2. Codebase Reference Map
- `lib/services/calendar_service.dart` — Native calendar wrapper via `device_calendar`.
- `lib/services/contacts_service.dart` — Device contacts lookups and email matching.
- `lib/services/scan_service.dart` & `lib/services/booking_parser.dart` — OCR text recognition & parser logic.
- `lib/providers/app_state.dart` — Central app state, settings persistence & SQLite interface.
- `lib/screens/scan_screen.dart` — Booking scanner & review flow.
- `lib/screens/settings_screen.dart` — App configuration screen.
- `lib/widgets/family_setup_section.dart` — Friends & Family UI widget.

---

## 3. Handover Instructions for Claude Code
1. Clone / pull branch `redesign/all-teed-up-v2` from `https://github.com/Alasdair-svg/teed-up.git`.
2. Execute the technical bug fixes detailed above across `CalendarService`, `ScanService`, `ContactsService`, `AppState`, `ScanScreen`, and `SettingsScreen`.
3. Verify that `flutter test` passes without errors.
4. Pass the modified code back to Antigravity to push to GitHub for automated CI/CD build & store deployment (TestFlight & Google Play Internal Testing).
