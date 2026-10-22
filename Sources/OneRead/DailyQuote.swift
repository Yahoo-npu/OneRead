import Foundation

struct DailyQuote: Identifiable {
    let id: String
    let english: String
    let chinese: String
    let author: String
    let work: String
    let source: String
    static let collection: [DailyQuote] = [
        .init(id: "bacon-reading", english: "Reading maketh a full man.", chinese: "阅读使人充实。", author: "Francis Bacon · 培根", work: "Of Studies", source: "https://www.gutenberg.org/files/575/575-h/575-h.htm"),
        .init(id: "bacon-consider", english: "Read not to contradict and confute; nor to believe and take for granted; nor to find talk and discourse; but to weigh and consider.", chinese: "读书不为反驳，不为盲信，也不为谈资，而是为了权衡与思考。", author: "Francis Bacon · 培根", work: "Of Studies", source: "https://www.gutenberg.org/files/575/575-h/575-h.htm"),
        .init(id: "emerson-enthusiasm", english: "Nothing great was ever achieved without enthusiasm.", chinese: "没有热忱，便成就不了伟业。", author: "Ralph Waldo Emerson · 爱默生", work: "Circles", source: "https://www.gutenberg.org/files/2944/2944-h/2944-h.htm"),
        .init(id: "emerson-trust", english: "Trust thyself: every heart vibrates to that iron string.", chinese: "相信自己：每颗心都随这根坚韧的琴弦共鸣。", author: "Ralph Waldo Emerson · 爱默生", work: "Self-Reliance", source: "https://www.gutenberg.org/files/2944/2944-h/2944-h.htm"),
        .init(id: "thoreau-detail", english: "Our life is frittered away by detail.", chinese: "我们的生命，消磨在琐事之中。", author: "Henry David Thoreau · 梭罗", work: "Walden", source: "https://www.gutenberg.org/files/205/205-h/205-h.htm"),
        .init(id: "thoreau-books", english: "Books are the treasured wealth of the world and the fit inheritance of generations and nations.", chinese: "书籍是世间珍贵的财富，是世代与民族应当继承的遗产。", author: "Henry David Thoreau · 梭罗", work: "Walden", source: "https://www.gutenberg.org/files/205/205-h/205-h.htm")
    ]
    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let day = calendar.dateComponents([.era, .year, .month, .day], from: date)
        return "\(day.era ?? 0)-\(day.year ?? 0)-\(day.month ?? 0)-\(day.day ?? 0)"
    }
    static func current(at date: Date = Date(), defaults: UserDefaults = .standard, calendar: Calendar = .current) -> DailyQuote {
        let day = dayKey(date, calendar: calendar)
        let oldID = defaults.string(forKey: "dailyQuote.id")
        if defaults.string(forKey: "dailyQuote.day") == day, let quote = collection.first(where: { $0.id == oldID }) { return quote }
        let quote = collection.filter { $0.id != oldID }.randomElement() ?? collection[0]
        defaults.set(quote.id, forKey: "dailyQuote.id"); defaults.set(day, forKey: "dailyQuote.day")
        return quote
    }
}
