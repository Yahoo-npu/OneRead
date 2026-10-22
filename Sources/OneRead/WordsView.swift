import SwiftUI

struct VocabularyButton: View {
    let count: Int
    var action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    private var ink: Color { colorScheme == .dark ? Color(red: 0.65, green: 0.78, blue: 0.67) : Color(red: 0.32, green: 0.49, blue: 0.37) }
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "book.closed").font(.system(size: 12, weight: .medium))
                Text("生词本").font(.system(size: 12, weight: .medium))
                if count > 0 { Text("\(count)").font(.system(size: 10, weight: .semibold)).monospacedDigit().padding(.horizontal, 5).padding(.vertical, 2).background(ink.opacity(0.1), in: Capsule()) }
            }.foregroundStyle(ink).padding(.horizontal, 10).padding(.vertical, 7)
                .background(ink.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(ink.opacity(0.12), lineWidth: 0.5))
        }.buttonStyle(.plain).help("打开生词本 · \(count) 个在学生词").accessibilityLabel("生词本，\(count) 个在学生词")
    }
}

struct WordsView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    @State private var query = ""
    @State private var group: String
    @State private var archived = false
    @State private var pendingDelete: Word?
    @State private var showExamSources = false
    @Environment(\.colorScheme) private var colorScheme
    private var accent: Color { colorScheme == .dark ? Color(red: 0.65, green: 0.78, blue: 0.67) : Color(red: 0.32, green: 0.49, blue: 0.37) }
    init(initialBookID: String? = nil) { _group = State(initialValue: initialBookID.map { "book:" + $0 } ?? "all") }
    private var books: [VocabularyBook] { Vocabulary.books(in: store.library) }
    private var visibleBooks: [VocabularyBook] { books.filter { !Vocabulary.words(in: store.library, group: "book:" + $0.id, archived: archived, query: "").isEmpty } }
    private var selectedBookID: String? { group.hasPrefix("book:") ? String(group.dropFirst(5)) : nil }
    private var entries: [Word] { Vocabulary.words(in: store.library, group: group, archived: archived, query: query) }
    private var heading: String { if let selectedBookID { return books.first { $0.id == selectedBookID }?.title ?? "书籍生词" }; return group == "uncategorized" ? "未分类生词" : "全部生词" }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "book.closed").font(.system(size: 22, weight: .light)).foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 4) { Text("我的生词本").font(.system(size: 21, weight: .semibold)); Text("阅读里的每一次积累").font(.system(size: 11)).foregroundStyle(.secondary) }
                Spacer()
                Button { showExamSources = true } label: { Label("词表说明", systemImage: "info.circle") }
                    .popover(isPresented: $showExamSources) { examSources }
                Button(action: store.sync) { Label(store.busy ? "同步中…" : "同步墨墨", systemImage: "arrow.triangle.2.circlepath") }
                    .disabled(store.busy || store.library.words.isEmpty).help("同步全部书籍中的生词，包含归档词；当前筛选不影响同步。")
                Button("完成") { store.pronunciation.stop(); dismiss() }.keyboardShortcut(.defaultAction)
            }.padding(.horizontal, 24).padding(.vertical, 20)
            Divider()
            HStack(spacing: 0) {
                sidebar.frame(width: 190)
                Divider()
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 5) { Text(heading).font(.system(size: 15, weight: .semibold)).lineLimit(1); Text("\(entries.count) 个生词").font(.system(size: 11)).foregroundStyle(.secondary) }
                        Spacer()
                        Picker("收纳状态", selection: $archived) { Text("在学").tag(false); Text("已归档").tag(true) }.pickerStyle(.segmented).labelsHidden().frame(width: 156)
                    }.padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 14)
                    HStack(spacing: 7) { Image(systemName: "magnifyingglass").foregroundStyle(.secondary); TextField("搜索单词、释义或出处", text: $query).textFieldStyle(.plain); if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain).help("清空搜索") } }
                        .font(.system(size: 12)).padding(10).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8)).padding(.horizontal, 22).padding(.bottom, 14)
                    if entries.isEmpty {
                        VStack(spacing: 13) {
                            Image(systemName: archived ? "archivebox" : "bookmark").font(.system(size: 30, weight: .ultraLight)).foregroundStyle(accent.opacity(0.7))
                            Text(query.isEmpty ? (archived ? "还没有归档生词" : "这里还没有生词") : "没有找到匹配的生词").font(.system(size: 15, weight: .medium))
                            Text(query.isEmpty ? "阅读时划选单词，点击“加入生词本”。\n可通过每行右侧菜单按书籍收纳。" : "试试其他关键词，或切换书籍分类。").font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(5)
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(entries) { entry in
                                    wordRow(entry)
                                    Divider().padding(.leading, 22).padding(.trailing, 22)
                                }
                            }.padding(.bottom, 12)
                        }
                    }
                }.frame(maxWidth: .infinity).background(Color(nsColor: .textBackgroundColor))
            }
            Divider()
            HStack(spacing: 8) {
                if store.busy { ProgressView().controlSize(.mini) }
                Text(store.status).lineLimit(1)
                Spacer()
                Text("分类与归档仅整理本地词汇，墨墨同步包含全部生词").lineLimit(1)
            }.font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal, 24).padding(.vertical, 12)
        }.frame(width: 1000, height: 670).background(Color(nsColor: .windowBackgroundColor))
            .onAppear { validateSelectedGroup() }
            .onChange(of: visibleBooks.map(\.id)) { _ in validateSelectedGroup() }
            .onDisappear { store.pronunciation.stop() }
            .confirmationDialog("删除这个生词？", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
                Button("删除生词", role: .destructive) { if let pendingDelete { store.deleteWord(pendingDelete.id) }; pendingDelete = nil }
                Button("取消", role: .cancel) { pendingDelete = nil }
            } message: { Text("只移除本地生词，不会删除墨墨云词本中的内容。") }
    }
    private var examSources: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("考试词表标签").font(.system(size: 16, weight: .semibold))
            Text("按本地词表实际收录情况匹配，可同时出现多个标签；支持原形匹配。没有标签仅表示未匹配当前词表，并不代表考试不涉及该词。").font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ForEach(VocabularyExam.allCases) { exam in
                HStack(spacing: 8) {
                    examBadge(exam)
                    Text("\(ExamVocabulary.shared.count(for: exam)) 词条").font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    Link("词表来源 ↗", destination: exam.sourceURL).font(.system(size: 11))
                }.help(exam.sourceDescription)
            }
            Divider()
            Text("以上为社区整理的考试参考词表，不等同于官方最新版完整大纲；IELTS、TOEFL 使用备考词表。各词表独立匹配，不自动把四级词标为六级词。标签不写入墨墨云词本。").font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("离线词表版本：\(ExamVocabulary.shared.version)").font(.system(size: 10)).foregroundStyle(.tertiary)
        }.padding(20).frame(width: 370)
    }
    private func examBadge(_ exam: VocabularyExam) -> some View {
        let color: Color = {
            switch exam {
            case .cet4: return .blue
            case .cet6: return .teal
            case .postgraduate: return Color(red: colorScheme == .dark ? 0.92 : 0.66, green: colorScheme == .dark ? 0.57 : 0.28, blue: colorScheme == .dark ? 0.57 : 0.32)
            case .ielts: return .purple
            case .toefl: return Color(red: colorScheme == .dark ? 0.91 : 0.61, green: colorScheme == .dark ? 0.72 : 0.44, blue: colorScheme == .dark ? 0.40 : 0.15)
            }
        }()
        return Text(exam.rawValue).font(.system(size: 9, weight: .medium)).fixedSize()
            .foregroundStyle(color).padding(.horizontal, 6).padding(.vertical, 3)
            .background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(color.opacity(0.16), lineWidth: 0.5))
            .help("收录于" + exam.sourceDescription + "；可点击顶部“词表说明”查看依据")
            .accessibilityLabel(exam.rawValue + "词表收录")
    }
    private func validateSelectedGroup() {
        if let selectedBookID, !visibleBooks.contains(where: { $0.id == selectedBookID }) { group = "all" }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 5) {
            groupButton("全部生词", icon: "square.stack", id: "all")
            groupButton("未分类", icon: "tray", id: "uncategorized")
            Text("按书籍查看").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary).padding(.horizontal, 12).padding(.top, 22).padding(.bottom, 6)
            ScrollView {
                LazyVStack(spacing: 4) { ForEach(visibleBooks) { book in groupButton(book.title, icon: "book.closed", id: "book:" + book.id) } }
            }
        }.padding(12).padding(.top, 10).frame(maxHeight: .infinity, alignment: .top)
    }
    private func groupButton(_ title: String, icon: String, id: String) -> some View {
        let count = Vocabulary.words(in: store.library, group: id, archived: archived, query: "").count
        return Button { group = id } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: icon).font(.system(size: 12)).frame(width: 15)
                Text(title).font(.system(size: 12)).lineLimit(2).multilineTextAlignment(.leading)
                Spacer(minLength: 2)
                Text("\(count)").font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
            }.padding(.horizontal, 10).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(group == id ? accent : Color.primary.opacity(0.75))
                .background(group == id ? accent.opacity(0.09) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).help(title)
    }
    private func wordRow(_ entry: Word) -> some View {
        let tags = ExamVocabulary.shared.tags(for: entry)
        let source = entry.source(in: selectedBookID)
        let meaning = entry.conciseMeaning(in: selectedBookID)
        let pos = entry.partOfSpeech(in: selectedBookID)
        let ipa = source?.ipaUS ?? entry.dictionary?.ipaUS ?? ""
        let provenance = source.map { "《\($0.bookTitle)》 · " + ($0.chapterTitle ?? "未记录文章") } ?? "历史收录 · 未记录出处"
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                Text(entry.spelling).font(.custom("Iowan Old Style", size: 19).weight(.semibold)).lineLimit(1).frame(width: 126, alignment: .leading).help(entry.spelling).textSelection(.enabled)
                Text(ipa.isEmpty ? "音标暂缺" : ipa).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1).frame(maxWidth: 138, alignment: .leading)
                Button { store.speakWord(entry.spelling) } label: { Image(systemName: "speaker.wave.2").font(.system(size: 13)).foregroundStyle(accent).frame(width: 23, height: 24) }
                    .buttonStyle(.plain).disabled(!DictionaryLookup.isWord(entry.spelling)).help("朗读单词").accessibilityLabel("朗读 \(entry.spelling)")
                if !pos.isEmpty { Text(pos).font(.system(size: 11, weight: .medium)).foregroundStyle(accent).lineLimit(1).padding(.horizontal, 5).padding(.vertical, 3).background(accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 4)).help(pos) }
                Text(meaning).font(.custom("Songti SC", size: 15)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading).help(meaning).textSelection(.enabled)
                Button { store.setWordArchived(entry.id, archived: !entry.isArchived) } label: { Image(systemName: entry.isArchived ? "arrow.uturn.backward" : "archivebox").font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 22, height: 24) }.buttonStyle(.plain).help(entry.isArchived ? "移回在学" : "归档收纳（仍会同步墨墨）")
                Menu {
                    Menu("书籍分类（可多选）") {
                        ForEach(books) { book in
                            Button { store.setWordCollection(entry.id, bookID: book.id) } label: { if entry.collectionIDs.contains(book.id) { Label(book.title, systemImage: "checkmark") } else { Text(book.title) } }
                        }
                        Divider(); Button("移至未分类") { store.setWordCollection(entry.id, bookID: nil) }
                    }
                    Button(entry.isArchived ? "移回在学" : "归档收纳") { store.setWordArchived(entry.id, archived: !entry.isArchived) }
                    Divider(); Button("删除生词", role: .destructive) { pendingDelete = entry }
                } label: { Image(systemName: "ellipsis").font(.system(size: 14, weight: .semibold)).foregroundStyle(accent).frame(width: 28, height: 26).background(accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 6)) }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("整理生词").accessibilityLabel("整理生词：" + entry.spelling)
            }
            HStack(spacing: 8) {
                Text(provenance).lineLimit(1).help(provenance + (source?.context.isEmpty == false ? "\n" + source!.context : ""))
                Spacer(minLength: 6)
                Text(source?.collectedAt ?? entry.created, format: .dateTime.year().month().day().hour().minute()).fixedSize()
            }.font(.system(size: 10)).foregroundStyle(.secondary)
            HStack(spacing: 5) {
                if tags.isEmpty {
                    Text(ExamVocabulary.shared.isAvailable ? "未匹配考试词表" : "考试词表暂不可用").font(.system(size: 9)).foregroundStyle(.tertiary)
                } else {
                    ForEach(tags) { exam in examBadge(exam) }
                }
            }
        }.padding(.horizontal, 22).padding(.vertical, 15)
    }
}
