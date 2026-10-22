import SwiftUI

struct MagazineImportView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var magazines: ForeignMagazines
    @State var kind: MagazineKind
    var onOpen: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            Picker("刊物", selection: $kind) {
                ForEach(MagazineKind.allCases) { Text($0.name).tag($0) }
            }.pickerStyle(.segmented).labelsHidden().padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 6).disabled(store.busy)
            EconomistView(onOpen: onOpen).environmentObject(store).environmentObject(magazines.library(kind)).id(kind)
        }.frame(width: 820).interactiveDismissDisabled(magazines.libraries.contains { $0.importingID != nil })
    }
}
