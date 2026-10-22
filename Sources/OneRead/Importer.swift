import Foundation
import PDFKit
import NaturalLanguage
import AppKit
import ImageIO
import UniformTypeIdentifiers

final class XMLNodes: NSObject, XMLParserDelegate {
    var roots: [String] = []
    var manifest: [String: String] = [:]
    var mediaTypes: [String: String] = [:]
    var properties: [String: String] = [:]
    var spine: [String] = []
    var coverID: String?
    var coverDocument: String?
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String]) {
        let n = name.components(separatedBy: ":").last ?? name
        if n == "meta", a["name"]?.lowercased() == "cover" { coverID = a["content"] }
        if n == "reference", a["type"]?.lowercased() == "cover" { coverDocument = a["href"] }
        if n == "rootfile", let path = a["full-path"] { roots.append(path) }
        if n == "item", let id = a["id"], let href = a["href"] { manifest[id] = href; mediaTypes[id] = a["media-type"]; properties[id] = a["properties"] }
        if n == "itemref", a["linear"] != "no", let id = a["idref"] { spine.append(id) }
    }
    static func parse(_ data: Data) throws -> XMLNodes {
        let delegate = XMLNodes(); let parser = XMLParser(data: data)
        parser.delegate = delegate; parser.shouldResolveExternalEntities = false
        guard parser.parse() else { throw ReadError.message("EPUB 目录解析失败") }; return delegate
    }
}

struct BlockDraft {
    var kind: String
    var text = ""
    var source: String?
    var alt: String?
    var level: Int?
}

final class HTMLContent: NSObject, XMLParserDelegate {
    var drafts: [BlockDraft] = []
    var buffer = ""
    var role = "paragraph"
    var level: Int?
    var inBody = false
    var skip = 0
    var firstHeading = ""
    let blockTags: Set<String> = ["p", "div", "section", "article", "li", "blockquote", "pre", "figcaption", "h1", "h2", "h3", "h4", "h5", "h6", "dt", "dd", "tr"]
    func flush() {
        let text = buffer.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { drafts.append(BlockDraft(kind: role, text: text, level: level)); if role == "heading" && firstHeading.isEmpty { firstHeading = text } }
        buffer = ""
    }
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String]) {
        let n = name.components(separatedBy: ":").last ?? name
        if n == "body" { inBody = true }
        guard inBody else { return }
        if ["script", "style", "iframe", "object", "noscript"].contains(n) { skip += 1 }
        guard skip == 0 else { return }
        if blockTags.contains(n) {
            flush(); role = n.hasPrefix("h") && Int(n.dropFirst()) != nil ? "heading" : (n == "li" ? "listItem" : (n == "blockquote" ? "quote" : (n == "figcaption" ? "caption" : "paragraph")))
            level = role == "heading" ? Int(n.dropFirst()) : nil
        }
        if n == "br" { buffer += " " }
        if n == "td" || n == "th" { if !buffer.isEmpty { buffer += "  |  " } }
        if n == "img" || n == "image", let source = a["src"] ?? a["href"] ?? a["xlink:href"] {
            flush(); drafts.append(BlockDraft(kind: "image", source: source, alt: a["alt"] ?? "原文插图"))
        }
        if n == "hr" { flush(); drafts.append(BlockDraft(kind: "rule")) }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { if inBody && skip == 0 { buffer += string } }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        let n = name.components(separatedBy: ":").last ?? name
        if ["script", "style", "iframe", "object", "noscript"].contains(n) && inBody { skip -= 1; return }
        guard inBody && skip == 0 else { return }
        if blockTags.contains(n) { flush(); role = "paragraph"; level = nil }
        if n == "body" { flush(); inBody = false }
    }
}

