# Show Stand — Slice 0 Build Spec

Universal iOS/iPadOS app that turns a phone or tablet into a branded booth display with offline lead capture. This file is the source of truth for the first build. Do not add features outside "In scope" without asking the owner (Perry).

**Goal of slice 0:** get a working build onto real devices and take it to a real event. Prove that visitors scan the QR code and fill out the form. Polish comes after that test, not before.

## Principles
- As simple and frictionless as possible. If a step can be removed, remove it.
- Fully offline. The app makes **zero network calls**. No accounts, no backend, no analytics, no third-party SDKs.
- One universal app (iPhone, iPad, iPhone Duo). Layout adapts to size class; no device-specific forks in slice 0.
- Keep the code small and readable. No extra architecture layers.

## Tech
- Swift + SwiftUI, SwiftData for storage.
- Minimum target: **iOS / iPadOS 17** (covers ~2018+ iPhones and the 10.5" iPad Pro used for testing).
- QR generation: Core Image `CIQRCodeGenerator` (error correction "M" or higher, rendered crisp with no interpolation).
- Images: `PhotosPicker`, stored as files in the app container (store a filename in the model, not image blobs).
- Auth: `LocalAuthentication`, policy `.deviceOwnerAuthentication` (Face ID / Touch ID with device passcode fallback).
- Export: `ShareLink` with a generated CSV file.
- Keep-awake: `UIApplication.shared.isIdleTimerDisabled = true` only while the display screen is showing; reset to false when leaving it or when the app backgrounds.

## Data model
```
Booth
  id, name, createdAt
  logoFilename (optional)
  tagline (optional)
  primaryLink (URL, required)        // QR #1
  intakeLink (URL, optional)         // QR #2, e.g. the vendor's own intake form
  intakeLabel (String, default "Book a deeper conversation")
  offerText (String, required)       // e.g. "Get the free catalog"
  accentColor (hex string)
  orientationPreference (auto | portrait | landscape)
  leads: [Lead]

Lead
  id, createdAt
  name (String, required)
  email (String, required, validated)
  phone (String, optional)
  booth (relationship)
```
The model supports multiple booths, but slice 0 UI only needs one (create on first launch, edit later). Multiple-booth UI is v1.

## Screens

### 1. Setup (first launch, four steps, ~60 seconds)
Each step is one screen with one job and a big Continue button. Back is always available.
1. **Logo** — pick from Photos (optional, "Skip" allowed) + business name (required).
2. **Link** — the URL the main QR opens. Prefix `https://` automatically if missing. Show a live QR preview.
3. **Offer** — what visitors get for leaving their info. Text field plus tappable suggestions, each with a one-line "why":
   - "Get our free catalog" — low commitment, works for product vendors
   - "10% off your first order" — gives a reason to act after the show
   - "Enter today's giveaway" — highest sign-ups, lower-quality leads
   - "Free 15-minute consult" — best for coaches and service businesses
   - "Get the slides / resources" — good for speakers and educators
4. **Go live** — orientation choice (Auto, Portrait, Landscape; default Auto) and a short Guided Access tip with a "Show me how" sheet. Big "Go Live" button.

Optional intake link (QR #2) is set in Edit Booth, not during setup.

### 2. Display (the public screen)
- Content: logo, business name, tagline, offer text, primary QR (large), "Leave your info" button. If `intakeLink` exists, show a second, smaller QR labeled with `intakeLabel`.
- **Phone portrait:** logo top, offer middle, QR + button bottom.
- **iPad / landscape:** brand + offer left, QR(s) + button right.
- Primary QR must be scannable from ~3 ft: minimum ~45% of the shorter screen dimension on phone.
- **OLED drift:** shift the whole layout a few points in a slow random walk every few minutes to avoid burn-in. Must not be noticeable.
- **Lock icon:** small, low-contrast lock in a corner. Tap → Face ID / Touch ID / passcode → Vendor area. Failed auth just returns to display.
- Orientation lock honors `orientationPreference` (use `UIWindowScene.requestGeometryUpdate` + supported orientations).
- Disable idle timer while visible.

### 3. Visitor form (sheet over display)
- Header repeats the offer.
- Fields: Name (required), Email (required, basic format validation), Phone (optional). Correct keyboard types and autofill content types.
- Disclosure line under the button: "Your info goes only to [business name] so they can follow up. It stays on this device."
- Submit → save → "Thanks! [offer text]" confirmation → auto-return to display after 4 seconds.
- **Auto-reset:** if the form sits untouched for 60 seconds, clear it and dismiss.
- The form never shows, suggests, or autocompletes from previous leads.

### 4. Vendor area (behind auth)
- Lead count, list newest-first (name, email, time).
- Swipe to delete a lead. "Clear all leads" with confirmation.
- **Export CSV** via ShareLink. Filename: `ShowStand-<BoothName>-<YYYY-MM-DD>.csv`. Columns: `Date, Time, Name, Email, Phone`. Properly escape commas, quotes, and newlines. UTF-8.
- Edit Booth (all booth fields, including optional intake link + label).
- "Back to display" button.
- Re-lock when the app backgrounds or after 2 minutes idle in the vendor area.

## In scope (slice 0)
Single booth, setup flow, display, visitor form, auth-locked lead list, CSV export, keep-awake, orientation choice, OLED drift, optional second intake QR, Guided Access tip.

## Slice 1 (built 2026-10-21, still fully offline)
- **Business type** step after the name step (Products, Services, Coaching, Food, Art & Crafts, Events), stored on Booth. Offer suggestions are tailored per type (3–5 each, each with a one-line why). No AI.
- **Offer is optional:** "Skip — no offer". With no offer the display hides the offer text and the button reads "Stay in touch".
- **Visual:** background image (PhotosPicker + Files) with Fill/Fit and a dim slider; accent defaults to the logo's dominant color (Core Image), user can override; themes Clean / Bold / Dark, picked in Go Live and Edit Booth.
- **Movable, resizable QR** ("Edit layout" from Go Live and Edit Booth): drag, pinch or corner handle; white card with fixed minimum quiet zone; live "Scans from about X ft" (≈10× QR width, points→inches estimated from device class and screen size); hard minimum ≈1 ft; snap guides to center lines, edges and thirds with light haptics; stored as screen fractions, separately for portrait and landscape; button and lock stay fixed and the QR can't cover them; "Reset layout"; OLED drift still applies.

## Out of scope (do not build yet)
Multiple-booth UI, custom form questions, slides/slideshow, tags/notes, business-card scanning, Canva/share extension, Duo tabletop or book-mode layouts, outer-display control, follow-up emails, cloud sync, CRM or Google Sheets integration, analytics, payments, any networking.

## Acceptance tests (run on a real iPhone and the 10.5" iPad Pro)
1. Fresh install to live QR on screen in about 60 seconds.
2. QR scans reliably from 3 ft with a second phone, in both orientations.
3. A stranger can submit the form without help.
4. After submission, nothing from that lead is visible from the public screen.
5. Lock icon cannot be bypassed; vendor area re-locks on background.
6. CSV opens correctly in Numbers and Google Sheets, including a name with a comma in it.
7. Airplane mode: everything works.
8. Screen stays on for 4+ hours on a charger; check heat.

## Run on devices
Open in Xcode, sign with a personal team (free provisioning), run on connected devices. Free-provisioned builds expire after 7 days; just re-run. A paid developer account is only needed for TestFlight/App Store.
