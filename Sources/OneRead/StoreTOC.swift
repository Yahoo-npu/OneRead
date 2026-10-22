import Foundation

extension Store {
    func navigateTOC(_ entry: TOCEntry) {
        guard let i = library.books.firstIndex(where: { $0.id == selected }), library.books[i].chapters.indices.contains(entry.chapterIndex) else { return }
        library.books[i].chapterIndex = entry.chapterIndex; library.books[i].selectedTOCEntryID = entry.id
        let ancestors = Set(library.books[i].tocOutline.ancestors(entry.id))
        library.books[i].collapsedTOCEntryIDs?.removeAll { ancestors.contains($0) }
        clearSelection(); save()
    }
    func toggleTOCRead(bookID: String, entryID: String) {
        guard let index = library.books.firstIndex(where: { $0.id == bookID }) else { return }
        let ids = Set(library.books[index].tocOutline.subtree(entryID).map(\.id))
        guard !ids.isEmpty else { return }
        let previous = library.books[index].readTOCEntryIDs
        var read = Set(previous ?? [])
        if ids.isSubset(of: read) { read.subtract(ids) } else { read.formUnion(ids) }
        library.books[index].readTOCEntryIDs = read.sorted()
        if !save() { library.books[index].readTOCEntryIDs = previous }
    }
    func markArticleUnread(bookID: String, chapterIndex: Int) {
        guard let index = library.books.firstIndex(where: { $0.id == bookID }) else { return }
        let previous = library.books[index].readTOCEntryIDs
        let aliases = Set(library.books[index].tocOutline.entries.filter { $0.chapterIndex == chapterIndex }.map(\.id))
        library.books[index].readTOCEntryIDs = (previous ?? []).filter { !aliases.contains($0) }
        if !save() { library.books[index].readTOCEntryIDs = previous }
    }
    func toggleTOCCollapse(bookID: String, entryID: String) {
        guard let index = library.books.firstIndex(where: { $0.id == bookID }), library.books[index].tocOutline.hasChildren(entryID) else { return }
        let previous = library.books[index].collapsedTOCEntryIDs
        var collapsed = Set(previous ?? [])
        if !collapsed.insert(entryID).inserted { collapsed.remove(entryID) }
        library.books[index].collapsedTOCEntryIDs = collapsed.sorted()
        if !save() { library.books[index].collapsedTOCEntryIDs = previous }
    }
    func setAllTOCCollapsed(bookID: String, collapsed: Bool) {
        guard let index = library.books.firstIndex(where: { $0.id == bookID }) else { return }
        let previous = library.books[index].collapsedTOCEntryIDs
        let outline = library.books[index].tocOutline
        library.books[index].collapsedTOCEntryIDs = collapsed ? outline.entries.filter { outline.hasChildren($0.id) }.map(\.id) : []
        if !save() { library.books[index].collapsedTOCEntryIDs = previous }
    }
    func translateTitles(bookID: String, retry: Bool = false) {
        guard !titleTranslating.contains(bookID), let index = library.books.firstIndex(where: { $0.id == bookID }) else { return }
        let titles = Set(library.books[index].tocOutline.entries.map(\.title))
        var cache = library.books[index].titleTranslations ?? [:]
        for sentence in library.books[index].chapters.flatMap(\.sentences) where titles.contains(sentence.original) && !sentence.translation.isEmpty && (cache[sentence.original] ?? "").isEmpty { cache[sentence.original] = sentence.translation }
        if !cache.isEmpty && cache != library.books[index].titleTranslations { library.books[index].titleTranslations = cache; guard save() else { return } }
        let book = library.books[index]
        guard !book.pendingTitleTexts.isEmpty else { return }
        guard retry || titleTranslationErrors[bookID] == nil else { return }
        let texts = book.pendingTitleTexts; let preferences = library.preferences
        titleTranslationErrors[bookID] = nil; titleTranslating.insert(bookID)
        titleTranslationProgress[bookID] = "目录翻译 · 0 / \(texts.count)"
        titleTranslationTasks[bookID] = Task {
            defer { titleTranslating.remove(bookID); titleTranslationTasks[bookID] = nil; titleTranslationProgress[bookID] = nil }
            do {
                var completed = 0
                for offset in stride(from: 0, to: texts.count, by: 16) {
                    try Task.checkCancellation()
                    let batch = Array(texts[offset..<min(offset + 16, texts.count)])
                    let translations = try await titleTranslator(batch, preferences)
                    try Task.checkCancellation()
                    guard let index = library.books.firstIndex(where: { $0.id == bookID }) else { return }
                    guard batch.allSatisfy({ !(translations[$0] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { throw ReadError.message("这一批目录标题返回不完整，请重试。") }
                    var saved = library.books[index].titleTranslations ?? [:]
                    for title in batch { saved[title] = translations[title] }
                    library.books[index].titleTranslations = saved
                    guard save() else { throw ReadError.message("目录译文保存失败。") }
                    completed += batch.count
                    titleTranslationProgress[bookID] = "目录翻译 · \(completed) / \(texts.count)"
                }
            } catch is CancellationError { titleTranslationErrors[bookID] = "目录翻译已暂停，已完成部分已保存。" }
            catch { if !Task.isCancelled { titleTranslationErrors[bookID] = error.localizedDescription } }
        }
    }
}
