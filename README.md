# Koard SDK Demo Apps

Official demo applications for the **Koard Merchant SDK** — reference
integrations you can build, run, and learn from. Each app exercises the SDK
end to end: authentication, location selection, device enrollment, and NFC
Tap-to-Pay transaction flows (sale, refund, reversal, tips, receipts).

## Demos

| Platform | Folder            | SDK delivery                                            |
| -------- | ----------------- | ------------------------------------------------------- |
| iOS      | [`ios/`](ios/)     | Swift Package Manager — `github.com/koardlabs/koard-ios` |
| Android  | [`android/`](android/) | Maven Central — `com.koard:koard-android-sdk`            |

Each demo has its own **README with full setup instructions** — start there:

- **iOS** → [`ios/README.md`](ios/README.md)
- **Android** → [`android/README.md`](android/README.md)

## Environments

Both demos ship **UAT** and **Production** targets only. You bring your own
API key per environment, obtained from the developers page of your Koard
dashboard:

| Environment | Dashboard                            |
| ----------- | ------------------------------------ |
| UAT         | https://app.uat.koard.com/developers |
| Production  | https://app.koard.com/developers     |

## API keys

Each demo reads your API key from a local config file. Copy the template and
paste your key:

- iOS: copy `Config.plist.template` → `Config.plist`
- Android: copy `apikeys.properties.template` → `apikeys.properties`

Git ignores both files, so your key stays on your machine. See each demo's
README for the exact steps.

## Repeatable validation

See [TESTING.md](TESTING.md) for the model, simulator and emulator test commands.

## License

MIT. See [LICENSE](LICENSE).
