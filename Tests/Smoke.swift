import Foundation
import CryptoKit
import PDFKit
import AppKit
import CoreText
import ImageIO
import UniformTypeIdentifiers
import LocalAuthentication
import Security

final class StubURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw ReadError.message("Missing test handler") }
            let (status, data) = try handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

actor FailOnceTranslator {
    var count = 0
    func translate(_ text: String) throws -> String {
        count += 1
        if count == 2 { throw ReadError.message("Simulated interruption") }
        return "译：" + text
    }
}

actor SelectionGate {
    var pending: [String: CheckedContinuation<String, Never>] = [:]
    var waiters: [String: CheckedContinuation<Void, Never>] = [:]
    func translate(_ text: String) async -> String {
        await withCheckedContinuation { continuation in
            pending[text] = continuation
            waiters.removeValue(forKey: text)?.resume()
        }
    }
    func waitForStart(_ text: String) async {
        if pending[text] != nil { return }
        await withCheckedContinuation { waiters[text] = $0 }
    }
    func finish(_ text: String, _ result: String) { pending.removeValue(forKey: text)?.resume(returning: result) }
}

@main struct Smoke {
    static func main() async throws {
        if CommandLine.arguments.contains("--economist-live-download-check") {
            let catalog = try JSONDecoder().decode(EconomistCatalog.self, from: Data(contentsOf: URL(fileURLWithPath: "Sources/OneRead/EconomistCatalogSeed.json")))
            let latest = catalog.issues[0]
            let data = try await EconomistRepository().download(latest)
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("OneRead-EconomistLive-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let file = directory.appendingPathComponent(latest.filename); try data.write(to: file)
            let book = try Importer.load(file, assetsRoot: directory.appendingPathComponent("Assets"))
            print("LIVE EPUB \(latest.displayDate) verified: \(data.count) bytes; \(book.chapters.count) chapters; \(book.chapters.flatMap { $0.blocks ?? [] }.filter { $0.kind == "image" }.count) image blocks; cover \(book.effectiveCoverResource != nil)")
            return
        }
        if CommandLine.arguments.contains("--economist-live-check") {
            let repository = EconomistRepository()
            let catalog = try await repository.refresh(previous: nil)
            guard let latest = catalog.issues.first else { fatalError("No issues") }
            print("LIVE catalog: \(catalog.issues.count) issues; latest \(latest.displayDate)")
            let data = try await repository.download(latest)
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("OneRead-EconomistLive-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let file = directory.appendingPathComponent(latest.filename)
            try data.write(to: file)
            let book = try Importer.load(file, assetsRoot: directory.appendingPathComponent("Assets"))
            print("LIVE EPUB verified: \(data.count) bytes; \(book.chapters.count) chapters; \(book.chapters.flatMap { $0.blocks ?? [] }.filter { $0.kind == "image" }.count) image blocks; cover \(book.effectiveCoverResource != nil)")
            return
        }
        if CommandLine.arguments.contains("--detect-agents") {
            let agents = await AgentDetection.detect()
            for agent in agents { print("DETECTED: \(agent.name) | \(agent.path) | \(agent.version)") }
            return
        }
        func check(_ value: Bool, _ message: String) { if !value { fatalError(message) }; print("PASS: \(message)") }
        let ss = Importer.sentences("Hello world. Reading makes life richer!")
        check(ss.count == 2, "sentence segmentation")
        check(Importer.sentences(" \n ").isEmpty, "empty text")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let package = dir.appendingPathComponent("epub")
        try FileManager.default.createDirectory(at: package.appendingPathComponent("META-INF"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: package.appendingPathComponent("OPS"), withIntermediateDirectories: true)
        try "<container><rootfiles><rootfile full-path='OPS/book.opf'/></rootfiles></container>".write(to: package.appendingPathComponent("META-INF/container.xml"), atomically: true, encoding: .utf8)
        try "<package><manifest><item id='b' href='b.xhtml'/><item id='a' href='a.xhtml'/></manifest><spine><itemref idref='a'/><itemref idref='b'/></spine></package>".write(to: package.appendingPathComponent("OPS/book.opf"), atomically: true, encoding: .utf8)
        for letter in ["a", "b"] { try "<html><head><title>Hidden title</title></head><body><h1>Chapter \(letter)</h1><p>Hello reader. Another sentence!</p><script>Bad content</script></body></html>".write(to: package.appendingPathComponent("OPS/\(letter).xhtml"), atomically: true, encoding: .utf8) }
        let archive = dir.appendingPathComponent("test.epub")
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/zip"); p.arguments = ["-qr", archive.path, "."]; p.currentDirectoryURL = package; try p.run(); p.waitUntilExit()
        let assets = dir.appendingPathComponent("assets")
        let book = try Importer.load(archive, assetsRoot: assets)
        check(book.chapters.count == 2 && book.chapters[0].title == "Chapter a", "EPUB spine reading order")
        check(!book.chapters.flatMap(\.sentences).contains { $0.original.contains("Hidden") || $0.original.contains("Bad content") }, "EPUB excludes scripts and metadata")
        var library = Library(); library.books = [book]; library.words = [Word(spelling: "reader", meaning: "读者", context: "test")]
        let decoded = try JSONDecoder().decode(Library.self, from: JSONEncoder().encode(library))
        check(decoded.books[0].chapters[0].sentences[0].id == book.chapters[0].sentences[0].id && decoded.words.count == 1, "persistence preserves sentence identity and vocabulary")
        let pdf = dir.appendingPathComponent("test.pdf")
        var rect = CGRect(x: 0, y: 0, width: 500, height: 700)
        let context = CGContext(pdf as CFURL, mediaBox: &rect, nil)!
        context.beginPDFPage(nil)
        let text = NSAttributedString(string: "Reading opens doors. Hello world!", attributes: [.font: NSFont.systemFont(ofSize: 18)])
        let line = CTLineCreateWithAttributedString(text); context.textPosition = CGPoint(x: 30, y: 650); CTLineDraw(line, context)
        let embeddedImage = CGContext(data: nil, width: 200, height: 100, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        embeddedImage.setFillColor(CGColor(red: 0.1, green: 0.55, blue: 0.3, alpha: 1)); embeddedImage.fill(CGRect(x: 0, y: 0, width: 200, height: 100))
        context.draw(embeddedImage.makeImage()!, in: CGRect(x: 30, y: 400, width: 400, height: 200))
        context.endPDFPage(); context.closePDF()
        let pdfBook = try Importer.load(pdf, assetsRoot: assets)
        check(pdfBook.chapters.count == 1 && pdfBook.chapters[0].sentences.count == 2, "PDF text extraction")
        let agent = dir.appendingPathComponent("agent.sh")
        try "#!/bin/sh\ncat >/dev/null\nprintf '你好，读者。'\n".write(to: agent, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: agent.path)
        var prefs = Preferences(); prefs.provider = "Agent"; prefs.agentPath = agent.path
        let translated = try await Translator.translate("Hello reader.", preferences: prefs)
        check(translated == "你好，读者。", "local agent stdin/stdout translation")
        try "#!/bin/sh\nexit 1\n".write(to: agent, atomically: true, encoding: .utf8)
        do { _ = try await Translator.translate("Hello", preferences: prefs); fatalError("Agent errors must propagate") } catch { print("PASS: local agent failure surfaces") }
        let configurationCases = [
            (" https://api.deepseek.com/ ", "https://api.deepseek.com/chat/completions"),
            ("https://api.deepseek.com/v1", "https://api.deepseek.com/v1/chat/completions"),
            ("https://api.deepseek.com/v1/", "https://api.deepseek.com/v1/chat/completions"),
            ("https://api.deepseek.com/chat/completions/", "https://api.deepseek.com/chat/completions"),
            ("https://example.org/proxy/v1/chat/completions", "https://example.org/proxy/v1/chat/completions"),
            ("http://localhost:1234/v1", "http://localhost:1234/v1/chat/completions")
        ]
        for (input, expected) in configurationCases {
            let config = try APIConfiguration(endpoint: input, model: "DeepSeek-V4.1-Flash")
            check(config.url.absoluteString == expected, "base URL normalization: \(input)")
        }
        let flash = try APIConfiguration(endpoint: "https://api.deepseek.com", model: " DeepSeek-V4.1-Flash ")
        check(flash.model == "deepseek-flash", "DeepSeek display name uses documented API ID")
        let custom = try APIConfiguration(endpoint: "https://example.org/v1", model: "DeepSeek-V4.1-Flash")
        check(custom.model == "DeepSeek-V4.1-Flash", "custom provider model IDs preserved")
        for invalid in ["http://remote.example/v1", "https://user:password@example.org", "https://example.org?key=secret", "not a URL"] {
            do { _ = try APIConfiguration(endpoint: invalid, model: "model"); fatalError("Invalid endpoint accepted") } catch { print("PASS: invalid endpoint rejected") }
        }
        let normalizedKey = try APIConfiguration.token(" \nBearer test-key\n ")
        check(normalizedKey == "test-key", "pasted credential whitespace and Bearer prefix normalized")
        do { _ = try APIConfiguration.token("test key"); fatalError("Whitespace inside API key accepted") } catch { print("PASS: malformed key rejected") }

        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: sessionConfig)
        defer { session.invalidateAndCancel() }
        var apiPreferences = Preferences(); apiPreferences.endpoint = "https://api.deepseek.com"; apiPreferences.model = "DeepSeek-V4.1-Flash"
        StubURLProtocol.handler = { request in
            guard request.url?.absoluteString == "https://api.deepseek.com/chat/completions",
                  request.httpMethod == "POST",
                  request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key" else { throw ReadError.message("Incorrect request endpoint or authorization") }
            var body = request.httpBody ?? Data()
            if body.isEmpty, let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; body.append(contentsOf: buffer.prefix(count)) }
            }
            guard let object = try JSONSerialization.jsonObject(with: body) as? [String: Any], object["model"] as? String == "deepseek-flash", object["stream"] as? Bool == false else { throw ReadError.message("Incorrect request model or format") }
            return (200, Data(#"{"choices":[{"message":{"content":"你好，读者。"}}]}"#.utf8))
        }
        let apiResult = try await Translator.translate("Hello reader.", preferences: apiPreferences, apiKey: " \nBearer test-key\n", session: session)
        check(apiResult == "你好，读者。", "translation request sends normalized endpoint, model and credential")
        for (status, expected) in [(401, "鉴权失败"), (402, "余额不足"), (404, "接口或模型不存在"), (429, "限额")] {
            StubURLProtocol.handler = { _ in (status, Data(#"{"error":{"message":"Rejected test-key sk-example-sensitive"}}"#.utf8)) }
            do { _ = try await Translator.translate("Hello", preferences: apiPreferences, apiKey: "test-key", session: session); fatalError("HTTP error was ignored") }
            catch {
                let message = error.localizedDescription
                check(message.contains(expected) && message.contains("HTTP \(status)") && !message.contains("test-key") && !message.contains("sk-example-sensitive"), "HTTP \(status) is actionable and redacts secrets")
            }
        }
        var requests = 0
        StubURLProtocol.handler = { _ in requests += 1; return (200, Data()) }
        do { _ = try await Translator.translate("Hello", preferences: apiPreferences, apiKey: " ", session: session); fatalError("Missing key was accepted") }
        catch { check(requests == 0 && error.localizedDescription.contains("尚未配置"), "missing remote key fails before any network request") }
        // Image-rich EPUB: paragraph boundaries, local paths, embedded resources and TOC.
        let imagesDirectory = package.appendingPathComponent("Images")
        try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        let imageContext = CGContext(data: nil, width: 80, height: 40, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        imageContext.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.3, alpha: 1)); imageContext.fill(CGRect(x: 0, y: 0, width: 80, height: 40))
        let sampleImage = imageContext.makeImage()!
        let imageFile = imagesDirectory.appendingPathComponent("reader art.png")
        let png = CGImageDestinationCreateWithURL(imageFile as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(png, sampleImage, nil); check(CGImageDestinationFinalize(png), "image fixture created")
        try "<package><manifest><item id='a' href='a.xhtml'/><item id='b' href='b.xhtml'/><item id='nav' href='nav.xhtml' properties='nav'/></manifest><spine><itemref idref='a'/><itemref idref='b'/></spine></package>".write(to: package.appendingPathComponent("OPS/book.opf"), atomically: true, encoding: .utf8)
        try "<html xmlns:epub='http://www.idpf.org/2007/ops'><body><nav epub:type='toc'><ol><li><a href='a.xhtml'>Part One</a><ol><li><a href='b.xhtml'>Part Two</a></li></ol></li></ol></nav></body></html>".write(to: package.appendingPathComponent("OPS/nav.xhtml"), atomically: true, encoding: .utf8)
        try "<html><body><h1>Illustrated reading</h1><p>Hello reader. Another sentence!</p><img src='../Images/reader%20art.png' alt='Green illustration'/><p>After the image.</p><script>Not visible</script><img src='../../../outside.png' alt='Blocked path'/></body></html>".write(to: package.appendingPathComponent("OPS/a.xhtml"), atomically: true, encoding: .utf8)
        let richArchive = dir.appendingPathComponent("illustrated.epub")
        let zip = Process(); zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip"); zip.arguments = ["-qr", richArchive.path, "."]; zip.currentDirectoryURL = package; try zip.run(); zip.waitUntilExit()
        let illustrated = try Importer.load(richArchive, assetsRoot: assets)
        let richBlocks = illustrated.chapters[0].blocks!
        check(richBlocks.map(\.kind).prefix(4).elementsEqual(["heading", "paragraph", "image", "paragraph"]), "EPUB retains heading, paragraphs and image order")
        check(richBlocks[1].sentenceIDs.count == 2, "sentences stay inside their original paragraph")
        let resource = richBlocks[2].imageResource!
        let localImage = AssetStore.resource(resource, assetID: illustrated.assetID!, root: assets)!
        check(FileManager.default.fileExists(atPath: localImage.path) && CGImageSourceCreateWithURL(localImage as CFURL, nil) != nil, "EPUB images persist as decodable local resources")
        check(richBlocks.last?.imageResource == nil, "image references cannot escape the EPUB package")
        check(illustrated.tableOfContents?.map(\.title) == ["Part One", "Part Two"] && illustrated.tableOfContents?[1].depth == 1, "EPUB hierarchical TOC labels map to spine chapters")
        check(AssetStore.resource("../library.json", assetID: illustrated.assetID!, root: assets) == nil, "asset handler rejects traversal")
        let svg = Data("<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 20 20' onload='bad()'><script>bad()</script><rect width='20' height='20' fill='green'/><use href='https://example.org/tracker.svg#x'/></svg>".utf8)
        let cleanedSVG = String(data: SVGCleaner.clean(svg)!, encoding: .utf8)!
        check(cleanedSVG.contains("<rect") && !cleanedSVG.contains("script") && !cleanedSVG.contains("onload") && !cleanedSVG.contains("https:"), "SVG illustration keeps static shapes and removes active external content")
        let pdfResource = pdfBook.chapters[0].blocks!.first!.imageResource!
        check(FileManager.default.fileExists(atPath: AssetStore.resource(pdfResource, assetID: pdfBook.assetID!, root: assets)!.path), "PDF original page rendered with images and layout")
        check(!(pdfBook.chapters[0].blocks!.first!.regions ?? []).isEmpty, "PDF retains selectable sentence regions over original page")

        let outlinedPDF = dir.appendingPathComponent("outlined.pdf")
        let outlined = PDFDocument()
        for _ in 0..<3 { outlined.insert(PDFDocument(url: pdf)!.page(at: 0)!, at: outlined.pageCount) }
        let outlineRoot = PDFOutline()
        for (index, label) in [(0, "First chapter"), (2, "Second chapter")] {
            let node = PDFOutline(); node.label = label; node.destination = PDFDestination(page: outlined.page(at: index)!, at: CGPoint(x: 0, y: 700)); outlineRoot.insertChild(node, at: outlineRoot.numberOfChildren)
        }
        outlined.outlineRoot = outlineRoot
        check(outlined.write(to: outlinedPDF), "PDF outline fixture created")
        let chapterPDF = try Importer.load(outlinedPDF, assetsRoot: assets)
        check(chapterPDF.chapters.count == 2 && chapterPDF.chapters[0].blocks?.count == 2 && chapterPDF.chapters[1].blocks?.count == 1, "PDF bookmark chapters retain their complete page ranges")

        var oldBook = book
        oldBook.chapters[0].sentences[0].translation = "已保存的译文"
        let restored = illustrated.restoringReadingState(from: oldBook)
        check(restored.id == oldBook.id && restored.assetID == illustrated.assetID, "reimport keeps book identity and attaches new resources")
        var existing = illustrated
        existing.chapters[0].sentences[1].translation = "你好，读者。"
        let migrated = illustrated.restoringReadingState(from: existing)
        check(migrated.chapters[0].sentences[1].translation == "你好，读者。", "reimport preserves translations of matching sentences")
        var legacyObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Library(books: [book]))) as! [String: Any]
        var legacyBooks = legacyObject["books"] as! [[String: Any]]
        for key in ["format", "assetID", "sourceName", "tableOfContents"] { legacyBooks[0].removeValue(forKey: key) }
        var legacyChapters = legacyBooks[0]["chapters"] as! [[String: Any]]
        for i in legacyChapters.indices { legacyChapters[i].removeValue(forKey: "blocks") }
        legacyBooks[0]["chapters"] = legacyChapters; legacyObject["books"] = legacyBooks
        let legacyLibrary = try JSONDecoder().decode(Library.self, from: JSONSerialization.data(withJSONObject: legacyObject))
        check(legacyLibrary.books[0].assetID == nil && legacyLibrary.books[0].chapters[0].blocks == nil, "old text-only libraries decode without data loss")

        var chapterBook = illustrated
        chapterBook.chapterIndex = 1
        let chapterStore = Store(dataDirectory: dir.appendingPathComponent("chapter-library"), translator: { text, _ in "译：" + text })
        await MainActor.run { chapterStore.library.books = [chapterBook]; chapterStore.selected = chapterBook.id; chapterStore.translateChapter() }
        await chapterStore.translationTask?.value
        let translatedBook = chapterStore.book!
        check(translatedBook.chapters[0].sentences.allSatisfy { $0.translation.isEmpty } && translatedBook.chapters[1].sentences.allSatisfy { !$0.translation.isEmpty }, "translate chapter touches only the selected chapter")
        let pendingChapter = TranslationPlan(book: translatedBook, chapterID: translatedBook.chapters[1].id)
        check(pendingChapter.pending.isEmpty, "completed chapter translation is not requested twice")
        await MainActor.run { chapterStore.translateAll() }
        await chapterStore.translationTask?.value
        let completeBook = chapterStore.book!
        check(completeBook.chapters.flatMap(\.sentences).allSatisfy { !$0.translation.isEmpty }, "full translation resumes the remaining chapters")
        let savedLibrary = try JSONDecoder().decode(Library.self, from: Data(contentsOf: dir.appendingPathComponent("chapter-library/library.json")))
        check(savedLibrary.books[0].chapters[1].sentences.allSatisfy { !$0.translation.isEmpty }, "chapter translations survive reloading local storage")
        let interruption = FailOnceTranslator()
        let resumeStore = Store(dataDirectory: dir.appendingPathComponent("resume-library"), translator: { text, _ in try await interruption.translate(text) })
        resumeStore.library.books = [illustrated]; resumeStore.selected = illustrated.id
        resumeStore.translateChapter(); await resumeStore.translationTask?.value
        let partial = resumeStore.book!
        check(partial.chapters[0].sentences.filter { !$0.translation.isEmpty }.count == 1 && resumeStore.error != nil, "interrupted chapter keeps completed sentences")
        resumeStore.error = nil; resumeStore.translateChapter(); await resumeStore.translationTask?.value
        check(resumeStore.book!.chapters[0].sentences.allSatisfy { !$0.translation.isEmpty } && resumeStore.book!.chapters[1].sentences.allSatisfy { $0.translation.isEmpty }, "resume retries only unfinished sentences in that chapter")
        let switchStore = Store(dataDirectory: dir.appendingPathComponent("switch-library"), translator: { text, _ in "译：" + text })
        switchStore.library.books = [illustrated]; switchStore.selected = illustrated.id
        switchStore.translateChapter(); switchStore.chapter(1); await switchStore.translationTask?.value
        check(switchStore.book!.chapters[0].sentences.allSatisfy { !$0.translation.isEmpty } && switchStore.book!.chapters[1].sentences.allSatisfy { $0.translation.isEmpty }, "changing chapters during a job does not change the translation scope")
        check(illustrated.effectiveCoverResource == richBlocks[2].imageResource, "existing illustrated books automatically use their first source image as cover")
        check(pdfBook.coverResource == pdfResource, "PDF cover uses the original first-page preview")
        check(abs((richBlocks[2].aspectRatio ?? 0) - 2) < 0.001, "image aspect ratio is reserved before loading to avoid layout jumps")
        let declaredCover = imagesDirectory.appendingPathComponent("declared-cover.png")
        let coverBitmap = CGContext(data: nil, width: 40, height: 70, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        coverBitmap.setFillColor(CGColor(red: 0.6, green: 0.2, blue: 0.2, alpha: 1)); coverBitmap.fill(CGRect(x: 0, y: 0, width: 40, height: 70))
        let coverOutput = CGImageDestinationCreateWithURL(declaredCover as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(coverOutput, coverBitmap.makeImage()!, nil); check(CGImageDestinationFinalize(coverOutput), "declared cover fixture created")
        for version in [2, 3] {
            let metadata = version == 2 ? "<metadata><meta name='cover' content='official-cover'/></metadata>" : ""
            let properties = version == 3 ? " properties='cover-image'" : ""
            try "<package>\(metadata)<manifest><item id='a' href='a.xhtml'/><item id='b' href='b.xhtml'/><item id='official-cover' href='../Images/declared-cover.png' media-type='image/png'\(properties)/></manifest><spine><itemref idref='a'/><itemref idref='b'/></spine></package>".write(to: package.appendingPathComponent("OPS/book.opf"), atomically: true, encoding: .utf8)
            let archive = dir.appendingPathComponent("cover-v\(version).epub")
            let zip = Process(); zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip"); zip.arguments = ["-qr", archive.path, "."]; zip.currentDirectoryURL = package; try zip.run(); zip.waitUntilExit()
            let imported = try Importer.load(archive, assetsRoot: assets)
            let coverURL = AssetStore.resource(imported.coverResource!, assetID: imported.assetID!, root: assets)!
            let ratio = AssetStore.imageAspectRatio(at: coverURL)!
            check(abs(ratio - 40.0/70.0) < 0.001 && imported.coverResource != imported.chapters[0].blocks?[2].imageResource, "EPUB \(version) declared cover wins even when absent from the spine")
        }

        let trashDirectory = dir.appendingPathComponent("trash-library")
        let trashStore = Store(dataDirectory: trashDirectory)
        var preserved = illustrated; preserved.chapters[0].sentences[0].translation = "保留的译文"
        let vocabulary = Word(spelling: "reader", meaning: "读者", context: "independent vocabulary")
        trashStore.library.books = [preserved, pdfBook]; trashStore.library.words = [vocabulary]; trashStore.selected = preserved.id
        trashStore.deleteBook(preserved.id)
        check(trashStore.library.books.map(\.id) == [pdfBook.id] && trashStore.selected == nil, "deleting a book removes its shelf card and clears its active reader")
        check(trashStore.library.trash?.first?.book.chapters[0].sentences[0].translation == "保留的译文" && trashStore.library.words.count == 1, "recoverable deletion preserves translations and vocabulary")
        check(FileManager.default.fileExists(atPath: localImage.path), "deletion does not remove original images or source files")
        let reopenedTrash = Store(dataDirectory: trashDirectory)
        check(reopenedTrash.library.trash?.count == 1 && reopenedTrash.library.books.count == 1, "recently deleted books survive app relaunch")
        reopenedTrash.restoreBook(reopenedTrash.library.trash!.first!.id)
        check(reopenedTrash.library.books.map(\.id) == [preserved.id, pdfBook.id] && reopenedTrash.library.trash!.isEmpty, "restoring returns the book to its shelf position")
        reopenedTrash.deleteBook(preserved.id); reopenedTrash.undoDelete()
        check(reopenedTrash.library.books.count == 2 && reopenedTrash.library.trash!.isEmpty, "undo restores the most recently deleted book")
        reopenedTrash.loadFailed = true; reopenedTrash.deleteBook(preserved.id)
        check(reopenedTrash.library.books.count == 2 && reopenedTrash.library.trash!.isEmpty, "failed persistence rolls deletion back")

        let gate = SelectionGate()
        let popupStore = Store(dataDirectory: dir.appendingPathComponent("popup-library"), translator: { text, _ in await gate.translate(text) })
        popupStore.library.books = [illustrated]; popupStore.selected = illustrated.id
        popupStore.selectText("slow", id: "request-one", context: "first selection")
        await gate.waitForStart("slow")
        popupStore.selectText("reader", id: "request-two", context: "Reading context")
        await gate.waitForStart("reader"); await gate.finish("reader", "读者")
        for _ in 0..<100 { if !popupStore.selectionTranslating { break }; try await Task.sleep(nanoseconds: 1_000_000) }
        check(popupStore.selectionTranslation == "读者" && popupStore.selectionID == "request-two", "floating selection translates the current request")
        await gate.finish("slow", "过期结果")
        try await Task.sleep(nanoseconds: 5_000_000)
        check(popupStore.selectionTranslation == "读者" && !popupStore.selectionTranslating, "late responses cannot replace a newer floating translation")
        popupStore.handleReaderAction(.collect(id: "request-one"))
        check(popupStore.library.words.isEmpty, "stale floating actions cannot collect a different selection")
        popupStore.handleReaderAction(.collect(id: "request-two"))
        check(popupStore.library.words.first?.spelling == "reader" && popupStore.library.words.first?.meaning == "读者", "floating action saves the selected word and its translation")
        popupStore.clearSelection(requestID: "request-one")
        check(popupStore.selectionID == "request-two", "an old dismissal cannot close the current popup")
        popupStore.clearSelection()
        check(popupStore.selectionID == nil && popupStore.selectionTranslation.isEmpty, "closing a floating popup clears its state")
        popupStore.selectText("closing", id: "request-three")
        await gate.waitForStart("closing"); popupStore.chapter(1); await gate.finish("closing", "不应再显示")
        try await Task.sleep(nanoseconds: 5_000_000)
        check(popupStore.selectionID == nil && popupStore.selectionTranslation.isEmpty, "changing chapters discards in-flight selection translations")
        check(DictionaryLookup.isWord("reader") && DictionaryLookup.isWord("well-known") && !DictionaryLookup.isWord("read this sentence") && !DictionaryLookup.isWord("<script>"), "dictionary and speech accept only a single English word")
        let dictionaryJSON = #"{"ipaUK":"/ˈriːdə/","ipaUS":"/ˈriːdər/","contextMeaning":"读者","meanings":[{"partOfSpeech":"n.","definitions":["读者","读本"]}],"exampleEnglish":"She is a keen reader.","exampleChinese":"她热爱阅读。"}"#
        let dictionary = try DictionaryLookup.parse("```json\n" + dictionaryJSON + "\n```")
        check(dictionary.meanings.first?.definitions.count == 2 && dictionary.ipaUS == "/ˈriːdər/", "dictionary parses phonetics, parts of speech and alternate senses")
        let inflected = try DictionaryLookup.parse(#"{"ipaUS":"/ræn/","lemma":"run","contextMeaning":"跑过","contextExplanation":"这里是 run 的过去式，描述已经发生的跑步动作。","meanings":[{"partOfSpeech":"v.","definitions":["跑","运转","经营","流淌"]}]}"#)
        check(inflected.lemma == "run" && inflected.contextExplanation?.contains("过去式") == true && inflected.meanings.first?.definitions == ["跑", "运转"], "compact dictionary preserves lemma and context explanation while limiting senses to two")
        let oldDictionary = try JSONDecoder().decode(DictionaryEntry.self, from: Data(dictionaryJSON.utf8))
        check(oldDictionary.lemma == nil && oldDictionary.contextExplanation == nil, "saved dictionaries from earlier versions remain readable")
        let partialDictionary = try DictionaryLookup.parse(#"{"contextMeaning":"读者"}"#)
        check(partialDictionary.ipaUK.isEmpty && partialDictionary.meanings.isEmpty, "missing dictionary fields degrade gracefully")
        do { _ = try DictionaryLookup.parse("{}"); check(false, "empty dictionary rejected") } catch { check(true, "empty dictionary rejected") }
        let detailedStore = Store(dataDirectory: dir.appendingPathComponent("dictionary-store"), selectionLookup: { _, _, _ in SelectionLookupResult(translation: dictionary.summary, dictionary: dictionary) })
        detailedStore.library.books = popupStore.library.books; detailedStore.selected = detailedStore.library.books.first?.id
        detailedStore.selectText("reader", id: "dictionary-request")
        for _ in 0..<100 { if !detailedStore.selectionTranslating { break }; try await Task.sleep(nanoseconds: 1_000_000) }
        detailedStore.addSelectedWord()
        let reloadedDictionaryStore = Store(dataDirectory: dir.appendingPathComponent("dictionary-store"))
        check(reloadedDictionaryStore.library.words.first?.dictionary?.ipaUS == dictionary.ipaUS && reloadedDictionaryStore.library.words.first?.meaning.contains("读本") == true, "wordbook persists dictionary details with alternate senses")
        detailedStore.addWord("reader", meaning: "更新释义", context: "", dictionary: dictionary)
        check(detailedStore.library.words.count == 1 && detailedStore.library.words.first?.meaning == "更新释义", "recollecting an existing word updates dictionary details without duplicates")
        let dictionaryAgent = dir.appendingPathComponent("dictionary-agent.sh")
        try ("#!/bin/sh\ncat >/dev/null\ncat <<'DICT'\n" + dictionaryJSON + "\nDICT\n").write(to: dictionaryAgent, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dictionaryAgent.path)
        var dictionaryPreferences = Preferences(); dictionaryPreferences.provider = "Agent"; dictionaryPreferences.agentPath = dictionaryAgent.path
        let agentLookup = try await DictionaryLookup.lookup("reader", context: "a keen reader", preferences: dictionaryPreferences)
        check(agentLookup.dictionary?.ipaUS == dictionary.ipaUS && agentLookup.translation.contains("读本"), "dictionary lookup runs through the configured local agent transport")
        detailedStore.clearSelection()
        check(detailedStore.selectionDictionary == nil, "closing popup removes previous dictionary details")
        check(SentenceAnalyzer.shouldAnalyze("The book that you gave me is fascinating.") && SentenceAnalyzer.shouldAnalyze("Birds can fly.") && !SentenceAnalyzer.shouldAnalyze("in the morning") && !SentenceAnalyzer.shouldAnalyze("reader"), "sentence routing distinguishes complete sentences from words and short phrases")
        let analysisJSON = #"{"translation":"尽管很累，他还是读完了你推荐的书。","backbone":"he finished the book — 主语 + 谓语 + 宾语","components":[{"label":"主语","text":"he","explanation":"主句动作的执行者。"},{"label":"谓语","text":"finished","explanation":"一般过去时，表示已经完成。"},{"label":"宾语","text":"the book","explanation":"finished 的宾语，后接定语从句。"}],"clauses":[{"label":"让步状语从句","text":"Although he was tired","explanation":"Although 引导，修饰主句，表示让步。"},{"label":"定语从句","text":"that you recommended","explanation":"that 引导，修饰先行词 book，that 作 recommended 的宾语。"}],"grammar":[{"label":"让步状语从句","text":"Although he was tired","explanation":"although 表示尽管，主句不再使用 but。"}]}"#
        let analysis = try SentenceAnalyzer.parse("```json\n" + analysisJSON + "\n```")
        check(analysis.clauses.count == 2 && analysis.components.count == 3 && analysis.grammar.first?.label == "让步状语从句", "sentence analysis preserves components, clause attachments and grammar explanations")
        do { _ = try SentenceAnalyzer.parse(#"{"translation":"只有翻译"}"#); check(false, "incomplete sentence analysis rejected") } catch { check(true, "incomplete sentence analysis rejected") }
        try ("#!/bin/sh\ncat >/dev/null\ncat <<'ANALYSIS'\n" + analysisJSON + "\nANALYSIS\n").write(to: dictionaryAgent, atomically: true, encoding: .utf8)
        let sentenceLookup = try await SentenceAnalyzer.analyze("Although he was tired, he finished the book that you recommended.", context: "", preferences: dictionaryPreferences)
        check(sentenceLookup.analysis?.clauses.count == 2 && sentenceLookup.dictionary == nil && sentenceLookup.translation == analysis.translation, "sentence selections route through the configured agent for translation plus analysis")
        let analysisStore = Store(dataDirectory: dir.appendingPathComponent("analysis-store"), analysisLookup: { _, _, _ in SelectionLookupResult(translation: analysis.translation, analysis: analysis) })
        analysisStore.library.books = detailedStore.library.books; analysisStore.selected = analysisStore.library.books.first?.id
        let hoveredSentence = analysisStore.library.books[0].chapters[analysisStore.library.books[0].chapterIndex].sentences[0]
        analysisStore.handleReaderAction(.analyze(sentenceID: "invalid-sentence", id: "invalid-request"))
        check(analysisStore.selectionID == nil, "hover analysis ignores sentence IDs outside the active chapter")
        analysisStore.handleReaderAction(.analyze(sentenceID: hoveredSentence.id, id: "sentence-analysis"))
        check(analysisStore.selectionAnalysisRequested && analysisStore.selection == hoveredSentence.original, "hover analysis uses the current chapter's original sentence and explicit mode")
        for _ in 0..<100 { if !analysisStore.selectionTranslating { break }; try await Task.sleep(nanoseconds: 1_000_000) }
        check(analysisStore.selectionPopoverState.analysis?.backbone == analysis.backbone && analysisStore.selectionTranslation == analysis.translation, "floating popup state carries the sentence analysis and translation")
        analysisStore.clearSelection()
        check(analysisStore.selectionAnalysis == nil, "closing selection clears sentence analysis")
        var migratedAPI = Preferences(); migratedAPI.endpoint = "https://api.deepseek.com"; migratedAPI.model = "deepseek-flash"
        APIProfiles.prepare(&migratedAPI)
        check(migratedAPI.activeAPIProfileID == "deepseek" && migratedAPI.apiCredentialAccount == "api" && migratedAPI.apiProfiles?.count == APIPreset.all.count, "API profile migration preserves the old provider, model and legacy credential without reading it")
        let openAIProfile = migratedAPI.apiProfiles!.first { $0.id == "openai" }!
        APIProfiles.activate(openAIProfile, preferences: &migratedAPI)
        check(migratedAPI.apiCredentialAccount == "api.openai" && migratedAPI.endpoint == openAIProfile.endpoint, "switching providers selects separate credential accounts and official endpoints")
        let profileRoundTrip = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(migratedAPI))
        check(profileRoundTrip.activeAPIProfileID == "openai" && profileRoundTrip.apiProfiles?.first?.model == "deepseek-flash", "provider configurations and model choices survive serialization")
        for preset in APIPreset.all {
            let url = try APIProfiles.modelListURL(endpoint: preset.endpoint)
            check(url.path.hasSuffix("/models") && !url.path.contains("/chat/"), "model discovery endpoint is derived correctly: " + preset.id)
        }
        let textIDs = APIProfiles.textModelIDs([["id":"gpt-6-luna"],["id":"gpt-image-2"],["id":"whisper-1"],["id":"gemini-embedding-001"],["id":"gpt-6-luna"],["id":"gpt-audio"],["id":"gpt-6.1-sol"]], presetID: "openai")
        check(textIDs == ["gpt-6-luna", "gpt-6.1-sol"], "model discovery filters non-text models and removes duplicates")
        StubURLProtocol.handler = { request in
            guard request.url?.absoluteString == "https://api.openai.com/v1/models", request.httpMethod == "GET", request.value(forHTTPHeaderField: "Authorization") == "Bearer model-test-key" else { throw ReadError.message("Incorrect model list request") }
            return (200, Data(#"{"data":[{"id":"gpt-6-luna"},{"id":"gpt-image-2"}]}"#.utf8))
        }
        let fetchedModels = try await APIProfiles.fetchModels(profile: openAIProfile, key: "model-test-key", session: session)
        check(fetchedModels == ["gpt-6-luna"], "provider model refresh uses the selected provider's key and GET endpoint")
        let silentQuery = Vault.readQuery("test-only")
        let explicitQuery = Vault.readQuery("test-only", allowInteraction: true)
        check((silentQuery[kSecUseAuthenticationUI as String] as? String) == (kSecUseAuthenticationUIFail as String) && explicitQuery[kSecUseAuthenticationUI as String] == nil, "Keychain reads never request authentication UI unless explicitly authorized")
        var credentialDraft = CredentialDraft(); var reads = 0; var writes: [(String, String)] = []
        credentialDraft.load("locked", reader: { _, interaction in reads += 1; check(!interaction, "opening settings requests silent credential access"); throw ReadError.message("Locked") })
        credentialDraft.load("locked", reader: { _, _ in reads += 1; return "should-not-read" })
        try credentialDraft.save(writer: { writes.append(($0,$1)) })
        check(reads == 1 && writes.isEmpty && credentialDraft.failures["locked"] != nil, "unread credentials are preserved and opening settings doesn't retry access repeatedly")
        credentialDraft.edit("", account: "locked")
        do { try credentialDraft.save(writer: { writes.append(($0,$1)) }); check(false, "unread secrets cannot be cleared by empty settings fields") } catch { check(writes.isEmpty, "unread secrets cannot be cleared by empty settings fields") }
        credentialDraft.edit("replacement-key", account: "locked")
        try credentialDraft.save(writer: { writes.append(($0,$1)) })
        check(writes.count == 1 && writes[0].1 == "locked", "explicitly entered replacement credentials are saved to their own account")
        try credentialDraft.save(writer: { writes.append(($0,$1)) })
        check(writes.count == 1, "unchanged credentials are not rewritten on repeated saves")
        credentialDraft.edit("new-key-to-keep", account: "requires-authorization")
        credentialDraft.load("requires-authorization", allowInteraction: true, reader: { _, interactive in
            check(interactive, "only the explicit restore action authorizes a credential prompt")
            return "previous-key"
        })
        check(credentialDraft.values["requires-authorization"] == "new-key-to-keep" && credentialDraft.loaded.contains("requires-authorization"), "authorizing an old item preserves the user's newly entered replacement key")
        var switchingKeys = CredentialDraft()
        switchingKeys.edit("key-for-deepseek", account: "api.deepseek")
        switchingKeys.edit("key-for-gemini", account: "api.gemini")
        var providerWrites: [String: String] = [:]
        try switchingKeys.save(writer: { providerWrites[$1] = $0 })
        check(providerWrites == ["api.deepseek":"key-for-deepseek", "api.gemini":"key-for-gemini"], "staged keys for different providers are saved independently")
        let fakeAgentDirectory = dir.appendingPathComponent("detected-agents"); try FileManager.default.createDirectory(at: fakeAgentDirectory, withIntermediateDirectories: true)
        let fakeCodex = fakeAgentDirectory.appendingPathComponent("codex")
        try "#!/bin/sh\nif [ \"$1\" = \"--version\" ]; then echo 'codex-cli fixture'; elif [ \"$2\" = \"--help\" ]; then echo '--output-last-message --sandbox --skip-git-repo-check'; else cat >/dev/null; while [ \"$#\" -gt 0 ]; do if [ \"$1\" = \"--output-last-message\" ]; then shift; printf '最终译文' > \"$1\"; fi; shift; done; echo 'progress noise'; fi\n".write(to: fakeCodex, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fakeCodex.path)
        let detected = await AgentDetection.detect(directories: [fakeAgentDirectory.path, fakeAgentDirectory.path])
        check(detected.count == 1 && detected[0].arguments.contains("read-only"), "agent detection inspects versions and help, deduplicates executables and configures read-only Codex")
        var detectedPreferences = Preferences(); detectedPreferences.provider = "Agent"; detected[0].apply(to: &detectedPreferences)
        let detectedTranslation = try await Translator.translate("A test sentence.", preferences: detectedPreferences)
        check(detectedTranslation == "最终译文", "detected Codex uses its final message file instead of progress output")
        check(AgentDetection.arguments(AgentDetection.displayArguments(["--tools", "", "--print"])) == ["--tools", "", "--print"], "agent configuration preserves empty arguments without shell interpretation")
        var existingProviders = migratedAPI
        existingProviders.apiProfiles!.append(APIProfile(id: "mistral", presetID: "mistral", name: "Mistral", endpoint: "https://api.mistral.ai/v1/chat/completions", model: "mistral-small-latest", models: [], credentialAccount: "api.mistral"))
        if let index = existingProviders.apiProfiles!.firstIndex(where: { $0.id == "qwen" }) { existingProviders.apiProfiles![index].name = "通义千问 · 百炼（中国内地）" }
        existingProviders.activeAPIProfileID = "mistral"
        APIProfiles.prepare(&existingProviders)
        check(existingProviders.apiProfiles!.allSatisfy { $0.presetID != "mistral" } && existingProviders.apiProfiles!.first(where: { $0.id == "qwen" })?.name == "通义千问", "old saved configurations remove the Mistral preset and update the Qwen label")
        check(existingProviders.activeAPIProfileID == "deepseek" && existingProviders.apiCredentialAccount == "api", "removing the active Mistral preset selects a remaining provider with its own credential")
        check(!APIPreset.all.contains(where: { $0.id == "mistral" }), "fresh provider menus do not offer Mistral")
        let geminiURL = URL(string: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions")!
        var retryRequests = 0; var retryDelays: [TimeInterval] = []
        StubURLProtocol.handler = { _ in
            retryRequests += 1
            return retryRequests < 3 ? (503, Data(#"{"error":{"message":"temporarily busy"}}"#.utf8)) : (200, Data(#"{"result":"recovered"}"#.utf8))
        }
        let recovered = try await HTTP.json(geminiURL, token: "fixture-only-key", session: session, retry: .transient, sleep: { retryDelays.append($0) })
        check(recovered["result"] as? String == "recovered" && retryRequests == 3 && retryDelays.count == 2 && retryDelays[1] > retryDelays[0], "temporary Gemini 503 recovers with two bounded exponential-backoff retries")
        retryRequests = 0
        StubURLProtocol.handler = { _ in retryRequests += 1; return (503, Data(#"{"error":{"message":"fixture-only-key overloaded"}}"#.utf8)) }
        do {
            _ = try await HTTP.json(geminiURL, token: "fixture-only-key", session: session, retry: .transient, sleep: { _ in })
            check(false, "persistent Gemini 503 stops after three attempts")
        } catch let failure as HTTPFailure {
            check(retryRequests == 3 && failure.attempts == 3 && failure.localizedDescription.contains("刷新可用模型") && !failure.localizedDescription.contains("fixture-only-key"), "persistent Gemini 503 stops after three attempts with model guidance and redacted secrets")
        }
        retryRequests = 0
        do { _ = try await HTTP.json(geminiURL, token: "fixture-only-key", session: session, retry: .transient, sleep: { _ in throw CancellationError() }); check(false, "cancelling backoff stops further requests") }
        catch is CancellationError { check(retryRequests == 1, "cancelling backoff stops further requests") }
        retryRequests = 0
        StubURLProtocol.handler = { _ in retryRequests += 1; return (401, Data(#"{"error":{"message":"invalid key"}}"#.utf8)) }
        do { _ = try await HTTP.json(geminiURL, token: "fixture-only-key", session: session, retry: .transient, sleep: { _ in }); check(false, "authentication failures never retry") }
        catch { check(retryRequests == 1, "authentication failures never retry") }
        retryRequests = 0
        StubURLProtocol.handler = { _ in retryRequests += 1; return (503, Data(#"{"error":{"message":"busy"}}"#.utf8)) }
        do { _ = try await HTTP.json(URL(string: "https://open.maimemo.com/open/api/v1/memo/notepads")!, token: "fixture-only-key", body: ["notepad":[:]], session: session, sleep: { _ in }); check(false, "cloud notepad writes are not automatically retried") }
        catch { check(retryRequests == 1, "cloud notepad writes are not automatically retried") }
        check(HTTP.retryAfter("4") == 4 && HTTPRetryPolicy.transient.delay(status: 503, retryIndex: 0, retryAfter: 30) == nil && HTTPRetryPolicy.transient.delay(status: 503, retryIndex: 0, retryAfter: 4)! >= 4, "retry respects server cooldowns and refuses waits beyond the bounded policy")
        let settingsWork = SettingsOperation(); let settingsGate = SelectionGate()
        var settingsResults: [String] = []; var settingsErrors: [String] = []
        settingsWork.run(label: "连接测试", timeout: 10, operation: { await settingsGate.translate("cancelled-settings") }, success: { settingsResults.append($0) }, failure: { settingsErrors.append($0.localizedDescription) })
        await settingsGate.waitForStart("cancelled-settings")
        settingsWork.cancel()
        check(!settingsWork.isRunning, "settings cancellation immediately unlocks the form without waiting for the request")
        settingsWork.run(label: "新连接测试", timeout: 1, operation: { "new-result" }, success: { settingsResults.append($0) }, failure: { settingsErrors.append($0.localizedDescription) })
        for _ in 0..<100 { if !settingsWork.isRunning { break }; try await Task.sleep(nanoseconds: 1_000_000) }
        await settingsGate.finish("cancelled-settings", "old-result")
        try await Task.sleep(nanoseconds: 5_000_000)
        check(settingsResults == ["new-result"] && settingsErrors.isEmpty, "a cancelled settings request cannot overwrite a newer connection result")
        settingsWork.run(label: "超时测试", timeout: 0.03, operation: { await settingsGate.translate("unresponsive-settings") }, success: { settingsResults.append($0) }, failure: { settingsErrors.append($0.localizedDescription) })
        await settingsGate.waitForStart("unresponsive-settings")
        for _ in 0..<100 { if !settingsWork.isRunning { break }; try await Task.sleep(nanoseconds: 2_000_000) }
        check(!settingsWork.isRunning && settingsErrors.count == 1 && settingsErrors[0].contains("超时"), "the settings watchdog releases the UI even when the underlying operation ignores cancellation")
        await settingsGate.finish("unresponsive-settings", "late-timeout-result")
        try await Task.sleep(nanoseconds: 5_000_000)
        check(settingsResults == ["new-result"], "timed-out settings operations cannot publish stale success")
        StubURLProtocol.handler = { request in
            check(request.timeoutInterval <= 2 && request.timeoutInterval > 0, "connection checks pass the remaining timeout budget to URLSession")
            throw URLError(.timedOut)
        }
        do { _ = try await HTTP.json(geminiURL, token: "fixture-only-key", session: session, retry: .transient, timeout: 2); check(false, "request timeout becomes an actionable error") }
        catch { check(error.localizedDescription.contains("网络或代理"), "request timeout becomes an actionable error without another long retry") }
        let nestedParent = PDFOutline(); nestedParent.label = "Part One"
        let nestedChild = PDFOutline(); nestedChild.label = "Opening"; nestedChild.destination = PDFDestination(page: outlined.page(at: 0)!, at: CGPoint(x: 0, y: 700))
        nestedParent.insertChild(nestedChild, at: 0)
        let nestedSecond = PDFOutline(); nestedSecond.label = "Details"; nestedSecond.destination = PDFDestination(page: outlined.page(at: 2)!, at: CGPoint(x: 0, y: 700))
        nestedParent.insertChild(nestedSecond, at: 1)
        let nestedRoot = PDFOutline(); nestedRoot.insertChild(nestedParent, at: 0); outlined.outlineRoot = nestedRoot
        let nestedPDFURL = dir.appendingPathComponent("nested-outline.pdf"); check(outlined.write(to: nestedPDFURL), "hierarchical PDF fixture created")
        let nestedPDFBook = try Importer.load(nestedPDFURL, assetsRoot: assets)
        check(nestedPDFBook.tableOfContents?.map(\.depth) == [0, 1, 1] && nestedPDFBook.tableOfContents?.count == 3 && nestedPDFBook.chapters.count == 2, "PDF bookmarks preserve parent groups and same-page child titles for hierarchical folding")
        let tocChapters = [Chapter(id: "toc-c0", title: "World", sentences: [Sentence(original: "World", translation: "世界"), Sentence(original: "The first page.")]), Chapter(id: "toc-c1", title: "Science", sentences: [Sentence(original: "A scientific discovery.")]), Chapter(id: "toc-c2", title: "Culture", sentences: [Sentence(original: "A cultural moment.")])]
        let tocEntries = [TOCEntry(id: "toc-root", title: "World", chapterIndex: 0, depth: 0), TOCEntry(id: "toc-child", title: "Science", chapterIndex: 1, depth: 1), TOCEntry(id: "toc-grandchild", title: "AI", chapterIndex: 1, depth: 2), TOCEntry(id: "toc-sibling", title: "Books", chapterIndex: 2, depth: 1), TOCEntry(id: "toc-other", title: "Culture", chapterIndex: 2, depth: 0)]
        let tocBook = Book(id: "toc-book", title: "TOC fixture", chapters: tocChapters, tableOfContents: tocEntries)
        let outline = tocBook.tocOutline
        check(outline.ancestors("toc-grandchild") == ["toc-root", "toc-child"] && outline.subtree("toc-child").map(\.id) == ["toc-child", "toc-grandchild"], "TOC hierarchy resolves ancestors and complete subtrees")
        check(outline.visible(collapsed: ["toc-child"]).map(\.id) == ["toc-root", "toc-child", "toc-sibling", "toc-other"] && outline.visible(collapsed: ["toc-root"]).map(\.id) == ["toc-root", "toc-other"], "hierarchical folding hides descendants and preserves sibling groups")
        var fallbackTOC = tocBook; fallbackTOC.tableOfContents = nil
        check(fallbackTOC.tocOutline.entries.map(\.id) == tocChapters.map(\.id), "legacy books get stable TOC identifiers from their chapters")
        let titleJSON = #"{"translations":[{"index":1,"translation":"科学"},{"index":0,"translation":"世界"}]}"#
        check(try TitleTranslator.parse(titleJSON, titles: ["World", "Science"]) == ["World":"世界", "Science":"科学"], "title translation maps indexed batch results without relying on response order")
        do { _ = try TitleTranslator.parse(#"{"translations":[{"index":true,"translation":"错误"}]}"#, titles: ["World"]); check(false, "invalid or incomplete title batch results are rejected") } catch { check(true, "invalid or incomplete title batch results are rejected") }
        var translatedTitleBatches: [[String]] = []
        let tocStore = Store(dataDirectory: dir.appendingPathComponent("toc-store"), translator: { text, _ in "正文译文：" + text }, titleTranslator: { titles, _ in
            translatedTitleBatches.append(titles); return Dictionary(uniqueKeysWithValues: titles.map { ($0, "译·" + $0) })
        })
        tocStore.library.books = [tocBook]; tocStore.selected = tocBook.id
        tocStore.toggleTOCCollapse(bookID: tocBook.id, entryID: "toc-root")
        tocStore.toggleTOCCollapse(bookID: tocBook.id, entryID: "toc-child")
        tocStore.navigateTOC(tocEntries[2])
        check(tocStore.book?.chapterIndex == 1 && tocStore.book?.selectedTOCEntryID == "toc-grandchild" && tocStore.book?.collapsedTOCEntryIDs?.isEmpty == true, "TOC navigation reveals only the selected path and tracks the exact entry")
        tocStore.toggleTOCRead(bookID: tocBook.id, entryID: "toc-child")
        check(Set(tocStore.book!.readTOCEntryIDs!) == ["toc-child", "toc-grandchild"] && tocStore.book?.chapterIndex == 1, "read circles mark an entire subtree without changing the current chapter")
        tocStore.toggleTOCRead(bookID: tocBook.id, entryID: "toc-root")
        check(tocStore.book?.readTOCEntryIDs?.count == 4, "parent read control completes a partially read subtree")
        tocStore.toggleTOCRead(bookID: tocBook.id, entryID: "toc-root")
        check(tocStore.book?.readTOCEntryIDs?.isEmpty == true, "completed subtree can be toggled back to unread")
        tocStore.toggleTOCRead(bookID: tocBook.id, entryID: "toc-child")
        tocStore.setAllTOCCollapsed(bookID: tocBook.id, collapsed: true)
        check(Set(tocStore.book!.collapsedTOCEntryIDs!) == ["toc-root", "toc-child"], "collapse all targets only entries that have children")
        tocStore.translateTitles(bookID: tocBook.id)
        await tocStore.titleTranslationTasks[tocBook.id]?.value
        check(translatedTitleBatches.count == 1 && !translatedTitleBatches[0].contains("World") && tocStore.book?.titleTranslations?["World"] == "世界" && tocStore.book?.pendingTitleTexts.isEmpty == true, "TOC translation first reuses existing heading translations then batches only missing titles")
        tocStore.translateTitles(bookID: tocBook.id)
        check(translatedTitleBatches.count == 1, "completed title translations are not requested again")
        let reloadedTOCStore = Store(dataDirectory: dir.appendingPathComponent("toc-store"))
        check(reloadedTOCStore.book?.titleTranslations?["Science"] == "译·Science" && Set(reloadedTOCStore.book!.collapsedTOCEntryIDs!) == ["toc-root", "toc-child"] && Set(reloadedTOCStore.book!.readTOCEntryIDs!) == ["toc-child", "toc-grandchild"], "title translations, reading marks and folding survive app restart")
        var newTOCImport = tocBook
        newTOCImport.tableOfContents = tocEntries.enumerated().map { index, entry in var copy = entry; copy.id = "new-toc-" + String(index); return copy }
        let restoredTOC = newTOCImport.restoringReadingState(from: tocStore.book!)
        check(Set(restoredTOC.readTOCEntryIDs!) == ["new-toc-1", "new-toc-2"] && Set(restoredTOC.collapsedTOCEntryIDs!) == ["new-toc-0", "new-toc-1"] && restoredTOC.titleTranslations?["Science"] == "译·Science", "reimport remaps TOC state by hierarchy instead of discarding it with fresh entry IDs")
        var batchAttempts = 0
        let resumeTitlesStore = Store(dataDirectory: dir.appendingPathComponent("toc-resume"), titleTranslator: { titles, _ in
            batchAttempts += 1
            if batchAttempts == 2 { throw ReadError.message("Simulated title batch interruption") }
            return Dictionary(uniqueKeysWithValues: titles.map { ($0, "译·" + $0) })
        })
        var manyTitles = tocBook
        manyTitles.tableOfContents = (0..<19).map { TOCEntry(id: "batch-title-" + String($0), title: "Title " + String($0), chapterIndex: 0) }
        resumeTitlesStore.library.books = [manyTitles]; resumeTitlesStore.selected = manyTitles.id
        resumeTitlesStore.translateTitles(bookID: manyTitles.id); await resumeTitlesStore.titleTranslationTasks[manyTitles.id]?.value
        check(resumeTitlesStore.book?.titleTranslations?.count == 16 && resumeTitlesStore.titleTranslationErrors[manyTitles.id] != nil, "title translation saves completed batches before an interruption")
        resumeTitlesStore.translateTitles(bookID: manyTitles.id, retry: true); await resumeTitlesStore.titleTranslationTasks[manyTitles.id]?.value
        check(resumeTitlesStore.book?.pendingTitleTexts.isEmpty == true && batchAttempts == 3, "title translation resumes only missing titles after an interruption")
        let titleGate = SelectionGate(); var bodyAfterTitles = false
        let priorityStore = Store(dataDirectory: dir.appendingPathComponent("toc-priority"), translator: { text, _ in bodyAfterTitles = true; return "译：" + text }, titleTranslator: { titles, _ in
            _ = await titleGate.translate("priority-titles"); return Dictionary(uniqueKeysWithValues: titles.map { ($0, "译·" + $0) })
        })
        priorityStore.library.books = [tocBook]; priorityStore.selected = tocBook.id
        priorityStore.translateTitles(bookID: tocBook.id); await titleGate.waitForStart("priority-titles")
        priorityStore.translateChapter(); try await Task.sleep(nanoseconds: 5_000_000)
        check(!bodyAfterTitles && priorityStore.translating, "body translation waits for prioritized TOC title translation")
        await titleGate.finish("priority-titles", "done"); await priorityStore.titleTranslationTasks[tocBook.id]?.value; await priorityStore.translationTask?.value
        check(bodyAfterTitles && !priorityStore.translating, "body translation proceeds after title translations finish")
        var progressBook = tocBook
        progressBook.readTOCEntryIDs = ["toc-child", "toc-grandchild"]
        check(progressBook.readingProgress.completed == 1 && progressBook.readingProgress.total == 3 && progressBook.readingProgress.percentage == 33 && progressBook.readArticles.first?.id == "toc-grandchild", "bookshelf progress counts a read article once when multiple TOC titles share its chapter")
        progressBook.readTOCEntryIDs = ["toc-child"]
        check(progressBook.readArticles.isEmpty, "a category marker alone does not count its unmarked child article as read")
        progressBook.readTOCEntryIDs = tocEntries.map(\.id)
        check(progressBook.readingProgress.completed == 3 && progressBook.readingProgress.percentage == 100, "bookshelf progress reaches 100 percent when all chapter content is marked read")
        let emptyProgressBook = Book(title: "Empty", chapters: [])
        check(emptyProgressBook.readingProgress.fraction == 0 && emptyProgressBook.readingProgress.percentage == 0, "empty books have a valid zero progress value")
        var legacyReadBook = fallbackTOC; legacyReadBook.readTOCEntryIDs = [tocChapters[1].id]
        check(legacyReadBook.readArticles.first?.title == "Science" && legacyReadBook.readingProgress.completed == 1, "read articles and shelf progress also work for books without explicit TOC metadata")
        tocStore.library.books[0].readTOCEntryIDs = ["toc-child", "toc-grandchild", "toc-other"]
        let previousReadingChapter = tocStore.book?.chapterIndex
        tocStore.markArticleUnread(bookID: tocBook.id, chapterIndex: 1)
        check(tocStore.book?.readTOCEntryIDs == ["toc-other"] && tocStore.book?.chapterIndex == previousReadingChapter && tocStore.book?.readArticles.count == 1, "removing a read article clears same-chapter aliases without navigating or clearing other articles")
        let progressReload = Store(dataDirectory: dir.appendingPathComponent("toc-store"))
        check(progressReload.book?.readingProgress.completed == 1 && progressReload.book?.readingProgress.percentage == 33, "bookshelf reading progress derives from persisted marks after relaunch")
        let vocabularyStore = Store(dataDirectory: dir.appendingPathComponent("vocabulary"))
        vocabularyStore.library.books = [tocBook]
        let firstDate = Date(timeIntervalSince1970: 1000)
        let firstSource = WordSource(bookID: tocBook.id, bookTitle: tocBook.title, chapterID: tocChapters[0].id, chapterTitle: "Article A", context: "A quiet room.", meaning: "安静的", partOfSpeech: "adj.", collectedAt: firstDate, ipaUS: "/ˈkwaɪət/")
        var secondSource = firstSource
        secondSource.bookID = "second-book"; secondSource.bookTitle = "Another Book"; secondSource.chapterTitle = "Article B"; secondSource.meaning = "平静的"; secondSource.collectedAt = Date(timeIntervalSince1970: 2000)
        vocabularyStore.addWord("Quiet", meaning: "安静", context: "", source: firstSource)
        vocabularyStore.addWord("quiet", meaning: "平静", context: "", source: secondSource)
        let wordID = vocabularyStore.library.words[0].id
        check(vocabularyStore.library.words.count == 1 && vocabularyStore.library.words[0].sources?.count == 2, "one spelling retains distinct book and article sources")
        check(Vocabulary.words(in: vocabularyStore.library, group: "book:" + tocBook.id, archived: false, query: "").first?.conciseMeaning(in: tocBook.id) == "安静的", "book groups display their own contextual meaning")
        vocabularyStore.addWord("quiet", meaning: "安静", context: "", source: firstSource)
        check(vocabularyStore.library.words[0].source(in: tocBook.id)?.collectedAt == firstDate && vocabularyStore.library.words[0].sources?.count == 2, "recollecting a source keeps its original collection date")
        let cloudBefore = Maimemo.mergedContent(words: vocabularyStore.library.words, existingContent: "remote\nQUIET")
        vocabularyStore.setWordArchived(wordID, archived: true)
        vocabularyStore.setWordCollection(wordID, bookID: nil)
        check(Vocabulary.words(in: vocabularyStore.library, group: "all", archived: false, query: "").isEmpty && Vocabulary.words(in: vocabularyStore.library, group: "uncategorized", archived: true, query: "").count == 1, "archive and uncategorized filters compose")
        check(Maimemo.mergedContent(words: vocabularyStore.library.words, existingContent: "remote\nQUIET") == cloudBefore && cloudBefore == "remote\nQUIET", "classification and archive preserve full cloud sync and remote words without duplicates")
        let vocabularyReload = Store(dataDirectory: dir.appendingPathComponent("vocabulary"))
        check(vocabularyReload.library.words[0].isArchived && vocabularyReload.library.words[0].collectionIDs.isEmpty && vocabularyReload.library.words[0].sources?.count == 2, "organization and provenance persist independently after restart")
        check(Vocabulary.books(in: vocabularyReload.library).contains { $0.id == "second-book" }, "source book categories remain available when their book is no longer on the shelf")
        vocabularyStore.setWordCollection(wordID, bookID: tocBook.id)
        check(vocabularyStore.library.words[0].collectionIDs == [tocBook.id], "words can be organized into a chosen book without losing sources")
        var legacyVocabulary = Library()
        legacyVocabulary.books = [tocBook]
        legacyVocabulary.words = [Word(spelling: "legacy", meaning: "历史词", context: tocBook.title), Word(spelling: "manual", meaning: "旧手动词", context: "")]
        check(Vocabulary.migrateSources(in: &legacyVocabulary) && legacyVocabulary.words[0].source()?.chapterTitle == nil && legacyVocabulary.words[1].sources == nil, "legacy migration recovers known books without inventing missing articles")
        check(!Vocabulary.migrateSources(in: &legacyVocabulary), "legacy provenance migration is idempotent")
        let memoID = "np-test_existing-Cloud_ID"
        let memoURL = try Maimemo.notepadURL(id: memoID)
        check(memoURL.lastPathComponent == memoID && memoURL.host == "open.maimemo.com", "cloud IDs containing underscores are valid opaque path segments")
        var memoMethods: [String] = []
        var uploadedNote: [String: Any] = [:]
        StubURLProtocol.handler = { request in
            check(request.url == memoURL && request.value(forHTTPHeaderField: "Authorization") == "Bearer memo-test-only", "cloud sync uses the bound opaque ID and credential for both requests")
            memoMethods.append(request.httpMethod ?? "")
            if request.httpMethod == "GET" {
                return (200, try JSONSerialization.data(withJSONObject: ["data": ["notepad": ["id": memoID, "content": "# My words\nREMOTE\nquiet", "title": "My cloud book", "brief": "Keep this", "tags": ["Personal"], "status": "PUBLISHED"]]]))
            }
            var data = request.httpBody ?? Data()
            if data.isEmpty, let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; data.append(contentsOf: buffer.prefix(count)) }
            }
            let body = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            check(body["id"] as? String == memoID, "update body repeats the bound cloud ID as required by the official schema")
            uploadedNote = body["notepad"] as! [String: Any]
            return (200, try JSONSerialization.data(withJSONObject: ["data": ["notepad": ["id": memoID]]]))
        }
        let memoResult = try await Maimemo.sync(words: [Word(spelling: "QUIET", meaning: "", context: ""), Word(spelling: "discovery", meaning: "", context: "", archivedAt: Date())], id: " \n" + memoID + "\n", token: "memo-test-only", session: session)
        check(memoResult == memoID && memoMethods == ["GET", "POST"] && uploadedNote["content"] as? String == "# My words\nREMOTE\nquiet\ndiscovery", "sync preserves cloud text and headings, deduplicates words, and includes archived words")
        check(uploadedNote["title"] as? String == "My cloud book" && uploadedNote["brief"] as? String == "Keep this" && uploadedNote["tags"] as? [String] == ["Personal"], "sync retains remote title, description and tags")
        var failedReadRequests = 0
        StubURLProtocol.handler = { _ in failedReadRequests += 1; return (404, Data("{}".utf8)) }
        do { _ = try await Maimemo.sync(words: library.words, id: memoID, token: "memo-test-only", session: session); fatalError("missing cloud note ignored") }
        catch { check(failedReadRequests == 1, "failed cloud read never overwrites a note or creates a duplicate") }
        failedReadRequests = 0
        for invalidID in ["../other", "bad/id", "bad?query", "bad#fragment"] {
            do { _ = try await Maimemo.sync(words: library.words, id: invalidID, token: "memo-test-only", session: session); fatalError("unsafe cloud ID accepted") }
            catch { check(failedReadRequests == 0, "malformed cloud IDs are rejected before requests") }
        }
        var createRequests = 0
        StubURLProtocol.handler = { request in
            createRequests += 1
            check(request.httpMethod == "POST" && request.url?.absoluteString == Maimemo.base, "new cloud notes use the documented creation endpoint")
            return (200, Data("{\"notepad\":{\"id\":\"np-created_new\"}}".utf8))
        }
        let createdMemo = try await Maimemo.sync(words: library.words, id: "", token: "memo-test-only", session: session)
        check(createdMemo == "np-created_new" && createRequests == 1, "initial creation accepts underscore IDs and never retries POST automatically")
        let examIndex = try ExamVocabulary(url: URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Sources/OneRead/ExamVocabulary.json"))
        check(examIndex.count(for: .ielts) == 5040 && examIndex.tags(spelling: "discovery").contains(.ielts), "replacement IELTS index contains the complete normalized ECDICT tagged set")
        check(examIndex.isAvailable && VocabularyExam.allCases.allSatisfy { examIndex.count(for: $0) > 500 }, "all five pinned exam membership lists are complete and nonempty")
        check(examIndex.tags(spelling: " ACADEMIC ") == VocabularyExam.allCases, "multiple exam tags appear in stable order after case and whitespace normalization")
        check(examIndex.tags(spelling: "hydrosphere") == [.toefl], "membership uses each independent exam list without inferring tags from difficulty")
        check(examIndex.tags(spelling: "implications", lemma: "implication") == examIndex.tags(spelling: "implication"), "dictionary lemma matches inflected vocabulary")
        check(examIndex.tags(spelling: "unlistedwordxyz").isEmpty && examIndex.tags(spelling: "quiet unlistedwordxyz", lemma: "quiet").isEmpty, "unlisted words and phrases are not tagged from component words")
        let existingExamWord = vocabularyReload.library.words[0]
        check(examIndex.tags(for: existingExamWord) == examIndex.tags(spelling: "quiet") && existingExamWord.isArchived, "old and archived words receive derived labels without a data migration")
        do {
            let corruptExamFile = dir.appendingPathComponent("incomplete-exams.json")
            try Data("{\"version\":\"test\",\"words\":{}}".utf8).write(to: corruptExamFile)
            _ = try ExamVocabulary(url: corruptExamFile)
            check(false, "an incomplete index must be rejected")
        } catch { check(true, "incomplete exam resource cannot silently appear as no membership") }
        let bundledIssues = try JSONDecoder().decode(EconomistCatalog.self, from: Data(contentsOf: URL(fileURLWithPath: "Sources/OneRead/EconomistCatalogSeed.json")))
        check(bundledIssues.issues.count == 94 && bundledIssues.issues.first?.date == "2026-10-17" && Set(bundledIssues.issues.map(\.id)).count == 94, "bundled public catalog provides a complete dated fallback for first launch when GitHub is unavailable")
        let magazineData = try Data(contentsOf: richArchive)
        var magazineHash = Insecure.SHA1(); magazineHash.update(data: Data("blob \(magazineData.count)\0".utf8)); magazineHash.update(data: magazineData)
        let magazineSHA = magazineHash.finalize().map { String(format: "%02x", $0) }.joined()
        let foreignSeeds = try JSONDecoder().decode([String: EconomistCatalog].self, from: Data(contentsOf: URL(fileURLWithPath: "Sources/OneRead/MagazineCatalogSeeds.json")))
        for kind in MagazineKind.allCases where kind != .economist {
            let catalog = foreignSeeds[kind.rawValue]!
            check(!catalog.issues.isEmpty && catalog.issues.allSatisfy { $0.kind == kind && $0.id.hasPrefix(kind.rawValue + ":") }, "foreign catalog contains namespaced EPUB issues for " + kind.name)
            let latest = catalog.issues[0]
            var localBook = illustrated; localBook.title = latest.filename; localBook.economistIssueID = nil
            check(latest.matches(localBook), "local filename duplicate detection recognizes " + kind.name)
            var preferences = Library(); preferences.preferences.magazineLastSeenIssueIDs = [kind.rawValue: latest.id]
            check(!EconomistLibrary.shouldNotify(latest, library: preferences), "dismissal persists independently for " + kind.name)
            preferences.preferences.magazineLastSeenIssueIDs = nil; preferences.books = [localBook]
            check(!EconomistLibrary.shouldNotify(latest, library: preferences), "already imported foreign issue does not notify for " + kind.name)
            preferences.books = []; preferences.trash = [TrashedBook(book: localBook, originalIndex: 0)]
            check(!EconomistLibrary.shouldNotify(latest, library: preferences), "trashed foreign issue does not notify for " + kind.name)
            let other = EconomistIssue(date: latest.date, path: latest.path, sha: latest.sha, size: latest.size)
            check(!other.matches(localBook) && other.id != latest.id, "same-date issues remain distinct between magazines")
        }
        let folderSHA = String(repeating: "a", count: 40)
        func magazineEntry(_ path: String, type: String = "blob") -> [String: Any] { ["path": path, "type": type, "sha": magazineSHA, "size": magazineData.count] }
        let magazineTree = try JSONSerialization.data(withJSONObject: ["sha": folderSHA, "truncated": false, "tree": [magazineEntry("2025/te_2025.12.27/TheEconomist.2025.12.27.epub"), magazineEntry("te_2026.10.17/TheEconomist.2026.10.17.epub"), magazineEntry("te_2026.10.17/alternate.2026.10.17.epub"), magazineEntry("te_2026.10.24/TheEconomist.2026.10.24.pdf"), magazineEntry("../bad.2026.11.01.epub"), magazineEntry("fonts/invalid.2026.02.30.epub"), magazineEntry("te_2026.10.31/fake.2026.10.31.epub", type: "tree")]])
        let magazineIssues = try EconomistRepository.parseIssues(magazineTree)
        check(magazineIssues.map(\.date) == ["2026-10-17", "2025-12-27"] && magazineIssues[0].filename == "TheEconomist.2026.10.17.epub", "repository catalog finds historical EPUBs, deduplicates dates, prefers canonical filenames and excludes PDFs and invalid paths")
        check(EconomistRepository.issueDate(in: "te_2024.02.29") == "2024-02-29" && EconomistRepository.issueDate(in: "te_2026.02.29") == nil, "issue dates are calendar-validated rather than lexically guessed")
        do { _ = try EconomistRepository.parseIssues(Data("{\"sha\":\"x\",\"truncated\":true,\"tree\":[]}".utf8)); fatalError("Truncated catalog accepted") }
        catch { check(true, "truncated GitHub trees cannot replace the complete cached catalog") }
        for kind in MagazineKind.allCases where kind != .economist {
            let path = "2026.10.19/" + kind.rawValue + ".2026.10.19.epub"
            let tree = try JSONSerialization.data(withJSONObject: ["sha": folderSHA, "truncated": false, "tree": [magazineEntry(path)]])
            let root = try JSONSerialization.data(withJSONObject: ["sha": String(repeating: "b", count: 40), "truncated": false, "tree": [["path": kind.directory, "type": "tree", "sha": folderSHA]]])
            StubURLProtocol.handler = { request in
                if request.url?.lastPathComponent == "master" { return (200, root) }
                if request.url?.query == "recursive=1" { return (200, tree) }
                check(request.url?.path == "/hehonghui/awesome-english-ebooks/master/" + kind.directory + "/" + path, "foreign download uses its own repository directory for " + kind.name)
                return (200, magazineData)
            }
            let foreignStore = Store(dataDirectory: dir.appendingPathComponent("foreign-" + kind.rawValue), titleTranslator: { _, _ in [:] })
            let foreignManager = EconomistLibrary(repository: EconomistRepository(session: session, kind: kind))
            await foreignManager.start(store: foreignStore)
            check(foreignManager.issues.count == 1 && foreignManager.pendingIssue?.kind == kind && foreignStore.library.books.isEmpty, "startup refresh discovers " + kind.name + " without automatically importing")
            let issue = foreignManager.issues[0]
            foreignManager.dismissUpdate(store: foreignStore)
            check(!EconomistLibrary.shouldNotify(issue, library: Store(dataDirectory: foreignStore.file.deletingLastPathComponent()).library), "foreign dismissal survives reload for " + kind.name)
            foreignManager.beginImport(issue, store: foreignStore); await foreignManager.waitForImport()
            check(foreignStore.library.books.count == 1 && foreignStore.library.books[0].economistIssueID == issue.id && foreignStore.library.books[0].shelfFolderID == kind.rawValue && foreignStore.library.books[0].effectiveCoverResource != nil && foreignManager.importError == nil, "foreign import validates EPUB and preserves covers and category for " + kind.name)
            foreignManager.beginImport(issue, store: foreignStore); await foreignManager.waitForImport()
            check(foreignStore.library.books.count == 1, "repeat foreign import opens existing issue for " + kind.name)
            if let fixtureRoot = ProcessInfo.processInfo.environment["ONEREAD_FOREIGN_FIXTURE_ROOT"] {
                let catalogIssue = foreignSeeds[kind.rawValue]!.issues[0]
                let url = URL(fileURLWithPath: fixtureRoot).appendingPathComponent(kind.rawValue + ".epub")
                let bytes = try Data(contentsOf: url); try EconomistRepository.validateEPUB(bytes, issue: catalogIssue)
                let imported = try Importer.load(url, assetsRoot: dir.appendingPathComponent("real-foreign-assets"))
                check(!imported.chapters.isEmpty && imported.effectiveCoverResource != nil, "real repository EPUB parses chapters and cover for " + kind.name)
            }
        }
        let allPublicationRoot = try JSONSerialization.data(withJSONObject: ["sha": String(repeating: "b", count: 40), "truncated": false, "tree": MagazineKind.allCases.map { ["path": $0.directory, "type": "tree", "sha": folderSHA] }])
        var sharedRootRequests = 0
        StubURLProtocol.handler = { request in
            if request.url?.lastPathComponent == "master" { sharedRootRequests += 1; return (200, allPublicationRoot) }
            return (200, magazineTree)
        }
        let sharedHub = ForeignMagazines(libraries: MagazineKind.allCases.map { EconomistLibrary(repository: EconomistRepository(session: session, kind: $0)) })
        let sharedStore = Store(dataDirectory: dir.appendingPathComponent("shared-magazine-check"))
        await sharedHub.start(store: sharedStore)
        check(sharedRootRequests == 1 && sharedHub.libraries.allSatisfy { !$0.issues.isEmpty && $0.pendingIssue?.kind == $0.kind }, "four publications share one startup repository request and each retain a latest issue")
        let firstPending = sharedHub.pending(in: sharedStore.library)!
        sharedHub.library(firstPending.kind).dismissUpdate(store: sharedStore)
        check(sharedHub.pending(in: sharedStore.library)?.kind != firstPending.kind, "dismissing one publication advances the update queue to another publication")
        let magazineRoot = try JSONSerialization.data(withJSONObject: ["sha": String(repeating: "b", count: 40), "truncated": false, "tree": [["path": "01_economist", "type": "tree", "sha": folderSHA]]])
        var magazineRequests: [URLRequest] = []
        StubURLProtocol.handler = { request in
            magazineRequests.append(request)
            if request.url?.lastPathComponent == "master" { return (200, magazineRoot) }
            if request.url?.query == "recursive=1" { return (200, magazineTree) }
            check(request.url?.host == "raw.githubusercontent.com" && request.url?.path.hasSuffix(magazineIssues[0].path) == true && request.value(forHTTPHeaderField: "Authorization") == nil, "EPUB download uses the official raw file host and sends no personal credentials")
            return (200, magazineData)
        }
        let magazineStore = Store(dataDirectory: dir.appendingPathComponent("magazine-library"), titleTranslator: { titles, _ in Dictionary(uniqueKeysWithValues: titles.map { ($0, "译·" + $0) }) })
        let magazineManager = EconomistLibrary(repository: EconomistRepository(session: session))
        await magazineManager.start(store: magazineStore)
        check(magazineRequests.count == 2 && magazineManager.issues.count == 2 && magazineManager.pendingIssue?.date == "2026-10-17" && magazineStore.library.books.isEmpty, "startup discovers the newest EPUB in two requests and prompts without importing automatically")
        magazineManager.dismissUpdate(store: magazineStore)
        let magazineReload = Store(dataDirectory: dir.appendingPathComponent("magazine-library"))
        check(!EconomistLibrary.shouldNotify(magazineIssues[0], library: magazineReload.library) && EconomistLibrary.shouldNotify(EconomistIssue(date: "2026-10-24", path: "", sha: magazineSHA, size: magazineData.count), library: magazineReload.library), "declining an issue persists across relaunch while a newer issue still triggers a prompt")
        magazineManager.beginImport(magazineIssues[0], store: magazineStore); await magazineManager.waitForImport()
        check(magazineStore.library.books.count == 1 && magazineStore.library.books[0].economistIssueID == magazineIssues[0].id && magazineStore.library.books[0].effectiveCoverResource != nil && !magazineStore.busy && magazineManager.importError == nil, "confirmed magazine download is hash-verified and imported with images, cover and persistent issue identity")
        check(illustrated.restoringReadingState(from: magazineStore.library.books[0]).economistIssueID == magazineIssues[0].id, "reloading a magazine original retains its repository identity")
        let requestCountBeforeDuplicate = magazineRequests.count
        let importedMagazineID = magazineStore.library.books[0].id
        magazineManager.beginImport(magazineIssues[0], store: magazineStore); await magazineManager.waitForImport()
        check(magazineRequests.count == requestCountBeforeDuplicate && magazineStore.library.books.count == 1 && magazineManager.importedBookID == importedMagazineID, "importing an existing issue opens it without downloading or losing reading state")
        magazineStore.deleteBook(importedMagazineID)
        check(!EconomistLibrary.shouldNotify(magazineIssues[0], library: magazineStore.library), "recently deleted issues are not advertised as unread new releases")
        magazineManager.beginImport(magazineIssues[0], store: magazineStore)
        check(magazineStore.library.books.first?.id == importedMagazineID && magazineRequests.count == requestCountBeforeDuplicate, "recently deleted magazine restores its original assets and state without another download")
        var oldMagazine = magazineStore.library.books[0]; oldMagazine.economistIssueID = nil; oldMagazine.title = "TheEconomist.2026.10.17"
        check(magazineIssues[0].matches(oldMagazine), "legacy manually imported issues are recognized by publication name and exact issue date")
        var cachedMagazine = magazineManager.catalog!; cachedMagazine.rootETag = "fixture-etag"
        StubURLProtocol.handler = { request in check(request.value(forHTTPHeaderField: "If-None-Match") == "fixture-etag", "startup revalidation sends the cached catalog ETag"); return (304, Data()) }
        let unchangedMagazine = try await EconomistRepository(session: session).refresh(previous: cachedMagazine)
        check(unchangedMagazine.issues == cachedMagazine.issues, "unchanged repository reuses its complete catalog on HTTP 304")
        StubURLProtocol.handler = { _ in (429, Data()) }
        await magazineManager.refresh(store: magazineStore)
        check(magazineManager.issues.count == 2 && magazineManager.catalogError != nil, "rate limits retain cached issues and show a retry message without blocking local reading")
        magazineManager.beginImport(magazineIssues[1], store: magazineStore); await magazineManager.waitForImport()
        check(magazineStore.library.books.count == 1 && magazineManager.importError != nil && !magazineStore.busy, "failed download leaves the shelf unchanged and releases import controls")
        var corruptedMagazine = magazineData; corruptedMagazine[corruptedMagazine.count - 1] ^= 1
        do { try EconomistRepository.validateEPUB(corruptedMagazine, issue: magazineIssues[0]); fatalError("Corrupt EPUB accepted") }
        catch { check(true, "tampered magazine download is rejected before extraction") }
        let front = Chapter(title: "第 1 章", sentences: [Sentence(original: "The world this week. Leaders. Letters.")], blocks: [ReadingBlock(kind: "image", imageResource: "cover.png")])
        let promo = Chapter(title: "优质App推荐", sentences: [Sentence(original: "An app promotion.")])
        let article = Chapter(title: "The world this week", sentences: [Sentence(original: "The news begins here.")])
        let articleTOC = TOCEntry(title: article.title, chapterIndex: 2)
        var issueWithFrontMatter = Book(title: "TheEconomist.2026.10.10", chapters: [front, promo, article], chapterIndex: 2, tableOfContents: [TOCEntry(title: front.title, chapterIndex: 0), TOCEntry(title: promo.title, chapterIndex: 1), articleTOC], readTOCEntryIDs: [articleTOC.id])
        let cleanIssue = EconomistContent.cleaned(issueWithFrontMatter)
        check(cleanIssue.chapters.map(\.title) == [article.title] && cleanIssue.tableOfContents?.first?.chapterIndex == 0 && cleanIssue.chapterIndex == 0 && cleanIssue.readTOCEntryIDs == [articleTOC.id], "Economist imports remove the front index and app promotion while remapping chapter navigation and preserving read marks")
        check(cleanIssue.coverResource == "cover.png" && EconomistContent.cleaned(cleanIssue).chapters.count == 1, "front matter cleanup retains the original cover and is idempotent")
        issueWithFrontMatter.title = "Another English Book"
        check(EconomistContent.cleaned(issueWithFrontMatter).chapters.count == 3, "unrelated books retain their first chapter and similarly named sections")
        check(EconomistContent.cleaned(issueWithFrontMatter, publicationTitle: "TheEconomist.2026.10.10").chapters.count == 1, "reloading a stored source EPUB applies cleanup using its original publication title")
        let realChapterOne = Book(title: "The Economist Special", chapters: [Chapter(title: "第 1 章", sentences: [Sentence(original: "A real article begins.")]), article])
        check(EconomistContent.cleaned(realChapterOne).chapters.count == 2, "a genuine first chapter without front matter evidence is retained")
        var legacyShelf = Library()
        legacyShelf.books = [Book(title: "TheEconomist.2026.10.17", chapters: []), Book(title: "The New Yorker 2026", chapters: []), Book(title: "Manual", shelfCategory: "精读", chapters: [])]
        check(ShelfOrganization.prepare(&legacyShelf) && legacyShelf.books[0].shelfFolderID == ShelfOrganization.economistID && legacyShelf.books[1].shelfFolderID == nil && legacyShelf.folders?.contains(where: { $0.name == "精读" }) == true, "folder migration preserves Economist and explicit manual categories while leaving other publishers unfiled")
        check(!ShelfOrganization.prepare(&legacyShelf), "folder migration runs only once and does not reclassify books on later launches")
        let shelfStore = Store(dataDirectory: dir.appendingPathComponent("shelf-organization"))
        let shelfBook = Book(title: "TheEconomist.2026.10.17", chapters: [article])
        shelfStore.library.books = [shelfBook]
        shelfStore.setShelfCategory(bookID: shelfBook.id, category: " 精读计划 ")
        shelfStore.library.preferences.shelfCoverWidth = 260; shelfStore.save()
        let shelfReload = Store(dataDirectory: dir.appendingPathComponent("shelf-organization"))
        check(ShelfOrganization.categories(in: shelfReload.library) == ["经济学人", "精读计划"] && ShelfOrganization.coverWidth(shelfReload.library.preferences) == 260, "custom shelf categories and cover size survive relaunch")
        check(illustrated.restoringReadingState(from: shelfReload.library.books[0]).shelfFolderID == shelfReload.library.books[0].shelfFolderID, "reimport preserves manually chosen magazine classification")
        shelfStore.setShelfCategory(bookID: shelfBook.id, category: nil)
        check(shelfStore.library.books[0].shelfFolderID == nil, "moving a book out of a folder leaves it unfiled without automatic classification")
        var sizePreferences = Preferences(); sizePreferences.shelfCoverWidth = 999
        check(ShelfOrganization.coverWidth(sizePreferences) == 260, "shelf layout clamps out-of-range saved sizes")
        let purgeStore = Store(dataDirectory: dir.appendingPathComponent("purge-library"))
        let ownedAssetID = UUID().uuidString
        let ownedDirectory = purgeStore.assetsRoot.appendingPathComponent(ownedAssetID)
        try FileManager.default.createDirectory(at: ownedDirectory, withIntermediateDirectories: true)
        let ownedFile = ownedDirectory.appendingPathComponent("source.epub"); try Data("owned copy".utf8).write(to: ownedFile)
        let originalOutsideLibrary = dir.appendingPathComponent("original-user-file.epub"); try Data("original".utf8).write(to: originalOutsideLibrary)
        let purgeBook = Book(title: "Deleted issue", chapters: [article], assetID: ownedAssetID)
        let deletedRecord = TrashedBook(book: purgeBook, originalIndex: 0)
        purgeStore.library.trash = [deletedRecord]; purgeStore.library.words = [Word(spelling: "quiet", meaning: "安静的", context: "Deleted issue")]; purgeStore.save()
        purgeStore.loadFailed = true
        purgeStore.permanentlyDeleteBook(deletedRecord.id)
        check(purgeStore.library.trash?.count == 1 && FileManager.default.fileExists(atPath: ownedFile.path), "failed permanent-delete persistence restores staged assets and trash entry")
        purgeStore.loadFailed = false
        var sharedBook = purgeBook; sharedBook.id = UUID().uuidString
        purgeStore.library.books = [sharedBook]; purgeStore.save()
        purgeStore.permanentlyDeleteBook(deletedRecord.id)
        check(purgeStore.library.trash?.isEmpty == true && FileManager.default.fileExists(atPath: ownedFile.path), "permanent deletion does not remove assets still referenced by a live book")
        let sharedDeleted = TrashedBook(book: sharedBook, originalIndex: 0)
        purgeStore.library.books = []; purgeStore.library.trash = [sharedDeleted]; purgeStore.save()
        purgeStore.permanentlyDeleteBook(sharedDeleted.id)
        let purgeReload = Store(dataDirectory: dir.appendingPathComponent("purge-library"))
        check(purgeReload.library.trash?.isEmpty == true && !FileManager.default.fileExists(atPath: ownedDirectory.path) && FileManager.default.fileExists(atPath: originalOutsideLibrary.path) && purgeReload.library.words.count == 1, "permanent deletion removes only unreferenced owned book files and persists while preserving vocabulary and original documents")
        let manualFolderID = shelfStore.saveFolder(id: nil, name: "科学阅读", cover: imageFile, automatic: false)!
        let savedFolder = shelfStore.library.folders!.first { $0.id == manualFolderID }!
        let savedCover = ShelfOrganization.coverURL(savedFolder.coverFilename, root: shelfStore.folderCoversRoot)!
        check(FileManager.default.fileExists(atPath: savedCover.path) && savedCover != imageFile, "custom folder covers are downsampled into app-owned files independent of the selected original")
        var secondShelfBook = shelfBook; secondShelfBook.id = UUID().uuidString; secondShelfBook.title = "Second Issue"
        shelfStore.library.books.append(secondShelfBook)
        shelfStore.moveBook(shelfBook.id, to: manualFolderID); shelfStore.moveBook(secondShelfBook.id, to: manualFolderID)
        shelfStore.recordReading(shelfBook.id, at: Date(timeIntervalSince1970: 2000)); shelfStore.recordReading(secondShelfBook.id, at: Date(timeIntervalSince1970: 4000))
        check(ShelfOrganization.coverBook(savedFolder, library: shelfStore.library)?.id == secondShelfBook.id && ShelfOrganization.recent(in: shelfStore.library).map(\.id) == [secondShelfBook.id, shelfBook.id], "folder fallback cover and recent reading are ordered by actual opening time")
        let recentReload = Store(dataDirectory: dir.appendingPathComponent("shelf-organization"))
        check(ShelfOrganization.recent(in: recentReload.library).first?.id == secondShelfBook.id, "recent reading order persists after restart")
        check(shelfStore.saveFolder(id: manualFolderID, name: "科学阅读", cover: nil, automatic: true) == manualFolderID && !FileManager.default.fileExists(atPath: savedCover.path) && FileManager.default.fileExists(atPath: imageFile.path), "resetting folder cover resumes recent-reading cover and removes only the old owned image")
        check(shelfStore.saveFolder(id: nil, name: "科学阅读", cover: nil, automatic: true) == nil, "duplicate folder names are rejected without replacing existing folders")
        let locationRoot = FileManager.default.temporaryDirectory.appendingPathComponent("OneRead-LocationTest-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: locationRoot, withIntermediateDirectories: true)
        let locationSource = locationRoot.appendingPathComponent("Original")
        let locationStore = Store(dataDirectory: locationSource)
        locationStore.library.books = [shelfBook]; locationStore.library.words = shelfStore.library.words
        check(locationStore.save(), "data relocation fixture saves")
        try FileManager.default.createDirectory(at: locationStore.assetsRoot, withIntermediateDirectories: true)
        let locationImage = locationStore.assetsRoot.appendingPathComponent("test.png")
        try Data("image-fixture".utf8).write(to: locationImage)
        let locationDefaultsName = "OneRead.LocationTest." + UUID().uuidString
        let locationDefaults = UserDefaults(suiteName: locationDefaultsName)!
        let locationTarget = locationRoot.appendingPathComponent("NewData")
        let movedLocation = await locationStore.relocateData(to: locationTarget, defaults: locationDefaults)
        let relocatedStore = Store(dataDirectory: locationTarget)
        check(movedLocation && locationStore.file.deletingLastPathComponent().path == locationTarget.path && relocatedStore.library.books.first?.id == shelfBook.id && FileManager.default.fileExists(atPath: locationImage.path) && (try? Data(contentsOf: locationTarget.appendingPathComponent("Assets/test.png"))) == Data("image-fixture".utf8), "relocation switches only after copying books and assets, preserves original and reloads new library")
        check(locationDefaults.string(forKey: DataLocation.preferenceKey) == locationTarget.path && !locationStore.busy && !locationStore.dataMoving, "relocation persists destination and resets busy state")
        let sameLocation = await locationStore.relocateData(to: locationTarget, defaults: locationDefaults)
        check(sameLocation, "reapplying current storage directory is a harmless success")
        let manualDestination = try DataLocation.destination("  ~/APP_Local_Data/OneRead  ")
        check(manualDestination.path == FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("APP_Local_Data/OneRead").path, "manual storage path expands home and trims whitespace without appending nested folders")
        do { _ = try DataLocation.destination("relative/path"); check(false, "relative storage path rejected") } catch { check(true, "relative storage path rejected") }
        let refusedLocation = await locationStore.relocateData(to: locationSource, defaults: locationDefaults)
        check(!refusedLocation && locationStore.file.deletingLastPathComponent().path == locationTarget.path, "existing destination is rejected and active storage remains unchanged")
        do { _ = try DataLocation.stage(source: locationTarget, destination: locationTarget.appendingPathComponent("nested")); check(false, "nested destination rejected") } catch { check(true, "nested destination rejected") }
        locationDefaults.removePersistentDomain(forName: locationDefaultsName)
        try FileManager.default.removeItem(at: locationRoot)
        let quoteSuite = "OneRead.QuoteTest." + UUID().uuidString
        let quoteDefaults = UserDefaults(suiteName: quoteSuite)!
        var quoteCalendar = Calendar(identifier: .gregorian); quoteCalendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let quoteDay = quoteCalendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 1))!
        let todayQuote = DailyQuote.current(at: quoteDay, defaults: quoteDefaults, calendar: quoteCalendar)
        check(DailyQuote.current(at: quoteDay.addingTimeInterval(3600), defaults: quoteDefaults, calendar: quoteCalendar).id == todayQuote.id, "daily quote stays stable within the same local calendar day")
        check(DailyQuote.current(at: quoteDay.addingTimeInterval(86400), defaults: quoteDefaults, calendar: quoteCalendar).id != todayQuote.id, "daily quote changes on the next local day without repeating yesterday")
        check(Set(DailyQuote.collection.map(\.id)).count == DailyQuote.collection.count && DailyQuote.collection.allSatisfy { !$0.chinese.isEmpty && URL(string: $0.source)?.scheme == "https" }, "daily quotes have unique identities, translations and source links")
        quoteDefaults.removePersistentDomain(forName: quoteSuite)
        let oldAdded = Date(timeIntervalSince1970: 100)
        shelfStore.library.books[0].shelfFolderAddedAt = oldAdded
        shelfStore.library.books[1].shelfFolderAddedAt = Date(timeIntervalSince1970: 200)
        check(ShelfOrganization.mosaicBooks(savedFolder, library: shelfStore.library).first?.id == secondShelfBook.id, "category mosaic uses membership date rather than last reading date")
        var mosaicLibrary = Library()
        mosaicLibrary.books = (0..<12).map { index in var book = shelfBook; book.id = "mosaic-\(index)"; book.shelfFolderID = manualFolderID; book.shelfFolderAddedAt = Date(timeIntervalSince1970: Double(index)); return book }
        check(ShelfOrganization.mosaicBooks(savedFolder, library: mosaicLibrary).map(\.id) == (3..<12).reversed().map { "mosaic-\($0)" }, "category mosaic caps at nine most recently added books")
        var deletedMember = shelfBook; deletedMember.shelfFolderID = manualFolderID
        shelfStore.library.trash = [TrashedBook(book: deletedMember, originalIndex: 0)]
        let wordCountBeforeCategoryDeletion = shelfStore.library.words.count
        let bookCountBeforeCategoryDeletion = shelfStore.library.books.count
        check(shelfStore.deleteFolder(manualFolderID) && shelfStore.library.folders?.contains(where: { $0.id == manualFolderID }) == false && shelfStore.library.books.allSatisfy { $0.shelfFolderID != manualFolderID } && shelfStore.library.trash?.first?.book.shelfFolderID == nil && shelfStore.library.words.count == wordCountBeforeCategoryDeletion && shelfStore.library.books.count == bookCountBeforeCategoryDeletion, "deleting category preserves books and vocabulary and unfiles live and trashed members")
        let bulkA = UUID().uuidString, bulkB = UUID().uuidString
        for id in [bulkA, bulkB] { let path = purgeStore.assetsRoot.appendingPathComponent(id); try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true); try Data("owned".utf8).write(to: path.appendingPathComponent("source.epub")) }
        let sharedLiveBook = Book(title: "Shared live", chapters: [], assetID: bulkB)
        purgeStore.library.books = [sharedLiveBook]
        purgeStore.library.trash = [TrashedBook(book: Book(title: "A", chapters: [], assetID: bulkA), originalIndex: 0), TrashedBook(book: Book(title: "B", chapters: [], assetID: bulkB), originalIndex: 0)]
        purgeStore.save(); purgeStore.loadFailed = true; purgeStore.emptyTrash()
        check(purgeStore.library.trash?.count == 2 && FileManager.default.fileExists(atPath: purgeStore.assetsRoot.appendingPathComponent(bulkA).path), "bulk clear rolls back all records and staged files if persistence fails")
        purgeStore.loadFailed = false; purgeStore.emptyTrash()
        check(purgeStore.library.trash?.isEmpty == true && !FileManager.default.fileExists(atPath: purgeStore.assetsRoot.appendingPathComponent(bulkA).path) && FileManager.default.fileExists(atPath: purgeStore.assetsRoot.appendingPathComponent(bulkB).path) && purgeStore.library.words.count == 1, "one-click trash clear protects live shared files and collected words while removing all deleted records")
        print("All smoke checks passed")
    }
}
