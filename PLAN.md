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
- [ ] 2.12 Label print / reprint: moved to Phase 7 (needs the document decision, G1)

### Phase 3 — Loading sheet (Nov 3 – Nov 4)
- [x] 3.1 Loading sheet list: Open / Dispatched / Completed tabs
- [x] 3.2 New loading sheet: To hub (assigned hub preselected), To branch, Next stop (hubs only), same modes as web
- [x] 3.3 Add shipments by scan, typing or tick list; phone explains why a scanned AWB cannot be loaded; server checks again
- [x] 3.4 Running totals: shipment count, packages, weight
- [x] 3.5 Remove shipment from an open sheet; creating the sheet is the save (no separate finalize step on the server)
- [x] 3.6 Loading sheet detail, Generate THC button for open sheets
- [x] 3.7 Tests: eligibility, request shape per mode, create flow with scan (45 tests)
- [ ] 3.8 Print / share loading sheet: Phase 7 (G1)

### Phase 4 — THC (Nov 5)
- [ ] 4.1 Pick eligible loading sheet
- [ ] 4.2 Transporter, vehicle (from `/vehicles`), driver, route fields
- [ ] 4.3 Transport charges where API gives them
- [ ] 4.4 Dispatch OTP request / verify if required, generate THC
- [ ] 4.5 THC number and detail; block second generation
- [ ] 4.6 Tests: THC generation, duplicate block

### Phase 5 — DRS (Nov 6 – Nov 9)
- [ ] 5.1 Select eligible shipments (scan / list)
- [ ] 5.2 Assign authorized delivery partner
- [ ] 5.3 Generate DRS (out-for-delivery)
- [ ] 5.4 DRS list and detail: AWB, receiver, address, phone, COD / To-Pay amount
- [ ] 5.5 Status tabs: assigned, pending, delivered, failed
- [ ] 5.6 Open address in Google Maps; tap-to-call
- [ ] 5.7 Tests: assignment rules, status changes

### Phase 6 — POD (Nov 10 – Nov 11)
- [ ] 6.1 Pick shipment: scan, search, or from DRS
- [ ] 6.2 Camera capture and gallery pick, image compression
- [ ] 6.3 Receiver name, signature pad, remarks, delivery OTP if needed
- [ ] 6.4 Upload with progress; retry without duplicates
- [ ] 6.5 Confirm delivery through `/deliver` only after server accepts; show server status
- [ ] 6.6 Failed delivery with reason
- [ ] 6.7 Tests: upload, retry, network loss mid-upload

### Phase 7 — Documents, testing and release (Nov 12 – Nov 17)
- [ ] 7.1 Documents: label, loading sheet, THC, DRS, POD — server PDF if added, else built in app from API data with `pdf` package
- [ ] 7.2 Print (Android print service / Bluetooth printer if needed) and share
- [ ] 7.3 Error handling pass: offline banner, retry, keep form drafts
- [ ] 7.4 Full test run on dev server: every module + permission checks
- [ ] 7.5 UI polish, small and large screens
- [ ] 7.6 Release signing key, `README` build steps, release APK + AAB
- [ ] 7.7 Hand-over: source, build guide, test report

**Total: about 12–14 working days. Target finish Tue 2026-11-17.**

## Open questions
1. Documents: add server PDF endpoints in `courier-service`, or build PDFs in the app?
2. Printer: normal Android print, or a thermal / Bluetooth label printer?
3. Offline: needed in phase 1 scope, or online-only first?
4. Dev server URL and a test branch user for each role.
5. Which repo is final: `itshubhamrk-eng/courier-mobile-application` or `occplsoftech/courier-mobile-app`?
