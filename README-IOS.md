# iOS build and status

This repository embeds the upstream `tg-ws-proxy-rs` Rust engine in a native SwiftUI iOS host through a small C ABI crate.

## Build

The iOS app is built on a macOS runner with Xcode and XcodeGen:

```sh
cargo test --locked -p tg-ws-proxy-rs
bash ios/build-rust.sh
brew install xcodegen
cd ios
xcodegen generate
xcodebuild -project TgWsProxy.xcodeproj -scheme TgWsProxy -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
```

GitHub Actions runs the Rust tests, builds the ARM64 iOS static library, builds the iOS app and validates the unsigned IPA bundle.

## Current iOS limitation — read before using

The app runs the proxy listener inside the normal iOS application process. iOS suspends ordinary apps after they move to the background; a normal `beginBackgroundTask` request only grants limited time to finish work and is not a permanent background-service API. A Live Activity is UI, not a way to keep the proxy process executing.

This means the current build is a foreground prototype and is **not yet a reliable way to proxy Telegram on the same iPhone after switching to Telegram**. The app displays this limitation before opening Telegram so that it is not mistaken for a ready background service.

We intentionally do not use continuous GPS updates or silent audio as artificial keep-alive mechanisms. They impose privacy/battery costs and are not a sound replacement for a supported networking extension.

A genuinely persistent iOS design needs a separately validated, Apple-supported architecture and the necessary capabilities, or the Rust proxy must run on an external host. Apple's Network Extension documentation specifically requires a real provider extension for packet tunnels and cautions against using packet-tunnel providers to host a listener/proxy server. See:

- https://developer.apple.com/documentation/xcode/configuring-background-execution-modes
- https://developer.apple.com/documentation/uikit/extending-your-app-s-background-execution-time
- https://developer.apple.com/documentation/networkextension/nepackettunnelprovider
- https://developer.apple.com/documentation/technotes/tn3120-expected-use-cases-for-network-extension-packet-tunnel-providers

## Signing

The CI build deliberately produces an unsigned IPA. It can be signed locally by AltStore/Sideloadly with a personal Apple ID. No Apple signing credentials are stored in this repository.

## Optional managed signing

For a development or ad-hoc IPA, a developer must supply a matching certificate, provisioning profile and Team ID through private GitHub Actions secrets. Never commit those files or passwords to source control.
