// Creates a separate local UI fixture. It never reads the user's library or Keychain.
import Foundation
import AppKit
import PDFKit
import CoreText

@main struct PreparePreview {
    static func main() throws {
        let workspace = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let directory = CommandLine.arguments.count > 1 ? URL(fileURLWithPath: CommandLine.arguments[1]) : workspace.appendingPathComponent(".build/PreviewFixtures/" + UUID().uuidString)
        guard !FileManager.default.fileExists(atPath: directory.appendingPathComponent("library.json").path) else { throw ReadError.message("预览目录已存在书库，请选择新的独立目录。") }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var book = try Importer.load(workspace.appendingPathComponent("Samples/Illustrated Reading.epub"), assetsRoot: directory.appendingPathComponent("Assets"))
        let chinese: [String: String] = [
            "A Small Reading Habit": "一个小小的阅读习惯",
            "A quiet place to read": "一处安静的阅读角落",
            "Every morning, I open a book before I open my phone.": "每天早晨，我总是先翻开一本书，然后才打开手机。",
            "The room is quiet, and the light falls gently across the page.": "房间里十分安静，光线柔和地洒在书页上。",
            "Reading in another language is an exercise in patience.": "阅读另一种语言，是一场关于耐心的练习。",
            "Some words feel familiar, while others invite us to pause and explore.": "有些词语似曾相识，有些则邀请我们停下脚步，细细探寻。",
            "A notebook can become a map of this journey.": "一本笔记本，可以成为这段旅程的地图。",
            "Each unfamiliar word is a small discovery, connected to a sentence and a moment.": "每个陌生的单词都是一次小小的发现，连接着一个句子，也连接着一个瞬间。"
        ]
        for index in book.chapters[0].sentences.indices { let text = book.chapters[0].sentences[index].original; book.chapters[0].sentences[index].translation = chinese[text] ?? "" }
        // Deliberately different column heights exercise scroll synchronization under momentum.
        for index in 1...24 {
            let items = Importer.sentences("Reading note \(index). Every new page brings a small discovery. Patience and curiosity make a useful pair of companions.")
            let translated = items.map { sentence -> Sentence in var value = sentence; value.translation = "阅读札记 \(index)：每一页都带来一点新的发现。耐心与好奇心，是阅读路上的好伙伴。"; return value }
            book.chapters[0].sentences += translated
            book.chapters[0].blocks?.append(ReadingBlock(kind: "paragraph", sentenceIDs: translated.map(\.id)))
        }
        var library = Library(books: [book]); library.preferences.theme = "light"
        let agent = directory.appendingPathComponent("preview-translator.sh")
        try "#!/bin/sh\ncat >/dev/null\nprintf '本地预览译文：阅读使我们发现更广阔的世界。'\n".write(to: agent, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: agent.path)
        library.preferences.provider = "Agent"; library.preferences.agentPath = agent.path
        try JSONEncoder().encode(library).write(to: directory.appendingPathComponent("library.json"), options: .atomic)

        let pdfURL = workspace.appendingPathComponent("Samples/Illustrated Reading.pdf")
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        let pdf = CGContext(pdfURL as CFURL, mediaBox: &box, nil)!
        for (index, chapter) in ["A Small Reading Habit", "One Page at a Time"].enumerated() {
            pdf.beginPDFPage(nil)
            func text(_ string: String, x: CGFloat, y: CGFloat, size: CGFloat) {
                let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: [.font: NSFont(name: "Georgia", size: size) ?? .systemFont(ofSize: size)]))
                pdf.textPosition = CGPoint(x: x, y: y); CTLineDraw(line, pdf)
            }
            text(chapter, x: 45, y: 770, size: 27)
            let bitmap = CGContext(data: nil, width: 1000, height: 500, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            bitmap.setFillColor(CGColor(red: 0.91, green: 0.94, blue: 0.89, alpha: 1)); bitmap.fill(CGRect(x: 0, y: 0, width: 1000, height: 500))
            bitmap.setFillColor(CGColor(red: 0.43, green: 0.62, blue: 0.45, alpha: 1)); bitmap.fillEllipse(in: CGRect(x: -100, y: -120, width: 1200, height: 480))
            bitmap.setFillColor(CGColor(red: 0.99, green: 0.98, blue: 0.94, alpha: 1)); bitmap.fill(CGRect(x: 250, y: 120, width: 500, height: 240))
            bitmap.setStrokeColor(CGColor(red: 0.3, green: 0.4, blue: 0.3, alpha: 1)); bitmap.setLineWidth(5)
            bitmap.move(to: CGPoint(x: 500, y: 120)); bitmap.addLine(to: CGPoint(x: 500, y: 360)); bitmap.strokePath()
            pdf.draw(bitmap.makeImage()!, in: CGRect(x: 45, y: 430, width: 505, height: 252))
            text("Every morning, I open a book before I open my phone.", x: 45, y: 380, size: 17)
            text("Reading in another language is an exercise in patience.", x: 45, y: 345, size: 17)
            text("Words and images help each other come alive.", x: 45, y: 310, size: 17)
            text("One Read / Illustrated PDF / Page \(index + 1)", x: 45, y: 55, size: 11)
            pdf.endPDFPage()
        }
        pdf.closePDF()
        let document = PDFDocument(url: pdfURL)!
        let root = PDFOutline()
        for (index, title) in ["A Small Reading Habit", "One Page at a Time"].enumerated() {
            let node = PDFOutline(); node.label = title; node.destination = PDFDestination(page: document.page(at: index)!, at: CGPoint(x: 0, y: 842)); root.insertChild(node, at: index)
        }
        document.outlineRoot = root
        guard document.write(to: pdfURL) else { throw ReadError.message("Unable to save PDF fixture") }
        var pdfBook = try Importer.load(pdfURL, assetsRoot: directory.appendingPathComponent("Assets"))
        for c in pdfBook.chapters.indices { for s in pdfBook.chapters[c].sentences.indices { let text = pdfBook.chapters[c].sentences[s].original; pdfBook.chapters[c].sentences[s].translation = chinese[text] ?? "" } }
        library.books.append(pdfBook)
        try JSONEncoder().encode(library).write(to: directory.appendingPathComponent("library.json"), options: .atomic)
        print("Prepared isolated preview library")
    }
}
