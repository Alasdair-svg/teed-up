# Teed Up — Codemagic Deployment Guide

> **Last updated:** 6 June 2026
>
> Build, sign, and ship Teed Up to the App Store and Google Play —
> entirely from Codemagic's cloud. No Xcode. No Android Studio.
> Your Mac is a thin client; Codemagic does the heavy lifting.

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Apple Developer Setup](#2-apple-developer-setup)
3. [Google Play Setup](#3-google-play-setup)
4. [Codemagic Setup](#4-codemagic-setup)
5. [Store Submission Workflow](#5-store-submission-workflow)
6. [Ongoing Workflow](#6-ongoing-workflow)
7. [Troubleshooting](#7-troubleshooting)
8. [Quick Reference](#8-quick-reference)

---

## 1. Prerequisites

You need three accounts before you begin. Everything else happens in the browser.

| Account | Cost | Link |
|---------|------|------|
| **Apple Developer Program** | $99 / year | https://developer.apple.com/programs/enroll/ |
| **Google Play Console** | $25 one-time | https://play.google.com/console/signup |
| **Codemagic** | Free (500 min/month) | https://codemagic.io |

### 1.1 Apple Developer Program

1. Go to https://developer.apple.com/programs/enroll/
2. Sign in with your Apple ID (or create one).
3. Choose **Enroll as an Individual** (or Organization if you have a D-U-N-S number for TAG).
4. Pay the **$99/year** fee.
5. Wait for approval — usually **24–48 hours** (sometimes instant).
6. Once approved, you'll have access to:
   - [App Store Connect](https://appstoreconnect.apple.com) — where your app listing, TestFlight, and submissions live.
   - [Apple Developer Portal](https://developer.apple.com/account) — where certificates, identifiers, and keys are managed.

### 1.2 Google Play Console

1. Go to https://play.google.com/console/signup
2. Sign in with the Google account you want to own the developer account.
3. Pay the **$25** one-time registration fee.
4. Complete your **developer profile** (name, address, contact email, website).
5. **Identity verification** is required — Google will ask for a photo ID and may take 2–5 business days.
6. Once verified, you can create app listings and upload builds.

### 1.3 Codemagic

1. Go to https://codemagic.io and click **Start building**.
2. Sign up with your **GitHub** account (recommended — easiest repo connection).
3. Confirm the free plan — you get **500 build minutes/month** on macOS M2 machines.
4. No credit card required.

---

## 2. Apple Developer Setup

> **Goal:** Create the credentials Codemagic needs to automatically
> sign your iOS app and upload it to TestFlight / App Store.

### 2.1 Create an App ID (Bundle Identifier)

The bundle ID for Teed Up is **`com.teedup.golf`** (already set in the Xcode project and `build.gradle`).

1. Go to https://developer.apple.com/account/resources/identifiers/list
2. Click the **+** button (top left).
3. Select **App IDs** → click **Continue**.
4. Select **App** (not App Clip) → click **Continue**.
5. Fill in:
   - **Description:** `Teed Up`
   - **Bundle ID:** Select **Explicit** and enter: `com.teedup.golf`
6. Under **Capabilities**, check the boxes for any entitlements your app needs:
   - ✅ Push Notifications (for reminder notifications)
   - ✅ In-App Purchase (for IAP)
   - Leave others unchecked unless needed.
7. Click **Continue** → **Register**.

### 2.2 Create an App Store Connect API Key

This key lets Codemagic authenticate with Apple **without** your Apple ID password. It handles code signing, provisioning profiles, and TestFlight uploads automatically.

1. Go to https://appstoreconnect.apple.com/access/integrations/api
2. If prompted, agree to the API terms.
3. Click the **+** button next to "Active" keys.
4. Fill in:
   - **Name:** `Codemagic CI`
   - **Access:** Select **App Manager** (minimum required role).
5. Click **Generate**.
6. **IMPORTANT — you can only download the `.p8` file once.**
   - Click **Download API Key** and save the file (e.g., `AuthKey_XXXXXXXXXX.p8`).
   - Store it somewhere safe (you'll upload it to Codemagic).
7. Note down these two values (visible on the keys page):
   - **Issuer ID** — a UUID at the top of the page (e.g., `69a6de7e-...`)
   - **Key ID** — the 10-character ID in the key's row (e.g., `ABC1234DEF`)

> **You now have three values:**
> | Value | Example |
> |-------|---------|
> | Issuer ID | `69a6de7e-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |
> | Key ID | `ABC1234DEF` |
> | Private Key | Contents of the `.p8` file |

### 2.3 How Code Signing Works (No Xcode Needed)

Codemagic manages signing **automatically** using the API key above:

- It creates/fetches the required **distribution certificate**.
- It creates/fetches the required **provisioning profile** for `com.teedup.golf`.
- The `codemagic.yaml` already calls `xcode-project use-profiles` which applies these.

**You do NOT need to:**
- ❌ Open Xcode
- ❌ Create certificates manually
- ❌ Download provisioning profiles
- ❌ Export signing identities from Keychain

Everything is handled by Codemagic's integration with the App Store Connect API.

---

## 3. Google Play Setup

> **Goal:** Create the credentials Codemagic needs to automatically
> sign your Android app and upload it to Google Play.

### 3.1 Create the App Listing

1. Go to https://play.google.com/console
2. Click **Create app** (top right).
3. Fill in:
   - **App name:** `Teed Up`
   - **Default language:** English (United Kingdom) or your preferred locale
   - **App or game:** App
   - **Free or paid:** Free (or Paid if applicable)
4. Check both declaration boxes → click **Create app**.
5. You'll be taken to the app's **Dashboard**. The left sidebar has a setup checklist — you'll need to complete this before publishing (screenshots, descriptions, etc.) but it's not needed for build uploads.

### 3.2 Create a Service Account for Automated Uploads

This service account lets Codemagic upload builds to Google Play without your Google password.

#### Step A: Create the service account in Google Cloud Console

1. Go to https://console.cloud.google.com
2. If you don't have a project linked to Play Console, create one:
   - Click the project dropdown (top left) → **New Project**
   - Name: `Teed Up CI` → **Create**
3. In the left sidebar, go to **IAM & Admin** → **Service Accounts**.
   - Direct link: https://console.cloud.google.com/iam-admin/serviceaccounts
4. Click **+ Create Service Account**.
5. Fill in:
   - **Service account name:** `codemagic-play-upload`
   - **Service account ID:** auto-fills (e.g., `codemagic-play-upload@teed-up-ci.iam.gserviceaccount.com`)
6. Click **Create and Continue**.
7. Skip the optional "Grant this service account access" step → click **Continue**.
8. Skip the optional "Grant users access" step → click **Done**.

#### Step B: Create and download the JSON key

1. In the Service Accounts list, find `codemagic-play-upload`.
2. Click the **⋮** menu (three dots) → **Manage keys**.
3. Click **Add Key** → **Create new key**.
4. Select **JSON** → click **Create**.
5. A `.json` file downloads — **save this securely**. This is your `GCLOUD_SERVICE_ACCOUNT_CREDENTIALS`.

#### Step C: Enable the Google Play Android Developer API

1. Go to https://console.cloud.google.com/apis/library/androidpublisher.googleapis.com
2. Make sure the correct project is selected.
3. Click **Enable**.

#### Step D: Grant the service account access in Google Play Console

1. Go to https://play.google.com/console → **Settings** (⚙️ in the left sidebar) → **API access**.
   - Direct link: https://play.google.com/console/developers/api-access
2. If prompted, **link** your Google Cloud project.
3. Under "Service accounts", find `codemagic-play-upload` → click **Manage Play Console permissions**.
4. Under the **App permissions** tab:
   - Click **Add app** → select **Teed Up** → **Apply**.
5. Under the **Account permissions** tab, grant these permissions:
   - ✅ Release apps to testing tracks
   - ✅ Manage production and testing track releases
   - ✅ Manage testing tracks and edit tester lists
6. Click **Invite user** → **Send invite**.
7. Accept the invitation (may arrive via email).

### 3.3 Create an Android Signing Keystore

Android apps must be signed with a keystore. You only create this **once** — losing it means you can never update your app.

> **Run this on your Mac in Terminal:**

```bash
keytool -genkey -v \
  -keystore teed-up-release.keystore \
  -alias teed-up \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000
```

You'll be prompted for:
- **Keystore password** — choose a strong password, note it down
- **Key password** — can be the same as keystore password
- **Your name, org, etc.** — fill in as appropriate

This creates a file called `teed-up-release.keystore`.

**Base64-encode it for Codemagic:**

```bash
base64 -i teed-up-release.keystore -o teed-up-release.keystore.base64
cat teed-up-release.keystore.base64
```

Copy the entire base64 output — you'll paste it into Codemagic.

> ⚠️ **BACK UP THIS KEYSTORE AND PASSWORDS.** If you lose them, you cannot update the app on Google Play. Store copies in your Google Drive and a password manager.

### 3.4 Enroll in Google Play App Signing (Recommended)

Google Play App Signing lets Google manage the app signing key. You upload with your upload key (the keystore above), and Google re-signs with the real key. This means if you lose your upload key, Google can reset it.

1. In Google Play Console, go to your app → **Setup** → **App signing**.
   - Direct link: https://play.google.com/console/app/app-signing
2. If prompted, opt in to **Google Play App Signing**.
3. Choose **Upload a Java keystore** → upload `teed-up-release.keystore`.
4. Done — Google now holds the actual signing key.

---

## 4. Codemagic Setup

> **Goal:** Connect your repo, add all credentials, and trigger your first build.

### 4.1 Connect Your GitHub Repository

1. Go to https://codemagic.io/apps
2. Click **Add application**.
3. Select **GitHub** as the provider.
4. Authorize Codemagic to access your GitHub account.
5. Select the **teed_up** repository.
6. Choose **Flutter App (via codemagic.yaml)** as the project type.
7. Click **Finish: Add application**.

Codemagic will detect the `codemagic.yaml` in your project root and use it for builds.

### 4.2 Configure Environment Variable Groups

Go to your app in Codemagic → **Settings** → **Environment variables**.

You need to create **three** groups that match what's in `codemagic.yaml`:

---

#### Group 1: `app_store_credentials`

| Variable Name | Value | Secure? |
|---------------|-------|---------|
| `APP_STORE_CONNECT_ISSUER_ID` | Your Issuer ID UUID (from Section 2.2) | Yes |
| `APP_STORE_CONNECT_KEY_IDENTIFIER` | Your Key ID (10 chars, from Section 2.2) | Yes |
| `APP_STORE_CONNECT_PRIVATE_KEY` | Entire contents of the `.p8` file (including `-----BEGIN PRIVATE KEY-----` and `-----END PRIVATE KEY-----`) | Yes |

**How to add each variable:**
1. Click **Add variable**.
2. Enter the **Variable name** exactly as shown above.
3. Paste the **Variable value**.
4. Check **Secure** (the value will be encrypted and hidden).
5. Under **Group**, type `app_store_credentials` (create the group on first use).
6. Click **Add**.

---

#### Group 2: `google_play_credentials`

| Variable Name | Value | Secure? |
|---------------|-------|---------|
| `GCLOUD_SERVICE_ACCOUNT_CREDENTIALS` | Entire contents of the service account `.json` file (from Section 3.2 Step B) | Yes |

**Steps:**
1. Open the downloaded `.json` file in a text editor.
2. Copy the **entire** contents.
3. Add as a variable in the `google_play_credentials` group.
4. Mark as **Secure**.

---

#### Group 3: `android_signing` (optional if using Play App Signing)

If you want Codemagic to sign the APK/AAB before upload:

| Variable Name | Value | Secure? |
|---------------|-------|---------|
| `CM_KEYSTORE` | Base64-encoded keystore (from Section 3.3) | Yes |
| `CM_KEY_ALIAS` | `teed-up` (or whatever alias you chose) | Yes |
| `CM_KEY_PASSWORD` | Your key password | Yes |
| `CM_KEYSTORE_PASSWORD` | Your keystore password | Yes |

> **Note:** If you enrolled in Google Play App Signing (Section 3.4), you may still want this so Codemagic signs with your upload key. The current `codemagic.yaml` uses the debug signing config — you'll want to update this for production (see Section 4.4).

---

### 4.3 The codemagic.yaml (Already in Your Project)

Your project already has a `codemagic.yaml` at the root with three workflows:

| Workflow | What it does | Machine |
|----------|-------------|---------|
| `android-release` | Builds APK + AAB, uploads to Google Play internal track | Linux x2 |
| `ios-release` | Builds IPA, uploads to TestFlight | macOS M2 |
| `release-all` | Builds both platforms in one workflow | macOS M2 |

> **Free tier note:** macOS M2 builds use your 500 min/month. A combined build
> typically takes 15–25 min. That gives you roughly **20–30 builds/month** for free.

### 4.4 Update Android Signing in build.gradle

The current `android/app/build.gradle` uses `signingConfigs.debug` for release builds. For production, you need to update this. However, **if you're using Codemagic's built-in Android signing**, you can add the signing setup directly in `codemagic.yaml`.

Add this script to the `release-all` workflow (before the "Build Android" step):

```yaml
- name: Set up Android signing
  script: |
    # Decode keystore from environment variable
    echo $CM_KEYSTORE | base64 --decode > /tmp/keystore.jks
    # Create key.properties for Gradle
    cat > $CM_BUILD_DIR/android/key.properties <<EOF
    storePassword=$CM_KEYSTORE_PASSWORD
    keyPassword=$CM_KEY_PASSWORD
    keyAlias=$CM_KEY_ALIAS
    storeFile=/tmp/keystore.jks
    EOF
```

Then update `android/app/build.gradle` to read from `key.properties`:

```groovy
// Add before the android { block:
def keystoreProperties = new Properties()
def keystorePropertiesFile = rootProject.file('key.properties')
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
}

// Replace the release signingConfig:
buildTypes {
    release {
        signingConfig = signingConfigs.create("release") {
            keyAlias = keystoreProperties['keyAlias']
            keyPassword = keystoreProperties['keyPassword']
            storeFile = keystoreProperties['storeFile'] ? file(keystoreProperties['storeFile']) : null
            storePassword = keystoreProperties['storePassword']
        }
        minifyEnabled true
        shrinkResources true
        proguardFiles getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro"
    }
}
```

### 4.5 Trigger Your First Build

1. Go to your app in Codemagic → https://codemagic.io/apps
2. Click on the **Teed Up** app.
3. Click **Start new build** (top right).
4. Select the **branch** (e.g., `main`).
5. Select the **workflow**:
   - For testing, start with `android-release` (faster, no iOS signing needed).
   - Once Android works, try `ios-release`.
   - For both platforms, use `release-all`.
6. Click **Start new build**.

### 4.6 Download Build Artifacts

After a successful build:

1. Go to the build page in Codemagic.
2. Scroll to **Artifacts**.
3. You'll see:
   - **Android:** `app-release.apk` and `app-release.aab`
   - **iOS:** `Teed Up.ipa`
4. Click to download any artifact.
5. If publishing is configured, artifacts are also auto-uploaded to the stores.

---

## 5. Store Submission Workflow

### 5.1 iOS: TestFlight → App Store

#### First Build to TestFlight

1. **Trigger the `ios-release` or `release-all` workflow** from Codemagic.
2. Codemagic builds the IPA, signs it with your App Store Connect API key, and uploads to TestFlight.
3. Go to https://appstoreconnect.apple.com → **My Apps** → **Teed Up** → **TestFlight**.
4. The build will appear after Apple processes it (**5–15 minutes**).
5. You may see a **compliance warning** — click "Manage" and answer:
   - "Does your app use encryption?" → **No** (unless you added custom encryption).
6. The build is now available to your **Internal Testers** group (up to 25 testers, no App Review needed).

#### Adding Internal Testers

1. In App Store Connect → **Users and Access** → https://appstoreconnect.apple.com/access/users
2. Add yourself and testers.
3. In **TestFlight** → **Internal Testing** → **Internal Testers** group:
   - Add the users you want to test.
4. Testers receive an email/push to install via the **TestFlight app** on their iPhone.

#### Submitting to the App Store

1. In App Store Connect → **My Apps** → **Teed Up** → **App Store** tab.
2. Complete the **App Information**:
   - App name, subtitle, category (Sports), privacy policy URL
3. Complete the **Version Information** (1.0):
   - Screenshots (6.7" and 5.5" sizes minimum)
   - Description, keywords, support URL
   - Select the TestFlight build to release
4. Click **Submit for Review**.
5. Apple reviews typically take **24–48 hours** (can be longer for first submissions).

#### App Review Tips (iOS)

- ✅ Include a **demo video or screenshots** showing the app works.
- ✅ Add a **privacy policy URL** (even a simple one on your website).
- ✅ If the app accesses camera/contacts/calendar, explain **why** in the review notes.
- ✅ Make sure the app doesn't crash on launch — test the IPA on a real device via TestFlight first.
- ❌ Don't mention "beta" or "test" in your app description.
- ❌ Don't include placeholder content or broken features.

### 5.2 Android: Internal Testing → Production

#### First Build to Internal Testing

1. **Trigger the `android-release` or `release-all` workflow** from Codemagic.
2. Codemagic builds the AAB and uploads to the **internal** track on Google Play.
3. Go to https://play.google.com/console → **Teed Up** → **Release** → **Testing** → **Internal testing**.
4. Click **Edit release** if the build shows as a draft → **Review release** → **Start rollout**.
5. Under **Testers**, create an email list and add your test accounts.
6. Share the **opt-in link** with testers (Google Play generates this).

#### The 14-Day Closed Testing Requirement

> ⚠️ **Google requires at least 14 consecutive days of closed testing with at least 12 testers before you can apply for production access.** This is non-negotiable for new developer accounts.

1. Go to **Testing** → **Closed testing** → **Create track** (or use the default "Alpha" track).
2. Upload a build (or promote from internal testing).
3. Add at least **12 testers** by email.
4. Run the test for **14+ consecutive days**.
5. After 14 days, the **"Production"** option unlocks in the left sidebar.

#### Submitting to Production

1. In Google Play Console → **Teed Up** → **Release** → **Production**.
2. Click **Create new release**.
3. Select the AAB from your testing track (or upload a new one).
4. Add **Release notes** (e.g., "Initial release of Teed Up").
5. Click **Review release** → **Start rollout to production**.
6. Google reviews typically take **a few hours to 3 days** (longer for first submissions).

#### Before You Can Submit: Complete the Store Listing

Google requires you to complete these before your first production release:

- [ ] **Store listing:** Title, short description, full description
- [ ] **Graphics:** App icon (512×512), feature graphic (1024×500), screenshots (min 2 per device type)
- [ ] **App content:** Privacy policy, app access instructions, ads declaration, content rating questionnaire, target audience, data safety form
- [ ] **App category:** Sports / Games (choose Sports)

Go to **Grow** → **Store presence** → **Main store listing** to fill these in.

---

## 6. Ongoing Workflow

Once everything is set up, your day-to-day workflow is simple:

```
Code on Mac → Push to GitHub → Codemagic auto-builds → Apps uploaded to stores
```

### 6.1 Automatic Builds

You can enable automatic builds on push:

1. In Codemagic → your app → **Settings** (⚙️ icon on the workflow).
2. Under **Build triggers**:
   - ✅ **Trigger on push** — select the branch (e.g., `main`).
   - Optionally, trigger only on tags (e.g., `v*`) for releases.
3. Every `git push` to `main` will trigger the selected workflow.

### 6.2 Version Bumping

Before each release, bump the version in `pubspec.yaml`:

```yaml
version: 1.0.1+2  # format: major.minor.patch+buildNumber
```

- **Version name** (`1.0.1`): Shown to users in the store.
- **Build number** (`+2`): Must be incremented for every upload. Both stores reject duplicate build numbers.

### 6.3 Build Time Budget (Free Tier)

| Workflow | Typical Duration | Builds/Month (500 min) |
|----------|-----------------|----------------------|
| `android-release` (Linux) | 8–12 min | ~45 builds |
| `ios-release` (macOS M2) | 15–20 min | ~28 builds |
| `release-all` (macOS M2) | 20–30 min | ~18 builds |

> **Tip:** Use `android-release` (on Linux) for Android-only changes — it's faster
> and doesn't consume macOS minutes. Reserve `release-all` for actual releases.

### 6.4 Cost Summary

| Item | Cost | Frequency |
|------|------|-----------|
| Apple Developer Program | $99 | Annual |
| Google Play Console | $25 | One-time |
| Codemagic Free Tier | $0 | Monthly (500 min) |
| **Total Year 1** | **$124** | |
| **Total Year 2+** | **$99/year** | |

---

## 7. Troubleshooting

### Build fails: "No matching provisioning profiles found"

- Verify the App Store Connect API key is correct in Codemagic.
- Check that the **Issuer ID**, **Key ID**, and **.p8 contents** are all in the `app_store_credentials` group.
- Make sure the API key has **App Manager** or **Admin** role.
- Confirm the bundle ID `com.teedup.golf` is registered at https://developer.apple.com/account/resources/identifiers/list

### Build fails: "The Android Gradle plugin supports only Kotlin Gradle plugin version 1.5.20 and higher"

- Update the Kotlin version in `android/build.gradle` or `android/settings.gradle`.
- The `codemagic.yaml` uses `java: 17` which should handle most cases.

### Build fails: "Signing APK failed"

- Check that `CM_KEYSTORE`, `CM_KEY_ALIAS`, `CM_KEY_PASSWORD`, and `CM_KEYSTORE_PASSWORD` are set in the `android_signing` group.
- Verify the keystore was base64-encoded correctly:
  ```bash
  base64 -i teed-up-release.keystore | head -c 50
  ```
  Should start with something like `MIIJ...`.

### Upload fails: "The service account does not have permission"

- Go to Google Play Console → **Settings** → **API access**.
- Verify the service account has **Release apps to testing tracks** permission.
- Make sure you **accepted the invitation** email.

### TestFlight build is "Processing" for too long

- Apple processing typically takes 5–15 minutes, but can take up to 1 hour.
- If it's been over 2 hours, check for compliance questionnaire alerts in App Store Connect.

### Build takes too long / times out

- Default `max_build_duration` is 30 min (Android) and 60 min (iOS) in the `codemagic.yaml`.
- If builds are timing out, check if `flutter pub get` is downloading large packages.
- Enable caching (already configured in `codemagic.yaml`).

### "You must complete the closed testing requirements"

- New Google Play developer accounts must run **14 days of closed testing** with **12+ testers** before getting production access.
- There is no shortcut — start this early.

---

## 8. Quick Reference

### Key URLs

| Resource | URL |
|----------|-----|
| Codemagic Dashboard | https://codemagic.io/apps |
| App Store Connect | https://appstoreconnect.apple.com |
| Apple Developer Portal | https://developer.apple.com/account |
| Apple Identifiers (Bundle IDs) | https://developer.apple.com/account/resources/identifiers/list |
| App Store Connect API Keys | https://appstoreconnect.apple.com/access/integrations/api |
| Google Play Console | https://play.google.com/console |
| Google Cloud Console | https://console.cloud.google.com |
| Google Play API Access | https://play.google.com/console/developers/api-access |
| Android Publisher API | https://console.cloud.google.com/apis/library/androidpublisher.googleapis.com |
| Codemagic Flutter Docs | https://docs.codemagic.io/flutter-configuration/flutter-projects/ |
| Codemagic YAML Reference | https://docs.codemagic.io/yaml/yaml-getting-started/ |
| Codemagic Code Signing (iOS) | https://docs.codemagic.io/yaml-code-signing/signing-ios/ |
| Codemagic Code Signing (Android) | https://docs.codemagic.io/yaml-code-signing/signing-android/ |

### Environment Variables Cheat Sheet

```
┌─────────────────────────────────────────────────────────────────┐
│  Group: app_store_credentials                                   │
│  ├─ APP_STORE_CONNECT_ISSUER_ID      (UUID from Apple)          │
│  ├─ APP_STORE_CONNECT_KEY_IDENTIFIER (10-char Key ID)           │
│  └─ APP_STORE_CONNECT_PRIVATE_KEY    (.p8 file contents)        │
│                                                                 │
│  Group: google_play_credentials                                 │
│  └─ GCLOUD_SERVICE_ACCOUNT_CREDENTIALS (JSON file contents)     │
│                                                                 │
│  Group: android_signing                                         │
│  ├─ CM_KEYSTORE          (base64-encoded .keystore file)        │
│  ├─ CM_KEY_ALIAS         (e.g., "teed-up")                      │
│  ├─ CM_KEY_PASSWORD      (key password)                         │
│  └─ CM_KEYSTORE_PASSWORD (keystore password)                    │
└─────────────────────────────────────────────────────────────────┘
```

### Your Project Configuration

| Setting | Value |
|---------|-------|
| Bundle ID (iOS + Android) | `com.teedup.golf` |
| Flutter SDK | stable |
| Min Android SDK | 23 (Android 6.0) |
| Target Android SDK | 34 (Android 14) |
| Xcode | latest (managed by Codemagic) |
| Java | 17 |
| Current version | `1.0.0+1` |

### Step-by-Step Checklist

Use this checklist to track your progress:

- [ ] **Apple Developer Program** — Enrolled and approved
- [ ] **App ID** — Created `com.teedup.golf` in Apple Developer Portal
- [ ] **App Store Connect API Key** — Created, `.p8` file downloaded
- [ ] **Google Play Console** — Registered and verified
- [ ] **Google Cloud Service Account** — Created, JSON key downloaded
- [ ] **Android Publisher API** — Enabled in Google Cloud Console
- [ ] **Play Console API Access** — Service account linked with correct permissions
- [ ] **Android Keystore** — Generated and base64-encoded
- [ ] **Codemagic Account** — Created and GitHub connected
- [ ] **Codemagic Env Vars** — All three groups configured
- [ ] **First Android Build** — Triggered and succeeded ✅
- [ ] **First iOS Build** — Triggered and succeeded ✅
- [ ] **TestFlight** — First build received and tested
- [ ] **Google Play Internal Testing** — First build uploaded and shared
- [ ] **Google Play Closed Testing** — 14-day period started with 12+ testers
- [ ] **App Store Submission** — Store listing complete, submitted for review
- [ ] **Google Play Production** — Store listing complete, submitted for review

---

> **Questions?** Codemagic has excellent docs at https://docs.codemagic.io and
> a responsive support team. For Apple-specific issues, check
> https://developer.apple.com/help/. For Google Play, see
> https://support.google.com/googleplay/android-developer/.
