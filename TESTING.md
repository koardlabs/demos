# Repeatable demo validation

Use Xcode with an installed iOS simulator, Android Studio's JDK 21, Android SDK 36, and a running Android emulator. Configure the ignored demo configuration files from their templates before testing. Do not commit those files or merchant login details.

Run from the repository root. Each command creates a new temporary artifact directory and prints its path. Build logs, test reports, and simulator screenshots remain there for review.

## iOS

```sh
python3 scripts/test-ios.py --scheme 'Koard Demo (UAT)' --simulator-id YOUR_SIMULATOR_UDID
```

The runner builds the actual app, runs five Foundation model tests against the app's ticket, keypad, and follow-up amount sources, then runs XCTest UI tests. UI coverage includes item quantities, custom amounts, checkout review and cancellation, authorization follow-ups, rejection of zero and invalid tip input, repeat location-picker opening, login typing, appearance persistence, and the Settings tutorial entry.

For a focused iPad register check, use the tablet simulator ID and add `--only-testing StandardDemoUITests/StandardDemoUITests/testRegisterTicketReviewAndCustomAmount`.

Preview tests use the demo's mock merchant service and never submit payments. The sample item catalog is local demonstration data. Existing tax, tip, surcharge, partial approval, and reader flows still handle checkout.

## Android

```sh
python3 scripts/test-android.py --variant UatDebug --serial YOUR_EMULATOR_SERIAL
```

The runner builds the app and test APK, runs available JUnit unit tests, and checks the swipeable tutorial in light and dark themes, including Back, Next, Done, and Close. The public demo's JUnit tests cover every published reader prompt, without treating a card read as payment approval. It also checks the actual app's asynchronous startup and credential field interactivity without submitting a login. The internal demo's JUnit tests cover authorized, settled, declined, reversed, canceled, error, and surcharge-pending follow-up actions.

Set `JAVA_HOME` to JDK 21 if your environment overrides Android Studio's bundled JDK. The runners target debug UAT builds. They do not perform production operations.

## Physical device checks

Simulators cannot validate contactless reads, account linking, Visa kernel enrollment, secure PIN, Apple's native tutorial presentation, or processor approvals. Run those on supported phones with the documented environment configuration. A card read alone is not payment approval. The iOS simulator checks the tutorial entry; supported iPhones open Apple's localized Tap to Pay tutorial.

Implementation contracts and platform requirements are maintained at [docs.koard.com](https://docs.koard.com). Public demos use published SDKs. The iOS free-form location metadata fix must be included in a published SDK release before public demo users receive it.
