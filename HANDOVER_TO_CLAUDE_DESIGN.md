# HANDOVER TO CLAUDE DESIGN — All Teed Up (iOS & Android)

## Overview & Context
This handover document is created for **Claude Design** to address user feedback regarding the visual fidelity, UI components, interaction design, and overall UX polish for the **All Teed Up** Flutter app (`com.teedup.golf`). 

The app automates golf tee-time calendar invites across iOS and Android without backend cloud dependencies. The core branding requirement is reproducing The Artesian Group (TAG) signature 3D spinning globe aesthetic transformed into a premium white golf ball with purple landmasses and dimples.

---

## 1. Primary Design Issues & Action Items

### 1.1 3D Golf Ball Spinning Logo Redesign (`lib/widgets/golf_ball_logo.dart`)
* **Current Implementation:** Built using a CustomPainter (`_GolfGlobePainter`) with 7 hardcoded 2D orthographic polygons (8–11 coordinates per continent). 
* **User Feedback:** Landmasses render in a very low-resolution, blocky, and unprofessional manner; spinning animation lacks depth and texture.
* **Design Action Plan:**
  1. **High-Fidelity Vector Outlines:** Replace the low-poly `_kContinents` list with high-density GeoJSON/SVG vector path datasets (Natural Earth 110m or 50m resolution mapped to latitude/longitude curve points).
  2. **3D Visual Depth & Lighting:**
     - Add smooth anti-aliased shoreline borders with a subtle outer glow (#7B2D8E / #5C1D6E).
     - Enhance the 392 dimples with a 3D spherical shading curve, subtle specular top-left highlight, and soft spherical rim lighting.
     - Implement proper perspective curvature (equator and meridian seam lines with depth squish) when rotating.
  3. **Alternative Flutter Render Strategy:** If 2D CustomPaint remains too flat, evaluate a high-res pre-rendered 60fps sprite-sheet/Lottie animation or Flutter 3D shader (FragmentProgram) that maps high-res TAG purple textures onto a 3D sphere mesh.

---

### 1.2 Multi-Calendar Account & Primary Calendar Selection UX (`lib/screens/onboarding_screen.dart` & `lib/screens/settings_screen.dart`)
* **Current Implementation:** Permission screen requests calendar access and immediately jumps to Family setup without displaying an account selection interface.
* **User Feedback:** Does not allow selecting multiple calendar accounts (Google, iCloud, Outlook, Exchange) or designating a Primary Calendar.
* **Design Action Plan:**
  1. **New Calendar Selection Screen / Component:**
     - Design a clean, structured Calendar Account Linker card system showing discovered native calendar accounts grouped by provider icon (Apple iCloud, Google Workspace, Microsoft Outlook/Exchange, CalDAV).
     - Include toggle switches to select which calendar accounts are linked.
     - Add a prominent "Primary Calendar" badge picker radio/card selection so users explicitly choose where tee-time events are written by default.
  2. **Permission Step Integration:** Introduce the Calendar Selector interface immediately after permission approval during Onboarding (Step 1b) and as a top-level section in Settings.

---

### 1.3 Friends & Family Setup UI & Freeze Prevention (`lib/widgets/family_setup_section.dart`)
* **Current Implementation:** Input fields with inline contact autocomplete.
* **User Feedback:** Adding friends and family is unresponsive, with periodic UI freezes.
* **Design Action Plan:**
  1. **Optimized Search & Chip Interface:**
     - Design an explicit modal contact picker sheet with search debounce loading states (skeleton loaders).
     - Display clear contact avatars, names, and email badges with explicit "+ Add" and "Remove" affordances.
     - Limit display to 5 slots with clear visual progress counters (`2 of 5 added`).

---

### 1.4 Scan Booking Processing & Feedback State (`lib/screens/scan_screen.dart`)
* **Current Implementation:** Upload zone shows a full-screen processing state ("Squinting at the tee sheet…") with the spinning logo, but hangs indefinitely if OCR parsing stalls.
* **User Feedback:** The spinning golf ball looks low-quality and the app sits on the processing screen for an eternity without feedback.
* **Design Action Plan:**
  1. **Interactive Processing Overlay:**
     - Add an animated progress ring with clear step status indicators:
       - *Step 1:* Reading screenshot image…
       - *Step 2:* Extracting course, date & tee time…
       - *Step 3:* Matching playing partners…
     - Include a visible **"Cancel & Enter Manually"** button if processing takes longer than 5 seconds.
     - Redesign the Dashed Drop Zone with modern drag/tap micro-interactions and explicit image preview thumbnails.

---

### 1.5 Settings Screen Overhaul (`lib/screens/settings_screen.dart`)
* **Current Implementation:** Minimal list tiles with incomplete action handlers.
* **User Feedback:** Settings page is largely non-functional.
* **Design Action Plan:**
  1. **Grouped Card Architecture:**
     - Group settings into distinct visual cards with clear header badges:
       - 📅 **Calendars & Accounts:** Primary calendar selection, linked accounts, sync preferences.
       - 🔔 **Notifications & Reminders:** Decline alerts, pre-round reminders (1h, 12h).
       - 👥 **Friends & Family:** Member list management, "Always Notify" toggles.
       - 📇 **Contacts & Privacy:** Contact cache status, re-sync button, local data privacy info.
       - 💳 **App License & About:** In-app purchase status, restore button, version badge.
     - Apply TAG brand guidelines: #7B2D8E primary accents, #5C1D6E dark theme highlights, clean typography (Outfit display + Inter body).

---

## 2. Key Design Files Reference
- `lib/widgets/golf_ball_logo.dart` — 3D Golf Ball / Globe Logo painter.
- `lib/theme/app_theme.dart` — Design tokens (AppColors, AppRadius, AppTypography).
- `lib/screens/onboarding_screen.dart` — Onboarding flow & permission screens.
- `lib/screens/scan_screen.dart` — Booking scanner UI & loading states.
- `lib/screens/settings_screen.dart` — App settings screen.
- `lib/widgets/family_setup_section.dart` — Friends & Family member chips & picker.

---

## 3. Handover Instructions for Claude Design
1. Review the visual assets and CustomPainter logic in `lib/widgets/golf_ball_logo.dart`.
2. Propose or generate refined vector landmass paths and improved 3D lighting shader parameters for the golf ball logo.
3. Design mockups / Flutter layout components for the **Multi-Calendar & Primary Calendar Selector**.
4. Pass the refined UI specifications and widget code back to Antigravity for integration and CI/CD push to GitHub.
