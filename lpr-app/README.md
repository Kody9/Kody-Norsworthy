# SAL — Secure Auto Logger

A personal license-plate quick-capture app for iPhone: point the camera at a
plate, on-device OCR reads it, you confirm it, and it's saved locally with a
timestamp, GPS location, and a photo. By default nothing ever leaves the
device — optional group sync (see below) is the one exception, and only
syncs the text fields, never photos.

## What this app does — and deliberately does not do

- **Capture & log**: camera → on-device OCR (Apple Vision) → you confirm/edit
  the plate text, state, tag, and notes → saved to SwiftData, entirely on the
  phone.
- **History**: searchable/filterable/sortable log of everything you've
  captured, with a real map view, CSV export (whole log, current filter, or a
  single day), and a "clear all data" option.
- **Past sightings**: an entry's detail screen shows every other time that
  exact plate has been logged, tap one to jump straight to it.
- **Group sync (optional, off by default)**: Setup → GROUP lets a trusted
  group of people (e.g. family/friends who also run this app) share a
  single log. Everyone types the same group code and a display name — no
  accounts, no login screen. Once joined, entries anyone in the group logs
  (plate, state, tag, notes, driver name, time, location — never photos)
  sync to everyone else's phone and merge into their local History, so the
  existing duplicate/BOLO-match banners on the Read screen catch a plate a
  groupmate already logged, not just ones you logged yourself. Requires a
  Firebase project you set up yourself — see "Group sync setup" below. The
  app works completely normally, fully local, without ever doing this.
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
      GroupSyncService.swift   Optional Firebase-backed group sync (see below)
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

## Group sync setup (optional)

Skip this whole section if you only ever want SAL fully local on one
phone — everything above works with zero setup. This is only needed to
turn on Setup → GROUP.

SAL doesn't ship with a backend of its own; it talks to a Firebase project
you create and own. Nobody but the people you give the group code to can
read or write your group's data.

1. **Create a Firebase project.** Go to
   [console.firebase.google.com](https://console.firebase.google.com),
   create a new project (any name — e.g. "SAL Group Log"). You don't need
   Google Analytics for this; you can decline it.
2. **Add an iOS app to the project.** In the project's settings, add an
   iOS app. The **bundle ID must exactly match**
   `com.kodynorsworthy.platelog` (from `project.yml`) or the app won't be
   able to find its configuration.
3. **Download `GoogleService-Info.plist`** from that step, and drop the
   file into `lpr-app/Sources/` in this repo (same folder as
   `PlateLogApp.swift`). XcodeGen's `sources: [Sources]` picks up any file
   in that tree automatically — no `project.yml` change needed. Re-run
   `xcodegen generate` after adding it.
4. **Enable Anonymous authentication.** In the Firebase console: Build →
   Authentication → Sign-in method → enable **Anonymous**. SAL uses this
   silently (no login screen) purely so Firestore's security rules below
   have a `request.auth` to check — it's not tied to anyone's real
   identity.
5. **Create a Firestore database.** Build → Firestore Database → Create
   database. Any region is fine; start in production mode (the rules
   below replace the defaults either way).
6. **Paste in these security rules** (Firestore Database → Rules):
   ```
   rules_version = '2';
   service cloud.firestore {
     match /databases/{database}/documents {
       match /groups/{groupCode}/entries/{entryId} {
         allow read, write: if request.auth != null;
       }
     }
   }
   ```
   This means: anyone who has the app installed and knows a group's code
   can read and write that group's entries, and nothing else. There's no
   per-person access control beyond the code itself — same trust model as
   a shared Wi-Fi password. Pick group codes accordingly (not `"1234"`).
7. **Rebuild and run.** Setup → GROUP will go from "add
   GoogleService-Info.plist" to a real join form once the app finds that
   file in its bundle.

Photos never sync, in either direction — only plate, state, VIN, driver
name, notes, tag, timestamp, and location. Deleting an entry only deletes
it on your own device; it isn't removed from the group or from anyone
else's copy (no delete-sync in this first pass).

## Known limitations

- The OCR plate-candidate filter is a simple heuristic (4–8 alphanumeric
  characters, at least one digit), not a specialized ALPR model — it will
  sometimes miss plates or pick up other text in frame. Always review/edit
  the suggested text before saving; that's why the confirm screen exists.
- VIN capture is manual entry only (no VIN-plate OCR, and no VIN decode
  lookup) — it's just a note field.
- Group sync is one-way-append only: new entries push and pull, but an
  edit (e.g. correcting a plate after the fact) or a delete only applies
  on the device that made it, not across the group. Editing a plate on a
  synced entry is local-only until this is addressed.
