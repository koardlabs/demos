# Koard iOS Demo (Swift)

A SwiftUI demo that integrates the **Koard Merchant SDK** with a pin-pad-first
checkout flow (sale, tips, refunds, receipts, reader-state handling).

The SDK is consumed via **Swift Package Manager** from the public
[`koardlabs/koard-ios`](https://github.com/koardlabs/koard-ios) release —
pinned in `KoardDemo.xcodeproj` to an exact version. No SDK source to clone.

## Requirements

- Xcode 16+
- iOS 17.6+ device or simulator
- A Koard **API key** (see setup below)

## Environments and schemes

The project ships **two shared schemes**, one per environment:

| Scheme                  | Build config | Swift flag             | Reads section | Environment            |
| ----------------------- | ------------ | ---------------------- | ------------- | ---------------------- |
| Koard Demo (UAT)        | `UAT`        | `KOARD_ENV_UAT`        | `UAT`         | `api.uat.koard.com`    |
| Koard Demo (Production) | `Production` | `KOARD_ENV_PRODUCTION` | `PRODUCTION`  | `api.koard.com`        |

Each scheme sets a Swift compile-time flag via
`SWIFT_ACTIVE_COMPILATION_CONDITIONS`, and `ConfigurationManager.swift`
resolves the env with a `#if` chain — the env is baked into the compiled
binary for **both Run and Archive**, so what you ship to TestFlight is the
env named in the scheme you archived. No runtime priming step.

## Setup

1. **Copy the config template:**

   ```bash
   cp KoardMerchantSDK-Demo/Config.plist.template KoardMerchantSDK-Demo/Config.plist
   ```

   The real `Config.plist` is **gitignored** — never commit it. Xcode's
   file-system-synchronized group picks it up automatically.

2. **Paste your API key** into `Config.plist` under the env you plan to run.
   Get a key from the **developers** page of your Koard dashboard:

   | Environment | Get your API key at                       |
   | ----------- | ----------------------------------------- |
   | UAT         | https://app.uat.koard.com/developers      |
   | Production  | https://app.koard.com/developers          |

   ```xml
   <dict>
       <key>UAT</key>        <dict><key>apiKey</key><string>…</string></dict>
       <key>PRODUCTION</key> <dict><key>apiKey</key><string>…</string></dict>
   </dict>
   ```

   **Merchant code and PIN are not stored here** — you enter them on the
   app's login screen at runtime.

3. **Open `KoardDemo.xcodeproj` in Xcode**, pick the **Koard Demo (UAT)** or
   **Koard Demo (Production)** scheme, and Run.

## What this demo shows

- **Pin-pad-first** cents-shift amount entry.
- **Checkout modes** (Retail, Restaurant/Bar with tips, Legacy form),
  switchable in Settings.
- **Reader-state machine** (`idle → preparing → ready → failed`) with
  auto-prepare on cold start / foreground / retry.
- **Refunds, reversals, receipts** from the transaction detail screen.
- **Dark mode** with a System / Light / Dark override in Settings.
