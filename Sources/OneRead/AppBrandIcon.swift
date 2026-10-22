import SwiftUI

struct AppBrandIcon: View {
    private var icon: NSImage? {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        return bundle.url(forResource: "AppIcon", withExtension: "png").flatMap { NSImage(contentsOf: $0) }
    }
    var body: some View {
        Group {
            if let icon { Image(nsImage: icon).resizable().interpolation(.high).scaledToFit() }
            else { Image(systemName: "book.pages").resizable().scaledToFit().padding(6) }
        }.frame(width: 32, height: 32).accessibilityHidden(true)
    }
}
