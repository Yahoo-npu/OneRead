import Foundation
import CryptoKit

enum MagazineKind: String, Codable, CaseIterable, Identifiable {
    case economist, newYorker, atlantic, wired
    var id: String { rawValue }
    var name: String { switch self { case .economist: return "经济学人"; case .newYorker: return "纽约客"; case .atlantic: return "The Atlantic"; case .wired: return "Wired" } }
    var englishName: String { switch self { case .economist: return "The Economist"; case .newYorker: return "The New Yorker"; case .atlantic: return "The Atlantic"; case .wired: return "Wired" } }
    var directory: String { switch self { case .economist: return "01_economist"; case .newYorker: return "02_new_yorker"; case .atlantic: return "04_atlantic"; case .wired: return "05_wired" } }
    var webURL: URL { URL(string: "https://github.com/hehonghui/awesome-english-ebooks/tree/master/" + directory)! }
    var cacheName: String { self == .economist ? "economist-catalog.json" : rawValue + "-catalog.json" }
    func recognizes(_ title: String) -> Bool {
        let title = title.lowercased()
        switch self {
        case .economist: return title.contains("economist") || title.contains("经济学人")
        case .newYorker: return title.contains("new_yorker") || title.contains("new yorker") || title.contains("newyorker") || title.contains("纽约客")
        case .atlantic: return title.contains("atlantic") || title.contains("大西洋")
        case .wired: return title.contains("wired") || title.contains("连线")
        }
    }
}

