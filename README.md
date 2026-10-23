# courier-mobile-application

Branch Operations Android app (Flutter) for the Courier Management SaaS. Client only: all business rules stay
in [`courier-service`](https://github.com/occplsoftech/courier-service).

- Plan and timeline: [`PLAN.md`](PLAN.md)
- Backend endpoints used: [`docs/API_MAP.md`](docs/API_MAP.md)
- Missing APIs and open questions: [`docs/API_GAPS.md`](docs/API_GAPS.md)

## Requirements
- Flutter 3.47.7 (stable), Java 21
- Android SDK (platform-tools, a recent platform and build-tools)

## Run

```bash
flutter pub get
flutter run --dart-define=API_BASE_URL=https://<dev-server> --dart-define=APP_ENV=dev
```

`API_BASE_URL` defaults to `http://10.0.2.2:8080` (a backend on the host machine, seen from the Android emulator).

## Check

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

## Layout

```
lib/
  core/        config, network (Dio client, API envelope, errors), theme, shared widgets
  features/    one folder per module (auth, dashboard, booking, tracking, loading_sheet, thc, drs, pod)
```

CI (`.github/workflows/ci.yml`) runs format, analyze, tests and a debug APK build on every pull request.
