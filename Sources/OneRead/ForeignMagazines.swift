import SwiftUI
import Combine

@MainActor final class ForeignMagazines: ObservableObject {
    let libraries: [EconomistLibrary]
    private var started = false
    private var subscriptions = Set<AnyCancellable>()
    init(libraries: [EconomistLibrary]? = nil) {
        self.libraries = libraries ?? MagazineKind.allCases.map { EconomistLibrary(repository: EconomistRepository(kind: $0)) }
        for library in self.libraries {
            library.objectWillChange.receive(on: RunLoop.main).sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
        }
    }
    func library(_ kind: MagazineKind) -> EconomistLibrary { libraries.first { $0.kind == kind }! }
    func pending(in library: Library) -> EconomistIssue? { libraries.compactMap(\.pendingIssue).first { EconomistLibrary.shouldNotify($0, library: library) } }
    func start(store: Store) async {
        guard !started else { return }; started = true
        for library in libraries { await library.start(store: store, performRefresh: false); library.checking = true }
        do {
            let etags = libraries.compactMap { $0.catalog?.rootETag }
            let previous = etags.count == libraries.count && Set(etags).count == 1 ? libraries[0].catalog : nil
            let root = try await libraries[0].repository.root(previous: previous)
            for library in libraries { library.checking = false }
            await withTaskGroup(of: Void.self) { group in
                for library in libraries { group.addTask { await library.refresh(store: store, root: root) } }
            }
        } catch {
            for library in libraries { library.checking = false; library.catalogError = "暂时无法检查更新：" + error.localizedDescription }
        }
    }

}

