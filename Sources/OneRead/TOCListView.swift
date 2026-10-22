import SwiftUI

struct TOCListView: View {
    @EnvironmentObject var store: Store
    let book: Book
    var onNavigate: (TOCEntry) -> Void
    private var outline: TOCOutline { book.tocOutline }
    private var collapsed: Set<String> { Set(book.collapsedTOCEntryIDs ?? []) }
    private var read: Set<String> { Set(book.readTOCEntryIDs ?? []) }
    private var visible: [TOCEntry] { outline.visible(collapsed: collapsed) }
    private var accent: Color { store.library.preferences.theme == "dark" ? Color(red: 0.65, green: 0.78, blue: 0.67) : Color(red: 0.27, green: 0.43, blue: 0.32) }
    private var fontSize: CGFloat { max(12, min(20, CGFloat(store.library.preferences.fontSize) - 4)) }
    private var scrollTarget: String? {
        guard let active = book.activeTOCEntryID else { return nil }
        let visibleIDs = Set(visible.map(\.id))
        return ([active] + outline.ancestors(active).reversed()).first { visibleIDs.contains($0) }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                let progress = book.readingProgress
                Text("已读 \(progress.completed) / \(progress.total)").font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                Spacer()
                if store.titleTranslating.contains(book.id) {
                    ProgressView().controlSize(.mini)
                    Button { store.titleTranslationTasks[book.id]?.cancel() } label: { Image(systemName: "stop.circle") }.help("暂停目录翻译")
                } else {
                    Button { store.translateTitles(bookID: book.id, retry: true) } label: { Image(systemName: "translate") }.help("翻译尚未完成的目录标题").disabled(book.pendingTitleTexts.isEmpty)
                }
                Menu {
                    Button("展开全部") { withAnimation(.easeInOut(duration: 0.18)) { store.setAllTOCCollapsed(bookID: book.id, collapsed: false) } }
                    Button("折叠全部") { withAnimation(.easeInOut(duration: 0.18)) { store.setAllTOCCollapsed(bookID: book.id, collapsed: true) } }
                } label: { Image(systemName: "list.bullet.indent").font(.system(size: 13, weight: .medium)).foregroundStyle(accent).frame(width: 28, height: 26).background(accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 6)) }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("展开或折叠目录").accessibilityLabel("目录展开与折叠")
            }.buttonStyle(.plain).padding(.horizontal, 16).padding(.vertical, 12)
            if let progress = store.titleTranslationProgress[book.id] { Text(progress).font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.bottom, 8) }
            if let message = store.titleTranslationErrors[book.id] {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "info.circle")
                    Text("目录译文未完成，点击翻译按钮继续。").lineLimit(2)
                }.font(.system(size: 11)).foregroundStyle(.secondary).help(message).padding(.horizontal, 16).padding(.bottom, 10)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(visible) { entry in row(entry).id(entry.id) }
                    }.padding(.horizontal, 8).padding(.bottom, 16)
                }
                .onAppear { if let target = scrollTarget { proxy.scrollTo(target, anchor: .center) } }
                .onChange(of: book.activeTOCEntryID) { _, _ in
                    Task { @MainActor in await Task.yield(); if let target = scrollTarget { proxy.scrollTo(target, anchor: .center) } }
                }
            }
        }
        .task(id: book.id) { store.translateTitles(bookID: book.id) }
    }
    private func row(_ entry: TOCEntry) -> some View {
        let subtree = outline.subtree(entry.id)
        let ids = Set(subtree.map(\.id))
        let complete = ids.isSubset(of: read)
        let partial = !complete && !ids.isDisjoint(with: read)
        let hasChildren = subtree.count > 1
        let active = book.activeTOCEntryID == entry.id
        let translation = book.titleTranslations?[entry.title] ?? ""
        return HStack(alignment: .top, spacing: 7) {
            if hasChildren {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { store.toggleTOCCollapse(bookID: book.id, entryID: entry.id) }
                } label: {
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).rotationEffect(.degrees(collapsed.contains(entry.id) ? 0 : 90))
                        .frame(width: 18, height: fontSize * 1.4).contentShape(Rectangle())
                }.accessibilityLabel((collapsed.contains(entry.id) ? "展开：" : "折叠：") + entry.title).help(collapsed.contains(entry.id) ? "展开子标题" : "折叠子标题")
            } else { Color.clear.frame(width: 18, height: 1).accessibilityHidden(true) }
            Button { onNavigate(entry) } label: {
                TOCTitleLabel(original: entry.title, translation: translation, bodySize: store.library.preferences.fontSize, active: active)
                    .contentShape(Rectangle())
            }.opacity(complete && !active ? 0.8 : 1)

            Button {
                withAnimation(.easeInOut(duration: 0.15)) { store.toggleTOCRead(bookID: book.id, entryID: entry.id) }
            } label: {
                Image(systemName: complete ? "checkmark.circle.fill" : (partial ? "minus.circle.fill" : "circle"))
                    .font(.system(size: 13, weight: .regular)).foregroundStyle(complete || partial ? accent : Color.secondary.opacity(0.45))
                    .frame(width: 24, height: fontSize * 1.4).contentShape(Rectangle())
            }.help((complete ? "标记为未读" : "标记为已读") + (hasChildren ? "（包含子标题）" : ""))
                .accessibilityLabel(entry.title + (complete ? "，已读，点击标记未读" : (partial ? "，部分已读，点击全部标记已读" : "，未读，点击标记已读")))
        }.buttonStyle(.plain).padding(.vertical, 9).padding(.leading, 4 + CGFloat(min(max(entry.depth, 0), 4)) * 10).padding(.trailing, 6)
            .background(active ? accent.opacity(0.09) : Color.clear, in: RoundedRectangle(cornerRadius: 9))
    }
}
