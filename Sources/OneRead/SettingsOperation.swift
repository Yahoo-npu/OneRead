import Foundation
import Combine

@MainActor final class SettingsOperation: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var label = ""
    @Published private(set) var startedAt = Date()
    @Published private(set) var timeout: TimeInterval = 0
    private var currentID: UUID?
    private var task: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?

    func cancel() {
        currentID = nil; isRunning = false
        task?.cancel(); watchdog?.cancel(); task = nil; watchdog = nil
    }
    func run<Value>(label: String, timeout: TimeInterval, operation: @escaping () async throws -> Value,
                    success: @escaping (Value) -> Void, failure: @escaping (Error) -> Void) {
        cancel()
        let id = UUID(); currentID = id; self.label = label; self.timeout = timeout; startedAt = Date(); isRunning = true
        task = Task {
            do {
                let value = try await operation()
                guard currentID == id else { return }
                finish(); success(value)
            } catch {
                guard currentID == id else { return }
                finish(); failure(error)
            }
        }
        watchdog = Task {
            do { try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000)) } catch { return }
            guard currentID == id else { return }
            task?.cancel(); finish()
            failure(ReadError.message("\(label)超时（\(Int(timeout)) 秒），已停止等待。请检查网络或代理是否能访问当前服务，或切换其他可用模型 / 服务商后重试。"))
        }
    }
    private func finish() {
        currentID = nil; isRunning = false; watchdog?.cancel(); watchdog = nil; task = nil
    }
}
