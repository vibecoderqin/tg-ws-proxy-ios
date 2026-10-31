# Review: NeonchikMPT/tgwsproxy-ios

Review target: `NeonchikMPT/tgwsproxy-ios`, default branch `main`, tree `f8a69a228aae6bd33b59f2ee5bbd818425a895a0` (reviewed 31 October 2026).

## Verdict

This repository is useful as a reference for a SwiftUI control screen and for understanding one possible hand-written iOS port. It is **not a drop-in improvement to this repository** and should not replace the Rust engine.

The iOS implementation in that repository is an independent Swift rewrite. Its files include `Crypto.swift`, `MTProtoHandshake.swift`, `RawWebSocket.swift` and `MTProtoProxyServer.swift`. Our app instead links the actual `tg-ws-proxy-rs` crate and uses the same MTProto, WebSocket, fallback and configuration implementation as the Rust upstream. Keeping one protocol implementation reduces the risk that the iOS version silently diverges from the maintained Rust code.

## Useful ideas

- A native SwiftUI screen with explicit status, connection details and a connection log.
- A dedicated server manager rather than placing network work in the view.
- Live Activity as a display surface for status, if a future app version needs it.

## Issues that prevent adopting it as-is

1. **The background claim is misleading.** `ProxyManager.swift` starts `LocationManager`, which requests Always location permission, enables `allowsBackgroundLocationUpdates`, and starts continuous location updates. Its location callback does not use the coordinates; the feature is being used as a keep-alive. That adds location privacy and battery costs and is not a sound general-purpose proxy lifecycle.
2. **Live Activity is not a background service.** ActivityKit displays state; it does not grant an ordinary app unlimited background CPU time. The sample also calls `startActivity` in both `ProxyManager.startProxy()` and `ContentView`, which can create duplicate activities.
3. **The declared Network Extension entitlement is not a Network Extension implementation.** The repository tree contains no `NEPacketTunnelProvider` subclass or packet-tunnel app-extension target, despite an entitlements file declaring `packet-tunnel-provider`. Apple's documentation requires a real provider extension, principal class and extension point. Apple's TN3120 also says not to use a packet-tunnel provider to host a listener or proxy server; the app-proxy APIs are the relevant family to investigate, subject to their platform/deployment requirements.
4. **The protocol implementation is maintained separately from the Rust engine.** This creates two places to fix parser, cipher, WebSocket framing and fallback issues. For example, `RawWebSocket.receiveRaw(maxLength:timeout:)` accepts a timeout argument but does not apply a timeout to the Network.framework receive operation; `MTProtoProxyServer.stop()` cancels the listener but does not explicitly cancel all already accepted client tasks.
5. **The handwritten handshake parser needs adversarial testing.** It parses untrusted client bytes and converts a signed DC index with `abs`; malformed `Int16.min` input can trap in Swift. The message splitter also reads a `UInt32` from a `Data` buffer using an alignment-sensitive load.

These are code-review observations, not proof that every feature fails on every device. The repository's successful build or a working foreground demo would not prove reliable long-running operation in the background.

## Decision for this repository

- Keep the upstream Rust proxy core as the single source of truth.
- Use only the useful UI concepts; do not copy the location keep-alive, placeholder Network Extension entitlements, or duplicate crypto/protocol code.
- Make the app's startup/stopping/error state explicit and document the foreground-only limitation honestly.
- Treat a persistent iOS service as a separate architecture task. Validate a permitted Network Extension/App Proxy design and signing capability before implementing it; otherwise run the Rust proxy on an external host and use Telegram on iPhone as the client.

## References

- Reference project: https://github.com/NeonchikMPT/tgwsproxy-ios
- Apple background execution modes: https://developer.apple.com/documentation/xcode/configuring-background-execution-modes
- Apple background task time: https://developer.apple.com/documentation/uikit/extending-your-app-s-background-execution-time
- Apple packet tunnel provider: https://developer.apple.com/documentation/networkextension/nepackettunnelprovider
- Apple TN3120: https://developer.apple.com/documentation/technotes/tn3120-expected-use-cases-for-network-extension-packet-tunnel-providers
