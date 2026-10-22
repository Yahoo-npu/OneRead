import Foundation

struct TranslationPlan {
    let bookID: String
    let chapterID: String?
    let pending: [Sentence]
    init(book: Book, chapterID: String? = nil) {
        bookID = book.id; self.chapterID = chapterID
        pending = book.chapters.filter { chapterID == nil || $0.id == chapterID }.flatMap(\.sentences).filter { !$0.original.isEmpty && $0.translation.isEmpty }
    }
}

extension Book {
    /// Reimporting enriches older, text-only books without losing saved translations or selection.
    func restoringReadingState(from previous: Book) -> Book {
        var updated = self
        updated.id = previous.id; updated.title = previous.title; updated.economistIssueID = previous.economistIssueID; updated.shelfCategory = previous.shelfCategory; updated.shelfFolderID = previous.shelfFolderID; updated.shelfFolderAddedAt = previous.shelfFolderAddedAt; updated.lastReadAt = previous.lastReadAt
        var translations: [String: String] = [:]
        for sentence in previous.chapters.flatMap(\.sentences) where !sentence.translation.isEmpty { translations[sentence.original.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)] = sentence.translation }
        for chapter in updated.chapters.indices {
            for sentence in updated.chapters[chapter].sentences.indices {
                let text = updated.chapters[chapter].sentences[sentence].original.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                if let translation = translations[text] { updated.chapters[chapter].sentences[sentence].translation = translation }
            }
        }
        if previous.chapters.indices.contains(previous.chapterIndex), let index = updated.chapters.firstIndex(where: { $0.title == previous.chapters[previous.chapterIndex].title }) { updated.chapterIndex = index }
        else { updated.chapterIndex = min(previous.chapterIndex, max(0, updated.chapters.count - 1)) }
        let newTitles = Set(updated.tocOutline.entries.map(\.title))
        updated.titleTranslations = previous.titleTranslations?.filter { newTitles.contains($0.key) }
        func paths(_ book: Book) -> [String: String] {
            let outline = book.tocOutline
            let titles = Dictionary(uniqueKeysWithValues: outline.entries.map { ($0.id, $0.title) })
            var counts: [String: Int] = [:]; var result: [String: String] = [:]
            for entry in outline.entries {
                let path = (outline.ancestors(entry.id).compactMap { titles[$0] } + [entry.title, book.chapters[entry.chapterIndex].title]).joined(separator: "\u{1f}")
                let occurrence = counts[path, default: 0]; counts[path] = occurrence + 1
                result[entry.id] = path + "#" + String(occurrence)
            }
            return result
        }
        let oldPaths = paths(previous), newPaths = paths(updated)
        let newIDs = Dictionary(uniqueKeysWithValues: newPaths.map { ($0.value, $0.key) })
        func mapped(_ ids: [String]?) -> [String]? { ids.map { $0.compactMap { oldPaths[$0].flatMap { newIDs[$0] } } } }
        updated.readTOCEntryIDs = mapped(previous.readTOCEntryIDs)
        updated.collapsedTOCEntryIDs = mapped(previous.collapsedTOCEntryIDs)
        updated.selectedTOCEntryID = previous.selectedTOCEntryID.flatMap { oldPaths[$0].flatMap { newIDs[$0] } }
        return updated
    }
}
