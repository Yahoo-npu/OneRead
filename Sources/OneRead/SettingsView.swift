import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    @State private var profiles: [APIProfile] = []
    @State private var selectedID = ""
    @State private var credentials = CredentialDraft()
    @State private var failure = ""
    @StateObject private var operation = SettingsOperation()
    @State private var connectionMessage = ""
    @State private var connectionSucceeded = false
    @State private var manualModel = false
    @State private var agents: [DetectedAgent] = []
    @State private var selectedAgent = ""
    @State private var agentMessage = ""
    @State private var tab = "appearance"
    @State private var storageMessage = ""
    @State private var storagePath = ""
    private let tabs = [("appearance", "阅读外观", "paintbrush.pointed"), ("translation", "翻译服务", "translate"), ("vocabulary", "墨墨同步", "arrow.triangle.2.circlepath"), ("storage", "本地数据", "externaldrive")]
    private var profile: APIProfile? { profiles.first { $0.id == selectedID } }
    private func field(_ key: WritableKeyPath<APIProfile, String>) -> Binding<String> {
        Binding(get: { profile?[keyPath: key] ?? "" }, set: { value in
            if let index = profiles.firstIndex(where: { $0.id == selectedID }) { profiles[index][keyPath: key] = value; connectionMessage = "" }
        })
    }
    private func keyBinding(_ account: String) -> Binding<String> {
        Binding(get: { credentials.values[account] ?? "" }, set: { credentials.edit($0, account: account); connectionMessage = "" })
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("设置").font(.system(size: 21, weight: .semibold)); Spacer(); Button("完成", action: saveSettings).keyboardShortcut(.defaultAction).disabled(store.dataMoving) }.padding(24)
            Divider()
            HStack(spacing: 0) {
                VStack(spacing: 6) {
                    ForEach(tabs, id: \.0) { item in
                        Button { tab = item.0 } label: {
                            Label(item.1, systemImage: item.2).font(.system(size: 13, weight: tab == item.0 ? .medium : .regular)).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 11)
                                .foregroundStyle(tab == item.0 ? Color.accentColor : Color.secondary)
                                .background(tab == item.0 ? Color.accentColor.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain)
                    }
                    Spacer()
                }.padding(14).frame(width: 174).background(Color.primary.opacity(0.018))
                Divider()
                Form {
                    if tab == "appearance" {
                        Section("阅读外观") {
                            Picker("主题", selection: $store.library.preferences.theme) { Text("纸张").tag("paper"); Text("浅色").tag("light"); Text("深色").tag("dark") }
                            Stepper("正文字号：\(store.library.preferences.fontSize)", value: $store.library.preferences.fontSize, in: 14...30)
                        }
                    } else if tab == "translation" {
                        Section("翻译服务") {
                            Picker("接入方式", selection: $store.library.preferences.provider) { Text("云端 API").tag("API"); Text("本地 Agent").tag("Agent") }
                            if store.library.preferences.provider == "API" { apiConfiguration } else { agentConfiguration }
                        }
                    } else if tab == "vocabulary" {
                        Section("墨墨背单词") {
                            SecureField("API Token", text: keyBinding("maimemo"))
                            credentialNotice("maimemo")
                            LabeledContent("云词本", value: store.library.preferences.notepadID.isEmpty ? "首次同步时创建" : "已绑定")
                        }
                    } else {
                        Section("数据保存位置") {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("保存路径").font(.caption).foregroundStyle(.secondary)
                                TextField("完整文件夹路径", text: $storagePath).textFieldStyle(.roundedBorder).font(.system(size: 12, design: .monospaced)).frame(minHeight: 28).onSubmit { applyLocation() }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            HStack {
                                Button("选择文件夹…", action: chooseLocation).disabled(store.busy || store.translating || !store.titleTranslating.isEmpty)
                                Button("应用路径", action: applyLocation).disabled(store.busy || store.translating || !store.titleTranslating.isEmpty || storagePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                Button("在 Finder 中显示") { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: store.file.deletingLastPathComponent().path) }
                            }
                            Text("使用完整路径，不额外创建子文件夹。应用后迁移数据，原位置保留副本。").font(.caption).foregroundStyle(.secondary)
                            if !storageMessage.isEmpty { Text(storageMessage).font(.caption).foregroundStyle(Color.accentColor) }
                        }
                    }
                }.formStyle(.grouped).disabled(operation.isRunning || store.dataMoving).frame(maxWidth: .infinity)
            }.disabled(store.dataMoving)
            if store.dataMoving { HStack { ProgressView().controlSize(.small); Text("正在迁移本地数据…").font(.caption); Spacer() }.padding(16) }
            if operation.isRunning {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    TimelineView(.periodic(from: operation.startedAt, by: 1)) { timeline in
                        Text("\(operation.label) · 已等待 \(max(0, Int(timeline.date.timeIntervalSince(operation.startedAt)))) 秒 / 最长 \(Int(operation.timeout)) 秒").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("取消请求") { operation.cancel(); connectionSucceeded = false; connectionMessage = "已取消，可修改配置或重新测试。" }
                }
            }
            if !failure.isEmpty { Text(failure).font(.caption).foregroundStyle(.red).textSelection(.enabled).padding(.horizontal, 24).padding(.vertical, 14) }
        }.frame(width: 850, height: 580)
        .tint(Color(red: 0.27, green: 0.43, blue: 0.32)).accentColor(Color(red: 0.27, green: 0.43, blue: 0.32))
        .interactiveDismissDisabled(store.dataMoving)
        .onAppear(perform: load)
        .onDisappear { operation.cancel(); store.save() }
        .onChange(of: tab) { _, value in
            if value == "translation", let profile { credentials.load(profile.credentialAccount) }
            if value == "vocabulary" { credentials.load("maimemo") }
        }
        .onChange(of: selectedID) { _, _ in
            manualModel = false; connectionMessage = ""
            if tab == "translation", let profile { credentials.load(profile.credentialAccount) }
        }
        .onChange(of: store.library.preferences.agentArguments) { _, value in
            store.library.preferences.agentArgumentList = AgentDetection.arguments(value)
        }
    }
    @ViewBuilder private var apiConfiguration: some View {
        Picker("服务商 / 已保存配置", selection: $selectedID) { ForEach(profiles) { Text($0.name).tag($0.id) } }
        if let profile {
            if profile.preset == nil { TextField("配置名称", text: field(\.name)); TextField("API 地址", text: field(\.endpoint)) }
            else { LabeledContent("接口地址") { Text(profile.endpoint).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) } }
            SecureField("API Key", text: keyBinding(profile.credentialAccount))
            credentialNotice(profile.credentialAccount)
            Picker("翻译模型", selection: Binding(get: { (manualModel || profile.model.isEmpty) ? "__manual" : profile.model }, set: { value in
                if value == "__manual" { manualModel = true }
                else { manualModel = false; field(\.model).wrappedValue = value }
            })) {
                ForEach(profile.modelChoices, id: \.self) { Text($0).tag($0) }
                Text("手动填写模型 ID…").tag("__manual")
            }
            if manualModel || profile.model.isEmpty { TextField("模型 API ID", text: field(\.model)) }
            HStack {
                Button("刷新可用模型", action: refreshModels)
                Button("测试翻译连接", action: testConnection)
                Spacer()
                Button("新增自定义配置") { let custom = APIProfile.custom(); profiles.append(custom); selectedID = custom.id; manualModel = true }
            }
            if !connectionMessage.isEmpty { Text(connectionMessage).font(.caption).foregroundStyle(connectionSucceeded ? Color.green : Color.red).textSelection(.enabled) }
        }
    }
    @ViewBuilder private func credentialNotice(_ account: String) -> some View {
        if credentials.failures[account] != nil {
            Text("旧密钥暂未授权读取；可保留不变，也可填写新密钥。").font(.caption).foregroundStyle(.secondary)
            Button("授权读取旧密钥（可能出现系统授权）") { credentials.load(account, allowInteraction: true); if let message = credentials.failures[account] { failure = message } else { failure = "" } }
        }
    }
    @ViewBuilder private var agentConfiguration: some View {
        HStack { Button("检测本地 Agent", action: detectAgents); Spacer(); Text("Codex CLI / Claude Code / Gemini CLI").font(.caption).foregroundStyle(.secondary) }
        if !agents.isEmpty {
            Picker("已检测到的 Agent", selection: $selectedAgent) { ForEach(agents) { Text("\($0.name) · \($0.version)").tag($0.id) } }
                .onChange(of: selectedAgent) { _, value in if let agent = agents.first(where: { $0.id == value }) { agent.apply(to: &store.library.preferences) } }
        }
        if !agentMessage.isEmpty { Text(agentMessage).font(.caption).foregroundStyle(.secondary) }
        TextField("可执行文件绝对路径", text: $store.library.preferences.agentPath)
        Text("启动参数（每行一个参数，空参数写为 \"\"）").font(.caption).foregroundStyle(.secondary)
        TextEditor(text: $store.library.preferences.agentArguments).font(.system(.caption, design: .monospaced)).frame(height: 90)
        Button("测试 Agent 连接", action: testConnection)
        if !connectionMessage.isEmpty { Text(connectionMessage).font(.caption).foregroundStyle(connectionSucceeded ? Color.green : Color.red).textSelection(.enabled) }
        Text("首次使用前，请在终端完成 Agent 登录。").font(.caption).foregroundStyle(.secondary)
    }
    private func chooseLocation() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true; panel.allowsMultipleSelection = false
        panel.prompt = "选择保存文件夹"; panel.message = "此文件夹将直接作为数据目录，不会追加 OneRead 子目录。"
        panel.directoryURL = store.file.deletingLastPathComponent()
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        storagePath = destination.path
    }
    private func applyLocation() {
        do {
            let destination = try DataLocation.destination(storagePath)
            Task { @MainActor in
                storageMessage = ""; failure = ""
                if await store.relocateData(to: destination) { storagePath = store.file.deletingLastPathComponent().path; storageMessage = "保存位置已更新" }
                else { failure = store.error ?? "迁移未完成"; store.error = nil }
            }
        } catch { failure = error.localizedDescription }
    }
    private func load() {
        storagePath = store.file.deletingLastPathComponent().path
        guard profiles.isEmpty else { return }
        var p = store.library.preferences; APIProfiles.prepare(&p)
        profiles = p.apiProfiles ?? []; selectedID = p.activeAPIProfileID ?? profiles.first?.id ?? ""
        if tab == "translation", let profile { credentials.load(profile.credentialAccount) }
        if tab == "vocabulary" { credentials.load("maimemo") }
    }
    private func preferencesForRequest() -> Preferences {
        var p = store.library.preferences
        if let profile { APIProfiles.activate(profile, preferences: &p) }
        return p
    }
    private func saveSettings() {
        operation.cancel()
        do {
            if let profile, store.library.preferences.provider == "API", !profile.model.isEmpty { _ = try APIConfiguration(endpoint: profile.endpoint, model: profile.model) }
            try credentials.save()
            store.library.preferences.apiProfiles = profiles
            if let profile { APIProfiles.activate(profile, preferences: &store.library.preferences) }
            guard store.save() else { failure = store.error ?? "设置保存失败"; return }
            dismiss()
        } catch { failure = error.localizedDescription }
    }
    private func refreshModels() {
        guard let profile else { return }
        let key = credentials.values[profile.credentialAccount] ?? ""
        connectionMessage = ""
        operation.run(label: "获取模型列表", timeout: 20, operation: {
            try await APIProfiles.fetchModels(profile: profile, key: key, timeout: 18)
        }, success: { models in
            if let index = profiles.firstIndex(where: { $0.id == profile.id }) { profiles[index].models = models; profiles[index].refreshedAt = Date() }
            connectionSucceeded = true; connectionMessage = "已获取 \(models.count) 个文本模型。当前选择保留不变。"
        }, failure: { error in connectionSucceeded = false; connectionMessage = error.localizedDescription })
    }
    private func testConnection() {
        let p = preferencesForRequest(); let key = profile.flatMap { credentials.values[$0.credentialAccount] } ?? ""
        connectionMessage = ""
        let timeout: TimeInterval = p.provider == "Agent" ? 45 : 30
        operation.run(label: p.provider == "Agent" ? "测试 Agent 连接" : "测试 API 连接", timeout: timeout, operation: {
            try await Translator.translate("Hello, reader.", preferences: p, apiKey: key, timeout: timeout - 2)
        }, success: { result in
            connectionSucceeded = true; connectionMessage = "连接成功：\(String(result.prefix(150)))"
        }, failure: { error in connectionSucceeded = false; connectionMessage = error.localizedDescription })
    }
    private func detectAgents() {
        agentMessage = ""
        operation.run(label: "检测本地 Agent", timeout: 15, operation: { await AgentDetection.detect() }, success: { detected in
            agents = detected
            if let agent = detected.first(where: { $0.path == store.library.preferences.agentPath }) ?? detected.first {
                selectedAgent = agent.id; agent.apply(to: &store.library.preferences)
                agentMessage = "已检测到 \(detected.count) 个可配置的 Agent，并填入路径与参数。请测试连接确认登录与模型可用。"
            } else { agentMessage = "未发现可配置的 Agent。请先安装 Codex CLI、Claude Code 或 Gemini CLI；也可手动填写包装脚本路径。" }
        }, failure: { error in agentMessage = error.localizedDescription })
    }
}
