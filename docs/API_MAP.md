# API map — courier-service for the Branch Operations app

Source: `occplsoftech/courier-service` `main` (read 2026-10-23), controllers and DTO records.
Also compared with `itshubhamrk-eng/courier-management-backend` (`backend/`, 2026-10-23): every endpoint and DTO
field listed here is the same in both; the only differences are customer-portal endpoints and three extra
`CustomerResponse` fields in courier-service, none used by the app.
To check against the live Swagger (`/v3/api-docs`) once a dev server URL is available.

## Common shapes

Every response is wrapped:

```
ApiResponse<T> { success, message, data: T, errorCode, errors: [FieldError], timestamp, path, requestId }
PageResponse<T> { content: [T], page, size, totalElements, totalPages, first, last, hasNext }
```

- Auth header: `Authorization: Bearer <accessToken>`.
- IDs are UUIDs. Money and weight are `BigDecimal` (send as string or number, read as string to keep precision).
- Show `message` and `errors[]` from the server as-is on validation failures; log `requestId`, never tokens.

## 1. Auth (`/api/v1/auth`)

| Method | Path | Body | Returns |
|---|---|---|---|
| POST | `/login` | `LoginRequest { companyId?, companyCode?, email, password, rememberMe, deviceId, deviceName }` | `LoginResponse` |
| POST | `/refresh` | `{ refreshToken }` | `LoginResponse` (refresh token rotates every use) |
| POST | `/logout` | `{ refreshToken, allDevices }` | — |
| GET | `/me` | — | `CurrentUserResponse { id, companyId, email, displayName, phone, status, roles, companyName, companyLogo }` |
| POST | `/change-password`, `/forgot-password` | | |

`LoginResponse { accessToken, refreshToken, tokenType, expiresIn (≈900 s), refreshExpiresIn (≈7 d), sessionId,
userId, companyId, email, displayName, roles[], permissions[], branchId, hubId, companyName, companyLogo }`

- Branch and permissions come from **LoginResponse**, not `/me` (`/me` has no `branchId` / `permissions`).
  Store them with the session and reload on every refresh.
- Branch isolation is enforced by the server from the token; the app never sends another branch's ID except in
  pickers the server provides.

## 2. Dashboard

| Method | Path | Returns |
|---|---|---|
| GET | `/api/v1/dashboard/summary` | `DashboardSummaryResponse { statistics, recentShipments, recentActivity, companyOverview, branchOverview, charts }` |
| GET | `/api/v1/shipments/summary` | `ShipmentSummaryStatsResponse` (filters as query) |
| GET | `/api/v1/manifests/summary` | `ManifestSummaryStatsResponse` |
| GET | `/api/v1/shipment-movement/drs?from&to&deliveryBranchId` | `[DrsSummaryResponse]` |
| GET | `/api/v1/pod/pending-review` | `[PodVerificationResponse]` |

`statistics { todayShipments, todayBookings, delivered, inTransit, pending, pendingDelivery, todayCollection, … }`
`branchOverview { pipeline[], readyForManifest, manifestsAwaitingDispatch, pendingDelivery, delayedShipments, podOverview, rejectedPods[], toPayAwaitingDelivery, inScanPending }`

Card → source:

| Card | Source |
|---|---|
| Today's bookings | `statistics.todayBookings` |
| Pending loading sheets | `branchOverview.readyForManifest` |
| Generated loading sheets | `manifests/summary` (status `CREATED`) |
| Pending dispatches | `branchOverview.manifestsAwaitingDispatch` |
| Generated THC | `manifests/summary` (status `DISPATCHED`) |
| Pending DRS | `branchOverview.pendingDelivery` / `inScanPending` — confirm |
| Out for delivery | `shipments/summary` or `pipeline` stage `OUT_FOR_DELIVERY` |
| Delivered | `statistics.delivered` |
| Pending POD | `branchOverview.podOverview` — confirm fields |

## 3. Booking

