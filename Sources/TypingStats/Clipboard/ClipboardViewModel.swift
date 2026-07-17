import Combine

@MainActor
final class ClipboardViewModel: ObservableObject {
    @Published private(set) var items: [ClipboardHistoryItem] = []
    @Published private(set) var selectionIndex = 0
    @Published private(set) var shortcut = ClipboardShortcut.defaultValue

    private var onClear: () -> Void = {}
    private var onPaste: (ClipboardHistoryItem) -> Void = { _ in }
    private var onSelect: (Int) -> Void = { _ in }

    func configure(
        onClear: @escaping () -> Void,
        onPaste: @escaping (ClipboardHistoryItem) -> Void,
        onSelect: @escaping (Int) -> Void
    ) {
        self.onClear = onClear
        self.onPaste = onPaste
        self.onSelect = onSelect
    }

    func update(items: [ClipboardHistoryItem]) {
        if self.items != items {
            self.items = items
        }
    }

    func update(selectionIndex: Int) {
        if self.selectionIndex != selectionIndex {
            self.selectionIndex = selectionIndex
        }
    }

    func update(shortcut: ClipboardShortcut) {
        if self.shortcut != shortcut {
            self.shortcut = shortcut
        }
    }

    func clear() {
        onClear()
    }

    func paste(_ item: ClipboardHistoryItem) {
        onPaste(item)
    }

    func select(at index: Int) {
        onSelect(index)
    }
}
