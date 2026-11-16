# Koard Android Demo (Kotlin)

A Jetpack Compose demo that integrates the **Koard Merchant SDK**: login,
location selection, device enrollment, and NFC Tap-to-Pay transaction flows
(sale, preauth, capture, refund, reversal, tip adjust, receipts).

The SDK is consumed from **Maven Central** as
`com.koard:koard-android-sdk` — no credentials, no SDK source to clone.

## Requirements

- Android Studio (Hedgehog or newer) with the Android SDK 36 platform
- JDK 21
- Physical Android 13+ (API 33+) device with NFC (Tap to Pay needs real hardware)
- A Koard **API key** (see below)

## Setup

The SDK resolves automatically from **Maven Central** — no repository setup or
credentials needed.

### 1. API keys

Copy the template and paste your keys — the real file is **gitignored**:

```bash
cp apikeys.properties.template apikeys.properties
```

Get your API key from the **developers** page of your Koard dashboard:

| Environment | Get your API key at                  |
| ----------- | ------------------------------------ |
| UAT         | https://app.uat.koard.com/developers |
| Production  | https://app.koard.com/developers     |

```properties
UAT_API_KEY=...
PROD_API_KEY=...
```

Merchant code + PIN are **not** stored here — you log in inside the app.

### 2. Build & run

The app has two product flavors — **`uat`** and **`prod`**:

```bash
./gradlew installUatDebug     # UAT
./gradlew installProdRelease  # Production
```

Or open the project in Android Studio and pick the `uatDebug` / `prodRelease`
build variant. (Prod debug is intentionally disabled.)

Then log in with your merchant code and PIN, select a location, and start a
transaction. Disable developer mode on the device before processing payments.

## What this demo shows

- **Payments**: sale, preauth, capture, refund, reversal and tip adjust.
  Payment and refund requests carry example transaction metadata.
- **Reader status** shown with a clear label for every status the SDK reports.
- **Tap to Pay guide** in Settings, a short walkthrough for the person taking
  the payment.
- **Reset SDK and sign out** in Settings. It calls `deinit()`, starts a fresh
  SDK instance and returns to login. An ordinary logout keeps the device
  enrollment.
- **Dark mode** with a System, Light or Dark choice in Settings.
