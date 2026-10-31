# iOS build

This repository contains the upstream Rust proxy core plus the SwiftUI iOS host app and Rust C-FFI crate.

## Build

The iOS app is built on macOS with Xcode and XcodeGen:

```sh
bash ios/build-rust.sh
brew install xcodegen
cd ios
xcodegen generate
xcodebuild -project TgWsProxy.xcodeproj -scheme TgWsProxy -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
```

The GitHub Actions workflow builds an unsigned IPA on every push to `main`. It also builds a signed IPA when the signing secrets below are configured.

## Optional code signing

Set these GitHub Actions repository secrets:

- `APPLE_CERTIFICATE_BASE64`: base64-encoded .p12 distribution/development certificate.
- `APPLE_CERTIFICATE_PASSWORD`: password for that .p12 file.
- `APPLE_PROVISIONING_PROFILE_BASE64`: base64-encoded iOS provisioning profile matching the app bundle ID.
- `APPLE_TEAM_ID`: Apple Developer Team ID.

Optional repository variables:

- `IOS_BUNDLE_ID` (default `com.vibecoderqin.tgwsproxy`).
- `IOS_EXPORT_METHOD` (default `ad-hoc`; use `development` with a development profile).
- `IOS_SIGNING_IDENTITY` (default `Apple Distribution`; use `Apple Development` for a development profile).

An ad-hoc profile must include the target iPhone's UDID. Unsigned IPAs cannot be installed directly on iPhone; they need to be signed first.
