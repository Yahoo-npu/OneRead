import SwiftUI
import UniformTypeIdentifiers

private struct FolderEditRequest: Identifiable { let id = UUID(); var folder: ShelfFolder?; var bookID: String? }

struct ShelfHomeView: View {
    @EnvironmentObject var store: Store
    @State private var folderID: String?
    @State private var showRecent = false
    @AppStorage("shelf.quote.width") private var quoteWidth = 400.0
    @AppStorage("shelf.quote.collapsed") private var quoteCollapsed = false
    @State private var quoteDragOrigin: Double?
    private func panelWidth(_ available: CGFloat) -> Double { min(max(quoteWidth.isFinite ? quoteWidth : 400, 280), min(620, max(280, available - 500))) }
    private func quoteDivider(available: CGFloat) -> some View {
        ZStack {
            Rectangle().fill(Color.primary.opacity(0.07)).frame(width: 1, height: 240)
            Capsule().fill(Color.secondary.opacity(0.35)).frame(width: 3, height: 30)
        }.frame(width: 18, height: 280).contentShape(Rectangle())
            .onHover { hovering in if hovering { NSCursor.resizeLeftRight.set() } else { NSCursor.arrow.set() } }
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("shelfQuoteResize")).onChanged { value in
                if quoteDragOrigin == nil { quoteDragOrigin = panelWidth(available) }
                quoteWidth = min(max((quoteDragOrigin ?? 400) - value.translation.width, 280), min(620, max(280, available - 500)))
            }.onEnded { _ in quoteDragOrigin = nil; NSCursor.arrow.set() })
            .accessibilityElement().accessibilityLabel("调整每日一言宽度").accessibilityValue("\(Int(panelWidth(available))) 点")
            .accessibilityAdjustableAction { direction in
                switch direction { case .increment: quoteWidth = min(panelWidth(available) + 30, min(620, max(280, available - 500))); case .decrement: quoteWidth = max(280, panelWidth(available) - 30); @unknown default: break }
            }.help("左右拖动，调整每日一言宽度")
    }
    @State private var showTrash = false
    @State private var editor: FolderEditRequest?
    @State private var deletingFolder: ShelfFolder?
    var onOpen: (Book) -> Void
    private var folders: [ShelfFolder] { store.library.folders ?? [] }
    private var activeFolder: ShelfFolder? { folders.first { $0.id == folderID } }
    private var width: Double { ShelfOrganization.coverWidth(store.library.preferences) }
    private var recent: [Book] { ShelfOrganization.recent(in: store.library) }
    private var loose: [Book] { store.library.books.filter { book in !folders.contains { $0.id == book.shelfFolderID } } }
    private var books: [Book] { if showRecent { return recent }; if let folder = activeFolder { return ShelfOrganization.members(folder, library: store.library) }; return loose }
    private func open(_ book: Book) { store.recordReading(book.id); onOpen(book) }
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header
            GeometryReader { geometry in
                ScrollView {
                    if activeFolder == nil && !showRecent && !quoteCollapsed && geometry.size.width >= 900 {
                        HStack(alignment: .top, spacing: 16) {
                            shelfContent.frame(maxWidth: .infinity, alignment: .leading)
                            quoteDivider(available: geometry.size.width).padding(.top, 76)
                            DailyQuoteView().frame(width: panelWidth(geometry.size.width)).padding(.top, 76).padding(.trailing, 12)
                        }.padding(.bottom, 24)
                    } else {
                        VStack(alignment: .leading, spacing: 32) {
                            if activeFolder == nil && !showRecent && !quoteCollapsed { DailyQuoteView().frame(maxWidth: 620).frame(maxWidth: .infinity).padding(.vertical, 18) }
                            shelfContent
                        }.padding(.bottom, 24)
                    }
                }
            }
            HStack { if store.busy { ProgressView().controlSize(.mini) }; Text(store.status).lineLimit(1); Spacer() }.font(.system(size: 10)).foregroundStyle(.secondary)
        }.coordinateSpace(name: "shelfQuoteResize").padding(32).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .alert("删除分类？", isPresented: Binding(get: { deletingFolder != nil }, set: { if !$0 { deletingFolder = nil } }), presenting: deletingFolder) { folder in
                Button("取消", role: .cancel) { deletingFolder = nil }
                Button("删除分类", role: .destructive) { if store.deleteFolder(folder.id) { if folderID == folder.id { folderID = nil } }; deletingFolder = nil }
            } message: { folder in Text("删除《\(folder.name)》后，其中的读物将移至未分类。书籍、阅读进度和生词均会保留。") }
            .sheet(isPresented: $showTrash) { DeletedBooksView().environmentObject(store) }
            .sheet(item: $editor) { request in
                ShelfFolderEditor(folder: request.folder) { id in if let bookID = request.bookID { store.moveBook(bookID, to: id) } }.environmentObject(store)
            }
    }
    private var shelfContent: some View {
                VStack(alignment: .leading, spacing: 30) {
                    if activeFolder == nil && !showRecent {
                        if !recent.isEmpty { recentSection }
                        sectionTitle("分类", detail: "\(folders.count) 个分类")
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                            ForEach(folders) { folder in
                                Button { folderID = folder.id } label: { FolderCard(folder: folder, width: width).environmentObject(store) }.buttonStyle(.plain)
                                    .accessibilityLabel("打开分类《\(folder.name)》")
                                    .contextMenu {
                                        Button("编辑分类…") { editor = FolderEditRequest(folder: folder) }
                                        Button("删除分类…", role: .destructive) { deletingFolder = folder }.disabled(store.busy || store.translating)
                                    }
                            }
                        }
                        if !loose.isEmpty { sectionTitle("未分类读物", detail: "右键移入分类") }
                    }
                    if !books.isEmpty { bookGrid }
                    else if activeFolder != nil || showRecent { emptyState }
                    if store.library.books.isEmpty && activeFolder == nil && !showRecent {
                        HStack { Text("导入期刊，开始积累你的阅读。").foregroundStyle(.secondary); Spacer(); Button("导入读物…", action: store.importBook).disabled(store.busy) }.padding(20).background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
                    }
                }.padding(.bottom, 24)
    }
    private var columns: [GridItem] { [GridItem(.adaptive(minimum: width, maximum: width), spacing: 24, alignment: .top)] }
    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            if activeFolder != nil || showRecent {
                HStack(spacing: 8) { Button { folderID = nil; showRecent = false } label: { Label("我的书架", systemImage: "chevron.left") }.buttonStyle(.plain); Text("/").foregroundStyle(.tertiary); Text(activeFolder?.name ?? "最近阅读").foregroundStyle(.secondary) }.font(.system(size: 12))
            }
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(activeFolder?.name ?? (showRecent ? "最近阅读" : "我的书架")).font(.system(size: 27, weight: .semibold))
                    Text(activeFolder != nil ? "\(books.count) 本期刊 · 慢慢读，常常读" : (showRecent ? "按最近打开的时间排列" : "\(store.library.books.count) 本读物 · 让阅读成为日常")).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 10)
                if activeFolder == nil && !showRecent {
                    Button { withAnimation(.easeInOut(duration: 0.2)) { quoteCollapsed.toggle() } } label: {
                        Image(systemName: "sidebar.right").font(.system(size: 14)).foregroundStyle(quoteCollapsed ? Color.secondary : Color.accentColor).frame(width: 29, height: 29)
                    }.help(quoteCollapsed ? "展开每日一言" : "折叠每日一言").accessibilityLabel(quoteCollapsed ? "展开每日一言" : "折叠每日一言")
                }
                sizeControls
                Divider().frame(height: 25)
                if let folder = activeFolder { Button { editor = FolderEditRequest(folder: folder) } label: { Image(systemName: "slider.horizontal.3") }.help("编辑分类名称") }
                Button { editor = FolderEditRequest() } label: { Image(systemName: "folder.badge.plus") }.help("新建分类").accessibilityLabel("新建分类")
                Button { showTrash = true } label: { Image(systemName: "trash") }.help("最近删除 · \(store.library.trash?.count ?? 0)").accessibilityLabel("最近删除，\(store.library.trash?.count ?? 0) 本")
            }.buttonStyle(.plain)
        }
    }
    private var sizeControls: some View {
        HStack(spacing: 2) {
            ForEach(Array(ShelfOrganization.sizes.enumerated()), id: \.offset) { index, size in
                let title = ["小封面", "中封面", "大封面"][index]
                Button { let previous = store.library.preferences.shelfCoverWidth; store.library.preferences.shelfCoverWidth = size; if !store.save() { store.library.preferences.shelfCoverWidth = previous } } label: {
                    Image(systemName: ["square.grid.3x3", "square.grid.2x2", "square"][index]).font(.system(size: 13)).frame(width: 31, height: 29)
                        .foregroundStyle(width == size ? Color.accentColor : Color.secondary)
                        .background(width == size ? Color.accentColor.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                }.buttonStyle(.plain).help(title).accessibilityLabel(title).accessibilityAddTraits(width == size ? .isSelected : [])
            }
        }.padding(3).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
    }
    private func sectionTitle(_ title: String, detail: String) -> some View {
        HStack { Text(title).font(.system(size: 15, weight: .semibold)); Spacer(); Text(detail).font(.system(size: 11)).foregroundStyle(.secondary) }
    }
    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("最近阅读").font(.system(size: 15, weight: .semibold)); Spacer(); Button("查看全部") { showRecent = true }.font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(.secondary) }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(Array(recent.prefix(6))) { book in
                        Button { open(book) } label: {
                            HStack(spacing: 13) {
                                BookCover(book: book, assetsRoot: store.assetsRoot).frame(width: 54, height: 72)
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(book.title).font(.system(size: 12, weight: .medium)).lineLimit(2).frame(width: 160, alignment: .leading)
                                    Text("已读 \(book.readingProgress.percentage)%").font(.system(size: 10)).foregroundStyle(.secondary)
                                    if let date = book.lastReadAt { Text(date, format: .dateTime.month().day().hour().minute()).font(.system(size: 9)).foregroundStyle(.tertiary) }
                                }
                            }.padding(12).background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.045), lineWidth: 0.5))
                        }.buttonStyle(.plain).help("继续阅读《\(book.title)》")
                    }
                }.padding(.bottom, 2)
            }
        }
    }
    private var bookGrid: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 25) {
            ForEach(books) { book in
                BookCard(book: book, assetsRoot: store.assetsRoot, coverHeight: width * 1.34,
                         categories: folders.map(\.name), currentCategory: folders.first { $0.id == book.shelfFolderID }?.name, onCategory: { name in store.moveBook(book.id, to: folders.first { $0.name == name }?.id) },
                         onCustomCategory: { editor = FolderEditRequest(bookID: book.id) }, deletingDisabled: store.busy,
                         onOpen: { open(book) }, onDelete: { store.deleteBook(book.id) })
            }
        }
    }
    private var emptyState: some View {
        VStack(spacing: 12) { Image(systemName: showRecent ? "clock" : "folder").font(.system(size: 32, weight: .ultraLight)); Text(showRecent ? "还没有最近阅读记录" : "分类还是空的").font(.system(size: 15)); Text("在书籍的右键菜单中，选择移入分类。").font(.system(size: 12)) }.foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 70)
    }
}

