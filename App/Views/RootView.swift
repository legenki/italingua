import SwiftData
import SwiftUI

struct RootView: View {
    @Query(sort: [SortDescriptor(\Lesson.level), SortDescriptor(\Lesson.order)])
    private var lessons: [Lesson]
    @Query private var progress: [WordProgress]
    @State private var selection: Lesson.ID?
    @Query private var vocab: [VocabItem]
    /// Dictionary-style search in the sidebar; a selected result shows its word.
    @State private var search = ""
    @State private var selectedWord: String?
    /// Screens pushed in the content pane by the study session plan.
    @State private var detailPath = NavigationPath()
    /// The lesson list holds keyboard focus from the start, so macOS does not
    /// put its focus ring on a toolbar button and the arrow keys work at once.
    @FocusState private var listFocused: Bool
    /// iPhone: the app opens on the Today screen (as the Mac window does);
    /// the lesson list is one step back, and the house button returns to Today.
    @State private var compactColumn = NavigationSplitViewColumn.detail
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    @State private var showStats = false
    @State private var showSettings = false
    /// Read so the window is rebuilt with the new accent when the palette changes.
    @AppStorage(Palette.storageKey) private var palette = Palette.green

    var body: some View {
        let results = search.isEmpty ? [] : WordSearch.results(search, in: vocab)
        NavigationSplitView(preferredCompactColumn: $compactColumn) {
            Group {
                if search.isEmpty { lessonList } else { resultList(results) }
            }
            .searchable(text: $search, placement: .sidebar, prompt: String(localized: "Поиск слова"))
            .onChange(of: search) {
                // Like the Dictionary app: the best match opens right away
                // beside the list. On iPhone the word would cover the list
                // after the first letter, so there the learner picks a row.
                #if os(iOS)
                if sizeClass == .compact {
                    selectedWord = nil
                    return
                }
                #endif
                selectedWord = WordSearch.results(search, in: vocab, limit: 1).first?.wordID
            }
            .navigationTitle("Italingua")
            .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 420)
            .toolbar {
                // On macOS Settings open from the app menu (⌘,), as in other Mac apps.
                #if os(iOS)
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "Сегодня"), systemImage: "house") { showToday() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(String(localized: "Настройки"), systemImage: "gearshape") { showSettings = true }
                }
                #endif
                ToolbarItem(placement: .primaryAction) {
                    Button(String(localized: "Статистика"), systemImage: "chart.pie") { showStats = true }
                }
            }
        } detail: {
            NavigationStack(path: $detailPath) {
                Group {
                if !search.isEmpty, let item = vocab.first(where: { $0.wordID == selectedWord }) {
                    WordDetailView(item: item) { id in
                        search = ""
                        selection = id
                    }
                } else if let lesson = lessons.first(where: { $0.id == selection }) {
                    LessonDetailView(lesson: lesson)
                } else {
                    TodayView { selection = $0 }
                        #if os(iOS)
                        // iPhone: the lesson list sits behind Today; a labelled
                        // grid button replaces the bare back chevron.
                        .navigationBarBackButtonHidden(sizeClass == .compact)
                        .toolbar {
                            if sizeClass == .compact {
                                ToolbarItem(placement: .topBarLeading) {
                                    Button(String(localized: "Все уроки"), systemImage: "square.grid.2x2") {
                                        compactColumn = .sidebar
                                    }
                                }
                            }
                        }
                        #endif
                }
                }
                .navigationDestination(for: SessionRoute.self) { route in
                    switch route {
                    case .vocabulary(let id): if let l = lesson(id) { VocabularyView(lesson: l) }
                    case .flashcards(let id): if let l = lesson(id) { FlashcardsView(lesson: l) }
                    case .reading(let id): if let l = lesson(id) { ReadingView(lesson: l) }
                    }
                }
            }
            .toolbar {
                // The 40-minute study session, in the middle of the top bar.
                // Not over a dictionary word: on iPhone it ran into the text
                // size buttons, and a word lookup is not a study step.
                if !showingWord {
                    ToolbarItem(placement: .principal) {
                        SessionCapsule(startLesson: lessons.first { $0.id == selection } ?? nextLesson,
                                       lessons: lessons, open: openStep)
                    }
                    // The capsule draws its own glass and glow.
                    .sharedBackgroundVisibility(.hidden)
                }
                // Top-right corner of the window, on every screen of the content pane.
                ToolbarItem(placement: .primaryAction) { TextSizeButtons() }
            }
            .onChange(of: selection) { detailPath = NavigationPath() }

        }
        // Accent for the sidebar selection, toggles and pickers.
        .tint(Theme.accent)
        // Default text at the size chosen with the "A / A" buttons.
        .font(.s(.body))
        // Theme colors are read when views are built, so a palette change
        // rebuilds the split view. Selection and sheets live outside it and stay.
        .id(palette)
        .sheet(isPresented: $showStats) {
            NavigationStack { StatsView() }
                .tint(Theme.accent)
                .font(.s(.body))
                #if os(macOS)
                .frame(minWidth: 620, idealWidth: 780, minHeight: 640, idealHeight: 860)
                #endif
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack { SettingsView() }.appAppearance()
        }
    }

    /// Sections in display order: per level, the intro course, then the main one.
    private var sections: [(title: String, lessons: [Lesson])] {
        levels.flatMap { level in
            ["intro", "main"].compactMap { part -> (String, [Lesson])? in
                let items = lessons.filter { $0.level == level && $0.sourcePart == part }
                return items.isEmpty ? nil
                    : ("\(level) · \(part == "intro" ? String(localized: "Вводный курс") : String(localized: "Основной курс"))", items)
            }
        }
    }

    @ViewBuilder
    private var lessonList: some View {
        let boxes = self.boxes
        #if os(macOS)
        // The system sidebar highlight ignores the app tint on macOS, so rows
        // draw their own selection: accent color, same radius as the buttons.
        ScrollViewReader { proxy in
            List {
                ForEach(sections, id: \.title) { section in
                    Section(section.title) {
                        ForEach(section.lessons) { lesson in
                            let selected = lesson.id == selection
                            LessonRow(lesson: lesson, progress: progress(of: lesson, boxes: boxes), selected: selected)
                                .padding(.horizontal, 8)
                                .background(selected ? Theme.accent : .clear,
                                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .contentShape(Rectangle())
                                .onTapGesture { selection = lesson.id }
                                .listRowInsets(EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 8))
                                .listRowSeparator(.hidden)
                                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                                .id(lesson.id)
                        }
                    }
                }
            }
            .focusable()
            .focusEffectDisabled()
            .focused($listFocused)
            .defaultFocus($listFocused, true)
            .onAppear { listFocused = true }
            .onKeyPress(.downArrow) { step(1, proxy); return .handled }
            .onKeyPress(.upArrow) { step(-1, proxy); return .handled }
        }
        #else
        List(selection: $selection) {
            ForEach(sections, id: \.title) { section in
                Section(section.title) {
                    ForEach(section.lessons) { lesson in
                        LessonRow(lesson: lesson, progress: progress(of: lesson, boxes: boxes), selected: false)
                            .tag(lesson.id)
                    }
                }
            }
        }
        #endif
    }

    @ViewBuilder
    private func resultList(_ results: [VocabItem]) -> some View {
        if results.isEmpty {
            ContentUnavailableView.search(text: search)
        } else {
            #if os(macOS)
            List {
                Section(String(localized: "Слова · \(results.count)")) {
                    ForEach(results, id: \.wordID) { item in
                        let selected = item.wordID == selectedWord
                        WordResultRow(item: item, selected: selected)
                            .padding(.horizontal, 8)
                            .background(selected ? Theme.accent : .clear,
                                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .contentShape(Rectangle())
                            .onTapGesture { selectedWord = item.wordID }
                            .listRowInsets(EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 8))
                            .listRowSeparator(.hidden)
                            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                    }
                }
            }
            #else
            List(selection: $selectedWord) {
                Section(String(localized: "Слова · \(results.count)")) {
                    ForEach(results, id: \.wordID) { item in
                        WordResultRow(item: item, selected: false).tag(item.wordID)
                    }
                }
            }
            #endif
        }
    }

    #if os(macOS)
    /// Arrow keys move the selection like in a regular sidebar.
    private func step(_ delta: Int, _ proxy: ScrollViewProxy) {
        let ordered = sections.flatMap(\.lessons).map(\.id)
        guard !ordered.isEmpty else { return }
        let current = selection.flatMap { ordered.firstIndex(of: $0) }
        let next = current.map { min(max($0 + delta, 0), ordered.count - 1) } ?? 0
        selection = ordered[next]
        proxy.scrollTo(ordered[next])
    }
    #endif

    private func lesson(_ id: String) -> Lesson? { lessons.first { $0.id == id } }

    /// A word from the search is open in the content pane.
    private var showingWord: Bool {
        !search.isEmpty && vocab.contains { $0.wordID == selectedWord }
    }

    /// Back to the Today screen from the lesson list.
    private func showToday() {
        search = ""
        selection = nil
        detailPath = NavigationPath()
        compactColumn = .detail
    }

    /// First lesson not done yet, for a session started without a selection.
    private var nextLesson: Lesson? {
        let boxes = self.boxes
        return sections.flatMap(\.lessons).first { progress(of: $0, boxes: boxes).state != .done }
    }

    /// Opens the screen of a session step: the lesson page for the rules,
    /// its vocabulary, flashcards or reading for the others.
    private func openStep(_ step: StudySession.Step) {
        guard let id = StudySession.shared.state?.lessonID else { return }
        search = ""
        selection = id
        Task { @MainActor in
            // After the selection change has reset the stack.
            var path = NavigationPath()
            switch step {
            case .rules: break
            case .words: path.append(SessionRoute.vocabulary(id))
            case .cards: path.append(SessionRoute.flashcards(id))
            case .reading: path.append(SessionRoute.reading(id))
            }
            detailPath = path
        }
    }

    private var levels: [String] {
        Array(Set(lessons.map(\.level))).sorted()
    }

    private var boxes: [String: Int] {
        Dictionary(progress.map { ($0.wordID, $0.box) }, uniquingKeysWith: max)
    }

    private func progress(of lesson: Lesson, boxes: [String: Int]) -> LessonProgress {
        LessonProgress(boxes: lesson.vocab.filter(FillBlankSession.isPracticable).map { boxes[$0.wordID] })
    }
}