| Method | Path | Notes |
|---|---|---|
| GET | `/api/v1/customers?…` | `PageResponse<CustomerSummaryResponse>` (id, customerCode, customerType, displayName, mobile, defaultPaymentMode) |
| GET | `/api/v1/customers/{id}` and `/{id}/addresses` | `CustomerAddressResponse` (ids for state/district/city/area/pincode, addressLine1/2, isDefaultPickup/Delivery) |
| GET | `/api/v1/global-masters/pincodes/lookup/{code}` | serviceability + area for a pincode |
| GET | `/api/v1/master/service-types` | paged |
| GET | `/api/v1/master/payment-modes` | paged, `cashOnDelivery` filter |
| GET | `/api/v1/branches/directory` | all active branches for pickers |
| POST | `/api/v1/pricing/calculate` | `PricingRequest` → `PricingResponse { chargeableWeight, volumetricWeight, chargeBreakup, … }` |
| POST | `/api/v1/shipments` | `CreateShipmentRequest` → `ShipmentResponse` (`shipmentNumber`, `trackingNumber` = AWB) |
| GET | `/api/v1/shipments/{id}`, `/{id}/charges`, `/{id}/items` | detail |
| GET | `/api/v1/shipments?…` | `PageResponse<ShipmentSummaryResponse>` |
| POST | `/api/v1/shipments/{id}/cancel?remarks=` | |

`CreateShipmentRequest` key fields: `bookingBranchId, pickupPincode, deliveryPincode, sender*/receiver*
(name, address, contact), serviceTypeId, packageTypeId, paymentModeId, shipmentType (DOCUMENT|NON_DOCUMENT|CARGO),
numberOfPackages, actualWeight, length, width, height, items[], declaredValue, invoiceValue, ewayBill,
deliveryType (DOOR|OFFICE), deliveryBranchId, destinationAreaId, businessCustomerId, flowType (STANDARD|MSRTC)`.

## 4. Tracking

| Method | Path | Returns |
|---|---|---|
| GET | `/api/v1/shipments/track/{trackingNumber}` | `ShipmentResponse` (AWB lookup; used after every scan) |
| GET | `/api/v1/shipments/{id}/timeline` | step list, completed/pending with time and user |
| GET | `/api/v1/shipments/{id}/history` | `[ShipmentStatusHistoryResponse { status, previousStatus, remarks, branchId, manifestId, vehicleId, changedBy, changedAt }]` |
| GET | `/api/v1/shipments/{id}/delivery-run` | DRS the shipment is on, or null |
| GET | `/api/v1/shipments/{id}/pod/verification` | POD photo, signature, status |
| GET | `/api/v1/hub-operations/exceptions?…` | hold / misroute / damaged / short / missing |

`ShipmentStatus`: `BOOKED, READY_FOR_MANIFEST, MANIFEST_CREATED, DISPATCHED, IN_SCAN, OUT_FOR_DELIVERY, DELIVERED, RETURNED, CANCELLED`.
`ShipmentExceptionType`: `MISSING, DAMAGED, SHORT, WRONG_DESTINATION, MISROUTED, ON_HOLD`.

## 5. Loading sheet (= manifest)

| Method | Path | Notes |
|---|---|---|
| GET | `/api/v1/manifests?status&bookingBranchId&deliveryBranchId&search&flowType` | `PageResponse<ManifestResponse>` |
| GET | `/api/v1/manifests/eligible-destinations?bookingBranchId=` | `[String]` next branch / hub |
| POST | `/api/v1/manifests` | `CreateManifestRequest { bookingBranchId, deliveryBranchId, deliveryMode (BRANCH_DELIVERY\|DIRECT_COMPANY_DELIVERY), destinationCity, shipmentIds[], remarks, hubTransfer, flowType }` |
| GET | `/api/v1/manifests/{id}`, `/{id}/shipments` | detail + shipment list |
| DELETE | `/api/v1/manifests/{id}/shipments/{shipmentId}` | remove one |
| POST | `/api/v1/hub-operations/out-scan` | `{ manifestId, hubBranchId, trackingNumbers[] }` → per-AWB `{ reference, success, message }` |

`ManifestResponse { id, manifestNumber, bookingBranchId, deliveryBranchId, deliveryMode, destinationCity, vehicleId,
driverUserId, status (CREATED|DISPATCHED|COMPLETED), dispatchedAt, departureTime, fuelCost, driverAdvance,
tollAmount, otherAmount, shipmentCount, totalWeight, totalPackages, version }`

Eligible shipments (as the web Loading Sheet page): `GET /api/v1/shipments?currentLocationId=<branch>&status=BOOKED&status=READY_FOR_MANIFEST&flowType=STANDARD`
plus `unassignedDeliveryBranch=true` for To hub / To branch, or `nextLocationId=<branch>` for Next stop (hub only).
Create sends `hubTransfer=true` for To hub. `eligible-destinations` is not used by the web page and not used here.

## 6. THC (= dispatch of a manifest)

