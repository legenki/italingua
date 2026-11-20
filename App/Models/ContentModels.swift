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

    /// "Вводный урок 3" / "Урок 12".
    var sourceLabel: String {
        sourcePart == "intro" ? String(localized: "Вводный урок \(sourceLesson)") : String(localized: "Урок \(sourceLesson)")
    }
}

@Model
final class GrammarTopic {
    var order: Int
    var topic: String
    /// Rule in the owner's own words; empty until written.
    var ruleRU: String
    /// Translations for the English and Spanish interface ("" = not translated yet).
    var topicEN: String = ""
    var topicES: String = ""
    var ruleEN: String = ""
    var ruleES: String = ""

    /// Topic name and rule in the interface language, Russian when not translated.
    var title: String { AppLanguage.pick(ru: topic, en: topicEN, es: topicES) }
    var rule: String { AppLanguage.pick(ru: ruleRU, en: ruleEN, es: ruleES) }
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
    var english: String = ""
    var spanish: String = ""

    /// The gloss in the interface language, Russian when not translated.
    var translation: String { AppLanguage.pick(ru: russian, en: english, es: spanish) }
    var posRaw: String
    var gender: String?
    var number: String?
    var stress: String?
    var formOf: String?
    /// Marked as new in this lesson.
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

    /// Shown in lists: the stressed form when marked.
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
        case .noun: String(localized: "сущ.")
        case .verb: String(localized: "гл.")
        case .adj: String(localized: "прил.")
        case .adv: String(localized: "нар.")
        case .pron: String(localized: "мест.")
        case .prep: String(localized: "предл.")
        case .conj: String(localized: "союз")
        case .art: String(localized: "арт.")
        case .num: String(localized: "числ.")
        case .interj: String(localized: "межд.")
        case .proper: String(localized: "имя")
        case .phrase: String(localized: "выраж.")
        case .other: "—"
        }
    }
}
