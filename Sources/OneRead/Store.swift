import SwiftUI

@MainActor final class Store: ObservableObject {
    @Published var library = Library()
    @Published var selected: String?
    @Published var status = "准备好开始阅读"
    @Published var error: String?
    @Published var busy = false
    @Published var translating = false
    @Published var translationBookID: String?
    @Published var translationChapterID: String?
    @Published var selection = ""
    @Published var selectionTranslation = ""
    @Published var selectionDictionary: DictionaryEntry?
    @Published var selectionAnalysis: SentenceAnalysis?
    @Published var selectionAnalysisRequested = false
    let analysisLookup: (String, String, Preferences) async throws -> SelectionLookupResult
    let pronunciation = PronunciationPlayer()
    let selectionLookup: (String, String, Preferences) async throws -> SelectionLookupResult
    @Published var selectionID: String?
    @Published var selectionError: String?
    @Published var selectionNotice = ""
    @Published var selectionTranslating = false
    private var selectionTask: Task<Void, Never>?
    private var selectionBookID: String?
    private var selectionChapterID: String?
    private var selectionContext = ""
    var translationTask: Task<Void, Never>?
    @Published var titleTranslating = Set<String>()
    @Published var titleTranslationErrors: [String: String] = [:]
    @Published var titleTranslationProgress: [String: String] = [:]
    var titleTranslationTasks: [String: Task<Void, Never>] = [:]
    let titleTranslator: ([String], Preferences) async throws -> [String: String]
    var loadFailed = false
    @Published var dataMoving = false
    @Published var file: URL
    @Published var assetsRoot: URL
    let translator: (String, Preferences) async throws -> String
    init(dataDirectory: URL = AssetStore.dataDirectory, translator: ((String, Preferences) async throws -> String)? = nil, selectionLookup: ((String, String, Preferences) async throws -> SelectionLookupResult)? = nil, titleTranslator: @escaping ([String], Preferences) async throws -> [String: String] = { try await TitleTranslator.translate($0, preferences: $1) }, analysisLookup: @escaping (String, String, Preferences) async throws -> SelectionLookupResult = { try await SentenceAnalyzer.analyze($0, context: $1, preferences: $2) }) {
        self.titleTranslator = titleTranslator
        self.analysisLookup = analysisLookup
        file = dataDirectory.appendingPathComponent("library.json")
        assetsRoot = dataDirectory.appendingPathComponent("Assets", isDirectory: true)
        self.translator = translator ?? { try await Translator.translate($0, preferences: $1) }
        if let selectionLookup { self.selectionLookup = selectionLookup }
        else if let translator { self.selectionLookup = { text, _, preferences in SelectionLookupResult(translation: try await translator(text, preferences)) } }
        else { self.selectionLookup = { try await DictionaryLookup.lookup($0, context: $1, preferences: $2) } }
        if FileManager.default.fileExists(atPath: file.path) { do { library = try JSONDecoder().decode(Library.self, from: Data(contentsOf: file)) } catch { loadFailed = true; self.error = "本地书库读取失败，原文件未修改：\(error.localizedDescription)" } }
        let migratedVocabulary = Vocabulary.migrateSources(in: &library)
        let migratedFolders = ShelfOrganization.prepare(&library)
        APIProfiles.prepare(&library.preferences)
        selected = library.books.first?.id
        if migratedVocabulary || migratedFolders { save() }
    }
    var book: Book? { library.books.first { $0.id == selected } }
    @discardableResult func save() -> Bool {
        guard !loadFailed else { error = "书库损坏，已禁止覆盖保存。请先备份并修复 library.json。"; return false }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(library).write(to: file, options: .atomic)
            return true
        } catch { self.error = "保存失败：\(error.localizedDescription)"; return false }
    }

    func deleteBook(_ bookID: String) {
        guard !busy, let index = library.books.firstIndex(where: { $0.id == bookID }) else { return }
        let previous = library
        let removed = library.books.remove(at: index)
        var trash = library.trash ?? []
        trash.append(TrashedBook(book: removed, originalIndex: index)); library.trash = trash
        guard save() else { library = previous; return }
        titleTranslationTasks[bookID]?.cancel()
        if translationBookID == bookID { translationTask?.cancel() }
        if selected == bookID { clearSelection(); selected = nil }
        status = "已将《\(removed.title)》移至最近删除，可随时恢复"
    }

    func restoreBook(_ trashID: String) {
        guard let index = library.trash?.firstIndex(where: { $0.id == trashID }), let entry = library.trash?[index], !library.books.contains(where: { $0.id == entry.book.id }) else { return }
        let previous = library
        library.books.insert(entry.book, at: min(entry.originalIndex, library.books.count))
        library.trash?.remove(at: index)
        guard save() else { library = previous; return }
        status = "已恢复《\(entry.book.title)》"
    }

    func undoDelete() { if let last = library.trash?.last { restoreBook(last.id) } }
    func importBook() { openDocuments(replacing: nil) }

    func reloadOriginal() {
        guard let book else { return }
        if let assetID = book.assetID, let source = book.sourceName,
           let file = AssetStore.resource(source, assetID: assetID, root: assetsRoot), FileManager.default.fileExists(atPath: file.path) {
            importDocuments([file], replacing: book.id)
        } else { openDocuments(replacing: book.id) }
    }

    private func openDocuments(replacing bookID: String?) {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.pdf, .epub]; panel.allowsMultipleSelection = bookID == nil
        if bookID != nil { panel.message = "选择这本读物最初导入的 PDF 或 EPUB，以恢复图片和段落排版。已有译文会保留。" }
        guard let window = NSApp.keyWindow ?? NSApp.windows.first else { return }
        panel.beginSheetModal(for: window) { response in
            guard response == .OK else { return }
            Task { @MainActor in self.importDocuments(panel.urls, replacing: bookID) }
        }
    }

    private func importDocuments(_ urls: [URL], replacing bookID: String?) {
        guard !busy && !translating else { return }
        busy = true; status = "正在解析原文与图片…"
        let root = assetsRoot
        Task {
            defer { busy = false }
            if let bookID, let task = titleTranslationTasks[bookID] { task.cancel(); await task.value }
            for url in urls {
                do {
                    let imported = try await Task.detached { try Importer.load(url, assetsRoot: root) }.value
                    if let bookID, let index = library.books.firstIndex(where: { $0.id == bookID }) {
                        library.books[index] = EconomistContent.cleaned(imported, publicationTitle: library.books[index].title).restoringReadingState(from: library.books[index]); selected = bookID
                    } else { library.books.append(imported); selected = imported.id }
                    save(); status = "已载入原文与图片"
                    if let selected { translateTitles(bookID: selected, retry: true) }
                } catch { self.error = error.localizedDescription; status = "导入未完成" }
            }
        }
    }

    func chapter(_ index: Int) {
        guard let i = library.books.firstIndex(where: { $0.id == selected }), library.books[i].chapters.indices.contains(index) else { return }
        library.books[i].chapterIndex = index
        library.books[i].lastReadAt = Date()
        let outline = library.books[i].tocOutline
        if let entry = outline.entries.last(where: { $0.chapterIndex == index }) {
            library.books[i].selectedTOCEntryID = entry.id
            let ancestors = Set(outline.ancestors(entry.id))
            library.books[i].collapsedTOCEntryIDs?.removeAll { ancestors.contains($0) }
        }
        clearSelection(); save()
    }
    func translateAll() { startTranslation(chapterID: nil) }
    func translateChapter() {
        guard let book, book.chapters.indices.contains(book.chapterIndex) else { return }
        startTranslation(chapterID: book.chapters[book.chapterIndex].id)
    }
    private func startTranslation(chapterID: String?) {
        guard let book, !translating && !busy else { return }
        let plan = TranslationPlan(book: book, chapterID: chapterID)
        let label = chapterID == nil ? "全文翻译" : "本章翻译"
        guard !plan.pending.isEmpty else { status = "本次范围内没有待翻译正文"; return }
        let preferences = library.preferences
        translating = true; translationBookID = plan.bookID; translationChapterID = plan.chapterID; status = "\(label) · 0 / \(plan.pending.count)"
        translationTask = Task {
            defer { translating = false; translationBookID = nil; translationChapterID = nil }
            var count = 0
            do {
                if titleTranslating.contains(plan.bookID) { status = "优先翻译目录标题…" }
                while titleTranslating.contains(plan.bookID) { try await Task.sleep(nanoseconds: 100_000_000) }
                try Task.checkCancellation()
                status = "\(label) · 0 / \(plan.pending.count)"
                for sentence in plan.pending {
                    try Task.checkCancellation()
                    let result = try await translator(sentence.original, preferences)
                    try Task.checkCancellation()
                    guard let bookIndex = library.books.firstIndex(where: { $0.id == plan.bookID }) else { return }
                    for chapter in library.books[bookIndex].chapters.indices {
                        if let index = library.books[bookIndex].chapters[chapter].sentences.firstIndex(where: { $0.id == sentence.id }) {
                            library.books[bookIndex].chapters[chapter].sentences[index].translation = result
                        }
                    }
                    count += 1; status = "\(label) · \(count) / \(plan.pending.count)"; save()
                }
                status = "\(label)完成"
            } catch is CancellationError { status = "翻译已停止，已完成的译文已保存" }
            catch { self.error = error.localizedDescription; status = "\(label)暂停，可继续未完成部分" }
        }
    }
    var selectionPopoverState: SelectionPopoverState {
        SelectionPopoverState(id: selectionID, text: selection, translation: selectionTranslation, error: selectionError, notice: selectionNotice, loading: selectionTranslating, dictionary: selectionDictionary, analysis: selectionAnalysis, analysisRequested: selectionAnalysisRequested)
    }
    func handleReaderAction(_ action: ReaderAction) {
        switch action {
        case let .select(text, id, context): selectText(text, id: id, context: context)
        case let .analyze(sentenceID, id):
            guard let book, book.chapters.indices.contains(book.chapterIndex) else { return }
            let chapter = book.chapters[book.chapterIndex]
            guard let sentence = chapter.sentences.first(where: { $0.id == sentenceID }) else { return }
            selectText(sentence.original, id: id, context: sentence.original, analyze: true)
        case let .translate(id): if selectionID == id { translateSelection() }
        case let .collect(id): if selectionID == id { addSelectedWord() }
        case let .speak(id, accent, slow):
            if isCurrentSelection(id) { do { try pronunciation.speak(selection, accent: accent, slow: slow) } catch { selectionNotice = error.localizedDescription } }
        case let .stopSpeaking(id): if selectionID == id { pronunciation.stop() }
        case let .dismiss(id): clearSelection(requestID: id)
        }
    }
    func clearSelection(requestID: String? = nil) {
        guard requestID == nil || selectionID == requestID else { return }
        pronunciation.stop(); selectionDictionary = nil; selectionAnalysis = nil; selectionAnalysisRequested = false
        selectionTask?.cancel(); selectionTask = nil
        selection = ""; selectionTranslation = ""; selectionID = nil; selectionError = nil; selectionNotice = ""; selectionTranslating = false
        selectionBookID = nil; selectionChapterID = nil; selectionContext = ""
    }
    func selectText(_ text: String, id: String, context: String = "", analyze: Bool = false) {
        guard !id.isEmpty, id.count <= 128, let book, book.chapters.indices.contains(book.chapterIndex) else { return }
        let text = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(12000))
        guard !text.isEmpty else { return }
        if selectionID == id && selection == text { return }
        clearSelection()
        selectionID = id; selection = text; selectionBookID = book.id; selectionChapterID = book.chapters[book.chapterIndex].id
        selectionAnalysisRequested = analyze
        selectionContext = String(context.prefix(2000))
        translateSelection()
    }
    private func isCurrentSelection(_ requestID: String) -> Bool {
        guard selectionID == requestID, let book, book.id == selectionBookID, book.chapters.indices.contains(book.chapterIndex) else { return false }
        return book.chapters[book.chapterIndex].id == selectionChapterID
    }
    func translateSelection() {
        guard let requestID = selectionID, isCurrentSelection(requestID), !selectionTranslating else { return }
        let text = selection; let preferences = library.preferences; let context = selectionContext
        let lookup = selectionAnalysisRequested ? analysisLookup : selectionLookup
        selectionError = nil; selectionTranslating = true
        selectionTask = Task {
            defer { if selectionID == requestID { selectionTranslating = false } }
            do {
                let result = try await lookup(text, context, preferences)
                guard !Task.isCancelled, isCurrentSelection(requestID) else { return }
                selectionTranslation = result.translation
                selectionDictionary = result.dictionary
                selectionAnalysis = result.analysis
            } catch {
                guard !Task.isCancelled, isCurrentSelection(requestID) else { return }
                selectionError = error.localizedDescription
            }
        }
    }
    func addSelectedWord() {
        guard let requestID = selectionID, isCurrentSelection(requestID) else { return }
        guard selection.count <= 120, !selection.contains("\n") else { selectionNotice = "请选中不超过 120 字符的单词或短语"; return }
        let count = library.words.count
        let chapter = book?.chapters.first { $0.id == selectionChapterID }
        let articleTitle = book.flatMap { current in current.tocOutline.entries.first { $0.id == current.activeTOCEntryID }?.title } ?? chapter?.title
        let source = book.map { WordSource(bookID: $0.id, bookTitle: $0.title, chapterID: chapter?.id, chapterTitle: articleTitle, context: selectionContext, meaning: selectionDictionary?.contextualMeaning ?? selectionTranslation, partOfSpeech: selectionDictionary?.contextualPOS, collectedAt: Date(), ipaUS: selectionDictionary?.ipaUS) }
        addWord(selection, meaning: selectionTranslation, context: (book?.title ?? "") + (selectionContext.isEmpty ? "" : " · " + selectionContext), dictionary: selectionDictionary, source: source)
        selectionNotice = library.words.count > count ? "已加入生词本" : (selectionDictionary == nil ? "生词本已收录该词" : "已更新生词本词典信息")
    }
    func addWord(_ text: String, meaning: String, context: String, dictionary: DictionaryEntry? = nil, source: WordSource? = nil) {
        let word = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !word.isEmpty, word.count <= 120, !word.contains("\n") else { error = "请输入单词或短语（不超过 120 字符）"; return }
        let previous = library.words
        if let index = library.words.firstIndex(where: { $0.spelling == word }) {
            if let dictionary { library.words[index].dictionary = dictionary; library.words[index].meaning = meaning }
            if let source {
                var sources = library.words[index].sources ?? []
                if let existing = sources.firstIndex(where: { $0.bookID == source.bookID && $0.chapterID == source.chapterID && $0.chapterTitle == source.chapterTitle }) {
                    var updated = source; updated.collectedAt = sources[existing].collectedAt; sources[existing] = updated
                } else { sources.append(source) }
                var collections = library.words[index].collectionIDs; collections.insert(source.bookID)
                library.words[index].sources = sources; library.words[index].collectionBookIDs = collections.sorted()
                library.words[index].archivedAt = nil
            }
            guard save() else { library.words = previous; return }
            status = "已更新：\(word)"; return
        }
        library.words.append(Word(spelling: word, meaning: meaning, context: context, dictionary: dictionary, sources: source.map { [$0] }))
        guard save() else { library.words = previous; return }
        status = "已收录：\(word)"
    }
    func setWordArchived(_ id: String, archived: Bool) {
        guard let index = library.words.firstIndex(where: { $0.id == id }) else { return }
        let previous = library.words[index].archivedAt
        library.words[index].archivedAt = archived ? Date() : nil
        if !save() { library.words[index].archivedAt = previous }
    }
    func setWordCollection(_ id: String, bookID: String?) {
        guard let index = library.words.firstIndex(where: { $0.id == id }) else { return }
        let previous = library.words[index].collectionBookIDs
        var groups = library.words[index].collectionIDs
        if let bookID { if !groups.insert(bookID).inserted { groups.remove(bookID) } } else { groups = [] }
        library.words[index].collectionBookIDs = groups.sorted()
        if !save() { library.words[index].collectionBookIDs = previous }
    }
    func deleteWord(_ id: String) {
        let previous = library.words; library.words.removeAll { $0.id == id }
        if !save() { library.words = previous }
    }

    func speakWord(_ text: String, accent: String = "en-US", slow: Bool = false) {
        do { try pronunciation.speak(text, accent: accent, slow: slow) } catch { self.error = error.localizedDescription }
    }
    func sync() { guard !busy else { return }; busy = true; let words = library.words; let id = library.preferences.notepadID
        Task { defer { busy = false }; do { let result = try await Maimemo.sync(words: words, id: id); library.preferences.notepadID = result; save(); status = "已同步 \(words.count) 个词到墨墨" } catch { self.error = error.localizedDescription } }
    }
}
