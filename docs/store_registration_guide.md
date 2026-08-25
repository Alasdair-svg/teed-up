# All Teed Up — App Store Registration Guide

> **Status:** URGENT — Complete today (6 June 2026)
> **Goal:** Register on both stores so we can publish All Teed Up within ~17 days.

---

## Table of Contents

1. [Google Play Console ($25 one-time)](#section-1-google-play-console-25-one-time)
2. [Apple Developer Program ($99/year)](#section-2-apple-developer-program-99year)
3. [Promo Codes Strategy (First 10 Free)](#section-3-promo-codes-strategy-first-10-free)
4. [Timeline](#section-4-timeline)
5. [Assets Checklist](#section-5-assets-checklist)

---

## Section 1: Google Play Console ($25 one-time)

### Step 1 — Create a Google Play Developer Account

1. Open: **https://play.google.com/console/signup**
2. Sign in with the Google account you want to own the app (e.g., your `@theartesiangroup.com` account).
3. Read and **accept the Google Play Developer Distribution Agreement**.
4. Pay the **$25 USD one-time registration fee** (Visa / Mastercard / Amex).
5. Complete **identity verification**:
   - Select **Organization** if publishing under The Artesian Group, or **Individual** if publishing under your personal name.
   - For Organization: provide legal entity name, address, D-U-N-S number (if required), and a contact phone number.
   - For Individual: provide legal name, address, and phone number.
   - Google may request a photo ID — have your Emirates ID or passport ready.
6. Verification can take **24–48 hours** (sometimes instant for individuals).

### Step 2 — Create the App

Once your account is verified:

1. Go to: **https://play.google.com/console**
2. Click **"Create app"** (blue button, top-right).
3. Fill in:

| Field | Value |
|---|---|
| App name | `All Teed Up` |
| Default language | `English (US) – en-US` |
| App or Game | `App` |
| Free or Paid | `Paid` |

4. Check both declaration boxes (program policies + US export laws).
5. Click **"Create app"**.

### Step 3 — Store Listing

Navigate to **Grow → Store presence → Main store listing**.

#### Short description (80 characters max)

```
Smart golf scorecard with NFC ball tracking and AI-powered analytics.
```
(70 characters — fits perfectly)

#### Full description (4,000 characters max)

```
All Teed Up is the smartest golf scorecard you'll ever use.

Track every shot with NFC-enabled golf balls. Just tap your phone to the ball before each shot, and All Teed Up automatically logs your position, club selection, and shot outcome using GPS precision. No manual data entry. No guesswork.

🏌️ INTELLIGENT SCORECARD
• Full 18-hole digital scorecard with automatic scoring
• Stableford, stroke play, match play, and skins formats
• Track putts, fairways hit, greens in regulation, and penalties
• Supports up to 4 players per round
• Offline-first: works perfectly without cell signal on the course

📡 NFC BALL TRACKING
• Tap your phone to your All Teed Up NFC golf ball before each shot
• Automatic shot detection and distance calculation
• Club-by-club statistics build over time
• See your average distances for every club in your bag
• Works with any NFC-enabled smartphone (iPhone 7+ / most Android phones)

📊 AI-POWERED ANALYTICS
• Post-round AI analysis breaks down your strengths and weaknesses
• Personalized practice recommendations based on your data
• Track handicap progression over time
• Compare your stats against course averages
• Visualise shot dispersion patterns and tendencies

🗺️ COURSE MAPS
• GPS distances to front, centre, and back of every green
• Hazard distances and layup targets
• Thousands of courses worldwide
• Works offline after initial course download

🏆 SOCIAL & COMPETITIVE
• Share scorecards with playing partners
• Leaderboards for your group
• Challenge friends to beat your best rounds
• Export scorecards as PDF for club handicap submissions

💎 PREMIUM EXPERIENCE
All Teed Up is a one-time purchase — no subscriptions, no ads, no in-app purchases. Pay once, own it forever. Every future update is included.

Whether you're a weekend warrior looking to break 90 or a single-digit handicapper chasing scratch, All Teed Up gives you tour-level analytics in your pocket.

Download All Teed Up today and start playing smarter golf.
```
(~1,780 characters — well within the 4,000 limit. Expand as needed.)

#### Graphics & Screenshots

| Asset | Spec | Notes |
|---|---|---|
| App icon | 512 × 512 px, PNG, 32-bit, no alpha | We have this ✅ |
| Feature graphic | 1024 × 500 px, PNG or JPEG | Required for store listing |
| Phone screenshots | Min 2, recommended 8 | 16:9 or 9:16, min 320px, max 3840px |
| 7-inch tablet screenshots | Optional but recommended | 16:9 or 9:16 |
| 10-inch tablet screenshots | Optional but recommended | 16:9 or 9:16 |

Upload screenshots at: **Main store listing → Phone screenshots**.

### Step 4 — Content Rating

1. Navigate to **Policy → App content → Content rating**.
2. Click **"Start questionnaire"**.
3. Select category: **Utility / Productivity / Sports** (whichever is offered).
4. Answer all questions honestly (no violence, no user-generated content, no gambling, etc.).
5. You should receive a rating of **Everyone / PEGI 3 / USK 0**.
6. Click **"Save"** and then **"Submit"**.

### Step 5 — Pricing & Distribution

1. Navigate to **Monetize → Pricing**.
2. Set the default price:
   - **USD $26.99** (Google will auto-convert to local currencies including AED).
   - Or set AED manually: go to **Pricing → Manage prices by country** → find UAE → set **AED 99**.
3. Navigate to **Countries / regions**: select **"All countries"** (or deselect any you want to exclude).

### Step 6 — Set Up Closed Testing (MANDATORY)

> ⚠️ **Google requires a minimum 14 days of closed testing with at least 20 testers (12 must opt in) before you can apply for production access.** This is non-negotiable for new developer accounts.

1. Navigate to **Testing → Closed testing**.
2. Click **"Create track"** (or use the default "Closed testing" track).
3. Create an email list of testers:
   - Click **"Manage track" → "Testers" → "Create email list"**.
   - Add at least **20 email addresses** (ask friends, family, colleagues — they just need Gmail accounts).
   - Name the list (e.g., "All Teed Up Beta Testers").
4. Upload your **AAB (Android App Bundle)** file:
   - Go to **Releases → Create new release**.
   - Upload the `.aab` file.
   - Add release notes (e.g., "Initial beta release of All Teed Up").
   - Click **"Review release" → "Start rollout"**.
5. Share the **opt-in link** (provided by Google) with your testers via email/WhatsApp.
6. Wait for **at least 12 testers to opt in and install**.
7. The 14-day clock starts when you create the closed testing release.

### Step 7 — Promote to Production (Day 15+)

1. After 14 days of closed testing with sufficient testers:
2. Navigate to **Production → Create new release**.
3. Upload the same (or updated) AAB.
4. Fill in release notes.
5. Click **"Review release" → "Start rollout to production"**.
6. Google review typically takes **1–3 days** for new apps.

---

## Section 2: Apple Developer Program ($99/year)

### Step 1 — Enroll in the Apple Developer Program

1. Open: **https://developer.apple.com/programs/enroll/**
2. Click **"Start Your Enrollment"**.
3. Sign in with your **Apple ID**.
   - Don't have one? Create at: **https://appleid.apple.com/account**
   - Use your `@theartesiangroup.com` email or personal email.
4. Select enrollment type:
   - **Individual** — if publishing under your personal name (simpler, faster).
   - **Organization** — if publishing under "The Artesian Group" (requires D-U-N-S number).
   - 💡 **Recommendation:** Start with **Individual** for speed. You can transfer the app to an organization account later.
5. Fill in your personal details (legal name, address, phone).
6. Pay **$99 USD/year** (auto-renews annually).
7. **Wait for approval: typically 24–48 hours** (sometimes same-day for individuals).
8. You'll receive an email: _"Welcome to the Apple Developer Program"_.

### Step 2 — Create the App in App Store Connect

Once approved:

1. Open: **https://appstoreconnect.apple.com**
2. Sign in with the same Apple ID.
3. Click **"My Apps"** → **"+"** → **"New App"**.
4. Fill in:

| Field | Value |
|---|---|
| Platforms | `iOS` |
| Name | `All Teed Up` |
| Primary language | `English (U.S.)` |
| Bundle ID | `com.teedup.golf` (must match Xcode project) |
| SKU | `teedup-golf-001` |
| User Access | `Full Access` |

5. Click **"Create"**.

### Step 3 — App Information

Navigate to **App Store → App Information**:

| Field | Value |
|---|---|
| Subtitle (30 chars) | `Smart Golf Scorecard & NFC` |
| Category | `Sports` |
| Secondary Category | `Utilities` (optional) |
| Content Rights | Does not contain third-party content |
| Age Rating | Fill questionnaire → should be `4+` |

### Step 4 — Pricing and Availability

1. Navigate to **App Store → Pricing and Availability**.
2. Click **"Price Schedule" → "Add Base Price"**.
3. Select **Price Tier 40** (= $26.99 USD / AED 99.99):

| Currency | Approx. Price |
|---|---|
| USD | $26.99 |
| AED | 99.99 |
| GBP | £22.99 |
| EUR | €26.99 |

4. **Availability:** Select **"All Territories"** (175 countries).
5. Click **"Save"**.

### Step 5 — App Store Listing

Navigate to **App Store → your version (e.g., 1.0)**:

#### Promotional Text (170 chars, can be updated without new review)

```
Track every shot with NFC golf balls. AI analytics that actually help you improve. One-time purchase — no subscriptions ever.
```

#### Description

```
All Teed Up is the smartest golf scorecard you'll ever use.

Track every shot with NFC-enabled golf balls. Just tap your phone to the ball before each shot, and All Teed Up automatically logs your position, club selection, and shot outcome using GPS precision. No manual data entry. No guesswork.

INTELLIGENT SCORECARD
• Full 18-hole digital scorecard with automatic scoring
• Stableford, stroke play, match play, and skins formats
• Track putts, fairways hit, greens in regulation, and penalties
• Supports up to 4 players per round
• Offline-first: works perfectly without cell signal on the course

NFC BALL TRACKING
• Tap your phone to your All Teed Up NFC golf ball before each shot
• Automatic shot detection and distance calculation
• Club-by-club statistics build over time
• See your average distances for every club in your bag
• Works with any NFC-enabled iPhone (iPhone 7 and later)

AI-POWERED ANALYTICS
• Post-round AI analysis breaks down your strengths and weaknesses
• Personalized practice recommendations based on your data
• Track handicap progression over time
• Compare your stats against course averages
• Visualise shot dispersion patterns and tendencies

COURSE MAPS
• GPS distances to front, centre, and back of every green
• Hazard distances and layup targets
• Thousands of courses worldwide
• Works offline after initial course download

SOCIAL & COMPETITIVE
• Share scorecards with playing partners
• Leaderboards for your group
• Challenge friends to beat your best rounds
• Export scorecards as PDF for club handicap submissions

PREMIUM EXPERIENCE
All Teed Up is a one-time purchase — no subscriptions, no ads, no in-app purchases. Pay once, own it forever. Every future update is included.
```

#### Keywords (100 chars, comma-separated)

```
golf,scorecard,NFC,ball tracking,GPS,analytics,handicap,score,putting,driving range,club distances
```
(99 characters)

#### What's New (for version 1.0)

```
Initial release of All Teed Up — your smart golf scorecard with NFC ball tracking and AI analytics.
```

#### Screenshots Required

| Device | Resolution | Quantity |
|---|---|---|
| 6.7" (iPhone 15 Pro Max) | 1290 × 2796 px | Min 3, recommended 6-8 |
| 6.5" (iPhone 11 Pro Max) | 1284 × 2778 px | Min 3, recommended 6-8 |
| 5.5" (iPhone 8 Plus) | 1242 × 2208 px | Min 3, recommended 6-8 |
| iPad Pro 12.9" (6th gen) | 2048 × 2732 px | Optional but recommended |

> 💡 **Tip:** You can use the 6.7" screenshots as the primary set and let Apple auto-scale for smaller devices. You only truly *need* the 6.7" set, but providing all sizes is better.

#### App Icon

- 1024 × 1024 px, PNG, no alpha, no rounded corners (Apple adds rounding automatically).

### Step 6 — Upload Build via TestFlight

1. Build the app in Xcode with your **Distribution certificate** and **provisioning profile**.
2. In Xcode: **Product → Archive → Distribute App → App Store Connect**.
3. The build will appear in App Store Connect under **TestFlight** within ~15 minutes.
4. Add **internal testers** (up to 25 from your team) — no review needed.
5. Add **external testers** — requires a quick Beta App Review (usually < 24 hours).

### Step 7 — Submit for App Review

1. Go to **App Store → your version → Build**: select the uploaded build.
2. Fill in all required metadata (screenshots, description, etc.).
3. Under **App Review Information**:
   - Contact: Your name, email, phone.
   - Notes: `"NFC features require a All Teed Up NFC golf ball. The app is fully functional as a standard scorecard without NFC."`
   - Demo account: Not required (no login).
4. Click **"Submit for Review"**.
5. Review typically takes **24–48 hours** (occasionally up to 5 days for new developers).

---

## Section 3: Promo Codes Strategy (First 10 Free)

### Google Play Promo Codes

**When:** After your app is live on the Play Store.

1. Go to: **https://play.google.com/console**
2. Select **All Teed Up** → **Monetize → Promo codes**.
3. Click **"Create promo code"**.
4. Configure:
   - Product: the paid app itself
   - Number of codes: **10**
   - Start date: immediately
   - End date: 30 days from now (or your preference)
5. Click **"Create"**.
6. Download the CSV file containing the 10 unique codes.
7. Send one code per user via email/WhatsApp/DM.

**How users redeem:**
1. Open the **Google Play Store** app.
2. Tap profile icon → **"Payments & subscriptions"** → **"Redeem code"**.
3. Enter the promo code.
4. App installs for free.

**Limits:**
- **500 promo codes per quarter** per app.
- Codes are single-use.
- You can create multiple batches.

### Apple App Store Promo Codes

**When:** After your app is approved and live (or ready for sale).

1. Go to: **https://appstoreconnect.apple.com**
2. Select **All Teed Up** → **App Store** tab.
3. In the sidebar, click **"Promo Codes"**.
4. Select the version (e.g., 1.0).
5. Enter number of codes: **10**.
6. Click **"Generate Codes"**.
7. Download the text file with 10 unique codes.
8. Send one code per user.

**How users redeem:**
1. Open the **App Store** app.
2. Tap profile icon → **"Redeem Gift Card or Code"**.
3. Enter the promo code manually (or use camera for physical cards).
4. App downloads for free.

**Limits:**
- **100 promo codes per version** of the app.
- Codes expire **28 days** after generation.
- Each new version (1.1, 1.2, etc.) resets the 100-code limit.
- Codes are single-use and cannot be regenerated.

### Promo Code Distribution Plan

| Recipient | Platform | Code Type | Notes |
|---|---|---|---|
| Testers 1-5 (Android) | Google Play | Promo code | First wave beta testers |
| Testers 6-10 (Android) | Google Play | Promo code | Second wave |
| Testers 1-5 (iOS) | App Store | Promo code | First wave beta testers |
| Testers 6-10 (iOS) | App Store | Promo code | Second wave |
| Golf influencers | Both | Promo code | For reviews/social posts |
| Golf club pros | Both | Promo code | For word-of-mouth |

---

## Section 4: Timeline

Starting from **today (6 June 2026)**:

```
Day 0  (6 Jun)  ✅ Register Google Play Console ($25)
Day 0  (6 Jun)  ✅ Enroll in Apple Developer Program ($99)
Day 1  (7 Jun)     Upload Android AAB to closed testing track
Day 1  (7 Jun)     Share opt-in link with 20+ testers
Day 1-2 (7-8 Jun)  Apple Developer approval received
Day 3  (9 Jun)     Create app in App Store Connect
Day 3  (9 Jun)     Upload iOS build to TestFlight
Day 3-7 (9-13 Jun) TestFlight beta testing
Day 7  (13 Jun)    Submit iOS build for App Review
Day 8-10 (14-16 Jun) iOS App Review (usually 24-48 hrs)
Day 10 (16 Jun)    iOS LIVE on App Store 🎉
Day 15 (21 Jun)    14-day Android closed testing complete
Day 15 (21 Jun)    Promote Android to production
Day 16-18 (22-24 Jun) Google Play production review
Day 18 (24 Jun)    Android LIVE on Google Play 🎉
Day 18 (24 Jun)    Generate promo codes on both platforms
Day 18 (24 Jun)    Distribute codes to first 10 users
```

### Critical Path

```
┌─────────────────────────────────────────────────────────────────┐
│ GOOGLE PLAY (18 days total)                                     │
│ Register → Upload → 14-day testing → Production review → LIVE  │
│ Day 0      Day 1    Day 1-15         Day 15-18          Day 18  │
├─────────────────────────────────────────────────────────────────┤
│ APPLE APP STORE (10 days total)                                 │
│ Enroll → Approval → Upload → Review → LIVE                     │
│ Day 0    Day 1-2     Day 3    Day 7-10  Day 10                  │
└─────────────────────────────────────────────────────────────────┘
```

> ⚠️ **The bottleneck is Google Play's 14-day closed testing requirement.** Start this immediately on Day 1. iOS will likely go live first.

---

## Section 5: Assets Checklist

Complete this checklist before uploading to either store:

### Required Assets

- [ ] **App icon** — 1024×1024 PNG (Apple), 512×512 PNG (Google)
- [ ] **Feature graphic** — 1024×500 PNG/JPEG (Google Play only)
- [ ] **Screenshots (Phone)** — minimum 2 per store, recommended 6-8
  - Google: 16:9 or 9:16, min 320px
  - Apple: 1290×2796 (6.7"), 1284×2778 (6.5"), 1242×2208 (5.5")
- [ ] **Screenshots (Tablet/iPad)** — optional but recommended
- [ ] **Privacy Policy URL** — required by both stores
  - Host at: `https://teedup.golf/privacy` or similar
  - Must cover: data collection, NFC usage, location data, analytics
- [ ] **Support URL** — required by Apple
  - e.g., `https://teedup.golf/support` or an email address
- [ ] **Marketing URL** — optional but recommended
  - e.g., `https://teedup.golf`

### Required Builds

- [ ] **Android App Bundle (.aab)** — signed with upload key
- [ ] **iOS Archive (.ipa)** — signed with distribution certificate

### Accounts & Credentials

- [ ] Google Play Console account (verified, $25 paid)
- [ ] Apple Developer Program membership (approved, $99 paid)
- [ ] Apple Distribution Certificate (created in Xcode or developer portal)
- [ ] Android Upload Key (generated during first AAB upload, or via `keytool`)

---

## Quick Reference — Key URLs

| Resource | URL |
|---|---|
| Google Play Console Signup | https://play.google.com/console/signup |
| Google Play Console Dashboard | https://play.google.com/console |
| Google Play Pricing Reference | https://support.google.com/googleplay/android-developer/answer/6334373 |
| Apple Developer Enrollment | https://developer.apple.com/programs/enroll/ |
| App Store Connect | https://appstoreconnect.apple.com |
| Apple ID Creation | https://appleid.apple.com/account |
| Apple Price Tier Matrix | https://developer.apple.com/help/app-store-connect/manage-app-pricing/price-points |
| Apple Screenshot Specs | https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications |
| Google Screenshot Specs | https://support.google.com/googleplay/android-developer/answer/9866151 |
| D-U-N-S Lookup (for Org accounts) | https://developer.apple.com/enroll/duns-lookup/ |

---

## ⚡ Action Items for TODAY

1. **RIGHT NOW:** Open https://play.google.com/console/signup → register → pay $25.
2. **RIGHT NOW:** Open https://developer.apple.com/programs/enroll/ → enroll → pay $99.
3. **While waiting for approvals:** Prepare all store assets (screenshots, feature graphic, privacy policy).
4. **Tomorrow:** Upload AAB to Google Play closed testing. Start the 14-day clock.

> 💡 **Every day you delay registration is a day added to your launch date.** The Google Play 14-day testing requirement is the longest lead time — start it today.
