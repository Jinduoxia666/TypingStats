import Combine
import Foundation

@MainActor
final class TimestampViewModel: ObservableObject {
    @Published var input = ""
    @Published private(set) var selectionIndex = 0
    @Published private(set) var now = Date()

    var items: [TimestampConversionItem] {
        TimestampConversionItem.items(input: input, now: now)
    }

    private var timer: Timer?
    private var onPaste: (TimestampConversionItem) -> Void = { _ in }

    deinit {
        timer?.invalidate()
    }

    func configure(onPaste: @escaping (TimestampConversionItem) -> Void) {
        self.onPaste = onPaste
    }

    func start() {
        timer?.invalidate()
        now = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.now = Date() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func select(at index: Int) {
        let values = items
        let nextIndex = values.isEmpty ? 0 : min(max(index, 0), values.count - 1)
        if selectionIndex != nextIndex {
            selectionIndex = nextIndex
        }
    }

    func moveSelection(by delta: Int) {
        select(at: selectionIndex + delta)
    }

    func paste(_ item: TimestampConversionItem) {
        onPaste(item)
    }
}
