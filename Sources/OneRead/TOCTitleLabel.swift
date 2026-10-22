import SwiftUI

/// Uses the same English and Chinese serif families as Reader.html, with a quieter sidebar scale.
struct TOCTitleLabel: View {
    let original: String
    let translation: String
    let bodySize: Int
    var active = false
    private var size: CGFloat { max(12, min(20, CGFloat(bodySize) - 4)) }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(original)
                .font(.custom("Iowan Old Style", size: size).weight(active ? .semibold : .regular))
                .foregroundStyle(Color.primary.opacity(active ? 1 : 0.86))
            if !translation.isEmpty && translation != original {
                Text(translation)
                    .font(.custom("Songti SC", size: size - 1))
                    .foregroundStyle(Color.primary.opacity(active ? 0.8 : 0.6))
            }
        }.lineSpacing(2).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
