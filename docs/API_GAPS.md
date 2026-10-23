# API gaps and questions

Found while mapping `courier-service` for the mobile app. Nothing here is built or changed in the backend
until approved.

| # | Gap | Impact on app | Proposal |
|---|---|---|---|
| G1 | No PDF / print endpoint for shipment label, loading sheet, THC, DRS. Web builds them in the browser (`window.print`). | Phase 7 documents | **A:** build PDFs in the app from API data (`pdf` package), no backend change. **B:** add `GET …/{id}/pdf` endpoints so web and mobile share one template. |
| G2 | `POST /api/v1/shipments` has no `Idempotency-Key` (the customer-portal booking does). | A retry after a timeout can book twice. | App: never auto-retry booking; on timeout, look up recent shipments before allowing resubmit. Backend (optional): accept `Idempotency-Key` like `PortalBookingService`. |
| G3 | `ShipmentStatus` has no failed-delivery, hold or misroute status; those live in hub exceptions (`ON_HOLD`, `MISROUTED`) and POD entry status (`NOT_DELIVERED`, `RTO`). | Tracking badges and failed-delivery screen | App combines status history + exceptions + POD entry. Confirm the failed-delivery path the web uses. |
| G4 | Drivers / delivery partners come from `GET /api/v1/users` (as on web), which needs COMPANY_ADMIN, BRANCH_MANAGER, HUB_MANAGER or `USER_READ`. A booking operator gets 403. | THC driver picker, DRS partner picker | App shows "your role cannot list drivers". Backend (proposed): a small branch-scoped picker (id, name, mobile) readable with `MANIFEST_DISPATCH` / `DELIVERY_ASSIGN`. |
| G5 | `/auth/me` has no `branchId` or `permissions`; only `LoginResponse` has them. | App restart with a saved token | App uses the refresh response, which is a full `LoginResponse`. No change needed. |
| G6 | Dashboard cards "Generated THC" and "Pending POD" have no single field. | Phase 1 dashboard | Built as: loading sheets = `manifests/summary?status=CREATED`, THC in transit = `status=DISPATCHED`, waiting for DRS / out for delivery = `shipments/summary` `statusCounts` (`IN_SCAN`, `OUT_FOR_DELIVERY`) for `deliveryBranchId`, delivered today = `deliveredDateFrom/To`, POD = `branchOverview.podOverview.pendingUpload`. Confirm on the live server. |
| G8 | Login needs a company: `LoginRequest` documents `companyCode` as reserved, but `AuthService` resolves it and the web login sends it. | Login screen | App asks for company code (remembered after first login). |
| G7 | Transporter (third-party carrier) is not a field on dispatch; dispatch takes `vehicleId` and `driverUserId` only. | THC form | Show vehicle + driver + charges only, unless a transporter master exists. |
| G9 | No booking dry-run endpoint. The web screen calls `/pricing/calculate` and `/district-level-freight/calculate`, then works out net amount, GST and round-off itself in the browser. | Booking summary | App shows both server previews line by line but **no total of its own**; the final net amount comes from the server after booking (`/shipments/{id}/charges`). Backend (proposed): `POST /api/v1/shipments/preview` taking `CreateShipmentRequest`, running the same pricing as create without saving, returning the charge breakup and net amount. |
| G10 | Chargeable weight for the previews must be computed before calling them (both endpoints take a weight). | Booking summary | App applies the server's rule from `ShipmentServiceImpl.summariseWeight` (volumetric L×W×H/5000 × qty, max with actual and the company minimum), as the web does. Preview input only; the server recomputes on booking. G9 would remove this. |
| G12 | No failed-delivery API for branch staff. `ShipmentStatus` has no failed state; NOT_DELIVERED / RETURNED / RTO exist only as `PodEntryStatus` on `/pod/company-upload` (COMPANY_ADMIN). | POD screen | App shows "Could not deliver?" with an explanation, records nothing. Backend (proposed): `POST /shipment-movement/{id}/delivery-attempt` with reason code (refused, address not found, customer away, reschedule) that keeps or returns the shipment to IN_SCAN and logs history. |
| G11 | Two backend repos with the same APIs: `occplsoftech/courier-service` and `itshubhamrk-eng/courier-management-backend` (`backend/`), both changing. | Which server the app talks to | Contract is identical for the app today. Need to know which one is deployed, and keep them in step (or retire one). |

## Booking features not in the mobile app (use the web app)
Crossing branches, appointment delivery, MSRTC flow, manual shipment number, rate / freight-factor / net-amount overrides, other-charges and ODA overrides, E-Way Bill document upload. Each can be added later if branch staff need it on mobile.

## Needed from you
1. Dev server base URL (Swagger reachable) and one test login per role: branch booking clerk, branch manager, delivery partner.
2. Decision on G1 (A or B).
3. Confirm the final repo.
