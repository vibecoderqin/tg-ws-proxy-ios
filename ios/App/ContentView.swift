import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var proxy = ProxyController.shared
    @State private var showBackgroundWarning = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    statusSection
                    argsSection
                    controlSection

                    if let error = proxy.errorMessage {
                        Text(error)
                            .font(.callout)
                            .foregroundColor(.red)
                    }

                    if let link = proxy.link {
                        linkSection(link)
                    }

                    backgroundNotice
                    logSection
                }
                .padding()
            }
            .navigationTitle("TG WS Proxy")
            .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(.stack)
        .alert("Ограничение фоновой работы iOS", isPresented: $showBackgroundWarning) {
            Button("Продолжить") { proxy.openInTelegram() }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("После перехода в Telegram iOS может приостановить TG WS Proxy. В текущей версии нет системного механизма, который гарантирует постоянную работу локального прокси в фоне. Поэтому Telegram может потерять соединение. Это предупреждение нельзя устранить одной Live Activity или обычной фоновой задачей.")
        }
    }

    private var statusSection: some View {
        VStack(spacing: 8) {
            Image(systemName: statusSymbol)
                .font(.system(size: 42))
                .foregroundColor(statusColor)

            Text(statusTitle)
                .font(.headline)
                .foregroundColor(statusColor)

            if proxy.status == .running, let link = proxy.link {
                Text(link.replacingOccurrences(of: "tg://proxy?", with: ""))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var statusTitle: String {
        switch proxy.status {
        case .stopped: return "Прокси остановлен"
        case .starting: return "Запуск прокси…"
        case .running: return "Прокси активен"
        case .stopping: return "Остановка прокси…"
        }
    }

    private var statusSymbol: String {
        switch proxy.status {
        case .stopped: return "antenna.radiowaves.left.and.right.slash"
        case .starting, .stopping: return "arrow.triangle.2.circlepath"
        case .running: return "antenna.radiowaves.left.and.right"
        }
    }

    private var statusColor: Color {
        switch proxy.status {
        case .stopped: return .secondary
        case .starting, .stopping: return .orange
        case .running: return .green
        }
    }

    private var argsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Параметры прокси")
                .font(.footnote)
                .foregroundColor(.secondary)

            TextEditor(text: $proxy.args)
                .font(.system(.footnote, design: .monospaced))
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .frame(minHeight: 80, maxHeight: 140)
                .padding(6)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(8)
                .disabled(proxy.status != .stopped)

            Text("По умолчанию используется локальный адрес 127.0.0.1. Меняй параметры только при необходимости.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var controlSection: some View {
        HStack(spacing: 12) {
            Button {
                switch proxy.status {
                case .stopped:
                    proxy.start()
                case .starting, .running:
                    proxy.stop()
                case .stopping:
                    break
                }
            } label: {
                Text(controlTitle)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(proxy.status == .running || proxy.status == .stopping ? .red : .blue)
            .disabled(proxy.status == .stopping)

            Button("Сбросить") {
                proxy.args = ProxyController.defaultArgs
            }
            .buttonStyle(.bordered)
            .disabled(proxy.status != .stopped)
        }
    }

    private var controlTitle: String {
        switch proxy.status {
        case .stopped: return "Запустить"
        case .starting: return "Отменить запуск"
        case .running: return "Остановить"
        case .stopping: return "Остановка…"
        }
    }

    private func linkSection(_ link: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ссылка для Telegram")
                .font(.footnote)
                .foregroundColor(.secondary)

            Text(link)
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Открыть в Telegram") {
                    showBackgroundWarning = true
                }
                .buttonStyle(.borderedProminent)

                Button("Копировать") {
                    UIPasteboard.general.string = link
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }

    private var backgroundNotice: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Ограничение iOS", systemImage: "info.circle")
                .font(.footnote.weight(.semibold))

            Text("Это локальный сервер внутри приложения. Когда ты открываешь Telegram, iOS может приостановить приложение и остановить обработку подключений. Текущая версия подходит для проверки ядра и работы на переднем плане, но ещё не гарантирует стабильную работу прокси при переключении между приложениями.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Журнал работы")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Очистить") { proxy.clearLog() }
                    .font(.footnote)
            }

            Text(proxy.logLines.isEmpty ? "Пока нет сообщений" : proxy.logLines.joined(separator: "\n"))
                .font(.system(size: 10, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
