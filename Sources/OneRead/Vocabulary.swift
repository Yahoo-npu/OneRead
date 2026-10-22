import Foundation

struct WordSource: Codable {
    var bookID: String
    var bookTitle: String
    var chapterID: String?
    var chapterTitle: String?
    var context: String
    var meaning: String?
    var partOfSpeech: String?
    var collectedAt: Date
    var ipaUS: String?
}
struct VocabularyBook: Identifiable {
    var id: String
    var title: String
}
extension Word {
    var collectionIDs: Set<String> { Set(collectionBookIDs ?? sources?.map(\.bookID) ?? []) }
    var isArchived: Bool { archivedAt != nil }
    func source(in bookID: String? = nil) -> WordSource? {
        let ordered = (sources ?? []).sorted { $0.collectedAt > $1.collectedAt }
        return bookID.flatMap { id in ordered.first { $0.bookID == id } } ?? ordered.first
    }
    func conciseMeaning(in bookID: String? = nil) -> String {
        let value = [source(in: bookID)?.meaning, dictionary?.contextualMeaning, meaning].compactMap { $0 }.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? ""
        return value.components(separatedBy: .newlines).first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? "暂无释义"
    }
    func partOfSpeech(in bookID: String? = nil) -> String {
        [source(in: bookID)?.partOfSpeech, dictionary?.contextualPOS].compactMap { $0 }.first { !$0.isEmpty } ?? ""
    }
}
enum Vocabulary {
    static func books(in library: Library) -> [VocabularyBook] {
        var seen = Set<String>(); var result: [VocabularyBook] = []
        for book in library.books where seen.insert(book.id).inserted { result.append(VocabularyBook(id: book.id, title: book.title)) }
        for source in library.words.flatMap({ $0.sources ?? [] }) where seen.insert(source.bookID).inserted { result.append(VocabularyBook(id: source.bookID, title: source.bookTitle)) }
        return result
    }
    static func words(in library: Library, group: String, archived: Bool, query: String) -> [Word] {
        let bookID = group.hasPrefix("book:") ? String(group.dropFirst(5)) : nil
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return library.words.filter { word in
            guard word.isArchived == archived else { return false }
            if group == "uncategorized", !word.collectionIDs.isEmpty { return false }
            if let bookID, !word.collectionIDs.contains(bookID) { return false }
            return search.isEmpty || ([word.spelling, word.meaning] + (word.sources ?? []).flatMap { [$0.bookTitle, $0.chapterTitle ?? "", $0.meaning ?? ""] }).contains { $0.localizedCaseInsensitiveContains(search) }
        }.sorted { ($0.source(in: bookID)?.collectedAt ?? $0.created) > ($1.source(in: bookID)?.collectedAt ?? $1.created) }
    }
    @discardableResult static func migrateSources(in library: inout Library) -> Bool {
        var changed = false
        let books = (library.books + (library.trash ?? []).map(\.book)).sorted { $0.title.count > $1.title.count }
        for index in library.words.indices where library.words[index].sources == nil {
            let word = library.words[index]
            guard let book = books.first(where: { word.context == $0.title || word.context.hasPrefix($0.title + " · ") }) else { continue }
            let text = word.context.hasPrefix(book.title + " · ") ? String(word.context.dropFirst(book.title.count + 3)) : ""
            let matchingChapters = text.isEmpty ? [] : book.chapters.filter { chapter in chapter.sentences.contains { !$0.original.isEmpty && text.contains($0.original) } }
            let chapter = matchingChapters.count == 1 ? matchingChapters[0] : nil
            library.words[index].sources = [WordSource(bookID: book.id, bookTitle: book.title, chapterID: chapter?.id, chapterTitle: chapter?.title, context: text, meaning: word.dictionary?.contextualMeaning ?? word.meaning, partOfSpeech: word.dictionary?.contextualPOS, collectedAt: word.created, ipaUS: word.dictionary?.ipaUS)]
            changed = true
        }
        return changed
    }
}
