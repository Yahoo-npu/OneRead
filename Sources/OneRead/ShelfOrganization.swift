import Foundation
import AppKit
import ImageIO
import UniformTypeIdentifiers

enum ShelfOrganization {
    static let economistID = "economist"
    static let presets = ["经济学人"]
    static let sizes: [Double] = [140, 190, 260]
    static func category(for book: Book) -> String { book.shelfCategory ?? "未收纳" }
    static func categories(in library: Library) -> [String] { (library.folders ?? []).map(\.name) }
    static func coverWidth(_ preferences: Preferences) -> Double {
        let value = preferences.shelfCoverWidth ?? 190
        return value.isFinite ? sizes.min(by: { abs($0 - value) < abs($1 - value) })! : 190
    }
    @discardableResult static func prepare(_ library: inout Library) -> Bool {
        guard library.folders == nil else { return false }
        var folders = [ShelfFolder(id: economistID, name: "经济学人")]
        func folder(_ name: String) -> String {
            if let existing = folders.first(where: { $0.name == name }) { return existing.id }
            let item = ShelfFolder(name: name); folders.append(item); return item.id
        }
        for index in library.books.indices {
            let book = library.books[index]
            if let manual = book.shelfCategory, !manual.isEmpty { library.books[index].shelfFolderID = folder(manual) }
            else if book.economistIssueID != nil || book.title.lowercased().contains("economist") || book.title.contains("经济学人") { library.books[index].shelfFolderID = economistID }
        }
        // Preserve manual organization for books that may later be restored.
        if var trash = library.trash {
            for index in trash.indices {
                if let manual = trash[index].book.shelfCategory, !manual.isEmpty { trash[index].book.shelfFolderID = folder(manual) }
                else if trash[index].book.economistIssueID != nil { trash[index].book.shelfFolderID = economistID }
            }
            library.trash = trash
        }
        library.folders = folders; return true
    }
    static func members(_ folder: ShelfFolder, library: Library) -> [Book] { library.books.filter { $0.shelfFolderID == folder.id } }
    static func mosaicBooks(_ folder: ShelfFolder, library: Library) -> [Book] {
        members(folder, library: library).enumerated().sorted { lhs, rhs in
            let left = lhs.element.shelfFolderAddedAt ?? .distantPast
            let right = rhs.element.shelfFolderAddedAt ?? .distantPast
            return left == right ? lhs.offset > rhs.offset : left > right
        }.prefix(9).map(\.element)
    }
    static func coverBook(_ folder: ShelfFolder, library: Library) -> Book? {
        members(folder, library: library).enumerated().max { lhs, rhs in
            let left = lhs.element.lastReadAt ?? .distantPast, right = rhs.element.lastReadAt ?? .distantPast
            return left == right ? lhs.offset < rhs.offset : left < right
        }?.element
    }
    static func recent(in library: Library) -> [Book] { library.books.filter { $0.lastReadAt != nil }.sorted { $0.lastReadAt! > $1.lastReadAt! } }
    static func coverURL(_ filename: String?, root: URL) -> URL? {
        guard let filename, (filename as NSString).pathExtension == "png", UUID(uuidString: (filename as NSString).deletingPathExtension) != nil else { return nil }
        return root.appendingPathComponent(filename)
    }
}
extension Store {
    var folderCoversRoot: URL { file.deletingLastPathComponent().appendingPathComponent("FolderCovers", isDirectory: true) }
    func recordReading(_ id: String, at date: Date = Date()) {
        guard let index = library.books.firstIndex(where: { $0.id == id }), abs((library.books[index].lastReadAt ?? .distantPast).timeIntervalSince(date)) > 3 else { return }
        let previous = library.books[index].lastReadAt
        library.books[index].lastReadAt = date
        if !save() { library.books[index].lastReadAt = previous }
    }
    func moveBook(_ id: String, to folderID: String?) {
        guard let index = library.books.firstIndex(where: { $0.id == id }), folderID == nil || (library.folders ?? []).contains(where: { $0.id == folderID }) else { return }
        guard library.books[index].shelfFolderID != folderID else { return }
        let previous = library.books[index]
        library.books[index].shelfFolderAddedAt = folderID == nil ? nil : Date()
        library.books[index].shelfFolderID = folderID; library.books[index].shelfCategory = nil
        if !save() { library.books[index] = previous }
    }
    // Compatibility for older callers; explicit names create a manual folder.
    func setShelfCategory(bookID: String, category: String?) {
        guard let category else { moveBook(bookID, to: nil); return }
        if let folder = library.folders?.first(where: { $0.name == category.trimmingCharacters(in: .whitespacesAndNewlines) }) { moveBook(bookID, to: folder.id); return }
        if let id = saveFolder(id: nil, name: category, cover: nil, automatic: true) { moveBook(bookID, to: id) }
    }
    @discardableResult func saveFolder(id: String?, name: String, cover: URL?, automatic: Bool) -> String? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 30 else { error = "分类名称需为 1～30 个字符"; return nil }
        guard !(library.folders ?? []).contains(where: { $0.id != id && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) else { error = "已有同名分类"; return nil }
        let previous = library
        var folder = id.flatMap { wanted in library.folders?.first { $0.id == wanted } } ?? ShelfFolder(name: name)
        folder.name = name
        let oldCover = folder.coverFilename
        var newURL: URL?
        do {
            if let cover {
                guard let source = CGImageSourceCreateWithURL(cover as CFURL, nil), let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1000, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { throw ReadError.message("无法读取封面图片") }
                try FileManager.default.createDirectory(at: folderCoversRoot, withIntermediateDirectories: true)
                let filename = UUID().uuidString + ".png", target = folderCoversRoot.appendingPathComponent(filename)
                newURL = target
                guard let output = CGImageDestinationCreateWithURL(target as CFURL, UTType.png.identifier as CFString, 1, nil) else { throw ReadError.message("无法保存封面") }
                CGImageDestinationAddImage(output, image, nil)
                guard CGImageDestinationFinalize(output) else { throw ReadError.message("无法保存封面") }
                folder.coverFilename = filename
            } else if automatic { folder.coverFilename = nil }
            var folders = library.folders ?? [ShelfFolder(id: ShelfOrganization.economistID, name: "经济学人")]
            if let index = folders.firstIndex(where: { $0.id == folder.id }) { folders[index] = folder } else { folders.append(folder) }
            library.folders = folders
            guard save() else { library = previous; if let newURL { try? FileManager.default.removeItem(at: newURL) }; return nil }
            if oldCover != folder.coverFilename, let old = ShelfOrganization.coverURL(oldCover, root: folderCoversRoot), !folders.contains(where: { $0.coverFilename == oldCover }) { try? FileManager.default.removeItem(at: old) }
            return folder.id
        } catch { library = previous; if let newURL { try? FileManager.default.removeItem(at: newURL) }; self.error = error.localizedDescription; return nil }
    }
    @discardableResult func deleteFolder(_ id: String) -> Bool {
        guard !busy, !translating, let folder = library.folders?.first(where: { $0.id == id }) else { return false }
        let previous = library
        library.folders?.removeAll { $0.id == id }
        for index in library.books.indices where library.books[index].shelfFolderID == id {
            library.books[index].shelfFolderID = nil; library.books[index].shelfFolderAddedAt = nil; library.books[index].shelfCategory = nil
        }
        if var trash = library.trash {
            for index in trash.indices where trash[index].book.shelfFolderID == id {
                trash[index].book.shelfFolderID = nil; trash[index].book.shelfFolderAddedAt = nil; trash[index].book.shelfCategory = nil
            }
            library.trash = trash
        }
        guard save() else { library = previous; return false }
        if let cover = ShelfOrganization.coverURL(folder.coverFilename, root: folderCoversRoot), !(library.folders ?? []).contains(where: { $0.coverFilename == folder.coverFilename }) { try? FileManager.default.removeItem(at: cover) }
        status = "已删除分类《\(folder.name)》，读物已保留在未分类中"
        return true
    }
    func permanentlyDeleteBook(_ trashID: String) { purgeTrash(ids: [trashID]) }
    func emptyTrash() { purgeTrash(ids: Set((library.trash ?? []).map(\.id))) }
    private func purgeTrash(ids: Set<String>) {
        guard !busy, !translating, !(library.trash ?? []).filter({ ids.contains($0.id) }).isEmpty else { return }
        let previous = library
        let removed = (library.trash ?? []).filter { ids.contains($0.id) }
        let remaining = (library.trash ?? []).filter { !ids.contains($0.id) }
        let protected = Set((library.books + remaining.map(\.book)).compactMap(\.assetID))
        let assets = Set(removed.compactMap { $0.book.assetID }).subtracting(protected)
        var staged: [(URL, URL)] = []
        func rollback() {
            library = previous
            for (original, temporary) in staged.reversed() { try? FileManager.default.moveItem(at: temporary, to: original) }
        }
        do {
            for asset in assets {
                guard let original = AssetStore.directory(asset, root: assetsRoot), FileManager.default.fileExists(atPath: original.path) else { continue }
                let temporary = assetsRoot.appendingPathComponent(".purge-" + UUID().uuidString)
                try FileManager.default.moveItem(at: original, to: temporary); staged.append((original, temporary))
            }
            library.trash = remaining
            guard save() else { rollback(); return }
        } catch { rollback(); self.error = "彻底删除未完成：" + error.localizedDescription; return }
        do { for (_, temporary) in staged { try FileManager.default.removeItem(at: temporary) } }
        catch { self.error = "记录已删除，但部分本地文件未清理完成：" + error.localizedDescription; return }
        status = "已彻底删除 \(removed.count) 本读物"
    }
}
