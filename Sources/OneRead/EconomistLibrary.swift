import SwiftUI

@MainActor final class EconomistLibrary: ObservableObject {
    @Published var catalog: EconomistCatalog?
    @Published var checking = false
    @Published var catalogError: String?
    @Published var pendingIssue: EconomistIssue?
    @Published var importingID: String?
    @Published var importPhase = ""
    @Published var importError: String?
    @Published var importedBookID: String?
    let repository: EconomistRepository
    private var started = false
    private var importTask: Task<Void, Never>?
    init(repository: EconomistRepository = EconomistRepository()) { self.repository = repository }
    var kind: MagazineKind { repository.kind }
    var issues: [EconomistIssue] { catalog?.issues ?? [] }
    func start(store: Store, performRefresh: Bool = true) async {
        guard !started else { return }; started = true
        let cache = store.file.deletingLastPathComponent().appendingPathComponent(kind.cacheName)
        if let data = try? Data(contentsOf: cache) { catalog = try? JSONDecoder().decode(EconomistCatalog.self, from: data) }
        if catalog == nil, kind == .economist {
            #if SWIFT_PACKAGE
            let seed = Bundle.module.url(forResource: "EconomistCatalogSeed", withExtension: "json")
            #else
            let seed = Bundle.main.url(forResource: "EconomistCatalogSeed", withExtension: "json")
            #endif
            if let seed, let data = try? Data(contentsOf: seed) { catalog = try? JSONDecoder().decode(EconomistCatalog.self, from: data) }
        }
        if catalog == nil, kind != .economist {
            #if SWIFT_PACKAGE
            let seed = Bundle.module.url(forResource: "MagazineCatalogSeeds", withExtension: "json")
            #else
            let seed = Bundle.main.url(forResource: "MagazineCatalogSeeds", withExtension: "json")
            #endif
            if let seed, let data = try? Data(contentsOf: seed), let seeds = try? JSONDecoder().decode([String: EconomistCatalog].self, from: data) { catalog = seeds[kind.rawValue] }
        }
        if performRefresh { await refresh(store: store) }
    }
    func refresh(store: Store, root: (Data, URLResponse)? = nil) async {
        guard !checking else { return }
        checking = true; catalogError = nil
        defer { checking = false }
        do {
            let result: EconomistCatalog
            if let root { result = try await repository.refresh(previous: catalog, rootData: root.0, rootResponse: root.1) }
            else { result = try await repository.refresh(previous: catalog) }
            try Task.checkCancellation()
            catalog = result
            let directory = store.file.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if let encoded = try? JSONEncoder().encode(result) { try? encoded.write(to: directory.appendingPathComponent(kind.cacheName), options: .atomic) }
            pendingIssue = result.issues.first.flatMap { Self.shouldNotify($0, library: store.library) ? $0 : nil }
        } catch is CancellationError { }
        catch { catalogError = "暂时无法检查更新：" + error.localizedDescription }
    }
    static func shouldNotify(_ issue: EconomistIssue, library: Library) -> Bool {
        (issue.kind == .economist ? library.preferences.economistLastSeenIssueID : library.preferences.magazineLastSeenIssueIDs?[issue.kind.rawValue]) != issue.id && !library.books.contains(where: issue.matches) && !(library.trash ?? []).contains(where: { issue.matches($0.book) })
    }
    func dismissUpdate(store: Store) {
        guard let issue = pendingIssue else { return }
        let previous = store.library.preferences
        if kind == .economist { store.library.preferences.economistLastSeenIssueID = issue.id }
        else {
            var seen = store.library.preferences.magazineLastSeenIssueIDs ?? [:]; seen[kind.rawValue] = issue.id; store.library.preferences.magazineLastSeenIssueIDs = seen
        }
        if store.save() { pendingIssue = nil } else { store.library.preferences = previous }

    }
    func existingBook(_ issue: EconomistIssue, store: Store) -> Book? { store.library.books.first(where: issue.matches) }
    func isTrashed(_ issue: EconomistIssue, store: Store) -> Bool { (store.library.trash ?? []).contains { issue.matches($0.book) } }
    func beginImport(_ issue: EconomistIssue, store: Store) {
        guard issue.kind == kind else { importError = "期刊来源不匹配，请重新选择。"; return }
        guard importingID == nil, !store.busy, !store.translating else { return }
        guard !store.loadFailed else { importError = "书库读取失败，请先修复本地书库后再导入。"; return }
        importError = nil; importedBookID = nil
        if let existing = existingBook(issue, store: store) { store.selected = existing.id; importedBookID = existing.id; if pendingIssue?.id == issue.id { pendingIssue = nil }; return }
        if let deleted = store.library.trash?.first(where: { issue.matches($0.book) }) {
            store.restoreBook(deleted.id)
            if let restored = existingBook(issue, store: store) { store.selected = restored.id; importedBookID = restored.id; if pendingIssue?.id == issue.id { pendingIssue = nil } }
            return
        }
        importingID = issue.id; store.busy = true; importPhase = "正在下载 \(issue.displayDate) · EPUB…"
        importTask = Task {
            var parsed: Book?
            var committed = false
            let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            defer {
                try? FileManager.default.removeItem(at: temporary)
                if !committed, let assetID = parsed?.assetID, let assets = AssetStore.directory(assetID, root: store.assetsRoot) { try? FileManager.default.removeItem(at: assets) }
                importingID = nil; importPhase = ""; store.busy = false; importTask = nil
            }
            do {
                let data = try await repository.download(issue)
                try Task.checkCancellation()
                try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
                let file = temporary.appendingPathComponent(issue.filename)
                try data.write(to: file)
                importPhase = "下载已校验，正在解析章节与图片…"
                let assets = store.assetsRoot
                var book = try await Task.detached { try Importer.load(file, assetsRoot: assets) }.value
                parsed = book
                try Task.checkCancellation()
                book.economistIssueID = issue.id
                book.shelfFolderAddedAt = Date()
                book.lastReadAt = Date()
                let previous = store.library
                let folderID: String
                if let existing = (store.library.folders ?? []).first(where: { $0.id == kind.rawValue || $0.name == kind.name }) { folderID = existing.id }
                else {
                    folderID = kind.rawValue
                    store.library.folders = (store.library.folders ?? []) + [ShelfFolder(id: folderID, name: kind.name)]
                }
                book.shelfFolderID = folderID
                store.library.books.append(book)
                guard store.save() else { store.library = previous; throw ReadError.message("期刊未保存成功，请检查本地存储后重试。") }
                committed = true
                store.selected = book.id; store.status = "已导入\(kind.name) · \(issue.displayDate)"
                if pendingIssue?.id == issue.id { pendingIssue = nil }
                importedBookID = book.id
                store.translateTitles(bookID: book.id, retry: true)
            } catch is CancellationError { store.status = "已取消期刊导入" }
            catch let error as URLError where error.code == .cancelled { store.status = "已取消期刊导入" }
            catch { importError = error.localizedDescription; store.status = "期刊导入未完成，可重试" }
        }
    }
    func cancelImport() { importPhase = "正在取消导入…"; importTask?.cancel() }
    func waitForImport() async { await importTask?.value }
}
