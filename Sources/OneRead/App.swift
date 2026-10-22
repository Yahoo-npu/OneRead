import SwiftUI
import UniformTypeIdentifiers

@main struct OneReadApp: App {
    @StateObject private var store = Store()
    @StateObject private var magazines = ForeignMagazines()
    var body: some Scene {
        WindowGroup("一读·One Read") { ContentView().environmentObject(store).environmentObject(magazines).frame(minWidth: 1000, minHeight: 680).tint(Color(red: 0.27, green: 0.43, blue: 0.32)).accentColor(Color(red: 0.27, green: 0.43, blue: 0.32)).preferredColorScheme(store.library.preferences.theme == "dark" ? .dark : .light) }
        .defaultSize(width: 1360, height: 860)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) { Button("导入读物…") { store.importBook() }.keyboardShortcut("o") }
            CommandMenu("阅读") {
                Button("解析鼠标悬停的句子") { NotificationCenter.default.post(name: .analyzeHoveredSentence, object: nil) }.keyboardShortcut("t", modifiers: .command)
            }
        }
        Settings { SettingsView().environmentObject(store) }
    }
}
struct ContentView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var magazines: ForeignMagazines
    @State private var magazineKind: MagazineKind = .economist
    @State private var showEconomist = false
    @State private var showWords = false
    @State private var showTrash = false
    @State private var showSettings = false
    @State private var showTOC = true
    @State private var showLibrary = true
    @State private var sidebarTab = "目录"
    @State private var focusSentenceID: String?
    @State private var showAppearance = false

    private var readingBook: Book? { showLibrary ? nil : store.book }
    private var readingMode: Binding<String> { Binding(get: { store.library.preferences.readingMode ?? "bilingual" }, set: { store.library.preferences.readingMode = $0; store.save() }) }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if let issue = magazines.pending(in: store.library) {
                updateBanner(issue)
                Divider()
            }
            if let book = readingBook, book.chapters.indices.contains(book.chapterIndex) {
                HStack(spacing: 0) {
                    if showTOC { chapterSidebar(book).frame(width: min(350, max(270, CGFloat(store.library.preferences.fontSize) * 15))); Divider() }
                    VStack(spacing: 0) {
                        if book.assetID == nil {
                            HStack { Image(systemName: "photo.on.rectangle"); Text("旧版导入内容仅保留了文字，重新载入原文件即可恢复图片与段落。")
                                Spacer(); Button("重新载入原文", action: store.reloadOriginal).disabled(store.busy || store.translating)
                            }.font(.caption).padding(.horizontal, 18).padding(.vertical, 10).background(Color.accentColor.opacity(0.06))
                            Divider()
                        }
                        ReaderView(book: book, chapter: book.chapters[book.chapterIndex], preferences: store.library.preferences, focusSentenceID: focusSentenceID, translating: store.translating && store.translationBookID == book.id && (store.translationChapterID == nil || store.translationChapterID == book.chapters[book.chapterIndex].id), selection: store.selectionPopoverState, onAction: store.handleReaderAction)
                    }

                }
                Divider()
                readingFooter(book)
            } else { libraryView }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .ignoresSafeArea(.container, edges: .top)
        .onChange(of: store.selected) { _, _ in showLibrary = false; store.clearSelection(); focusSentenceID = nil; if let id = store.selected { store.recordReading(id) } }
        .task { if let book = readingBook { store.recordReading(book.id) }; await magazines.start(store: store) }
        .sheet(isPresented: $showEconomist) { MagazineImportView(kind: magazineKind) { showLibrary = false }.environmentObject(store).environmentObject(magazines) }
        .sheet(isPresented: $showTrash) { DeletedBooksView().environmentObject(store) }
        .sheet(isPresented: $showWords) { WordsView(initialBookID: readingBook?.id).environmentObject(store) }
        .sheet(isPresented: $showSettings) { SettingsView().environmentObject(store) }
        .alert("需要留意", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("知道了") { store.error = nil }
        } message: { Text(store.error ?? "") }
    }

    private var toolbar: some View {
        HStack(spacing: 14) {
            if let book = readingBook {
                Button { showLibrary = true; store.clearSelection() } label: { Image(systemName: "arrow.left") }.help("返回书架")
                Button { showTOC.toggle() } label: { Image(systemName: "sidebar.left") }.help("目录与已读文章")
                Divider().frame(height: 20)
                Text(book.title).font(.system(size: 13, weight: .semibold)).lineLimit(1).frame(maxWidth: 260, alignment: .leading)
                Text(book.format?.hasPrefix("pdf") == true ? "PDF" : "EPUB").font(.system(size: 10, weight: .medium)).padding(.horizontal, 7).padding(.vertical, 4).background(.quaternary, in: Capsule())
                Spacer(minLength: 8)
                if store.translating {
                    Button { store.translationTask?.cancel() } label: { Label("停止翻译", systemImage: "stop.circle") }
                } else {
                    Button(action: store.translateChapter) { Label(book.format == "pdf-pages" ? "翻译本页" : "翻译本章", systemImage: "translate") }.disabled(store.busy)
                }
                Picker("阅读模式", selection: readingMode) { Text("仅原文").tag("original"); Text("原文译文").tag("bilingual"); Text("仅译文").tag("translation") }.pickerStyle(.segmented).frame(width: 225).labelsHidden()
                Divider().frame(height: 20)
                VocabularyButton(count: store.library.words.filter { !$0.isArchived }.count) { showWords = true }
                Button { showAppearance.toggle() } label: { Image(systemName: "paintbrush.pointed").font(.system(size: 15)).frame(width: 28, height: 28) }.help("阅读外观").accessibilityLabel("阅读外观").popover(isPresented: $showAppearance) { appearancePanel }
                Menu { Button("翻译全文", action: store.translateAll).disabled(store.busy || store.translating); Button("重新载入原文", action: store.reloadOriginal).disabled(store.busy || store.translating) } label: { Image(systemName: "ellipsis").font(.system(size: 15, weight: .semibold)).frame(width: 30, height: 28).background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 7)) }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("更多阅读操作").accessibilityLabel("更多阅读操作")
                Button { showSettings = true } label: { Image(systemName: "slider.horizontal.3") }.help("翻译与阅读设置")
            } else {
                AppBrandIcon(); Text("一读·One Read").font(.system(size: 15, weight: .semibold)); Spacer()
                Button { openEconomist() } label: { Label("导入外刊", systemImage: "newspaper") }.disabled(store.busy || store.translating)
                Button(action: store.importBook) { Label("导入读物", systemImage: "plus") }.disabled(store.busy || store.translating)
                VocabularyButton(count: store.library.words.filter { !$0.isArchived }.count) { showWords = true }
                Button { showSettings = true } label: { Image(systemName: "slider.horizontal.3") }
            }
        }.buttonStyle(.plain).padding(.leading, 84).padding(.trailing, 20).frame(height: 52)
    }

    private func openEconomist(_ kind: MagazineKind = .economist) { magazineKind = kind; for library in magazines.libraries { library.importedBookID = nil }; showEconomist = true }
    private func updateBanner(_ issue: EconomistIssue) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "newspaper.fill").foregroundStyle(Color(red: 0.66, green: 0.28, blue: 0.32))
            VStack(alignment: .leading, spacing: 3) {
                Text(issue.kind.name + "有新刊 · " + issue.displayDate).font(.system(size: 12, weight: .semibold))
                Text("仓库已更新 EPUB，是否加入书架？").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            Button("查看各期") { openEconomist(issue.kind) }
            Button("暂不导入") { magazines.library(issue.kind).dismissUpdate(store: store) }
            Button("导入本期") { openEconomist(issue.kind); magazines.library(issue.kind).beginImport(issue, store: store) }.disabled(store.busy || store.translating).buttonStyle(.borderedProminent)
        }.padding(.horizontal, 24).padding(.vertical, 12).background(Color.accentColor.opacity(0.055))
    }
    private var appearancePanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("阅读外观").font(.headline)
            Picker("主题", selection: $store.library.preferences.theme) { Text("浅色").tag("light"); Text("纸张").tag("paper"); Text("深色").tag("dark") }.pickerStyle(.segmented)
            Stepper("字号 \(store.library.preferences.fontSize)", value: $store.library.preferences.fontSize, in: 14...30)
        }.padding(22).frame(width: 280).onDisappear { store.save() }
    }

    private func chapterSidebar(_ book: Book) -> some View {
        VStack(spacing: 0) {
            Picker("导航", selection: $sidebarTab) { Text("目录").tag("目录"); Text("已读").tag("已读") }.pickerStyle(.segmented).labelsHidden().padding(14)
            Divider()
            if sidebarTab == "已读" {
                ReadArticlesView(book: book) { entry in store.navigateTOC(entry); focusSentenceID = nil }

            } else {
                TOCListView(book: book) { entry in store.navigateTOC(entry); focusSentenceID = nil }
            }
        }.background(Color(nsColor: .controlBackgroundColor))
    }

    private func readingFooter(_ book: Book) -> some View {
        HStack(spacing: 10) {
            if store.busy || store.translating { ProgressView().controlSize(.small) }
            Text(store.status).lineLimit(1)
            Spacer()
            Button { store.chapter(book.chapterIndex - 1) } label: { Image(systemName: "chevron.left") }.disabled(book.chapterIndex == 0)
            Text("\(book.chapterIndex + 1) / \(book.chapters.count)").monospacedDigit()
            Button { store.chapter(book.chapterIndex + 1) } label: { Image(systemName: "chevron.right") }.disabled(book.chapterIndex + 1 >= book.chapters.count)
        }.font(.system(size: 11)).foregroundStyle(.secondary).buttonStyle(.plain).padding(.horizontal, 18).frame(height: 32)
    }

    private var libraryView: some View {
        ShelfHomeView { book in store.selected = book.id; showLibrary = false }.environmentObject(store)
    }
}
