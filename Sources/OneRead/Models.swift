import Foundation
import Security

struct Sentence: Codable, Identifiable { var id = UUID().uuidString; var original: String; var translation = "" }
struct PDFTextRegion: Codable {
    var sentenceID: String
    var text: String
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}
struct ReadingBlock: Codable, Identifiable {
    var id = UUID().uuidString
    var kind: String
    var sentenceIDs: [String] = []
    var imageResource: String?
    var alt: String?
    var level: Int?
    var pageNumber: Int?
    var aspectRatio: Double?
    var regions: [PDFTextRegion]?
}
struct TOCEntry: Codable, Identifiable {
    var id = UUID().uuidString
    var title: String
    var chapterIndex: Int
    var depth: Int = 0
}
struct Chapter: Codable, Identifiable {
    var id = UUID().uuidString
    var title: String
    var sentences: [Sentence]
    var blocks: [ReadingBlock]?
}
struct Book: Codable, Identifiable {
    var id = UUID().uuidString
    var title: String
    var shelfFolderID: String?
    var shelfFolderAddedAt: Date?
    var lastReadAt: Date?
    var shelfCategory: String?
    var economistIssueID: String?
    var chapters: [Chapter]
    var chapterIndex = 0
    var format: String?
    var assetID: String?
    var sourceName: String?
    var tableOfContents: [TOCEntry]?
    var coverResource: String?
    var titleTranslations: [String: String]?
    var readTOCEntryIDs: [String]?
    var collapsedTOCEntryIDs: [String]?
    var selectedTOCEntryID: String?
    var effectiveCoverResource: String? {
        coverResource ?? chapters.lazy.flatMap { $0.blocks ?? [] }.first(where: { ["image", "pdfPage"].contains($0.kind) && $0.imageResource != nil })?.imageResource
    }
}
struct TrashedBook: Codable, Identifiable {
    var id = UUID().uuidString
    var book: Book
    var originalIndex: Int
    var deletedAt = Date()
}
struct SelectionPopoverState {
    var id: String?
    var text = ""
    var translation = ""
    var error: String?
    var notice = ""
    var loading = false
    var dictionary: DictionaryEntry?
    var analysis: SentenceAnalysis?
    var analysisRequested = false
}
enum ReaderAction {
    case select(text: String, id: String, context: String)
    case analyze(sentenceID: String, id: String)
    case translate(id: String)
    case collect(id: String)
    case dismiss(id: String)
    case speak(id: String, accent: String, slow: Bool)
    case stopSpeaking(id: String)
}
struct Word: Codable, Identifiable { var id = UUID().uuidString; var spelling: String; var meaning: String; var context: String; var created = Date(); var dictionary: DictionaryEntry?; var sources: [WordSource]?; var collectionBookIDs: [String]?; var archivedAt: Date? }
struct Preferences: Codable { var endpoint = "https://api.openai.com/v1/chat/completions"; var model = ""; var provider = "API"; var agentPath = ""; var agentArguments = ""; var theme = "paper"; var fontSize = 19; var shelfCoverWidth: Double?; var notepadID = ""; var economistLastSeenIssueID: String?; var magazineLastSeenIssueIDs: [String: String]?; var readingMode: String?; var apiProfiles: [APIProfile]?; var activeAPIProfileID: String?; var apiCredentialAccount: String?; var agentArgumentList: [String]?; var detectedAgentID: String? }
struct ShelfFolder: Codable, Identifiable { var id = UUID().uuidString; var name: String; var coverFilename: String? }
struct Library: Codable { var folders: [ShelfFolder]?; var books: [Book] = []; var words: [Word] = []; var preferences = Preferences(); var trash: [TrashedBook]? }
enum ReadError: LocalizedError { case message(String); var errorDescription: String? { if case .message(let s) = self { return s }; return nil } }
private enum VaultMemory {
    static let lock = NSLock()
    static var values: [String: String] = [:]
    static func get(_ account: String) -> String? { lock.lock(); defer { lock.unlock() }; return values[account] }
    static func set(_ value: String, account: String) { lock.lock(); defer { lock.unlock() }; values[account] = value }
}
enum Vault {
    private static var service: String {
        // Separate namespaces allow isolated UI verification without reading production credentials.
        Bundle.main.object(forInfoDictionaryKey: "OneReadKeychainService") as? String ?? "com.oneread.reader"
    }
    static func readQuery(_ account: String, allowInteraction: Bool = false) -> [String: Any] {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        // Classic login-keychain ACL prompts must also be suppressed, including ad-hoc rebuilds.
        if !allowInteraction { query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail }
        return query
    }
    static func read(_ account: String, allowInteraction: Bool = false) throws -> String {
        if !allowInteraction, let cached = VaultMemory.get(account) { return cached }
        let q = readQuery(account, allowInteraction: allowInteraction)
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw ReadError.message("无法读取 macOS 钥匙串中的\(account.hasPrefix("api") ? "翻译 API Key" : "墨墨 token")（错误 \(status)）。设置不会自动弹出钥匙串授权。请点击“授权读取旧密钥”，或重新填写该凭据。")
        }
        VaultMemory.set(value, account: account)
        return value
    }
    static func save(_ value: String, account: String) throws {
        if VaultMemory.get(account) == value { return }
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail]
        let status: OSStatus
        if value.isEmpty { status = SecItemDelete(q as CFDictionary) } else {
            let attrs = [kSecValueData as String: Data(value.utf8)]
            let update = SecItemUpdate(q as CFDictionary, attrs as CFDictionary)
            status = update == errSecItemNotFound ? SecItemAdd(q.filter { $0.key != (kSecUseAuthenticationUI as String) }.merging(attrs) { _, new in new } as CFDictionary, nil) : update
        }
        guard status == errSecSuccess || (value.isEmpty && status == errSecItemNotFound) else { throw ReadError.message("钥匙串保存失败：\(status)。旧项目可能需要点击“授权读取旧密钥”后再保存。") }
        VaultMemory.set(value, account: account)
    }
}