struct EconomistIssue: Codable, Identifiable, Equatable {
    var date: String
    var path: String
    var sha: String
    var size: Int
    var magazine: MagazineKind?
    var kind: MagazineKind { magazine ?? .economist }
    var id: String { kind.rawValue + ":" + date }
    var displayDate: String { date.replacingOccurrences(of: "-", with: ".") }
    var filename: String { (path as NSString).lastPathComponent }
    var year: String { String(date.prefix(4)) }
    func matches(_ book: Book) -> Bool {
        if let origin = book.economistIssueID { return origin == id }
        let title = book.title.lowercased()
        return kind.recognizes(title) && EconomistRepository.issueDate(in: book.title) == date
    }
}
struct EconomistCatalog: Codable {
    var treeSHA: String
    var rootETag: String?
    var issues: [EconomistIssue]
    var checkedAt: Date
}
struct EconomistRepository {
    static let webURL = URL(string: "https://github.com/hehonghui/awesome-english-ebooks/tree/master/01_economist")!
    static let api = "https://api.github.com/repos/hehonghui/awesome-english-ebooks/git/trees/"
    let session: URLSession
    let kind: MagazineKind
    init(session: URLSession = .shared, kind: MagazineKind = .economist) { self.session = session; self.kind = kind }
    struct Tree: Decodable {
        var sha: String
        var truncated: Bool
        var tree: [Entry]
    }
    struct Entry: Decodable {
        var path: String
        var type: String
        var sha: String
        var size: Int?
    }
    static func issueDate(in text: String) -> String? {
        guard let range = text.range(of: #"(?<![0-9])20[0-9]{2}[.\-_][0-9]{2}[.\-_][0-9]{2}(?![0-9])"#, options: .regularExpression) else { return nil }
        let pieces = text[range].split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard pieces.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let parts = DateComponents(year: pieces[0], month: pieces[1], day: pieces[2])
        guard let date = calendar.date(from: parts), calendar.dateComponents([.year, .month, .day], from: date) == parts else { return nil }
        return String(format: "%04d-%02d-%02d", pieces[0], pieces[1], pieces[2])
    }
    static func parseIssues(_ data: Data, kind: MagazineKind = .economist) throws -> [EconomistIssue] {
        let tree = try JSONDecoder().decode(Tree.self, from: data)
        guard !tree.truncated else { throw ReadError.message("仓库目录返回不完整，请稍后刷新。") }
        var byDate: [String: EconomistIssue] = [:]
        for item in tree.tree.sorted(by: { $0.path < $1.path }) {
            guard item.type == "blob", item.path.lowercased().hasSuffix(".epub"),
                  !item.path.hasPrefix("/"), !item.path.contains("\\"), !item.path.split(separator: "/").contains(".."),
                  item.sha.range(of: "^[a-f0-9]{40}$", options: .regularExpression) != nil,
                  let size = item.size, size > 0, size <= 80_000_000,
                  let date = issueDate(in: (item.path as NSString).lastPathComponent) ?? issueDate(in: item.path) else { continue }
            let issue = EconomistIssue(date: date, path: item.path, sha: item.sha, size: size, magazine: kind == .economist ? nil : kind)
            // Prefer the repository's canonical EPUB if a folder also has variants.
            if byDate[date] == nil || issue.filename.lowercased() == "theeconomist.\(issue.displayDate).epub" { byDate[date] = issue }
        }
        let result = byDate.values.sorted { $0.date > $1.date }
        guard !result.isEmpty else { throw ReadError.message("仓库中暂未找到可导入的 EPUB 期刊。") }
        return result
    }
    func root(previous: EconomistCatalog?) async throws -> (Data, URLResponse) {
        var rootRequest = request(URL(string: Self.api + "master")!)
        if let etag = previous?.rootETag { rootRequest.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        return try await session.data(for: rootRequest)
    }
    func refresh(previous: EconomistCatalog?) async throws -> EconomistCatalog {
        let (data, response) = try await root(previous: previous)
        return try await refresh(previous: previous, rootData: data, rootResponse: response)
    }
    func refresh(previous: EconomistCatalog?, rootData: Data, rootResponse: URLResponse) async throws -> EconomistCatalog {
        if (rootResponse as? HTTPURLResponse)?.statusCode == 304, var cached = previous { cached.checkedAt = Date(); return cached }
        try Self.validate(rootResponse)
        let root = try JSONDecoder().decode(Tree.self, from: rootData)
        guard !root.truncated, let folder = root.tree.first(where: { $0.path == kind.directory && $0.type == "tree" }), folder.sha.range(of: "^[a-f0-9]{40}$", options: .regularExpression) != nil else { throw ReadError.message("仓库目录结构已变化，请稍后刷新。") }
        let etag = (rootResponse as? HTTPURLResponse)?.value(forHTTPHeaderField: "ETag")
        if var previous, previous.treeSHA == folder.sha { previous.checkedAt = Date(); previous.rootETag = etag; return previous }
        let (data, response) = try await session.data(for: request(URL(string: Self.api + folder.sha + "?recursive=1")!))
        try Self.validate(response)
        return EconomistCatalog(treeSHA: folder.sha, rootETag: etag, issues: try Self.parseIssues(data, kind: kind), checkedAt: Date())
    }
    func download(_ issue: EconomistIssue) async throws -> Data {
        guard issue.kind == kind else { throw ReadError.message("期刊来源不匹配，请重新选择。") }
        guard issue.sha.range(of: "^[a-f0-9]{40}$", options: .regularExpression) != nil, issue.size > 0, issue.size <= 80_000_000 else { throw ReadError.message("期刊文件信息无效，请刷新目录。") }
        guard !issue.path.hasPrefix("/"), !issue.path.contains("\\"), !issue.path.split(separator: "/").contains(".."), issue.path.lowercased().hasSuffix(".epub") else { throw ReadError.message("期刊文件路径无效，请刷新目录。") }
        // The raw file CDN does not consume the REST API request quota.
        let raw = URL(string: "https://raw.githubusercontent.com/hehonghui/awesome-english-ebooks/master/" + kind.directory + "/")!.appendingPathComponent(issue.path)
        do {
            var r = request(raw); r.timeoutInterval = 60; r.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
            let (data, response) = try await session.data(for: r)
            try Self.validate(response)
            try Self.validateEPUB(data, issue: issue)
            return data
        } catch is CancellationError { throw CancellationError() }
        catch let error as URLError where error.code == .cancelled { throw error }
        catch let error as ReadError {
            // A changed/corrupt file must be refreshed, never accepted through another path.
            if error.localizedDescription.contains("校验失败") || error.localizedDescription.contains("不完整") { throw error }
        } catch { }
        let url = URL(string: "https://api.github.com/repos/hehonghui/awesome-english-ebooks/git/blobs/" + issue.sha)!
        var r = request(url); r.timeoutInterval = 90
        r.setValue("application/vnd.github.raw+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: r)
        try Self.validate(response)
        try Self.validateEPUB(data, issue: issue)
        return data
    }
    static func validateEPUB(_ data: Data, issue: EconomistIssue) throws {
        guard data.count == issue.size, data.starts(with: [0x50, 0x4b, 0x03, 0x04]) else { throw ReadError.message("下载的 EPUB 不完整或格式无效，请重试。") }
        var hasher = Insecure.SHA1(); hasher.update(data: Data("blob \(data.count)\0".utf8)); hasher.update(data: data)
        let hash = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard hash == issue.sha else { throw ReadError.message("EPUB 校验失败，未导入，请刷新目录后重试。") }
    }
    private func request(_ url: URL) -> URLRequest {
        var r = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25)
        r.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        r.setValue("OneRead-Economist", forHTTPHeaderField: "User-Agent")
        r.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        return r
    }
    private static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw ReadError.message("仓库未返回有效响应。") }
        switch http.statusCode {
        case 200..<300: return
        case 403, 429: throw ReadError.message("GitHub 请求暂时受限，请稍后重试；已缓存的期刊目录仍可查看。")
        case 404: throw ReadError.message("仓库文件暂不可用，请刷新目录后重试。")
        default: throw ReadError.message("连接仓库失败（HTTP \(http.statusCode)），请稍后重试。")
        }
    }
}
