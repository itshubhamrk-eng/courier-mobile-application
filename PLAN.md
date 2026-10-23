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

Estimates are working days, one developer, starting **Mon 2026-10-26**. Each phase ends with your
test and sign-off before the next one starts.

### Phase 0 — Setup and API discovery (3 days · Oct 26 – Oct 28)
- [ ] 0.1 Install Flutter SDK, Android SDK and emulator (Flutter not on this Mac yet)
- [ ] 0.2 Create Flutter project (`com.occpl.branchops`), folder structure (feature-first), lint rules
- [ ] 0.3 Add packages: Riverpod, Dio, secure storage, go_router, scanner, camera, image_picker, pdf, printing
- [ ] 0.4 Environments (dev / prod base URL) with `--dart-define`
- [ ] 0.5 Pull OpenAPI JSON from dev server; confirm the API map above; write `docs/API_MAP.md`
- [ ] 0.6 List missing APIs (documents, branch-scoped dashboard counts) in `docs/API_GAPS.md` for approval
- [ ] 0.7 Theme (blue/white), shared widgets: cards, status badge, timeline, empty/error/loading states
- [ ] 0.8 GitHub Actions: analyze + test + debug APK on every PR

### Phase 1 — Login, auth and dashboard (5 days · Oct 29 – Nov 4)
- [ ] 1.1 Login screen, form validation, show server errors
- [ ] 1.2 Token storage in secure storage; Dio interceptor adds token, refreshes on 401, logs out when refresh fails
- [ ] 1.3 Load `/auth/me`: company, branch, roles, permissions into a session provider
- [ ] 1.4 Permission guard for routes and buttons; hide what role cannot do
- [ ] 1.5 Logout, session-expired screen, no tokens in logs
- [ ] 1.6 Bottom navigation: Home, Bookings, Loading Sheets, Delivery, More
- [ ] 1.7 Dashboard: 9 count cards + 6 quick actions, pull-to-refresh
- [ ] 1.8 Tests: login, refresh, expiry, branch isolation (other branch IDs rejected by server)

### Phase 2 — Shipment booking and tracking (8 days · Nov 5 – Nov 16)
- [ ] 2.1 Customer picker (search individual / business)
- [ ] 2.2 Sender / receiver and pickup / delivery address selection
- [ ] 2.3 Destination pincode serviceability check
- [ ] 2.4 Package details: quantity, weight, L × W × H (multiple pieces)
- [ ] 2.5 Service type and payment mode from server
- [ ] 2.6 Freight and charges from server; booking summary screen
- [ ] 2.7 Submit once (double-tap guard, idempotent retry), show AWB
- [ ] 2.8 Shipment list (bookings tab) and shipment detail
- [ ] 2.9 Track screen: AWB search + barcode / QR scan
- [ ] 2.10 Movement timeline (hub, failed, hold, misroute, RTO), POD block when delivered
- [ ] 2.11 Tests: booking happy path, validation errors, tracking

### Phase 3 — Loading sheet (5 days · Nov 17 – Nov 23)
- [ ] 3.1 Loading sheet list with filters
- [ ] 3.2 New loading sheet: pick next branch / hub from `eligible-destinations`
- [ ] 3.3 Add shipments by scan or search; server checks eligibility; block duplicates
- [ ] 3.4 Running totals: shipment count, packages, weight
- [ ] 3.5 Remove shipment, save, finalize
- [ ] 3.6 Loading sheet detail
- [ ] 3.7 Tests: eligibility, duplicate, incompatible shipment

### Phase 4 — THC (4 days · Nov 24 – Nov 27)
- [ ] 4.1 Pick eligible loading sheet
- [ ] 4.2 Transporter, vehicle (from `/vehicles`), driver, route fields
- [ ] 4.3 Transport charges where API gives them
- [ ] 4.4 Dispatch OTP request / verify if required, generate THC
- [ ] 4.5 THC number and detail; block second generation
- [ ] 4.6 Tests: THC generation, duplicate block

### Phase 5 — DRS (5 days · Nov 30 – Dec 4)
- [ ] 5.1 Select eligible shipments (scan / list)
- [ ] 5.2 Assign authorized delivery partner
- [ ] 5.3 Generate DRS (out-for-delivery)
- [ ] 5.4 DRS list and detail: AWB, receiver, address, phone, COD / To-Pay amount
- [ ] 5.5 Status tabs: assigned, pending, delivered, failed
- [ ] 5.6 Open address in Google Maps; tap-to-call
- [ ] 5.7 Tests: assignment rules, status changes

### Phase 6 — POD (5 days · Dec 7 – Dec 11)
- [ ] 6.1 Pick shipment: scan, search, or from DRS
- [ ] 6.2 Camera capture and gallery pick, image compression
- [ ] 6.3 Receiver name, signature pad, remarks, delivery OTP if needed
- [ ] 6.4 Upload with progress; retry without duplicates
- [ ] 6.5 Confirm delivery through `/deliver` only after server accepts; show server status
- [ ] 6.6 Failed delivery with reason
- [ ] 6.7 Tests: upload, retry, network loss mid-upload

### Phase 7 — Documents, testing and release (7 days · Dec 14 – Dec 22)
- [ ] 7.1 Documents: label, loading sheet, THC, DRS, POD — server PDF if added, else built in app from API data with `pdf` package
- [ ] 7.2 Print (Android print service / Bluetooth printer if needed) and share
- [ ] 7.3 Error handling pass: offline banner, retry, keep form drafts
- [ ] 7.4 Full test run on dev server: every module + permission checks
- [ ] 7.5 UI polish, small and large screens
- [ ] 7.6 Release signing key, `README` build steps, release APK + AAB
- [ ] 7.7 Hand-over: source, build guide, test report

**Total: 42 working days, about 9 weeks. Target finish Tue 2026-12-22.**

## Open questions
1. Documents: add server PDF endpoints in `courier-service`, or build PDFs in the app?
2. Printer: normal Android print, or a thermal / Bluetooth label printer?
3. Offline: needed in phase 1 scope, or online-only first?
4. Dev server URL and a test branch user for each role.
5. Which repo is final: `itshubhamrk-eng/courier-mobile-application` or `occplsoftech/courier-mobile-app`?
