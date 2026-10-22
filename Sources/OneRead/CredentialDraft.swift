import Foundation

/// Settings may preserve unread secrets, but must never overwrite them with a blank field.
struct CredentialDraft {
    var values: [String: String] = [:]
    var failures: [String: String] = [:]
    private(set) var attempted = Set<String>()
    private(set) var loaded = Set<String>()
    private(set) var dirty = Set<String>()
    private var original: [String: String] = [:]
    mutating func load(_ account: String, allowInteraction: Bool = false, reader: (String, Bool) throws -> String = { try Vault.read($0, allowInteraction: $1) }) {
        guard allowInteraction || !attempted.contains(account) else { return }
        guard allowInteraction || !dirty.contains(account) else { return }
        attempted.insert(account)
        do {
            let value = try reader(account, allowInteraction)
            if !dirty.contains(account) { values[account] = value }
            original[account] = value; loaded.insert(account); failures[account] = nil
        } catch { failures[account] = error.localizedDescription }
    }
    mutating func edit(_ value: String, account: String) { values[account] = value; dirty.insert(account) }
    mutating func save(writer: (String, String) throws -> Void = { try Vault.save($0, account: $1) }) throws {
        // Validate every field before writing any, so one invalid input doesn't cause a partial change.
        var changes: [(String, String)] = []
        for account in dirty.sorted() {
            let value = try APIConfiguration.token(values[account] ?? "")
            if value.isEmpty && !loaded.contains(account) { throw ReadError.message("该密钥尚未读取，不能以空值覆盖。请授权读取旧密钥，或填写新的密钥。") }
            if value != original[account] { changes.append((account, value)) }
        }
        for (account, value) in changes {
            try writer(value, account)
            original[account] = value; values[account] = value; loaded.insert(account); failures[account] = nil; dirty.remove(account)
        }
        dirty = dirty.filter { values[$0] != original[$0] }
    }
}
