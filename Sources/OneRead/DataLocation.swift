import Foundation

enum DataLocation {
    static let preferenceKey = "OneRead.dataDirectory"
    static func destination(_ path: String) throws -> URL {
        let expanded = (path.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
        guard expanded.hasPrefix("/"), !expanded.contains("\0"), expanded != "/" else { throw ReadError.message("请输入有效的绝对路径，例如 ~/APP_Local_Data/OneRead。") }
        return URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL.resolvingSymlinksInPath()
    }
    static func stage(source: URL, destination: URL) throws -> URL {
        let source = source.standardizedFileURL.resolvingSymlinksInPath()
        let destination = destination.standardizedFileURL.resolvingSymlinksInPath()
        guard source.path != destination.path, !destination.path.hasPrefix(source.path + "/"), !source.path.hasPrefix(destination.path + "/") else { throw ReadError.message("请选择当前数据目录以外的位置。") }
        let fm = FileManager.default
        guard !fm.fileExists(atPath: destination.path) else { throw ReadError.message("目标位置已存在 OneRead 文件夹，请选择其他位置，以免覆盖数据。") }
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let stage = destination.deletingLastPathComponent().appendingPathComponent(".OneRead-transfer-" + UUID().uuidString, isDirectory: true)
        do {
            if fm.fileExists(atPath: source.path) { try fm.copyItem(at: source, to: stage) }
            else { try fm.createDirectory(at: stage, withIntermediateDirectories: true) }
            return stage
        } catch { try? fm.removeItem(at: stage); throw error }
    }
}

extension Store {
    @discardableResult func relocateData(to destination: URL, defaults: UserDefaults = .standard) async -> Bool {
        guard !busy, !translating, titleTranslating.isEmpty, !dataMoving, !loadFailed else { error = "请先等待导入或翻译完成，再更改保存位置。"; return false }
        if file.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath().path == destination.standardizedFileURL.resolvingSymlinksInPath().path { return true }
        guard save() else { return false }
        let source = file.deletingLastPathComponent()
        dataMoving = true; busy = true
        defer { dataMoving = false; busy = false }
        var staged: URL?
        do {
            let stage = try await Task.detached { try DataLocation.stage(source: source, destination: destination) }.value
            staged = stage
            let data = try JSONEncoder().encode(library)
            try data.write(to: stage.appendingPathComponent("library.json"), options: .atomic)
            _ = try JSONDecoder().decode(Library.self, from: Data(contentsOf: stage.appendingPathComponent("library.json")))
            try FileManager.default.moveItem(at: stage, to: destination)
            file = destination.appendingPathComponent("library.json")
            assetsRoot = destination.appendingPathComponent("Assets", isDirectory: true)
            defaults.set(destination.path, forKey: DataLocation.preferenceKey)
            status = "数据保存位置已更新，原位置副本已保留"
            return true
        } catch {
            if let staged { try? FileManager.default.removeItem(at: staged) }
            self.error = "更改保存位置失败：" + error.localizedDescription
            return false
        }
    }
}
