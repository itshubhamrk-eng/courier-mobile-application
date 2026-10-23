# API gaps and questions

Found while mapping `courier-service` for the mobile app. Nothing here is built or changed in the backend
until approved.

| # | Gap | Impact on app | Proposal |
|---|---|---|---|
| G1 | No PDF / print endpoint for shipment label, loading sheet, THC, DRS. Web builds them in the browser (`window.print`). | Phase 7 documents | **A:** build PDFs in the app from API data (`pdf` package), no backend change. **B:** add `GET …/{id}/pdf` endpoints so web and mobile share one template. |
| G2 | `POST /api/v1/shipments` has no `Idempotency-Key` (the customer-portal booking does). | A retry after a timeout can book twice. | App: never auto-retry booking; on timeout, look up recent shipments before allowing resubmit. Backend (optional): accept `Idempotency-Key` like `PortalBookingService`. |
| G3 | `ShipmentStatus` has no failed-delivery, hold or misroute status; those live in hub exceptions (`ON_HOLD`, `MISROUTED`) and POD entry status (`NOT_DELIVERED`, `RTO`). | Tracking badges and failed-delivery screen | App combines status history + exceptions + POD entry. Confirm the failed-delivery path the web uses. |
| G4 | No clear endpoint listing delivery partners / drivers for a branch user (`/api/v1/users` may need admin permission). | DRS partner picker, THC driver picker | Check what the web DRS / THC pages call; add a branch-scoped picker endpoint only if none exists. |
| G5 | `/auth/me` has no `branchId` or `permissions`; only `LoginResponse` has them. | App restart with a saved token | App uses the refresh response, which is a full `LoginResponse`. No change needed. |
| G6 | Dashboard cards "Generated THC" and "Pending POD" have no single field. | Phase 1 dashboard | Use `manifests/summary` and `branchOverview.podOverview`; confirm the field names on the live server. |
| G7 | Transporter (third-party carrier) is not a field on dispatch; dispatch takes `vehicleId` and `driverUserId` only. | THC form | Show vehicle + driver + charges only, unless a transporter master exists. |

## Needed from you
1. Dev server base URL (Swagger reachable) and one test login per role: branch booking clerk, branch manager, delivery partner.
2. Decision on G1 (A or B).
3. Confirm the final repo.
