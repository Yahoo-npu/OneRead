import Foundation
import NaturalLanguage

enum VocabularyExam: String, CaseIterable, Identifiable {
    case cet4 = "CET-4", cet6 = "CET-6", postgraduate = "考研", ielts = "IELTS", toefl = "TOEFL"
    var id: String { rawValue }
    var sourceURL: URL {
        URL(string: self == .ielts ? "https://github.com/skywind3000/ECDICT" : "https://github.com/KyleBing/english-vocabulary")!
    }
    var sourceDescription: String {
        self == .ielts ? "ECDICT · IELTS 标注词表（社区整理）" : "english-vocabulary 考试词表（社区整理）"
    }
}

/// Immutable local membership index. Never sends the user's words to a service.
struct ExamVocabulary {
    private struct Payload: Decodable { var version: String; var words: [String: [String]] }
    let version: String
    private let lists: [VocabularyExam: Set<String>]
    var isAvailable: Bool { VocabularyExam.allCases.allSatisfy { !(lists[$0] ?? []).isEmpty } }
    static let shared: ExamVocabulary = {
        #if SWIFT_PACKAGE
        let url = Bundle.module.url(forResource: "ExamVocabulary", withExtension: "json")
        #else
        let url = Bundle.main.url(forResource: "ExamVocabulary", withExtension: "json")
        #endif
        return url.flatMap { try? ExamVocabulary(url: $0) } ?? ExamVocabulary(version: "", lists: [:])
    }()
    init(url: URL) throws {
        let payload = try JSONDecoder().decode(Payload.self, from: Data(contentsOf: url))
        version = payload.version
        lists = Dictionary(uniqueKeysWithValues: VocabularyExam.allCases.map { exam in
            (exam, Set((payload.words[exam.rawValue] ?? []).map(Self.normalize)))
        })
        guard isAvailable else { throw ReadError.message("考试词表不完整") }
    }
    private init(version: String, lists: [VocabularyExam: Set<String>]) { self.version = version; self.lists = lists }
    func count(for exam: VocabularyExam) -> Int { lists[exam]?.count ?? 0 }
    func tags(for word: Word) -> [VocabularyExam] { tags(spelling: word.spelling, lemma: word.dictionary?.lemma) }
    func tags(spelling: String, lemma: String? = nil) -> [VocabularyExam] {
        let spelling = Self.normalize(spelling)
        guard !spelling.isEmpty else { return [] }
        var candidates: Set<String> = [spelling]
        // Whole phrases match only as phrases; an individual component is not evidence.
        if spelling.range(of: "^[a-z]+(?:['-][a-z]+)*$", options: .regularExpression) != nil {
            if let lemma {
                let base = Self.normalize(lemma)
                if base.range(of: "^[a-z]+(?:['-][a-z]+)*$", options: .regularExpression) != nil { candidates.insert(base) }
            }
            let tagger = NLTagger(tagSchemes: [.lemma])
            tagger.string = spelling; tagger.setLanguage(.english, range: spelling.startIndex..<spelling.endIndex)
            let (tag, _) = tagger.tag(at: spelling.startIndex, unit: .word, scheme: .lemma)
            if let tag { candidates.insert(Self.normalize(tag.rawValue)) }
        }
        return VocabularyExam.allCases.filter { !(lists[$0] ?? []).isDisjoint(with: candidates) }
    }
    static func normalize(_ value: String) -> String {
        value.precomposedStringWithCanonicalMapping.lowercased()
            .replacingOccurrences(of: "’", with: "'").replacingOccurrences(of: "–", with: "-")
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}
