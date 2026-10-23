# courier-mobile-application

Branch Operations Android app (Flutter) for the Courier Management SaaS. Branch staff book shipments, track them,
make loading sheets, generate THC and DRS, receive incoming THCs, upload POD, and print labels and sheets.

The app is a client only: prices, AWB numbers, statuses and every business rule stay on the server
([`courier-service`](https://github.com/occplsoftech/courier-service); the same API also lives in
`itshubhamrk-eng/courier-management-backend`).

- Plan, phases and status: [`PLAN.md`](PLAN.md)
- Endpoints used: [`docs/API_MAP.md`](docs/API_MAP.md)
- Missing APIs and decisions: [`docs/API_GAPS.md`](docs/API_GAPS.md)

## Requirements

- Flutter 3.47.7 (stable), Java 21
- Android SDK: platform-tools, Android 36, build-tools 36 (Gradle downloads the NDK on first build)
- Disk: about 8 GB free for the first build

## Run on a phone

1. Turn on USB debugging on the phone and connect it (`flutter devices` should list it).
2. Run against the dev server:

```bash
flutter run --dart-define=API_BASE_URL=https://<dev-server> --dart-define=APP_ENV=dev
```

`API_BASE_URL` is the server origin without `/api/v1`. Without it the app calls `http://10.0.2.2:8080` (a backend on
the same computer, seen from the Android emulator). `APP_ENV=dev` logs request method, path and status only; never
headers, bodies or tokens.

## Release build

### 1. Signing key (once)

Create an upload keystore and keep it, and its passwords, outside git and backed up. Losing it means a new Play
Store listing.

```bash
keytool -genkey -v -keystore ~/keys/branch-ops-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Copy `android/key.properties.example` to `android/key.properties` (git-ignored) and fill in the path and passwords.
Without `key.properties`, release builds are signed with the debug key: fine for testing, not for the Play Store.

### 2. Version

Raise `version:` in `pubspec.yaml` for every release (`1.0.1+2`: name `1.0.1`, build number `2`; the build number
must always go up).

### 3. Build

Play Store bundle:

```bash
flutter build appbundle --release --dart-define=API_BASE_URL=https://<prod-server> --dart-define=APP_ENV=prod
```

APKs for direct install (one per phone CPU type; most phones use `arm64-v8a`):

```bash
flutter build apk --release --split-per-abi --dart-define=API_BASE_URL=https://<prod-server> --dart-define=APP_ENV=prod
```

Output: `build/app/outputs/bundle/release/app-release.aab` and `build/app/outputs/flutter-apk/app-*-release.apk`.
Release builds need an `https://` server: Android blocks plain `http` in release apps.

## Checks

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

CI (`.github/workflows/ci.yml`) runs the same checks and a debug APK build on every pull request.

Screens for design review (renders every screen with sample data to `test_screenshots/screens/`):

```bash
flutter test test_screenshots --update-goldens
```

## Layout

```
lib/
  core/        config, network (Dio client, auth refresh, API envelope, errors), theme, shared widgets, scan codes
  features/
    auth/          sign in, session restore and refresh, permissions
    dashboard/     branch counts and quick actions
    booking/       four-step booking
    shipments/     bookings list, shipment detail, timeline
    tracking/      Track Shipment
    loading_sheet/ loading sheets (manifests)
    thc/           Trip Hire Challan (dispatch), staff picker
    drs/           receive THCs (in-scan), DRS, delivery runs
    pod/           proof of delivery and delivery confirmation
    documents/     PDF labels, loading sheet, THC, DRS, POD; print and share
assets/fonts/  Roboto for PDFs (Apache 2.0, see Roboto_LICENSE.txt)
```

## Scanning

Labels printed by the web app and by this app carry a package id in the barcode and QR (`<AWB>-001`, `<AWB>-002`, ...).
Every scan field accepts a package id, an AWB or a shipment number.
