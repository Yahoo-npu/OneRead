import SwiftUI
import ImageIO

private enum PreparedCover: Sendable {
    case raster(CGImage)
    case vector(Data)
}
@MainActor private enum CoverImages {
    static let cache: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>(); cache.countLimit = 80; cache.totalCostLimit = 40_000_000; return cache
    }()
    nonisolated static func prepare(_ url: URL) -> PreparedCover? {
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 600] as CFDictionary) { return .raster(thumbnail) }
        if let data = try? Data(contentsOf: url) { return .vector(data) }
        return nil
    }
    static func finish(_ prepared: PreparedCover, url: URL) -> NSImage? {
        let image: NSImage?
        switch prepared { case .raster(let cg): image = NSImage(cgImage: cg, size: .zero); case .vector(let data): image = NSImage(data: data) }
        if let image { cache.setObject(image, forKey: url as NSURL, cost: max(1, Int(image.size.width * image.size.height * 4))) }
        return image
    }
}

struct BookCover: View {
    var book: Book
    var assetsRoot: URL
    @State private var image: NSImage?
    private var url: URL? {
        guard let assetID = book.assetID, let name = book.effectiveCoverResource else { return nil }
        return AssetStore.resource(name, assetID: assetID, root: assetsRoot)
    }
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.035))
            if let image {
                Image(nsImage: image).resizable().scaledToFit().padding(4)
            } else {
                GeometryReader { geometry in
                    VStack(spacing: 18) {
                        Image(systemName: "book.closed").font(.system(size: geometry.size.width < 90 ? 22 : 34, weight: .ultraLight))
                        if geometry.size.width >= 90 { Text(book.title).font(.system(size: 16, design: .serif)).lineLimit(4).multilineTextAlignment(.center) }
                    }.padding(geometry.size.width < 90 ? 6 : 24).frame(width: geometry.size.width, height: geometry.size.height).foregroundStyle(Color.accentColor)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .task(id: url) {
            image = nil
            guard let url else { return }
            if let cached = CoverImages.cache.object(forKey: url as NSURL) { image = cached; return }
            let prepared = await Task.detached(priority: .utility) { CoverImages.prepare(url) }.value
            guard !Task.isCancelled, let prepared else { return }
            image = CoverImages.finish(prepared, url: url)
        }
        .accessibilityHidden(true)
    }
}

struct BookCard: View {
    var book: Book
    var assetsRoot: URL
    var coverHeight: CGFloat = 240
    var categories: [String] = ShelfOrganization.presets
    var currentCategory: String?
    var onCategory: ((String?) -> Void)?
    var onCustomCategory: (() -> Void)?
    var deletingDisabled: Bool
    var onOpen: () -> Void
    var onDelete: () -> Void
    var body: some View {
        let progress = book.readingProgress
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .topTrailing) {
                Button(action: onOpen) { BookCover(book: book, assetsRoot: assetsRoot).frame(height: coverHeight).contentShape(Rectangle()) }
                    .buttonStyle(.plain).accessibilityLabel("阅读《\(book.title)》")
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash").font(.system(size: 12)).padding(8).background(.regularMaterial, in: Circle())
                }.buttonStyle(.plain).padding(7).disabled(deletingDisabled).help("移至最近删除，可恢复").accessibilityLabel("删除《\(book.title)》")
            }
            Button(action: onOpen) { Text(book.title).font(.system(size: 13, weight: .medium)).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(.plain)
            Text("\(book.format?.hasPrefix("pdf") == true ? "PDF" : (book.format == nil ? "文档" : "EPUB")) · \(book.chapters.count) 个章节 / 页面").font(.caption).foregroundStyle(.secondary)
            VStack(spacing: 6) {
                HStack {
                    Text("已读 \(progress.completed) / \(progress.total)")
                    Spacer()
                    Text("\(progress.percentage)%").monospacedDigit()
                }.font(.system(size: 11)).foregroundStyle(.secondary)
                GeometryReader { geometry in
                    Capsule().fill(Color.primary.opacity(0.07))
                    Capsule().fill(Color(red: 0.36, green: 0.53, blue: 0.40)).frame(width: geometry.size.width * progress.fraction)
                }.frame(height: 4)
            }.accessibilityElement(children: .ignore)
                .accessibilityLabel("阅读进度 \(progress.percentage)%，已读 \(progress.completed) / \(progress.total)")
                .help("根据手动已读标记计算；同一章节的重复目录只计一次，翻译完成不计为已读。")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
         .contextMenu {
            Button("阅读", action: onOpen)
            Menu("移入分类") {
                Button("移出分类") { onCategory?(nil) }
                ForEach(categories, id: \.self) { category in
                    Button { onCategory?(category) } label: { if (currentCategory ?? ShelfOrganization.category(for: book)) == category { Label(category, systemImage: "checkmark") } else { Text(category) } }
                }
                Divider(); Button("新建分类…") { onCustomCategory?() }
            }
            Button("删除书籍", role: .destructive, action: onDelete).disabled(deletingDisabled)
        }
    }
}

struct DeletedBooksView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    @State private var pendingDeletion: TrashedBook?
    @State private var clearAll = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("最近删除").font(.title2.bold()); Spacer(); Button("一键清空", role: .destructive) { clearAll = true }.foregroundStyle(.red).disabled((store.library.trash ?? []).isEmpty || store.busy || store.translating); Button("完成") { dismiss() } }
            Text("删除的书籍可在这里恢复，原文图片、译文和阅读章节一并保留。").font(.caption).foregroundStyle(.secondary)
            if (store.library.trash ?? []).isEmpty {
                Spacer(); Text("没有最近删除的书籍").foregroundStyle(.secondary).frame(maxWidth: .infinity); Spacer()
            } else {
                List {
                    ForEach(Array((store.library.trash ?? []).reversed())) { entry in
                        HStack(spacing: 16) {
                            BookCover(book: entry.book, assetsRoot: store.assetsRoot).frame(width: 54, height: 72)
                            VStack(alignment: .leading, spacing: 6) { Text(entry.book.title).font(.headline); Text(entry.deletedAt, style: .date).font(.caption).foregroundStyle(.secondary) }
                            Spacer(); Button("恢复") { store.restoreBook(entry.id) }.buttonStyle(.borderless).disabled(store.busy)
                            Button("彻底删除", role: .destructive) { pendingDeletion = entry }.buttonStyle(.borderless).foregroundStyle(.red).disabled(store.busy || store.translating)
                        }.padding(.vertical, 7)
                    }
                }
            }
        }.padding(24).frame(width: 760, height: 500)
            .confirmationDialog("清空最近删除中的全部 \(store.library.trash?.count ?? 0) 本读物？", isPresented: $clearAll, titleVisibility: .visible) {
                Button("清空全部", role: .destructive) { store.emptyTrash() }
                Button("取消", role: .cancel) { }
            } message: { Text("全部最近删除内容将被永久清理，无法恢复。已收录生词、原始导入文件与墨墨云词本会保留。") }
            .confirmationDialog("彻底删除《\(pendingDeletion?.book.title ?? "")》？", isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }), titleVisibility: .visible) {
                Button("彻底删除", role: .destructive) { if let entry = pendingDeletion { store.permanentlyDeleteBook(entry.id) }; pendingDeletion = nil }
                Button("取消", role: .cancel) { pendingDeletion = nil }
            } message: { Text("将永久移除这本书的本地原文、图片、译文和阅读记录，无法恢复。已收录的生词会保留，原始导入文件与墨墨云词本不受影响。") }
    }
}
