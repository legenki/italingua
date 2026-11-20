import CryptoKit
import Foundation
import SwiftData

// JSON shape of Content/<LEVEL>.json.
nonisolated struct ContentFileDTO: Decodable, Sendable {
    let level: String
    let lessons: [LessonDTO]

    struct LessonDTO: Decodable, Sendable {
        let id: String
        let title: String
        let grammar: [GrammarDTO]
        let vocab: [VocabDTO]
        let patterns: [String]
        let source: SourceDTO?
    }
    struct GrammarDTO: Decodable, Sendable {
        let topic: String
        let rule_ru: String
        var topic_en: String? = nil
        var topic_es: String? = nil
        var rule_en: String? = nil
        var rule_es: String? = nil
    }
    struct VocabDTO: Decodable, Sendable {
        let it: String
        let ru: String
        var en: String? = nil
        var es: String? = nil
        let pos: String
        let gender: String?
        let number: String?
        let stress: String?
        let form_of: String?
        let new: Bool?
    }
    struct SourceDTO: Decodable, Sendable {
        let part: String
        let lesson: Int
    }
}

/// Loads the bundled course content into the local content store.
/// Runs at every launch but only touches a level when its JSON changed
/// (tracked by SHA-256), so editing the JSON and rebuilding is enough to
/// update the app. Progress is keyed by wordID and survives re-imports.
enum ContentImporter {
    static let hashKeyPrefix = "contentHash."

    static func importBundledContent(into context: ModelContext,
                                     bundle: Bundle = .main,
                                     defaults: UserDefaults = .standard) throws {
        let urls = bundle.urls(forResourcesWithExtension: "json", subdirectory: "Content") ?? []
        for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let data = try Data(contentsOf: url)
            let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            let level = url.deletingPathExtension().lastPathComponent
            let key = hashKeyPrefix + level
            let alreadyImported = try context.fetchCount(
                FetchDescriptor<Lesson>(predicate: #Predicate { $0.level == level })) > 0
            if defaults.string(forKey: key) == hash && alreadyImported { continue }
            try importLevel(data: data, into: context)
            defaults.set(hash, forKey: key)
        }
    }

    /// Replaces one level's content with the given JSON.
    static func importLevel(data: Data, into context: ModelContext) throws {
        let file = try JSONDecoder().decode(ContentFileDTO.self, from: data)
        let level = file.level
        try context.delete(model: Lesson.self, where: #Predicate { $0.level == level })
        // Cascade deletes do not run for batch deletes in every SwiftData
        // version, so clear orphans explicitly.
        try context.delete(model: GrammarTopic.self, where: #Predicate { $0.lesson == nil })
        try context.delete(model: VocabItem.self, where: #Predicate { $0.lesson == nil })
        let levelKey = level.lowercased()
        let existing = Set(try context.fetch(FetchDescriptor<VocabItem>()).map(\.wordID))

        for (index, dto) in file.lessons.enumerated() {
            let lesson = Lesson(id: dto.id, level: level, order: index,
                                title: dto.title,
                                sourcePart: dto.source?.part ?? "main",
                                sourceLesson: dto.source?.lesson ?? index + 1,
                                patterns: dto.patterns)
            context.insert(lesson)
            for (gi, g) in dto.grammar.enumerated() {
                let topic = GrammarTopic(order: gi, topic: g.topic, ruleRU: g.rule_ru)
                topic.topicEN = g.topic_en ?? ""
                topic.topicES = g.topic_es ?? ""
                topic.ruleEN = g.rule_en ?? ""
                topic.ruleES = g.rule_es ?? ""
                topic.lesson = lesson
            }
            for (vi, v) in dto.vocab.enumerated() {
                let id = wordID(level: levelKey, italian: v.it)
                if existing.contains(id) { continue }   // defensive: validator forbids dups
                let item = VocabItem(wordID: id, order: vi, italian: v.it, russian: v.ru,
                                     posRaw: v.pos, gender: v.gender, number: v.number,
                                     stress: v.stress, formOf: v.form_of, isNew: v.new ?? false)
                item.english = v.en ?? ""
                item.spanish = v.es ?? ""
                item.lesson = lesson
            }
        }
        try dropMergedRuleNotes(file: file, in: context)
        try context.save()
    }

    /// Once the bundled rule text equals an in-app note, the note is no longer needed.
    static func dropMergedRuleNotes(file: ContentFileDTO, in context: ModelContext) throws {
        var bundled: [String: String] = [:]
        for lesson in file.lessons {
            for g in lesson.grammar where !g.rule_ru.isEmpty {
                bundled[RuleNote.key(lessonID: lesson.id, topic: g.topic)] = g.rule_ru
            }
        }
        for note in try context.fetch(FetchDescriptor<RuleNote>())
        where bundled[note.key].map(normalizedRule) == normalizedRule(note.text) {
            context.delete(note)
        }
    }

    nonisolated static func normalizedRule(_ s: String) -> String {
        s.replacingOccurrences(of: "\r\n", with: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Same folding as the Python validator: lowercase, ’→', no diacritics.
    nonisolated static func wordID(level: String, italian: String) -> String {
        let folded = italian.replacingOccurrences(of: "’", with: "'")
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "it"))
        return "\(level.lowercased())/\(folded)"
    }
}
