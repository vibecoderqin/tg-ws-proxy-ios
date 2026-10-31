import Foundation
import SwiftUI
import UIKit

// MARK: - C callbacks
// These are plain C function pointers, so they cannot capture anything.
// They may fire on any Rust thread, hence the hop to the main actor.

private let onLogCallback: tgws_str_cb = { text, _ in
    guard let text else { return }
    let line = String(cString: text)
    Task { @MainActor in ProxyController.shared.appendLog(line) }
}

private let onErrorCallback: tgws_str_cb = { text, _ in
    let message = text.map { String(cString: $0) } ?? "unknown error"
    Task { @MainActor in ProxyController.shared.didFail(message) }
}

private let onListeningCallback: tgws_str_cb = { text, _ in
    guard let text else { return }
    let link = String(cString: text)
    Task { @MainActor in ProxyController.shared.didStartListening(link) }
}

private let onStoppedCallback: tgws_void_cb = { _ in
    Task { @MainActor in ProxyController.shared.didStop() }
}

// MARK: - Controller

@MainActor
final class ProxyController: ObservableObject {
    static let shared = ProxyController()

    /// Same flags the `tg-ws-proxy` binary accepts. Keep the host on 127.0.0.1
    /// so Telegram on the same phone can reach it; `--link-ip` makes the printed
    /// `tg://` link point at it too instead of an auto-detected Wi-Fi address.
    static let defaultArgs = "--host 127.0.0.1 --link-ip 127.0.0.1 --quiet"

    @Published var args: String {
        didSet { UserDefaults.standard.set(args, forKey: "proxyArgs") }
    }
    @Published private(set) var isRunning = false
    @Published private(set) var link: String?
    @Published private(set) var errorMessage: String?
    @Published private(set) var logLines: [String] = []

    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    private init() {
        args = UserDefaults.standard.string(forKey: "proxyArgs") ?? Self.defaultArgs
        tgws_set_callbacks(onLogCallback, onErrorCallback, onListeningCallback, onStoppedCallback, nil)
    }

    // MARK: Actions

    func start() {
        errorMessage = nil
        link = nil
        if let cError = tgws_start(args) {
            errorMessage = String(cString: cError)
            tgws_free_string(cError)
            return
        }
        isRunning = true
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func stop() {
        tgws_stop()
        isRunning = false
        link = nil
        UIApplication.shared.isIdleTimerDisabled = false
        endBackgroundTask()
    }

    func openInTelegram() {
        guard let link, let url = URL(string: link) else { return }
        beginBackgroundTask()
        UIApplication.shared.open(url)
    }

    func clearLog() { logLines.removeAll() }

    func sceneDidEnterBackground() {
        if isRunning { beginBackgroundTask() }
    }

    // MARK: Callbacks from Rust

    func appendLog(_ line: String) {
        logLines.append(line)
        if logLines.count > 500 { logLines.removeFirst(logLines.count - 500) }
    }

    func didStartListening(_ link: String) {
        self.link = link
    }

    func didFail(_ message: String) {
        errorMessage = message
        isRunning = false
        link = nil
        UIApplication.shared.isIdleTimerDisabled = false
        endBackgroundTask()
    }

    func didStop() {
        isRunning = false
        link = nil
        UIApplication.shared.isIdleTimerDisabled = false
        endBackgroundTask()
    }

    // MARK: Background time

    private func beginBackgroundTask() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "tg-ws-proxy") { [weak self] in
            Task { @MainActor in self?.endBackgroundTask() }
        }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }
}
