import Foundation

struct APIPreset: Identifiable {
    let id: String
    let name: String
    let endpoint: String
    let models: [String]
    static let all = [
        APIPreset(id: "deepseek", name: "DeepSeek", endpoint: "https://api.deepseek.com/chat/completions", models: ["deepseek-flash", "deepseek-v4-pro"]),
        APIPreset(id: "openai", name: "OpenAI · ChatGPT", endpoint: "https://api.openai.com/v1/chat/completions", models: ["gpt-6-luna", "gpt-6.1-sol", "gpt-6-astra"]),
        APIPreset(id: "gemini", name: "Google Gemini", endpoint: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions", models: ["gemini-3.8-flash", "gemini-3.5-flash-lite"]),
        APIPreset(id: "qwen", name: "通义千问", endpoint: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions", models: ["qwen-plus", "qwen-flash", "qwen-max"])
    ]
}
struct APIProfile: Codable, Identifiable {
    var id: String
    var presetID: String?
    var name: String
    var endpoint: String
    var model: String
    var models: [String]
    var credentialAccount: String
    var refreshedAt: Date?
    var preset: APIPreset? { APIPreset.all.first { $0.id == presetID } }
    var modelChoices: [String] { Array(Set(models + (model.isEmpty ? [] : [model]))).sorted() }
    static func custom() -> APIProfile {
        let id = UUID().uuidString
        return APIProfile(id: id, name: "自定义兼容 API", endpoint: "https://", model: "", models: [], credentialAccount: "api." + id)
    }
}
enum APIProfiles {
    static func prepare(_ p: inout Preferences) {
        if let existing = p.apiProfiles, !existing.isEmpty {
            var updated = existing.filter { $0.presetID != "mistral" && $0.id != "mistral" }
            for index in updated.indices where updated[index].presetID == "qwen" { updated[index].name = "通义千问" }
            if updated.isEmpty {
                updated = APIPreset.all.map { APIProfile(id: $0.id, presetID: $0.id, name: $0.name, endpoint: $0.endpoint, model: $0.models[0], models: $0.models, credentialAccount: "api." + $0.id) }
            }
            p.apiProfiles = updated
            let active = updated.first { $0.id == p.activeAPIProfileID } ?? updated.first { $0.id == "deepseek" } ?? updated[0]
            activate(active, preferences: &p)
            return
        }
        var profiles = APIPreset.all.map { preset in
            APIProfile(id: preset.id, presetID: preset.id, name: preset.name, endpoint: preset.endpoint, model: preset.models[0], models: preset.models, credentialAccount: "api." + preset.id)
        }
        let old = try? APIConfiguration(endpoint: p.endpoint, model: p.model.isEmpty ? "placeholder" : p.model)
        let index = profiles.firstIndex { profile in
            (try? APIConfiguration(endpoint: profile.endpoint, model: "placeholder").url) == old?.url
        }
        let chosen: Int
        if let index { chosen = index }
        else {
            var custom = APIProfile.custom(); custom.name = "原有自定义 API"; custom.endpoint = p.endpoint; custom.model = p.model
            profiles.append(custom); chosen = profiles.count - 1
        }
        if !p.model.isEmpty { profiles[chosen].model = old?.model ?? p.model }
        profiles[chosen].credentialAccount = "api" // Keep the legacy item without reading or rewriting it.
        p.apiProfiles = profiles
        activate(profiles[chosen], preferences: &p)
    }
    static func activate(_ profile: APIProfile, preferences p: inout Preferences) {
        p.activeAPIProfileID = profile.id; p.endpoint = profile.endpoint; p.model = profile.model
        p.apiCredentialAccount = profile.credentialAccount
    }
    static func modelListURL(endpoint: String) throws -> URL {
        let completion = try APIConfiguration(endpoint: endpoint, model: "placeholder").url
        return completion.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("models")
    }
    static func textModelIDs(_ data: [[String: Any]], presetID: String?) -> [String] {
        data.compactMap { item -> String? in
            guard let id = item["id"] as? String, !id.isEmpty, id.count <= 200, !id.contains(where: { $0.isWhitespace }) else { return nil }
            let lower = id.lowercased()
            let nonText = ["embedding", "embed-", "tts", "transcrib", "whisper", "realtime", "live", "audio", "image", "moderation", "robotics", "veo", "sora", "research", "codex", "computer-use"]
            guard !nonText.contains(where: { lower.contains($0) }) else { return nil }
            if let capabilities = item["capabilities"] as? [String: Any], capabilities["completion_chat"] as? Bool == false { return nil }
            if presetID == "openai" && !(lower.hasPrefix("gpt-") || lower.hasPrefix("chatgpt-") || lower.range(of: "^o[1-9]", options: .regularExpression) != nil) { return nil }
            if presetID == "gemini" && !lower.hasPrefix("gemini-") { return nil }
            return id
        }.reduce(into: Set<String>()) { $0.insert($1) }.sorted()
    }
    static func fetchModels(profile: APIProfile, key: String, session: URLSession = .shared, timeout: TimeInterval = 20) async throws -> [String] {
        let token = try APIConfiguration.token(key)
        let url = try modelListURL(endpoint: profile.endpoint)
        guard !token.isEmpty || APIConfiguration.isLocal(url.host ?? "") else { throw ReadError.message("请先填写当前服务商的 API Key。") }
        let object = try await HTTP.json(url, token: token, session: session, retry: .transient, timeout: timeout)
        guard let data = object["data"] as? [[String: Any]] else { throw ReadError.message("服务未返回兼容的模型列表。可继续使用预置模型或手动填写模型 ID。") }
        let models = textModelIDs(data, presetID: profile.presetID)
        guard !models.isEmpty else { throw ReadError.message("未发现文本对话模型。可手动填写模型 ID 后测试连接。") }
        return models
    }
}