private struct FolderCard: View {
    @EnvironmentObject var store: Store
    var folder: ShelfFolder
    var width: Double
    private var members: [Book] { ShelfOrganization.members(folder, library: store.library) }
    private var covers: [Book] { ShelfOrganization.mosaicBooks(folder, library: store.library) }
    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            GeometryReader { geometry in
                let cell = (geometry.size.width - 32) / 3
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(cell), spacing: 5), count: 3), spacing: 5) {
                    ForEach(0..<9, id: \.self) { index in
                        Group {
                            if index < covers.count { BookCover(book: covers[index], assetsRoot: store.assetsRoot) }
                            else { RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.035)) }
                        }.frame(width: cell, height: cell * 1.34).clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }.padding(11)
            }.frame(height: (width - 32) * 1.34 + 32)
                .background(Color.accentColor.opacity(0.045), in: RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.accentColor.opacity(0.12), lineWidth: 0.7))
            HStack(spacing: 6) { Image(systemName: "square.grid.2x2.fill").font(.system(size: 10)).foregroundStyle(Color.accentColor.opacity(0.75)); Text(folder.name).font(.system(size: 13, weight: .medium)).lineLimit(1); Spacer(minLength: 2) }
            Text("\(members.count) 本读物").font(.system(size: 11)).foregroundStyle(.secondary)
        }.contentShape(Rectangle())
    }
}

private struct ShelfFolderEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let folder: ShelfFolder?
    var onSaved: (String) -> Void
    @State private var name: String
    @State private var inlineError: String?
    init(folder: ShelfFolder?, onSaved: @escaping (String) -> Void) { self.folder = folder; self.onSaved = onSaved; _name = State(initialValue: folder?.name ?? "") }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label(folder == nil ? "新建分类" : "编辑分类", systemImage: "square.grid.2x2").font(.system(size: 20, weight: .semibold))
            TextField("分类名称", text: $name).textFieldStyle(.roundedBorder)
            Text("分类封面会以九宫格展示最近加入的 9 本读物。").font(.system(size: 12)).foregroundStyle(.secondary)
            if let inlineError { Text(inlineError).font(.system(size: 11)).foregroundStyle(.red) }
            HStack { Spacer(); Button("取消") { dismiss() }.keyboardShortcut(.cancelAction); Button("保存") {
                if let id = store.saveFolder(id: folder?.id, name: name, cover: nil, automatic: true) { onSaved(id); dismiss() } else { inlineError = store.error ?? "分类未保存，请重试"; store.error = nil }
            }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 30).keyboardShortcut(.defaultAction) }
        }.padding(26).frame(width: 400)
    }
}