final class EPUBNavigation: NSObject, XMLParserDelegate {
    struct Item { var title: String; var href: String; var depth: Int }
    var items: [Item] = []
    var listDepth = 0
    var navDepth = 0
    var active = false
    var href: String?
    var text = ""
    var ncxPoints: [(title: String, source: String, depth: Int)] = []
    var inLabel = false
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String]) {
        let n = name.components(separatedBy: ":").last ?? name
        if n == "nav" { navDepth += 1; if (a["epub:type"] ?? a["type"] ?? "").split(separator: " ").contains("toc") { active = true } }
        if active && n == "ol" { listDepth += 1 }
        if active && n == "a" { href = a["href"]; text = "" }
        if n == "navPoint" { ncxPoints.append(("", "", ncxPoints.count)) }
        if n == "navLabel" { inLabel = true }
        if n == "content", let source = a["src"], !ncxPoints.isEmpty { ncxPoints[ncxPoints.count - 1].source = source }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if href != nil { text += string }
        if inLabel && !ncxPoints.isEmpty { ncxPoints[ncxPoints.count - 1].title += string }
    }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        let n = name.components(separatedBy: ":").last ?? name
        if n == "a", let href { items.append(Item(title: text.trimmingCharacters(in: .whitespacesAndNewlines), href: href, depth: max(0, listDepth - 1))); self.href = nil }
        if active && n == "ol" { listDepth -= 1 }
        if n == "nav" { navDepth -= 1; if navDepth == 0 { active = false } }
        if n == "navLabel" { inLabel = false }
        if n == "navPoint", let point = ncxPoints.popLast() { items.append(Item(title: point.title.trimmingCharacters(in: .whitespacesAndNewlines), href: point.source, depth: point.depth)) }
    }
}

