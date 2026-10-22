import SwiftUI

struct DailyQuoteView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var quote = DailyQuote.current()
    private let accent = Color(red: 0.27, green: 0.43, blue: 0.32)
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Rectangle().fill(accent.opacity(0.45)).frame(width: 24, height: 1)
                    Text("每日一言").font(.system(size: 10, weight: .medium)).tracking(3).foregroundStyle(accent)
                    Spacer()
                    Text(context.date, format: .dateTime.month().day()).font(.system(size: 10)).foregroundStyle(.tertiary)
                }.padding(.bottom, 26)
                Image(systemName: "quote.opening").font(.system(size: 36, weight: .light)).foregroundStyle(accent.opacity(0.22)).accessibilityHidden(true).padding(.bottom, 12)
                Text(quote.english).font(.custom("Iowan Old Style", size: 28)).lineSpacing(6).foregroundStyle(.primary.opacity(0.85)).fixedSize(horizontal: false, vertical: true)
                Text(quote.chinese).font(.custom("Songti SC", size: 15)).lineSpacing(5).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).padding(.top, 20)
                Link(destination: URL(string: quote.source)!) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(quote.author).font(.system(size: 11, weight: .medium))
                        Text(quote.work).font(.custom("Iowan Old Style", size: 12).italic()).foregroundStyle(.secondary)
                    }
                }.foregroundStyle(accent).help("查看原文出处").padding(.top, 28)
            }.padding(.horizontal, 8)
                .onChange(of: DailyQuote.dayKey(context.date)) { _, _ in quote = DailyQuote.current(at: context.date) }
        }.onChange(of: scenePhase) { _, phase in if phase == .active { quote = DailyQuote.current() } }
    }
}
