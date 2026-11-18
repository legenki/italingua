import Speech
import SwiftUI

struct SettingsView: View {
    @AppStorage(SettingsKey.appearance) private var appearance = Appearance.system
    @AppStorage(SettingsKey.voiceAnswers) private var voiceAnswers = true
    @AppStorage(Palette.storageKey) private var palette = Palette.green
    @State private var package: AssetInventory.Status?
    @State private var input = SpeechInput()
    @State private var downloadError: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("Оформление") {
                Picker("Тема", selection: $appearance) {
                    ForEach(Appearance.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Цвет")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 68), spacing: 8)], spacing: 8) {
                        ForEach(Palette.allCases) { p in
                            Button { palette = p } label: {
                                PaletteSwatch(palette: p, selected: p == palette)
                            }
                            .buttonStyle(.plain)
                            .help(p.title)
                            .accessibilityLabel(p.title)
                            .accessibilityAddTraits(p == palette ? .isSelected : [])
                        }
                    }
                }
            }

            Section {
                Toggle("Отвечать голосом", isOn: $voiceAnswers)
                LabeledContent("Итальянская речь") {
                    switch input.state {
                    case .downloading(let p):
                        ProgressView(value: p).frame(width: 120)
                    default:
                        Text(packageText).foregroundStyle(.secondary)
                    }
                }
                if package == .supported {
                    Button("Скачать пакет распознавания") { Task { await download() } }
                }
                if let downloadError {
                    Text(downloadError).font(.s(.footnote)).foregroundStyle(Theme.feminine)
                }
            } header: {
                Text("Упражнения")
            } footer: {
                Text("В «Вставь слово» можно нажать микрофон и сказать ответ. Речь распознаётся на устройстве; проверяется, какое слово понято, а не акцент.")
            }

            Section {
                LabeledContent("Состояние", value: modelText)
            } header: {
                Text("Apple Intelligence")
            } footer: {
                if !ModelStatus.current().isAvailable {
                    Text("Модель нужна для предложений в упражнениях. Проверь Системные настройки → Apple Intelligence и Siri: Apple Intelligence должен быть включён, а язык Siri — совпадать с языком системы. После этого модель скачается сама.")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Настройки")
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .confirmationAction) {
                Button("Готово") { dismiss() }
            }
            #endif
        }
        .task { package = await SpeechInput.packageStatus() }
    }

    private var packageText: String {
        switch package {
        case .installed: "Установлена"
        case .downloading: "Скачивается…"
        case .supported: "Не скачана"
        case .unsupported: "Не поддерживается"
        case nil: "Проверяю…"
        @unknown default: "Неизвестно"
        }
    }

    private var modelText: String {
        switch ModelStatus.current() {
        case .available: "Готова"
        case .unavailable(let reason): reason
        }
    }

    private func download() async {
        downloadError = nil
        do {
            try await input.preparePackage()
        } catch {
            downloadError = "Не удалось скачать: \(error.localizedDescription)"
        }
        package = await SpeechInput.packageStatus()
    }
}

/// A round sample of a palette: its chart shades around the accent.
private struct PaletteSwatch: View {
    let palette: Palette
    let selected: Bool

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle().fill(Theme.accent(of: palette))
                Circle().trim(from: 0, to: 0.5).fill(Theme.ramp(of: palette)[1]).rotationEffect(.degrees(-45))
            }
            .frame(width: 28, height: 28)
            .overlay(Circle().stroke(selected ? Color.primary : .clear, lineWidth: 2).padding(-4))
            Text(palette.title).font(.s(.caption2)).foregroundStyle(selected ? .primary : .secondary)
        }
        .padding(.vertical, 4)
    }
}
