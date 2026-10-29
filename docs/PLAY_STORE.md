# Play Store release: Courier Pro

Answers for each Play Console section. Keep them in step with the app and with the
privacy policy page; if the app starts using new data or permissions, update all three.

| Item | Value |
|---|---|
| App name | Courier Pro |
| Package | `com.softech.branch_ops` (permanent once uploaded) |
| Developer | OCCPL Softech Private Limited |
| Support email | support@occplsoftech.com |
| Phone | +91 97677 89780 |
| Website | https://www.occplsoftech.com |
| Privacy policy | https://www.occplsoftech.com/privacy/courier-pro |
| Delete account URL | https://www.occplsoftech.com/courier-pro/delete-account |
| Category | Business |
| Free / paid | Free, no Play in-app purchases, no ads (branch wallet recharge is paid to the courier company through Razorpay, see section 8) |

The two policy pages ship with the softech-website repo (`src/app/pages/legal/courier-pro-*.ts`).
They must be live before you submit.

## 1. Signing and build

Create the upload key once and keep it, and its passwords, out of git. Losing it means
asking Google for an upload-key reset.

```bash
keytool -genkey -v -keystore ~/keys/courier-pro-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

`android/key.properties` (git-ignored):

```properties
storePassword=...
keyPassword=...
keyAlias=upload
storeFile=/Users/<you>/keys/courier-pro-upload.jks
```

Build the bundle (Play needs `.aab`, not `.apk`). Raise `--build-number` for every upload.

```bash
flutter build appbundle --release --build-number=1 --obfuscate --split-debug-info=build/symbols --dart-define=API_BASE_URL=https://vendor.amazinglpl.com --dart-define=APP_ENV=prod
```

Output: `build/app/outputs/bundle/release/app-release.aab`. Keep `build/symbols` for each release:
it is needed to read obfuscated crash stack traces (`flutter symbolize`).

Sideload APK (one per CPU type, about 11 MB each; give phones `app-arm64-v8a-release.apk`):

```bash
flutter build apk --release --split-per-abi --obfuscate --split-debug-info=build/symbols --dart-define=API_BASE_URL=https://vendor.amazinglpl.com --dart-define=APP_ENV=prod
```

Barcode scanning uses the ML Kit model from Google Play services (not bundled, saves about
5 MB), so phones need Play services; the model downloads at install or on first scan. Enrol in Play App Signing when asked.

## 2. App access

All features need a sign-in, so give the reviewers a working account.

- Choose "All or some functionality is restricted".
- Instructions:
  > Courier Pro is for the branch staff of courier companies. Accounts are created by the
  > company; there is no sign-up. Sign in with the details below. The account is a
  > branch operator at a demo branch with sample shipments.
- Username / password: a dedicated **reviewer** account on prod (operator role, demo
  branch, no real customer data). Create it in the web app; do not reuse a staff login.
  Keep it active and don't change its password while a review is open.

## 3. Ads

No, the app has no ads.

## 4. Content rating (IARC questionnaire)

- Category: "All other app types" (utility / productivity / business).
- Violence, sexual content, language, controlled substances, gambling: No.
- User-generated content shared with other users: No (data is visible only to staff of the same company).
- Shares the user's location: No.
- Digital purchases: No.

Expected rating: Everyone / 3+.

## 5. Target audience and content

- Target age: 18 and over only.
- Appeals to children: No.

## 6. Data safety

Overview answers:

- Does the app collect or share any of the required user data types? **Yes**
- Is all user data encrypted in transit? **Yes** (HTTPS only)
- Do you provide a way for users to request deletion? **Yes**, URL above.

"Shared" means sent to a third party. Data sent to our own servers that host the
service for the courier company counts as collected, not shared. Service providers acting
for us (hosting, file storage) are not "sharing" either.

| Data type | Collected | Shared | Optional? | Purposes |
|---|---|---|---|---|
| Personal info: Name | Yes | No | Required | App functionality, Account management |
| Personal info: Email address | Yes | No | Required | App functionality, Account management |
| Personal info: Phone number | Yes | No | Required | App functionality |
| Personal info: Address | Yes | No | Required | App functionality |
| Photos and videos: Photos | Yes | No | Optional | App functionality (proof-of-delivery photos) |
| Files and docs | Yes | No | Optional | App functionality (shipment documents, signature image) |
| App info and performance: Diagnostics | Yes | No | Required | Analytics (Google ML Kit, see below) |
| Device or other IDs | Yes | No | Required | App functionality, Fraud prevention, security and compliance (installation ID for the signed-in device list; device details the Razorpay SDK uses for payment fraud checks) |
| Financial info: User payment info | Yes | No | Optional | App functionality (wallet recharge), Fraud prevention, security and compliance |
| Financial info: Purchase history | Yes | No | Optional | App functionality (wallet recharges, ledger, receipts) |

Not collected: location, credit score, other financial info, health, messages, contacts,
calendar, audio, web browsing, app activity, advertising ID.

Collection is not "ephemeral" for any of these: they are stored on the server.

Notes:

- Name, phone and address cover both the staff user and the sender / receiver entered on a booking.
- Barcode scanning uses Google ML Kit on the device. Camera frames stay on the device, but
  the ML Kit library may send Google device and performance diagnostics, which is why
  Diagnostics is declared.
- There is no analytics, crash reporting or ads SDK in the app.
- Wallet recharge uses Razorpay Standard Checkout (`razorpay_flutter`). Card, UPI, net banking
  and wallet details are entered in Razorpay's checkout and go to Razorpay, the payment
  processor acting for the courier company; the app and our servers never see or store them.
  Our servers keep the recharge amount, Razorpay order / payment IDs and status, and the wallet
  ledger. A payment processor acting on our behalf is a service provider, so this is
  "collected", not "shared". User payment info is optional: only staff who recharge enter it.

## 7. Permissions

From the merged release manifest (`aapt2 dump permissions`):

| Permission | Why |
|---|---|
| `CAMERA` | Scan shipment barcodes / QR codes; take proof-of-delivery photos. Requested only when the scanner or camera opens. |
| `INTERNET` | Talk to the courier server. |
| `ACCESS_NETWORK_STATE` | Show the offline banner and avoid sending while offline. |
| `NFC` | Added by the Razorpay SDK: tap-to-pay cards in checkout. Normal permission, no prompt. |
| `READ_BASIC_PHONE_STATE` | Added by the Razorpay SDK (Android 13+): basic device / SIM state for UPI payment flows. Normal permission, no prompt; it cannot read the phone number or call log. |

Gallery picks use the Android photo picker, so there is no storage or media permission.
No location, contacts, SMS, call log or background permissions.

## 8. Government apps, financial features, health

- Government apps, health: No.
- Financial features declaration: choose **"My app doesn't provide any financial features"**. The app
  is not a payment service, wallet, bank or lender for its users: branch staff prepay their own
  courier company (the app's operator) for courier services, through Razorpay. Check this with your
  own reading of the current declaration wording before submitting.
- Play Billing: not required. The wallet pays for physical courier services, not digital goods or
  app features, which Google Play's payments policy lets apps charge for with another processor.
- Content rating "Digital purchases": No, for the same reason.

## 9. Store listing

**Short description (80 max)**

> Book, scan, dispatch and deliver shipments for your courier branch.

**Full description**

> Courier Pro is the branch operations app for courier companies that run on OCCPL Softech's
> courier management software. It is for branch staff: your company creates your account.
>
> - Book shipments with server-calculated charges, GST and ODA, and print labels
> - Track any shipment by AWB, package or shipment number, or by scanning its barcode or QR code
> - Create loading sheets by scanning packages, then dispatch them on a Trip Hire Challan (THC)
> - Receive incoming loads with in-scan and see shortages
> - Build delivery run sheets (DRS) and update each delivery
> - Capture proof of delivery with photos and the receiver's signature
> - Print or share labels, loading sheets, THC, DRS and POD as PDF
> - See your branch dashboard and wallet balance
>
> What you see depends on your role and branch. Need an account? Ask your company's administrator.

**Graphics**

| Asset | Spec | File |
|---|---|---|
| App icon | 512 x 512 PNG, no transparency | `store/icon-512.png` |
| Feature graphic | 1024 x 500 PNG/JPG | `store/feature-graphic.png` |
| Phone screenshots | 2 to 8, 9:16, at least 1080 px on the short side recommended | take on a phone from the prod app with the reviewer account |

Screenshots must not show real customer names or phone numbers; use the demo branch.

## 10. Release

1. Internal testing track first: upload the `.aab`, add testers, install from the Play link.
2. New personal developer accounts must run a closed test with at least 12 testers for 14 days
   before production; an organisation account (OCCPL Softech, with D-U-N-S) does not.
3. Promote to production. Review usually takes a few days.
