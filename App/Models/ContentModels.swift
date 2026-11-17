import Foundation
import SwiftData

// Static course content, imported from Content/<LEVEL>.json.
// Lives in a local-only store ("Content"): it is re-imported whenever the
// bundled JSON changes, so it never syncs and may use unique constraints.

@Model
final class Lesson {
    @Attribute(.unique) var id: String
    var level: String
    var order: Int
    var title: String
    var sourcePart: String
    var sourceLesson: Int
    var patterns: [String]

    @Relationship(deleteRule: .cascade, inverse: \GrammarTopic.lesson)
    var grammar: [GrammarTopic] = []

    @Relationship(deleteRule: .cascade, inverse: \VocabItem.lesson)
    var vocab: [VocabItem] = []

    init(id: String, level: String, order: Int, title: String,
         sourcePart: String, sourceLesson: Int, patterns: [String]) {
        self.id = id
        self.level = level
        self.order = order
        self.title = title
        self.sourcePart = sourcePart
        self.sourceLesson = sourceLesson
        self.patterns = patterns
    }

    var sortedGrammar: [GrammarTopic] { grammar.sorted { $0.order < $1.order } }
    var sortedVocab: [VocabItem] { vocab.sorted { $0.order < $1.order } }

    /// "Вводный урок 3" / "Урок 12" — where it sits in the textbook.
    var sourceLabel: String {
        sourcePart == "intro" ? "Вводный урок \(sourceLesson)" : "Урок \(sourceLesson)"
    }
}

@Model
final class GrammarTopic {
    var order: Int
    var topic: String
    /// Rule in the owner's own words; empty until written.
    var ruleRU: String
    var lesson: Lesson?

    init(order: Int, topic: String, ruleRU: String) {
        self.order = order
        self.topic = topic
        self.ruleRU = ruleRU
    }
}

@Model
final class VocabItem {
    /// Stable across re-imports: "<level>/<word folded>". Progress refers to it.
    @Attribute(.unique) var wordID: String
    var order: Int
    var italian: String
    var russian: String
    var posRaw: String
    var gender: String?
    var number: String?
    var stress: String?
    var formOf: String?
    /// Marked as new in this lesson by the textbook.
    var isNew: Bool = false
    var lesson: Lesson?

    init(wordID: String, order: Int, italian: String, russian: String, posRaw: String,
         gender: String?, number: String?, stress: String?, formOf: String?, isNew: Bool = false) {
        self.wordID = wordID
        self.order = order
        self.italian = italian
        self.russian = russian
        self.posRaw = posRaw
        self.gender = gender
        self.number = number
        self.stress = stress
        self.formOf = formOf
        self.isNew = isNew
    }

    var pos: PartOfSpeech { PartOfSpeech(rawValue: posRaw) ?? .other }

    /// Shown in lists: the stressed form if the book marks it.
    var displayItalian: String { stress ?? italian }

    var isPlural: Bool { number == "pl" }

    /// "il lavoro" for nouns, the word itself otherwise. Also what is spoken.
    var withArticle: String {
        guard pos == .noun else { return italian }
        return Articles.withArticle(italian, gender: gender, plural: isPlural) ?? italian
    }

    var displayWithArticle: String {
        guard pos == .noun, let full = Articles.withArticle(displayItalian, gender: gender, plural: isPlural)
        else { return displayItalian }
        return full
    }
}

nonisolated enum PartOfSpeech: String, CaseIterable, Sendable {
    case noun, verb, adj, adv, pron, prep, conj, art, num, interj, proper, phrase, other

    var shortRU: String {
        switch self {
        case .noun: "сущ."
        case .verb: "гл."
        case .adj: "прил."
        case .adv: "нар."
        case .pron: "мест."
        case .prep: "предл."
        case .conj: "союз"
        case .art: "арт."
        case .num: "числ."
        case .interj: "межд."
        case .proper: "имя"
        case .phrase: "выраж."
        case .other: "—"
        }
    }
}
