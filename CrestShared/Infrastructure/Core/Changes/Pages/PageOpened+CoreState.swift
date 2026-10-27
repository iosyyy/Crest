import Foundation

extension PageOpened {
    @MainActor func apply(to state: CoreState) {
        state.pageOpened(PageStateModel(page))
    }
}