enum Importer {
    static func sentences(_ text: String) -> [Sentence] {
        let content = text.replacingOccurrences(of: "\u{00a0}", with: " ")
        let tokenizer = NLTokenizer(unit: .sentence); tokenizer.string = content
        var result: [Sentence] = []
        tokenizer.enumerateTokens(in: content.startIndex..<content.endIndex) { range, _ in
            let sentence = content[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty { result.append(Sentence(original: sentence)) }; return true
        }; return result
    }

    static func load(_ url: URL, assetsRoot: URL = AssetStore.root) throws -> Book {
        let format = url.pathExtension.lowercased()
        guard ["pdf", "epub"].contains(format) else { throw ReadError.message("请选择 PDF 或 EPUB 文件") }
        guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 200_000_000 else { throw ReadError.message("首版支持 200 MB 以内的读物") }
        let assetID = UUID().uuidString
        let output = assetsRoot.appendingPathComponent(assetID, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var completed = false
        defer { if !completed { try? FileManager.default.removeItem(at: output) } }
        let sourceName = "source." + format
        try FileManager.default.copyItem(at: url, to: output.appendingPathComponent(sourceName))
        var book = try format == "pdf" ? loadPDF(url, output: output) : EconomistContent.cleaned(loadEPUB(url, output: output))
        book.format = book.format ?? format; book.assetID = assetID; book.sourceName = sourceName
        completed = true
        return book
    }

    private static func loadEPUB(_ url: URL, output: URL) throws -> Book {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let names = try run("/usr/bin/unzip", ["-Z1", url.path]).split(separator: "\n")
        guard names.count <= 20_000, names.allSatisfy({ !$0.hasPrefix("/") && !$0.contains("\\") && !$0.split(separator: "/").contains("..") }) else { throw ReadError.message("EPUB 包含不安全的路径或过多资源") }
        let listing = try run("/usr/bin/zipinfo", ["-l", url.path])
        guard !listing.split(separator: "\n").contains(where: { $0.hasPrefix("l") }) else { throw ReadError.message("EPUB 不允许符号链接") }
        if let match = listing.range(of: #"[0-9]+ bytes uncompressed"#, options: .regularExpression), let size = Int64(listing[match].split(separator: " ")[0]), size > 600_000_000 { throw ReadError.message("EPUB 解压后超过 600 MB 限制") }
        _ = try run("/usr/bin/unzip", ["-qq", url.path, "-d", directory.path])
        func safe(_ base: URL, _ reference: String) throws -> URL {
            guard let components = URLComponents(string: reference), components.scheme == nil, components.host == nil,
                  let path = components.percentEncodedPath.removingPercentEncoding, !path.contains("\\") else { throw ReadError.message("EPUB 资源路径无效") }
            let file = (path.hasPrefix("/") ? directory.appendingPathComponent(String(path.dropFirst())) : base.appendingPathComponent(path)).standardizedFileURL.resolvingSymlinksInPath()
            guard file.path.hasPrefix(directory.path + "/") else { throw ReadError.message("EPUB 资源路径无效") }; return file
        }
        let container = try XMLNodes.parse(Data(contentsOf: directory.appendingPathComponent("META-INF/container.xml")))
        guard let root = container.roots.first else { throw ReadError.message("EPUB 缺少目录") }
        let opfURL = try safe(directory, root); let opf = try XMLNodes.parse(Data(contentsOf: opfURL))
        let images = ImageArchive(packageRoot: directory, output: output)
        var coverResource: String?
        let coverImageID = opf.properties.keys.sorted().first(where: { (opf.properties[$0] ?? "").split(separator: " ").contains("cover-image") }) ?? opf.coverID
        if let id = coverImageID, let href = opf.manifest[id] { coverResource = try? images.image(href, relativeTo: opfURL) }
        if coverResource == nil, let href = opf.coverDocument, let coverFile = try? safe(opfURL.deletingLastPathComponent(), href), let data = try? Data(contentsOf: coverFile) {
            let content = HTMLContent(); let parser = XMLParser(data: data); parser.delegate = content; parser.shouldResolveExternalEntities = false
            if parser.parse(), let image = content.drafts.first(where: { $0.kind == "image" })?.source { coverResource = try? images.image(image, relativeTo: coverFile) }
        }
        var chapters: [Chapter] = []
        var chapterFiles: [String: Int] = [:]
        for id in opf.spine {
            guard let reference = opf.manifest[id] else { continue }
            let file = try safe(opfURL.deletingLastPathComponent(), reference)
            let delegate = HTMLContent(); let parser = XMLParser(data: try Data(contentsOf: file)); parser.delegate = delegate; parser.shouldResolveExternalEntities = false
            guard parser.parse() else { throw ReadError.message("EPUB 章节不是有效 XHTML：\(reference)") }
            var blocks: [ReadingBlock] = []; var content: [Sentence] = []
            for draft in delegate.drafts {
                if draft.kind == "image" {
                    let resource = try images.image(draft.source ?? "", relativeTo: file)
                    blocks.append(ReadingBlock(kind: "image", imageResource: resource, alt: draft.alt, aspectRatio: resource.flatMap { AssetStore.imageAspectRatio(at: output.appendingPathComponent($0)) }))
                } else if draft.kind == "rule" { blocks.append(ReadingBlock(kind: "rule")) }
                else {
                    let items = sentences(draft.text)
                    if !items.isEmpty { content += items; blocks.append(ReadingBlock(kind: draft.kind, sentenceIDs: items.map(\.id), level: draft.level)) }
                }
            }
            if !blocks.isEmpty {
                chapterFiles[file.path] = chapters.count
                chapters.append(Chapter(title: delegate.firstHeading.isEmpty ? "第 \(chapters.count + 1) 章" : delegate.firstHeading, sentences: content, blocks: blocks))
            }
        }
        guard !chapters.isEmpty else { throw ReadError.message("EPUB 无可读内容，可能受 DRM 保护") }
        var toc: [TOCEntry] = []
        let navID = opf.spine.first(where: { (opf.properties[$0] ?? "").split(separator: " ").contains("nav") }) ?? opf.properties.keys.sorted().first(where: { (opf.properties[$0] ?? "").split(separator: " ").contains("nav") }) ?? opf.mediaTypes.keys.sorted().first(where: { opf.mediaTypes[$0] == "application/x-dtbncx+xml" })
        if let navID, let href = opf.manifest[navID], let navFile = try? safe(opfURL.deletingLastPathComponent(), href), let data = try? Data(contentsOf: navFile) {
            let nav = EPUBNavigation(); let parser = XMLParser(data: data); parser.delegate = nav; parser.shouldResolveExternalEntities = false
            if parser.parse() {
                for item in nav.items {
                    if let file = try? safe(navFile.deletingLastPathComponent(), item.href), let index = chapterFiles[file.path], !item.title.isEmpty {
                        if !toc.contains(where: { $0.chapterIndex == index && $0.title == item.title }) { toc.append(TOCEntry(title: item.title, chapterIndex: index, depth: item.depth)) }
                        if chapters[index].title.hasPrefix("第 ") { chapters[index].title = item.title }
                    }
                }
            }
        }
        // Ensure every spine document remains reachable even when the publisher omits it from the TOC.
        for (index, chapter) in chapters.enumerated() where !toc.contains(where: { $0.chapterIndex == index }) { toc.append(TOCEntry(title: chapter.title, chapterIndex: index)) }
        toc.sort { $0.chapterIndex < $1.chapterIndex }
        return Book(title: url.deletingPathExtension().lastPathComponent, chapters: chapters, tableOfContents: toc, coverResource: coverResource)
    }

    private static func loadPDF(_ url: URL, output: URL) throws -> Book {
        guard let document = PDFDocument(url: url), !document.isLocked else { throw ReadError.message("无法打开 PDF，文件可能已加密") }
        guard document.pageCount > 0 else { throw ReadError.message("PDF 没有页面") }
        var starts: [(page: Int, title: String)] = []
        var bookmarks: [(page: Int, title: String, depth: Int)] = []
        func firstPage(_ node: PDFOutline) -> Int? {
            if let page = node.destination?.page {
                let index = document.index(for: page)
                if index != NSNotFound { return index }
            }
            for index in 0..<node.numberOfChildren { if let child = node.child(at: index), let page = firstPage(child) { return page } }
            return nil
        }
        func visit(_ node: PDFOutline, depth: Int) {
            if let index = firstPage(node), let title = node.label, !title.isEmpty {
                bookmarks.append((index, title, depth))
                if !starts.contains(where: { $0.page == index }) { starts.append((index, title)) }
            }
            for index in 0..<node.numberOfChildren { if let child = node.child(at: index) { visit(child, depth: depth + 1) } }
        }
        if let root = document.outlineRoot {
            for index in 0..<root.numberOfChildren { if let child = root.child(at: index) { visit(child, depth: 0) } }
        }
        starts.sort { $0.page < $1.page }
        let hasOutline = !starts.isEmpty
        if starts.isEmpty { starts = (0..<document.pageCount).map { ($0, "第 \($0 + 1) 页") } }
        else if starts[0].page > 0 { starts.insert((0, "封面与前言"), at: 0) }
        var chapters: [Chapter] = []
        for (index, start) in starts.enumerated() {
            let end = index + 1 < starts.count ? starts[index + 1].page : document.pageCount
            var content: [Sentence] = []; var blocks: [ReadingBlock] = []
            for pageIndex in start.page..<end {
                guard let page = document.page(at: pageIndex) else { continue }
                let raw = page.string ?? ""
                let items = sentences(raw); content += items
                let image = page.thumbnail(of: CGSize(width: 1600, height: 2200), for: .cropBox)
                guard let tiff = image.tiffRepresentation, let source = CGImageSourceCreateWithData(tiff as CFData, nil), let cg = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw ReadError.message("PDF 第 \(pageIndex + 1) 页渲染失败") }
                let resource = "page-\(pageIndex + 1).jpg"
                guard let destination = CGImageDestinationCreateWithURL(output.appendingPathComponent(resource) as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { throw ReadError.message("无法保存 PDF 页面") }
                CGImageDestinationAddImage(destination, cg, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
                guard CGImageDestinationFinalize(destination) else { throw ReadError.message("PDF 页面保存失败") }
                let bounds = page.bounds(for: .cropBox)
                var regions: [PDFTextRegion] = []; var offset = 0
                let nsText = raw as NSString
                if page.rotation % 360 == 0 && bounds.width > 0 && bounds.height > 0 {
                    for item in items {
                        let range = nsText.range(of: item.original, options: [], range: NSRange(location: offset, length: nsText.length - offset))
                        guard range.location != NSNotFound else { continue }; offset = NSMaxRange(range)
                        guard let selection = page.selection(for: range) else { continue }
                        for line in selection.selectionsByLine() {
                            let rect = line.bounds(for: page).intersection(bounds)
                            if !rect.isEmpty { regions.append(PDFTextRegion(sentenceID: item.id, text: line.string ?? item.original, x: (rect.minX - bounds.minX) / bounds.width, y: (bounds.maxY - rect.maxY) / bounds.height, width: rect.width / bounds.width, height: rect.height / bounds.height)) }
                        }
                    }
                }
                blocks.append(ReadingBlock(kind: "pdfPage", sentenceIDs: items.map(\.id), imageResource: resource, alt: "原始 PDF · 第 \(pageIndex + 1) 页", pageNumber: pageIndex + 1, aspectRatio: Double(cg.width) / Double(cg.height), regions: regions))
            }
            chapters.append(Chapter(title: start.title, sentences: content, blocks: blocks))
        }
        var toc = hasOutline ? bookmarks.compactMap { bookmark -> TOCEntry? in
            guard let index = starts.lastIndex(where: { $0.page <= bookmark.page }) else { return nil }
            return TOCEntry(title: bookmark.title, chapterIndex: index, depth: bookmark.depth)
        } : chapters.enumerated().map { TOCEntry(title: $0.element.title, chapterIndex: $0.offset) }
        if hasOutline, starts.first?.title == "封面与前言" { toc.insert(TOCEntry(title: "封面与前言", chapterIndex: 0), at: 0) }
        var book = Book(title: url.deletingPathExtension().lastPathComponent, chapters: chapters, tableOfContents: toc)
        // A PDF without bookmarks uses pages as chapter units rather than inventing chapter boundaries.
        book.format = hasOutline ? "pdf" : "pdf-pages"
        book.coverResource = chapters.first?.blocks?.first?.imageResource
        return book
    }

    static func run(_ executable: String, _ args: [String]) throws -> String {
        let process = Process(); process.executableURL = URL(fileURLWithPath: executable); process.arguments = args
        let pipe = Pipe(); process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        try process.run(); let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw ReadError.message("EPUB 解压失败") }; return String(data: data, encoding: .utf8) ?? ""
    }
}

/// Remove repository front matter only for identifiable Economist publications.
enum EconomistContent {
    static func cleaned(_ source: Book, publicationTitle: String? = nil) -> Book {
        let title = (publicationTitle ?? source.title).lowercased()
        guard source.economistIssueID != nil || title.contains("economist") || title.contains("经济学人") else { return source }
        func normalized(_ text: String) -> String { text.lowercased().filter { !$0.isWhitespace } }
        let promotions = Set(source.chapters.indices.filter { normalized(source.chapters[$0].title) == "优质app推荐" })
        var removed = promotions
        if let first = source.chapters.first, normalized(first.title) == "第1章" {
            let text = first.sentences.map(\.original).joined(separator: " ").lowercased()
            if promotions.contains(1) || ["the world this week", "leaders", "letters"].allSatisfy({ text.contains($0) }) { removed.insert(0) }
        }
        guard !removed.isEmpty, removed.count < source.chapters.count else { return source }
        var book = source
        book.coverResource = source.effectiveCoverResource
        let retained = source.chapters.indices.filter { !removed.contains($0) }
        let indices = Dictionary(uniqueKeysWithValues: retained.enumerated().map { ($0.element, $0.offset) })
        book.chapters = retained.map { source.chapters[$0] }
        book.tableOfContents = source.tableOfContents.map { entries in entries.compactMap { entry in
            guard let index = indices[entry.chapterIndex] else { return nil }
            var copy = entry; copy.chapterIndex = index; return copy
        } }
        book.chapterIndex = indices[source.chapterIndex] ?? 0
        let ids = Set(book.tocOutline.entries.map(\.id))
        book.readTOCEntryIDs = source.readTOCEntryIDs.map { $0.filter { ids.contains($0) } }
        book.collapsedTOCEntryIDs = source.collapsedTOCEntryIDs.map { $0.filter { ids.contains($0) } }
        book.selectedTOCEntryID = source.selectedTOCEntryID.flatMap { ids.contains($0) ? $0 : nil }
        let titles = Set(book.tocOutline.entries.map(\.title))
        book.titleTranslations = source.titleTranslations.map { $0.filter { titles.contains($0.key) } }
        return book
    }
}
