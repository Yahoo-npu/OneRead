import SwiftUI

struct EconomistView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var economist: EconomistLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var year = "全部年份"
    @State private var query = ""
    var onOpen: () -> Void
    private var years: [String] { Array(Set(economist.issues.map(\.year))).sorted(by: >) }
    private var filtered: [EconomistIssue] { economist.issues.filter { (year == "全部年份" || $0.year == year) && (query.isEmpty || $0.displayDate.contains(query) || $0.date.contains(query)) } }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "newspaper").font(.system(size: 25, weight: .light)).foregroundStyle(Color(red: 0.66, green: 0.28, blue: 0.32))
                VStack(alignment: .leading, spacing: 4) { Text(economist.kind.name).font(.system(size: 22, weight: .semibold)); Text(economist.kind.englishName.uppercased() + " · EPUB").font(.system(size: 10)).tracking(1).foregroundStyle(.secondary) }
                Spacer()
                Link("仓库来源 ↗", destination: economist.kind.webURL).font(.system(size: 11))
                Button { Task { await economist.refresh(store: store) } } label: { Label(economist.checking ? "检查中…" : "刷新", systemImage: "arrow.clockwise") }.disabled(economist.checking)
                Button("完成") { dismiss() }.disabled(economist.importingID != nil).keyboardShortcut(.defaultAction)
            }.padding(24)
            Divider()
            HStack {
                Picker("年份", selection: $year) { Text("全部年份").tag("全部年份"); ForEach(years, id: \.self) { Text($0).tag($0) } }.frame(width: 155)
                HStack { Image(systemName: "magnifyingglass").foregroundStyle(.secondary); TextField("按日期查找，例如 2026.10", text: $query).textFieldStyle(.plain) }.padding(8).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
                Text("\(filtered.count) 期").font(.caption).foregroundStyle(.secondary).frame(width: 40)
            }.padding(.horizontal, 24).padding(.vertical, 16)
            if let error = economist.catalogError { HStack { Image(systemName: "wifi.exclamationmark"); Text(error).fixedSize(horizontal: false, vertical: true); Spacer() }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 24).padding(.bottom, 12) }
            if filtered.isEmpty {
                VStack(spacing: 14) { if economist.checking { ProgressView(); Text("正在连接期刊仓库…") } else { Image(systemName: "newspaper").font(.largeTitle); Text(economist.issues.isEmpty ? "暂未获取到期刊，点击刷新重试" : "没有匹配的期刊") } }.foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filtered) { issue in
                            HStack(spacing: 15) {
                                VStack(spacing: 4) { Text(String(issue.date.suffix(2))).font(.system(size: 23, weight: .light)); Text(String(issue.date.dropFirst(5).prefix(2)) + " 月").font(.system(size: 10)) }.foregroundStyle(Color(red: 0.66, green: 0.28, blue: 0.32)).frame(width: 47, height: 56).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
                                VStack(alignment: .leading, spacing: 7) {
                                    HStack { Text(economist.kind.englishName + " · " + issue.displayDate).font(.custom("Iowan Old Style", size: 17)); if issue.id == economist.issues.first?.id { Text("最新一期").font(.system(size: 9, weight: .medium)).foregroundStyle(.green).padding(.horizontal, 6).padding(.vertical, 3).background(Color.green.opacity(0.08), in: Capsule()) } }
                                    Text("EPUB · " + ByteCountFormatter.string(fromByteCount: Int64(issue.size), countStyle: .file)).font(.system(size: 11)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if economist.importingID == issue.id { ProgressView().controlSize(.small) }
                                else if economist.existingBook(issue, store: store) != nil { Label("已在书架", systemImage: "checkmark.circle").font(.system(size: 11)).foregroundStyle(.secondary) }
                                Button(economist.existingBook(issue, store: store) != nil ? "打开" : (economist.isTrashed(issue, store: store) ? "恢复到书架" : "导入本期")) { economist.beginImport(issue, store: store) }
                                    .disabled(store.busy || store.translating).frame(minWidth: 78)
                            }.padding(.horizontal, 24).padding(.vertical, 13)
                            Divider().padding(.horizontal, 24)
                        }
                    }
                }
            }
            if let error = economist.importError { HStack { Image(systemName: "exclamationmark.circle"); Text(error).textSelection(.enabled); Spacer() }.font(.system(size: 12)).foregroundStyle(.red).padding(16) }
            Divider()
            HStack(spacing: 10) {
                if economist.importingID != nil { ProgressView().controlSize(.small); Text(economist.importPhase).lineLimit(1); Spacer(); Button("取消导入", action: economist.cancelImport) }
                else { Text("每次启动自动检查新刊 · 由你确认后导入"); Spacer(); if let date = economist.catalog?.checkedAt, date.timeIntervalSinceReferenceDate > 0 { Text(date, format: .dateTime.month().day().hour().minute()) } }
            }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 24).padding(.vertical, 14)
        }.frame(width: 820, height: 650).background(Color(nsColor: .windowBackgroundColor))
            .interactiveDismissDisabled(economist.importingID != nil)
            .onChange(of: economist.importedBookID, initial: true) { _, value in if value != nil { onOpen(); dismiss() } }
    }
}