| Method | Path | Body |
|---|---|---|
| GET | `/api/v1/vehicles?activeOnly=true` | `[VehicleResponse]` |
| POST | `/api/v1/shipment-movement/dispatch-otp/request` | `{ manifestId, driverUserId }` |
| POST | `/api/v1/shipment-movement/dispatch-otp/verify` | `{ manifestId, driverUserId, otp }` |
| POST | `/api/v1/shipment-movement/dispatch` | `{ manifestId, vehicleId, driverUserId, departureTime, fuelCost, driverAdvance, tollAmount, otherAmount }` → `DispatchManifestResponse` |

Server moves manifest `CREATED → DISPATCHED`, so a second dispatch is rejected ("already been dispatched").
The THC number is the manifest number (as on the web Trip Hire Challan page). Driver OTP is optional on web and here.
When the sheet's booking branch is a HUB, every shipment must first be out-scanned
(`POST /api/v1/hub-operations/out-scan`, `{manifestId, hubBranchId, trackingNumbers}`), or dispatch fails with
"has shipments that have not been out-scanned yet". Drivers come from `GET /api/v1/users?status=ACTIVE` (see G4).

## 7. DRS

| Method | Path | Body / params |
|---|---|---|
| POST | `/api/v1/shipment-movement/out-for-delivery` | `{ shipmentIds[], deliveryUserId, vehicleId, fuelCost, deliveryCharge }` → `BulkMovementResponse { results[], successCount, failureCount, drsNumber }` |
| GET | `/api/v1/shipment-movement/drs?from&to&deliveryBranchId` | `[DrsSummaryResponse { deliveryUserId, runDate, drsNumber, shipmentCount, deliveredCount, pendingCount }]` |
| GET | `/api/v1/shipment-movement/drs/detail?deliveryUserId&deliveryBranchId&runDate` | `DrsDetailResponse { drsNumber, shipments[] }` |

Eligible shipments (as the web Out For Delivery page): `deliveryBranchId=<branch>&status=IN_SCAN`; at a hub, hub direct:
`currentLocationId=<hub>&unassignedDeliveryBranch=true&status=READY_FOR_MANIFEST`. In-scan, out-for-delivery and deliver need
role COMPANY_ADMIN, BRANCH_MANAGER or OPERATOR on the server.

Receiving (before DRS): incoming THCs `GET /api/v1/manifests?status=DISPATCHED&deliveryBranchId=<branch>`, then
`POST /api/v1/shipment-movement/in-scan` `{receivingBranchId, trackingNumbers[], manifestNumber, missingTrackingNumbers[], remarks, photoUrl}`
→ per-AWB results + `shortageTicketNumber`. The server refuses a shipment that is not DISPATCHED, so a repeat cannot double-receive.

## 8. POD and delivery

| Method | Path | Body |
|---|---|---|
| POST | `/api/v1/shipment-movement/{shipmentId}/pod-upload` | multipart `file`, `kind` = `PHOTO`\|`SIGNATURE` → `{ url }` (upload only, no status change) |
| POST | `/api/v1/shipment-movement/delivery-otp/request` / `/verify` | `{ deliveryUserId }` / OTP |
| POST | `/api/v1/shipment-movement/deliver` | `{ shipmentId, receiverName, remarks, otp, signatureUrl, photoUrl }` → `ShipmentResponse` (status change) |
| POST | `/api/v1/pod/company-upload/{shipmentId}` | multipart `photo`, `signature?`, `receiverName`, `deliveryDate`, `deliveredBy`, `podDate`, `podTime`, `status` (DELIVERED\|NOT_DELIVERED\|RETURNED\|RTO), `remark` |
| GET | `/api/v1/shipments/{shipmentId}/pod/verification` | `PodVerificationResponse` |

Flow in the app (same as the web delivery page): `POST /shipments/{id}/pod/verify` (multipart `photo`, `signature?`,
`receiverName`, `awbNumber`, `shipmentNumber`, `deliveryDateTime`) → `PodVerificationResponse` (always PENDING for a branch;
PASS / FAIL after company review) → `POST /shipment-movement/deliver` `{shipmentId, receiverName, remarks}` → show the
returned status. Each verify call stores a new POD row, so the app reads `GET /shipments/{id}/pod/verification` first and
reuses a PENDING / PASS one. Verify and deliver need COMPANY_ADMIN, BRANCH_MANAGER or OPERATOR.

## 9. Documents

| Method | Path |
|---|---|
| GET | `/api/v1/shipments/{id}/documents` |
| POST | `/api/v1/shipments/{id}/documents` |

No PDF endpoint for label, loading sheet, THC or DRS. See `API_GAPS.md`.
