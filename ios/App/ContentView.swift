import SwiftUI

struct ContentView: View {
    @StateObject private var proxy = ProxyController.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
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
                    noticeSection
                    logSection
                }
                .padding()
            }
            .navigationTitle("TG WS Proxy")
            .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(.stack)
        .onChange(of: scenePhase) { phase in
            if phase == .background { proxy.sceneDidEnterBackground() }
        }
    }

    private var argsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Аргументы (как у tg-ws-proxy)")
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
                .disabled(proxy.isRunning)
            Text("Например: --secret <32 hex> --default-domains. Уберите --quiet, чтобы видеть логи.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var controlSection: some View {
        HStack(spacing: 12) {
            Button {
                proxy.isRunning ? proxy.stop() : proxy.start()
            } label: {
                Text(proxy.isRunning ? "Стоп" : "Старт")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(proxy.isRunning ? .red : .blue)

            Button("Сбросить аргументы") { proxy.args = ProxyController.defaultArgs }
                .buttonStyle(.bordered)
                .disabled(proxy.isRunning)
        }
    }

    private func linkSection(_ link: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ссылка на прокси")
                .font(.footnote)
                .foregroundColor(.secondary)
            Text(link)
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
            HStack {
                Button("Открыть в Telegram") { proxy.openInTelegram() }
                    .buttonStyle(.borderedProminent)
                Button("Копировать") { UIPasteboard.general.string = link }
                    .buttonStyle(.bordered)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }

    private var noticeSection: some View {
        Text("iOS приостанавливает приложения в фоне, поэтому прокси работает, пока это приложение открыто, и ещё недолго после выхода из него.")
            .font(.caption)
            .foregroundColor(.secondary)
    }

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Лог").font(.footnote).foregroundColor(.secondary)
                Spacer()
                Button("Очистить") { proxy.clearLog() }.font(.footnote)
            }
            Text(proxy.logLines.isEmpty ? "—" : proxy.logLines.joined(separator: "\n"))
                .font(.system(size: 10, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
