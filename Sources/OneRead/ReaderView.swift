import SwiftUI
import WebKit

extension Notification.Name { static let analyzeHoveredSentence = Notification.Name("OneRead.analyzeHoveredSentence") }

final class ReaderAssets: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url, let assetID = url.host,
              let file = AssetStore.resource(String(url.path.dropFirst()), assetID: assetID),
              ["png", "jpg", "jpeg", "gif", "webp", "svg"].contains(file.pathExtension.lowercased()) else {
            task.didFailWithError(URLError(.fileDoesNotExist)); return
        }
        do {
            let data = try Data(contentsOf: file, options: .mappedIfSafe)
            let types = ["png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "gif": "image/gif", "webp": "image/webp", "svg": "image/svg+xml"]
            task.didReceive(URLResponse(url: url, mimeType: types[file.pathExtension.lowercased()], expectedContentLength: data.count, textEncodingName: nil))
            task.didReceive(data); task.didFinish()
        } catch { task.didFailWithError(error) }
    }
    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

struct ReaderView: NSViewRepresentable {
    var book: Book
    var chapter: Chapter
    var preferences: Preferences
    var focusSentenceID: String?
    var translating: Bool
    var selection: SelectionPopoverState
    var onAction: (ReaderAction) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onAction: onAction) }
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "reader")
        config.setURLSchemeHandler(ReaderAssets(), forURLScheme: "oneread-asset")
        let web = WKWebView(frame: .zero, configuration: config); web.navigationDelegate = context.coordinator
        context.coordinator.installShortcut(on: web)
        web.setValue(false, forKey: "drawsBackground")
        #if SWIFT_PACKAGE
        let resources = Bundle.module
        #else
        let resources = Bundle.main
        #endif
        if let url = resources.url(forResource: "Reader", withExtension: "html") { web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent()) }
        return web
    }
    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.onAction = onAction
        var blocks: [[String: Any]] = []
        if let data = try? JSONEncoder().encode(chapter.blocks ?? []), let objects = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] { blocks = objects }
        if blocks.isEmpty {
            blocks = [["id": "title", "kind": "heading", "text": chapter.title, "level": 1, "sentenceIDs": []], ["id": "legacy", "kind": "paragraph", "sentenceIDs": chapter.sentences.map(\.id)]]
        }
        for index in blocks.indices {
            if let resource = blocks[index]["imageResource"] as? String, let assetID = book.assetID {
                blocks[index]["imageURL"] = "oneread-asset://\(assetID)/\(resource)"
            }
        }
        var selectionObject: [String: Any] = ["id": selection.id ?? "", "text": selection.text, "translation": selection.translation, "error": selection.error ?? "", "notice": selection.notice, "loading": selection.loading, "analysisRequested": selection.analysisRequested]
        if let entry = selection.dictionary, let data = try? JSONEncoder().encode(entry), let value = try? JSONSerialization.jsonObject(with: data) { selectionObject["dictionary"] = value }
        if let analysis = selection.analysis, let data = try? JSONEncoder().encode(analysis), let value = try? JSONSerialization.jsonObject(with: data) { selectionObject["analysis"] = value }
        let object: [String: Any] = ["id": chapter.id, "theme": preferences.theme, "fontSize": preferences.fontSize,
                                    "mode": preferences.readingMode ?? "bilingual", "title": chapter.title,
                                    "focusSentenceID": focusSentenceID ?? "", "translating": translating, "blocks": blocks,
                                    "selection": selectionObject,
                                    "sentences": chapter.sentences.map { ["id": $0.id, "original": $0.original, "translation": $0.translation] }]
        if let data = try? JSONSerialization.data(withJSONObject: object, options: .sortedKeys), let json = String(data: data, encoding: .utf8) {
            let script = "window.render(\(json))"
            if context.coordinator.script != script { context.coordinator.script = script; if context.coordinator.loaded { view.evaluateJavaScript(script) } }
        }
    }
    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) { coordinator.removeShortcut(); view.configuration.userContentController.removeScriptMessageHandler(forName: "reader") }
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        private var shortcutObserver: NSObjectProtocol?
        func installShortcut(on web: WKWebView) {
            shortcutObserver = NotificationCenter.default.addObserver(forName: .analyzeHoveredSentence, object: nil, queue: .main) { [weak web] _ in
                guard let web, let window = web.window, (window.isKeyWindow || window.isMainWindow), window.attachedSheet == nil,
                      !web.isHiddenOrHasHiddenAncestor else { return }
                let point = web.convert(window.mouseLocationOutsideOfEventStream, from: nil)
                guard web.bounds.contains(point) else { return }
                let y = web.isFlipped ? point.y : web.bounds.height - point.y
                web.evaluateJavaScript("window.analyzeHoveredSentence && (window.analyzeHoveredSentence() || window.analyzeHoveredSentence(\(point.x), \(y)))")
            }
        }
        func removeShortcut() { if let shortcutObserver { NotificationCenter.default.removeObserver(shortcutObserver) }; shortcutObserver = nil }
        deinit { if let shortcutObserver { NotificationCenter.default.removeObserver(shortcutObserver) } }
        var onAction: (ReaderAction) -> Void; var script = ""; var loaded = false
        init(onAction: @escaping (ReaderAction) -> Void) { self.onAction = onAction }
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame, let object = message.body as? [String: Any], let kind = object["type"] as? String, let id = object["id"] as? String, !id.isEmpty, id.count <= 128 else { return }
            switch kind {
            case "selection": if let text = object["text"] as? String { onAction(.select(text: String(text.prefix(12000)), id: id, context: String((object["context"] as? String ?? "").prefix(2000)))) }
            case "analyze": if let sentenceID = object["sentenceID"] as? String, sentenceID.count <= 128 { onAction(.analyze(sentenceID: sentenceID, id: id)) }
            case "translate": onAction(.translate(id: id))
            case "collect": onAction(.collect(id: id))
            case "speak":
                if let accent = object["accent"] as? String, ["en-US", "en-GB"].contains(accent) { onAction(.speak(id: id, accent: accent, slow: object["slow"] as? Bool ?? false)) }
            case "stopSpeaking": onAction(.stopSpeaking(id: id))
            case "dismiss": onAction(.dismiss(id: id))
            default: break
            }
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loaded = true; webView.evaluateJavaScript(script) }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) { decisionHandler(action.request.url?.isFileURL == true ? .allow : .cancel) }
    }
}
