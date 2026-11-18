import SwiftData
import SwiftUI

/// Star that adds a word to the "Избранное" deck or removes it.
struct FavoriteButton: View {
    let wordID: String
    let isFavorite: Bool
    var size: CGFloat = 32
    /// Colors for use on an accent background.
    var onAccent = false
    @Environment(\.modelContext) private var context

    var body: some View {
        Button {
            withAnimation(.snappy) { _ = try? context.toggleFavorite(wordID: wordID) }
        } label: {
            Image(systemName: isFavorite ? "star.fill" : "star")
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundStyle(onAccent ? Theme.onAccent : (isFavorite ? Theme.accent : Theme.secondaryText))
                .frame(width: size, height: size)
                .contentShape(Rectangle())
                .symbolEffect(.bounce, value: isFavorite)
        }
        .buttonStyle(.plain)
        .help(isFavorite ? "Убрать из избранного" : "В избранное")
        .accessibilityLabel(isFavorite ? "Убрать из избранного" : "Добавить в избранное")
    }
}

/// Starred words with a button for flashcards over them.
struct FavoritesView: View {
    @Query(sort: \FavoriteWord.addedAt, order: .reverse) private var favorites: [FavoriteWord]
    @Query private var vocab: [VocabItem]

    var body: some View {
        let items = Self.items(favorites: favorites, vocab: vocab)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Избранное").font(.largeTitle.weight(.bold))
                if items.isEmpty {
                    Card {
                        Label("Пока пусто", systemImage: "star").font(.headline)
                        Text("Отмечай слова звёздочкой в лексике урока, в карточках или в «Слове дня». Здесь из них соберётся своя колода.")
                            .foregroundStyle(Theme.secondaryText)
                    }
                } else {
                    NavigationLink {
                        FlashcardsView(items: items, title: "Избранное")
                    } label: {
                        Label("Учить карточками · \(items.count) \(wordWord(items.count))",
                              systemImage: "rectangle.on.rectangle.angled")
                            .font(.headline)
                            .foregroundStyle(Theme.onAccent)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Card(padding: 0) {
                        VStack(spacing: 0) {
                            ForEach(Array(items.enumerated()), id: \.element.wordID) { index, item in
                                if index > 0 {
                                    Rectangle().fill(Theme.separator).frame(height: 1).padding(.leading, 72)
                                }
                                HStack(spacing: 12) {
                                    SpeakButton(text: item.withArticle)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.displayWithArticle).font(.body.weight(.semibold))
                                        Text(item.russian + (item.lesson.map { " · \($0.sourceLabel)" } ?? ""))
                                            .font(.subheadline)
                                            .foregroundStyle(Theme.secondaryText)
                                    }
                                    Spacer(minLength: 8)
                                    FavoriteButton(wordID: item.wordID, isFavorite: true)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                            }
                        }
                        .padding(.vertical, 4)
                        .textSelection(.enabled)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
        .navigationTitle("")
    }

    /// Starred words in the order they were added (newest first), each once.
    static func items(favorites: [FavoriteWord], vocab: [VocabItem]) -> [VocabItem] {
        let byID = Dictionary(vocab.map { ($0.wordID, $0) }, uniquingKeysWith: { a, _ in a })
        var seen = Set<String>()
        return favorites.compactMap { fav in
            guard seen.insert(fav.wordID).inserted else { return nil }
            return byID[fav.wordID]
        }
    }
}
