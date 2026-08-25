# 🏌️ All Teed Up

**Snap your booking. Your group is sorted.**

A premium Flutter golf booking management app. Photograph your tee-time confirmation, and All Teed Up uses on-device OCR to extract the details, create calendar events, and manage your group's RSVPs — all without any cloud backend.

**Price:** AED 99 (one-time purchase)
**Bundle ID:** `com.teedup.golf`

---

## ✨ Features

- 📸 **OCR Booking Capture** — Snap a photo of your golf booking confirmation. On-device ML extracts course name, date, time, and player count instantly.
- 📅 **Universal Calendar Sync** — Creates events in any calendar provider (iCloud, Google, Outlook, Exchange) via device-native APIs.
- 👥 **Smart Contact Matching** — Finds your golf buddies from device contacts. Tracks RSVPs and sends invite reminders.
- 🔔 **Background RSVP Monitoring** — Runs periodic checks for pending responses and sends local notifications for declines.
- 🔒 **Zero Backend** — All data stays on your device. No accounts, no cloud, no tracking. Privacy by design.

---

## 🛠 Tech Stack

| Layer | Technology |
|---|---|
| Framework | Flutter 3.24+ / Dart 3.5+ |
| State Management | Provider |
| OCR | Google ML Kit (on-device) |
| Calendar | device_calendar (universal) |
| Contacts | flutter_contacts (device-native) |
| Database | sqflite (local SQLite) |
| Background Tasks | workmanager |
| Notifications | flutter_local_notifications |
| Purchase | in_app_purchase |

---

## 🚀 Getting Started

### Prerequisites

- Flutter SDK `>=3.24.0`
- Dart SDK `^3.5.0`
- Xcode 15+ (for iOS)
- Android Studio / IntelliJ (for Android)
- CocoaPods (for iOS dependencies)

### Setup

```bash
# Clone the repository
git clone <repository-url>
cd teed_up

# Install dependencies
flutter pub get

# iOS: Install CocoaPods dependencies
cd ios && pod install && cd ..

# Run the app
flutter run
```

### Android

- **Min SDK:** 23 (Android 6.0)
- **Target SDK:** 34 (Android 14)
- **Compile SDK:** 34

### iOS

- **Minimum Deployment Target:** iOS 15.0

---

## 📁 Project Structure

```
teed_up/
├── lib/
│   ├── main.dart              # App entry point
│   ├── models/                # Data models (Booking, Player, etc.)
│   ├── providers/             # State management (Provider)
│   ├── screens/               # UI screens
│   ├── services/              # Business logic (OCR, calendar, contacts)
│   ├── widgets/               # Reusable UI components
│   └── utils/                 # Constants, helpers, theme
├── assets/
│   ├── images/                # App images
│   └── icons/                 # App icons
├── fonts/                     # Outfit & Inter font families
├── android/                   # Android platform project
├── ios/                       # iOS platform project
└── test/                      # Unit and widget tests
```

---

## 🎨 Brand Design Tokens

| Token | Value |
|---|---|
| Primary Purple | `#7B2D8E` |
| Deep Purple (hover) | `#5C1D6E` |
| Soft Purple (accent) | `#9B4DB8` |
| Pale Purple (bg tint) | `#F3EAF6` |
| Heading Font | Outfit (600–700) |
| Body Font | Inter (400–500) |
| Border Radius | 12px cards, 8px buttons |
| Theme | **Light only** — white backgrounds, no dark mode |

---

## 🔐 Permissions

### Android
- `READ_CALENDAR` / `WRITE_CALENDAR` — Calendar event creation
- `READ_CONTACTS` — Golf buddy lookup
- `CAMERA` — Booking photo capture
- `READ_MEDIA_IMAGES` — Gallery access for bookings
- `POST_NOTIFICATIONS` — RSVP decline alerts
- `RECEIVE_BOOT_COMPLETED` / `WAKE_LOCK` — Background task scheduling

### iOS
- Calendar access
- Contacts access
- Camera access
- Photo library access
- Notifications

---

## 🧪 Testing

```bash
# Run all tests
flutter test

# Run with coverage
flutter test --coverage
```

---

## 📄 License

Proprietary — The Artesian Group. All rights reserved.
