# Branch Operations Android App — Delivery Plan

Flutter app for branch staff of the Multi-Company Courier Management SaaS. All business logic
(pricing, AWB, status transitions, validations) stays in
[`courier-service`](https://github.com/occplsoftech/courier-service) (Spring Boot 3, `/api/v1/**`, springdoc OpenAPI).
The app is a client only.

**Stack:** Flutter + Dart, Riverpod, Dio, flutter_secure_storage, mobile_scanner, camera + image_picker,
go_router, pdf + printing (documents), url_launcher (navigation).

## API map (first pass, from courier-service source)

| Feature | Existing API | Notes |
|---|---|---|
| Login / session | `POST /api/v1/auth/login`, `/refresh`, `/logout`, `GET /auth/me` | company + branch come from `/me` |
| Dashboard | `GET /api/v1/dashboard/summary`, `/shipments/summary`, `/manifests/summary` | check which counts are branch-scoped |
| Customers / addresses | `CustomerController` (`/customers`, `/customers/{id}/addresses`) | individual + business |
| Serviceability / pricing | `PincodeController`, `ServiceTypeController`, `PaymentModeController`, `PricingController` | freight from server only |
| Booking | `POST /api/v1/shipments`, `GET /shipments/{id}`, `/{id}/charges`, `/{id}/items` | AWB returned by server |
| Tracking | `GET /shipments/track/{trackingNumber}`, `/{id}/timeline`, `/{id}/history` | real events only |
| Loading sheet | `/api/v1/manifests` (create, list, detail, `eligible-destinations`, remove shipment) + `/hub-operations/out-scan` | "Loading Sheet" = manifest |
| THC | `/api/v1/shipment-movement/dispatch` (+ `dispatch-otp/request`, `/verify`), `/api/v1/vehicles` | THC = dispatch step |
| DRS | `/shipment-movement/out-for-delivery`, `GET /shipment-movement/drs`, `/drs/detail`, `/shipments/{id}/delivery-run` | |
| POD | `POST /shipment-movement/{id}/pod-upload` (multipart), `/deliver`, `/delivery-otp/*`, `/shipments/{id}/pod/verification` | deliver ≠ upload |
| Documents | `/shipments/{id}/documents` | **Gap:** web prints label / loading sheet / THC / DRS client-side (`window.print`), no server PDF endpoint |

Confirm every row against Swagger (`/swagger-ui.html`) in Phase 0 before coding.

## Phases, tasks and timeline

Built with Claude (Opus 5.5, medium effort; high for Phases 1 and 6). Dates assume you test each phase the
same or next day. Each phase ends with your test and sign-off before the next one starts.

### Phase 0 — Setup and API discovery (Oct 23 – Oct 26)
- [x] 0.1 Install Flutter SDK and Android command-line tools (SDK packages wait for license acceptance)
- [x] 0.2 Create Flutter project (`com.occpl.branch_ops`), folder structure (feature-first), lint rules
- [x] 0.3 Add packages: Riverpod, Dio, secure storage, go_router, scanner, camera, image_picker, pdf, printing
- [x] 0.4 Environments (dev / prod base URL) with `--dart-define`
- [x] 0.5 Write `docs/API_MAP.md` from source (live Swagger check pending a dev server URL)
- [x] 0.6 List missing APIs (documents, branch-scoped dashboard counts) in `docs/API_GAPS.md` for approval
- [x] 0.7 Theme (blue/white), shared widgets: cards, status badge, timeline, empty/error/loading states
- [x] 0.8 GitHub Actions: analyze + test + debug APK on every PR

### Phase 1 — Login, auth and dashboard (Oct 27 – Oct 28)
- [x] 1.1 Login screen, form validation, show server errors
- [x] 1.2 Token storage in secure storage; Dio interceptor adds token, refreshes on 401, logs out when refresh fails
- [x] 1.3 Company, branch, roles, permissions from the login / refresh response (`/auth/me` lacks branch and permissions)
- [x] 1.4 Hide quick actions and menu items the role cannot use (route guards added with each real screen; server checks every call)
- [x] 1.5 Logout, session-expired screen, no tokens in logs
- [x] 1.6 Bottom navigation: Home, Bookings, Loading Sheets, Delivery, More
- [x] 1.7 Dashboard: 9 count cards + 6 quick actions, pull-to-refresh
- [ ] 1.8 Tests: login, refresh, expiry, permissions, layout (done); branch isolation on the live server (needs test logins)

### Phase 2 — Shipment booking and tracking (Oct 29 – Nov 2)
- [x] 2.1 Customer picker (search individual / business)
- [x] 2.2 Sender / receiver and pickup / delivery address selection
- [x] 2.3 Destination pincode serviceability check
- [x] 2.4 Package details: quantity, weight, L × W × H (multiple pieces)
- [x] 2.5 Service type and payment mode from server
- [x] 2.6 Freight and charges previews from server; booking summary screen (final net amount from server after booking, see G9)
- [x] 2.7 Submit once (double-tap guard, no auto-retry; timeout warns to check Bookings), show AWB
- [x] 2.8 Shipment list (bookings tab) and shipment detail
- [x] 2.9 Track screen: AWB search + barcode / QR scan
- [x] 2.10 Movement timeline (hub, failed, hold, misroute, RTO), POD block when delivered
- [x] 2.11 Tests: booking happy path, timeout, validation errors, tracking (37 tests)
- [x] 2.12 Label print / reprint (Phase 7)

### Phase 3 — Loading sheet (Nov 3 – Nov 4)
- [x] 3.1 Loading sheet list: Open / Dispatched / Completed tabs
- [x] 3.2 New loading sheet: To hub (assigned hub preselected), To branch, Next stop (hubs only), same modes as web
- [x] 3.3 Add shipments by scan, typing or tick list; phone explains why a scanned AWB cannot be loaded; server checks again
- [x] 3.4 Running totals: shipment count, packages, weight
- [x] 3.5 Remove shipment from an open sheet; creating the sheet is the save (no separate finalize step on the server)
- [x] 3.6 Loading sheet detail, Generate THC button for open sheets
- [x] 3.7 Tests: eligibility, request shape per mode, create flow with scan (45 tests)
- [x] 3.8 Print / share loading sheet (Phase 7)

### Phase 4 — THC (Nov 5)
- [x] 4.1 Pick an open loading sheet (or arrive from the sheet's Generate THC button)
- [x] 4.2 Vehicle (active `/vehicles`), driver (`/users`), departure time. No transporter or route fields in the API (G7)
- [x] 4.3 Trip expenses the API takes: fuel, driver advance, toll, other
- [x] 4.4 Optional driver OTP (as on web), out-scan step when the sheet starts at a hub (server requires it), generate THC
- [x] 4.5 THC number (= loading sheet number) and details; a dispatched sheet shows its THC instead of a form; lost answer is settled by reading the sheet back
- [x] 4.6 Tests: generation, hub out-scan, lost answer, already dispatched (50 tests)
- [x] 4.7 Print / share THC (Phase 7)

### Phase 5 — DRS (Nov 6 – Nov 9)
- [x] 5.0 Receive incoming THCs (in-scan): scan / tick what arrived, the rest is reported missing (server raises a shortage ticket). Added: without it nothing becomes eligible for DRS
- [x] 5.1 Select eligible shipments (received at this branch; hub direct at hubs), by list or scan
- [x] 5.2 Assign delivery partner (staff list, G4), optional vehicle, fuel, delivery charge, optional partner OTP
- [x] 5.3 Generate DRS (out-for-delivery), per-shipment refusals listed
- [x] 5.4 DRS runs (today / 7 / 30 days) and run detail: AWB, receiver, address, phone, COD / To-Pay amount from payment-mode flags
- [x] 5.5 Status tabs: all, pending, delivered, not delivered
- [x] 5.6 Navigate (Google Maps) and call buttons
- [x] 5.7 Tests: receive with missing, DRS with refusal, run view, request shapes (56 tests)
- [x] 5.8 Print DRS (Phase 7)

### Phase 6 — POD (Nov 10 – Nov 11)
- [x] 6.1 Pick shipment: scan, search, or POD button on a DRS row / shipment detail; must be OUT_FOR_DELIVERY
- [x] 6.2 Camera and gallery via image_picker (JPEG quality 70, max 1600 px); `camera` package dropped
- [x] 6.3 Receiver name, signature pad, remarks. No delivery OTP on deliver (web sends none; partner OTP is at DRS)
- [x] 6.4 Upload to `/shipments/{id}/pod/verify` with progress; existing pending / approved POD reused; lost answer checked before retry
- [x] 6.5 Complete delivery via `/deliver` only after a usable POD; screen shows the status the server returns; lost answer settled by reading the shipment back
- [ ] 6.6 Failed delivery with reason: no branch-level API (G12); app explains and points to the branch manager
- [x] 6.7 Tests: wrong status, fresh upload, reuse, lost upload answer, rejected POD, lost deliver answer (63 tests)

### Phase 7 — Documents, testing and release
- [x] 7.1 Documents built in the app from server data (G1 option A): shipment labels (one 4×6 per package, barcode + QR of `<AWB>-NNN`), loading sheet, THC, DRS, POD
- [x] 7.2 Print and share through the Android print / share sheet (PdfPreview); Roboto bundled so ₹ prints offline
- [x] 7.3 Scanning accepts label package ids everywhere (found while building labels: web labels encode `<AWB>-NNN`)
- [ ] 7.4 Full test run on the dev server: every module + permission checks (blocked: needs server URL and test logins)
- [x] 7.5 UI polish: colourful dashboard, design review page of all screens, layout fixes from tests
- [x] 7.6 Release signing via `android/key.properties`, R8 shrink, README build steps; release AAB and split APKs build
- [ ] 7.7 Hand-over: signed release from your keystore, test report from the dev server run

**Total: about 12–14 working days. Target finish Tue 2026-11-17.**

## Open questions
1. Documents: add server PDF endpoints in `courier-service`, or build PDFs in the app?
2. Printer: normal Android print, or a thermal / Bluetooth label printer?
3. Offline: needed in phase 1 scope, or online-only first?
4. Dev server URL and a test branch user for each role.
5. Which repo is final: `itshubhamrk-eng/courier-mobile-application` or `occplsoftech/courier-mobile-app`?
