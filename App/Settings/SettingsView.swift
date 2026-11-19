import Speech
import SwiftUI

struct SettingsView: View {
    @AppStorage(SettingsKey.appearance) private var appearance = Appearance.system
    @AppStorage(SettingsKey.voiceAnswers) private var voiceAnswers = true
    @AppStorage(Palette.storageKey) private var palette = Palette.green
    @State private var language = AppLanguage.chosen
    @State private var askRestart = false
    @State private var package: AssetInventory.Status?
    @State private var input = SpeechInput()
    @State private var downloadError: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                Picker(String(localized: "Язык"), selection: $language) {
                    ForEach(AppLanguage.allCases) { Text(verbatim: $0.nativeName).tag($0) }
                }
                .onChange(of: language) { _, new in
                    AppLanguage.choose(new)
                    askRestart = AppLanguage.needsRestart || new == .system
                }
            } header: {
                Text(String(localized: "Язык интерфейса"))
            } footer: {
                Text(String(localized: "Меню, экраны, переводы слов и правил. Язык меняется после перезапуска приложения. Английские и испанские переводы слов сделаны моделью на устройстве и могут быть неточными."))
            }
            .alert(String(localized: "Перезапустить приложение?"), isPresented: $askRestart) {
                #if os(macOS)
                Button(String(localized: "Перезапустить")) { AppLanguage.relaunch() }
                Button(String(localized: "Позже"), role: .cancel) {}
                #else
                Button(String(localized: "Понятно"), role: .cancel) {}
                #endif
            } message: {
                #if os(macOS)
                Text(String(localized: "Новый язык включится после перезапуска."))
                #else
                Text(String(localized: "Новый язык включится, когда вы закроете и снова откроете приложение."))
                #endif
            }

            Section(String(localized: "Оформление")) {
                Picker(String(localized: "Тема"), selection: $appearance) {
                    ForEach(Appearance.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "Цвет"))
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
                Toggle(String(localized: "Отвечать голосом"), isOn: $voiceAnswers)
                LabeledContent(String(localized: "Итальянская речь")) {
                    switch input.state {
                    case .downloading(let p):
                        ProgressView(value: p).frame(width: 120)
                    default:
                        Text(packageText).foregroundStyle(.secondary)
                    }
                }
                if package == .supported {
                    Button(String(localized: "Скачать пакет распознавания")) { Task { await download() } }
                }
                if let downloadError {
                    Text(downloadError).font(.s(.footnote)).foregroundStyle(Theme.feminine)
                }
            } header: {
                Text(String(localized: "Упражнения"))
            } footer: {
                Text(String(localized: "В «Вставь слово» можно нажать микрофон и сказать ответ. Речь распознаётся на устройстве; проверяется, какое слово понято, а не акцент."))
            }

            Section {
                LabeledContent(String(localized: "Состояние"), value: modelText)
            } header: {
                Text("Apple Intelligence")
            } footer: {
                if !ModelStatus.current().isAvailable {
                    Text(String(localized: "Модель нужна для предложений в упражнениях. Проверь Системные настройки → Apple Intelligence и Siri: Apple Intelligence должен быть включён, а язык Siri — совпадать с языком системы. После этого модель скачается сама."))
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(String(localized: "Настройки"))
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .confirmationAction) {
                Button(String(localized: "Готово")) { dismiss() }
            }
            #endif
        }
        .task { package = await SpeechInput.packageStatus() }
    }

    private var packageText: String {
        switch package {
        case .installed: String(localized: "Установлена")
        case .downloading: String(localized: "Скачивается…")
        case .supported: String(localized: "Не скачана")
        case .unsupported: String(localized: "Не поддерживается")
        case nil: String(localized: "Проверяю…")
        @unknown default: String(localized: "Неизвестно")
        }
    }

    private var modelText: String {
        switch ModelStatus.current() {
        case .available: String(localized: "Готова")
        case .unavailable(let reason): reason
        }
    }

    private func download() async {
        downloadError = nil
        do {
            try await input.preparePackage()
        } catch {
            downloadError = String(localized: "Не удалось скачать: \(error.localizedDescription)")
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
