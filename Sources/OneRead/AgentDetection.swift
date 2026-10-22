import Foundation

struct DetectedAgent: Identifiable {
    var id: String { path }
    var name: String
    var path: String
    var version: String
    var arguments: [String]
    var usesOutputFile: Bool
    func apply(to p: inout Preferences) {
        p.agentPath = path; p.agentArgumentList = arguments
        p.agentArguments = AgentDetection.displayArguments(arguments)
        p.detectedAgentID = usesOutputFile ? "codex" : name.lowercased()
    }
}
enum AgentDetection {
    static func displayArguments(_ arguments: [String]) -> String { arguments.map { $0.isEmpty ? "\"\"" : $0 }.joined(separator: "\n") }
    static func arguments(_ text: String) -> [String] {
        text.components(separatedBy: "\n").filter { !$0.isEmpty }.map { $0 == "\"\"" ? "" : $0 }
    }
    static func searchDirectories() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var paths = (ProcessInfo.processInfo.environment["PATH"] ?? "").components(separatedBy: ":")
        paths += [home + "/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", home + "/.npm-global/bin", home + "/.volta/bin", home + "/.bun/bin", "/Applications/Codex.app/Contents/Resources"]
        let nvm = home + "/.nvm/versions/node"
        for version in ((try? FileManager.default.contentsOfDirectory(atPath: nvm)) ?? []).sorted().reversed().prefix(12) { paths.append(nvm + "/" + version + "/bin") }
        var seen = Set<String>()
        return paths.filter { $0.hasPrefix("/") && seen.insert($0).inserted }
    }
    static func environment(executable: String) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = ([URL(fileURLWithPath: executable).deletingLastPathComponent().path] + searchDirectories()).joined(separator: ":")
        env["NO_COLOR"] = "1"
        return env
    }
    private static func inspect(path: String, arguments: [String]) async throws -> String {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let output = dir.appendingPathComponent("output")
        FileManager.default.createFile(atPath: output.path, contents: nil)
        let handle = try FileHandle(forWritingTo: output); defer { try? handle.close() }
        let process = Process(); process.executableURL = URL(fileURLWithPath: path); process.arguments = arguments
        process.environment = environment(executable: path); process.currentDirectoryURL = dir
        process.standardInput = FileHandle.nullDevice; process.standardOutput = handle; process.standardError = FileHandle.nullDevice
        try process.run(); defer { if process.isRunning { process.terminate() } }
        let deadline = Date().addingTimeInterval(4)
        while process.isRunning && Date() < deadline { try await Task.sleep(nanoseconds: 50_000_000) }
        guard !process.isRunning, process.terminationStatus == 0 else { throw ReadError.message("检测超时或命令不可用") }
        return String((try String(contentsOf: output, encoding: .utf8)).prefix(40_000))
    }
    static func detect(directories: [String]? = nil) async -> [DetectedAgent] {
        let directories = directories ?? searchDirectories()
        var paths: [(String, String)] = []; var seen = Set<String>()
        for name in ["codex", "claude", "gemini"] {
            for directory in directories {
                let path = URL(fileURLWithPath: directory).appendingPathComponent(name).path
                let canonical = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
                if FileManager.default.isExecutableFile(atPath: path), seen.insert(canonical).inserted { paths.append((name, path)) }
            }
        }
        return await withTaskGroup(of: DetectedAgent?.self) { group in
            for (name, path) in paths {
                group.addTask {
                    do {
                        let version = try await inspect(path: path, arguments: ["--version"]).trimmingCharacters(in: .whitespacesAndNewlines)
                        let help = try await inspect(path: path, arguments: name == "codex" ? ["exec", "--help"] : ["--help"])
                        let args: [String]
                        switch name {
                        case "codex":
                            guard help.contains("--output-last-message"), help.contains("--sandbox"), help.contains("--skip-git-repo-check") else { return nil }
                            args = ["exec", "--skip-git-repo-check", "--sandbox", "read-only", "--color", "never", "--output-last-message", "{output}", "-"]
                        case "claude":
                            guard help.contains("--print"), help.contains("--output-format"), help.contains("--tools") else { return nil }
                            args = ["--print", "--output-format", "text", "--tools", ""]
                        default:
                            guard help.contains("--prompt"), help.contains("--output-format") else { return nil }
                            args = ["--prompt", "Complete only the request on standard input. Return the requested text without using tools.", "--output-format", "text"]
                        }
                        return DetectedAgent(name: name == "codex" ? "Codex CLI" : (name == "claude" ? "Claude Code" : "Gemini CLI"), path: path, version: String(version.prefix(180)), arguments: args, usesOutputFile: name == "codex")
                    } catch { return nil }
                }
            }
            var result: [DetectedAgent] = []
            for await item in group { if let item { result.append(item) } }
            return result.sorted {
                let firstBundled = $0.path.contains(".app/") || $0.version.contains("alpha")
                let secondBundled = $1.path.contains(".app/") || $1.version.contains("alpha")
                if firstBundled != secondBundled { return !firstBundled }
                return $0.name == $1.name ? $0.path < $1.path : $0.name < $1.name
            }
        }
    }
}
