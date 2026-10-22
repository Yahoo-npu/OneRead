import SwiftUI

struct ReadArticlesView: View {
    @EnvironmentObject var store: Store
    let book: Book
    var onNavigate: (TOCEntry) -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("已读文章 · \(book.readArticles.count)").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
            }.padding(.horizontal, 16).padding(.vertical, 12)
            if book.readArticles.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle").font(.system(size: 26, weight: .ultraLight))
                    Text("还没有已读文章").font(.system(size: 13))
                    Text("在目录中点击标题右侧的小圆圈，\n即可将文章收进这里。").font(.system(size: 11)).multilineTextAlignment(.center).lineSpacing(4)
                }.foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.top, 48)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 5) {
                        ForEach(book.readArticles) { entry in
                            HStack(alignment: .top, spacing: 8) {
                                Button { onNavigate(entry) } label: {
                                    TOCTitleLabel(original: entry.title, translation: book.titleTranslations?[entry.title] ?? "", bodySize: store.library.preferences.fontSize, active: book.chapterIndex == entry.chapterIndex)
                                        .contentShape(Rectangle())
                                }
                                Button {
                                    withAnimation(.easeInOut(duration: 0.15)) { store.markArticleUnread(bookID: book.id, chapterIndex: entry.chapterIndex) }
                                } label: {
                                    Image(systemName: "checkmark.circle.fill").font(.system(size: 13))
                                        .foregroundStyle(Color(red: 0.36, green: 0.53, blue: 0.40)).frame(width: 24, height: 24)
                                }.help("标记为未读，并从已读列表移除").accessibilityLabel("将《\(entry.title)》标记为未读")
                            }.buttonStyle(.plain).padding(12)
                                .background(book.chapterIndex == entry.chapterIndex ? Color(red: 0.36, green: 0.53, blue: 0.40).opacity(0.09) : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                        }
                    }.padding(.horizontal, 8).padding(.bottom, 16)
                }
            }
        }
    }
}
