import Foundation
import SwiftUI
import UIKit

// MARK: - C callbacks
// Rust invokes these callbacks from worker threads. Always hop to the main actor
// before changing SwiftUI-observed state.

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

// MARK: - Lifecycle state

enum ProxyStatus: Equatable {
    case stopped
    case starting
    case running
    case stopping
}

// MARK: - Controller

@MainActor
final class ProxyController: ObservableObject {
    static let shared = ProxyController()

    /// The proxy only listens on loopback: Telegram on this same iPhone is the
    /// intended client. Do not publish this listener to the local Wi-Fi network.
    /// Keep logs enabled by default so startup and connection failures are visible.
    static let defaultArgs = "--host 127.0.0.1 --link-ip 127.0.0.1"

    @Published var args: String {
        didSet { UserDefaults.standard.set(args, forKey: "proxyArgs") }
    }
    @Published private(set) var status: ProxyStatus = .stopped
    @Published private(set) var link: String?
    @Published private(set) var errorMessage: String?
    @Published private(set) var logLines: [String] = []

    private init() {
        args = UserDefaults.standard.string(forKey: "proxyArgs") ?? Self.defaultArgs
        tgws_set_callbacks(onLogCallback, onErrorCallback, onListeningCallback, onStoppedCallback, nil)
    }

    // MARK: Actions

    func start() {
        guard status == .stopped else { return }

        errorMessage = nil
        link = nil
        status = .starting

        if let cError = tgws_start(args) {
            errorMessage = String(cString: cError)
            tgws_free_string(cError)
            status = .stopped
        }
    }

    func stop() {
        guard status == .starting || status == .running else { return }
        status = .stopping
        tgws_stop()
    }

    func openInTelegram() {
        guard status == .running,
              let link,
              let url = URL(string: link) else { return }
        UIApplication.shared.open(url)
    }

    func clearLog() {
        logLines.removeAll()
    }

    // MARK: Callbacks from Rust

    func appendLog(_ line: String) {
        logLines.append(line)
        if logLines.count > 500 {
            logLines.removeFirst(logLines.count - 500)
        }
    }

    func didStartListening(_ link: String) {
        // A Stop can be pressed while the Rust worker is still binding.
        // Do not repaint the UI as Running after the user requested a stop.
        guard status != .stopping else { return }
        self.link = link
        status = .running
    }

    func didFail(_ message: String) {
        errorMessage = message
        link = nil
        status = .stopped
    }

    func didStop() {
        link = nil
        status = .stopped
    }
}