/// A lesson in the sidebar, laid out like a chat row: status badge, title
/// and how many of its words are known.
private struct LessonRow: View {
    let lesson: Lesson
    let progress: LessonProgress
    /// Drawn on the accent background: white text, outlined badge.
    let selected: Bool

    var body: some View {
        HStack(spacing: 12) {
            LessonBadge(number: lesson.sourceLesson, progress: progress)
                .overlay(Circle().stroke(Theme.onAccent, lineWidth: selected ? 2 : 0))
            VStack(alignment: .leading, spacing: 3) {
                Text(lesson.title.isEmpty ? lesson.id : lesson.title)
                    .font(.s(.body).weight(.semibold))
                    .lineLimit(2)
                    .foregroundStyle(selected ? Theme.onAccent : .primary)
                Text(statusText)
                    .font(.s(.subheadline))
                    .monospacedDigit()
                    .foregroundStyle(selected ? Theme.onAccent.opacity(0.85)
                                     : progress.state == .done ? Theme.accent : .secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private var statusText: String {
        switch progress.state {
        case .notStarted: String(localized: "Не начат · \(progress.total) слов")
        case .inProgress: String(localized: "Знакомо \(progress.known) из \(progress.total) слов")
        case .done: String(localized: "Пройден · \(progress.total) слов")
        }
    }
}

/// Round badge in place of a chat avatar: the lesson number in a grey circle
/// (not started), a progress ring around it (in progress), or a green check (done).
struct LessonBadge: View {
    let number: Int
    let progress: LessonProgress
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            switch progress.state {
            case .done:
                Circle().fill(Theme.accent)
                Image(systemName: "checkmark")
                    .font(.scaledSystem(size: size * 0.4, weight: .bold))
                    .foregroundStyle(Theme.onAccent)
            case .inProgress:
                Circle().fill(Theme.accentSoft)
                Circle().stroke(Theme.separator, lineWidth: 3).padding(1.5)
                Circle()
                    .trim(from: 0, to: max(progress.fraction, 0.04))
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(1.5)
                label.foregroundStyle(Theme.accent)
            case .notStarted:
                Circle().fill(Theme.tile)
                Circle().stroke(Theme.separator, lineWidth: 1)
                label.foregroundStyle(Theme.secondaryText)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(accessibility)
    }

    private var label: some View {
        Text("\(number)").font(.scaledSystem(size: size * 0.4, weight: .bold, design: .rounded))
    }

    private var accessibility: String {
        switch progress.state {
        case .notStarted: String(localized: "Не начат")
        case .inProgress: String(localized: "В процессе, \(Int(progress.fraction * 100))%")
        case .done: String(localized: "Пройден")
        }
    }
}
