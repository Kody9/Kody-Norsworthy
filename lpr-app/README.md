# SAL — Secure Auto Logger

A personal license-plate quick-capture app for iPhone: point the camera at a
plate, on-device OCR reads it, you confirm it, and it's saved locally with a
timestamp, GPS location, and a photo. Nothing ever leaves the device.

## What this app does — and deliberately does not do

- **Capture & log**: camera → on-device OCR (Apple Vision) → you confirm/edit
  the plate text, state, tag, and notes → saved to SwiftData, entirely on the
  phone.
- **History**: searchable/filterable/sortable log of everything you've
  captured, with a real map view, CSV export (whole log, current filter, or a
  single day), and a "clear all data" option.
- **Past sightings**: an entry's detail screen shows every other time that
  exact plate has been logged, tap one to jump straight to it.
- **No plate-to-owner lookup, ever.** DMV registration records are protected
  by the federal Driver's Privacy Protection Act (and most state equivalents).
  There is no legitimate public API that maps a plate to an owner's identity,
  and the "people search" sites that claim to are either non-functional or
  operating in violation of DPPA and their own data-source agreements. This
  app will not scrape or integrate with any of them.
  - `Sources/Services/OwnerLookupProvider.swift` defines a protocol
    (`OwnerLookupProviding`) as an extension point, left intentionally
    unimplemented. If your department later issues you authorized, audited
    API access to an RMS/NCIC system, that's the place to wire it in — not
    before.
  - **No real-time vehicle tracking.** This app has no concept of "where is
    this car right now" — only where *you* were standing when you captured
    a plate. Live location tracking of a vehicle is surveillance and
    requires legal process, not an app.

Use of this app — what you capture, retain, and do with it — is your
responsibility under your department's policy and applicable law. A
disclaimer to this effect shows on first launch (Settings → "View Usage
Disclaimer" to see it again).

## Project layout

```
lpr-app/
  project.yml              XcodeGen spec (optional, see setup below)
  Sources/
    PlateLogApp.swift      @main App entry point
    Models/
      PlateEntry.swift     SwiftData model
      USStates.swift        State abbreviation list
    Services/
      CameraController.swift   AVFoundation capture session + preview
      PlateOCRService.swift    Vision-based plate text recognition
      LocationService.swift    CoreLocation wrapper
      OwnerLookupProvider.swift  Unimplemented extension point (see above)
      CSVExporter.swift        Export entries to CSV
    Views/
      ContentView.swift, CaptureView.swift, ConfirmEntryView.swift,
      HistoryListView.swift, EntryDetailView.swift, SettingsView.swift,
      DisclaimerView.swift
```

## Setup (you'll need a Mac with Xcode — this can't be built/run from a
Linux/CI environment)

### Option A: XcodeGen (recommended, fastest)

```bash
brew install xcodegen
cd lpr-app
xcodegen generate
open PlateLog.xcodeproj
```

### Option B: Manual Xcode project

1. In Xcode: **File → New → Project → iOS → App**. Name it `PlateLog`,
   interface **SwiftUI**, storage **SwiftData**, minimum deployment **iOS 17**.
2. Delete the template's `ContentView.swift` and `PlateLogApp.swift`.
3. Drag the `Sources/Models`, `Sources/Services`, `Sources/Views` folders and
   `Sources/PlateLogApp.swift` into the project (check "Copy items if
   needed").
4. In the target's **Info** tab, add these keys (also listed in
   `project.yml` if you switch to Option A later):
   - `NSCameraUsageDescription` — "SAL uses the camera to capture
     license plate photos for your personal log."
   - `NSLocationWhenInUseUsageDescription` — "SAL records the location
     where each plate was captured."
   - `NSFaceIDUsageDescription` — "SAL can use Face ID to lock the app when
     App Lock is turned on in Setup."

### Running it

- **Camera capture only works on a real iPhone** — the iOS Simulator has no
  camera. You'll need a free Apple ID signed into Xcode to install a
  developer-signed build on your own device (Settings app → General → VPN &
  Device Management → trust the developer certificate after first install).
- Location works in the Simulator too (Xcode lets you simulate a GPS
  position), if you just want to test the UI flow before deploying to your
  phone.

## Known limitations

- The OCR plate-candidate filter is a simple heuristic (4–8 alphanumeric
  characters, at least one digit), not a specialized ALPR model — it will
  sometimes miss plates or pick up other text in frame. Always review/edit
  the suggested text before saving; that's why the confirm screen exists.
- VIN capture is manual entry only (no VIN-plate OCR, and no VIN decode
  lookup) — it's just a note field.
