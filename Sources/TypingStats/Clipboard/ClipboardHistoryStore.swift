import AppKit
import Foundation
import CryptoKit

@MainActor
final class ClipboardHistoryStore: ObservableObject {
    @Published private(set) var items: [ClipboardHistoryItem] = []

    private let pasteboard: NSPasteboard
    private let maxItems = 50
    private var timer: Timer?
    private var lastChangeCount: Int
    private let storageURL: URL

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
        self.lastChangeCount = pasteboard.changeCount

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("TypingStats", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.storageURL = dir.appendingPathComponent("clipboard-history.json")
        load()
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollPasteboard() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func clear() {
        items.removeAll()
        save()
    }

    func writeToPasteboard(_ item: ClipboardHistoryItem) {
        pasteboard.clearContents()

        switch item.kind {
        case .text:
            pasteboard.setString(item.text ?? "", forType: .string)
        case .image:
            guard let data = item.imagePNGData, let image = NSImage(data: data) else { return }
            pasteboard.writeObjects([image])
        }

        lastChangeCount = pasteboard.changeCount
    }

    private func pollPasteboard() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        if let item = currentPasteboardItem() {
            add(item)
        }
    }

    private func currentPasteboardItem() -> ClipboardHistoryItem? {
        if let string = pasteboard.string(forType: .string) {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let data = Data(string.utf8)
            return ClipboardHistoryItem(
                id: UUID(),
                kind: .text,
                createdAt: Date(),
                text: string,
                imagePNGData: nil,
                contentHash: Self.hash(data)
            )
        }

        guard let image = NSImage(pasteboard: pasteboard),
              let pngData = image.pngData else {
            return nil
        }

        return ClipboardHistoryItem(
            id: UUID(),
            kind: .image,
            createdAt: Date(),
            text: nil,
            imagePNGData: pngData,
            contentHash: Self.hash(pngData)
        )
    }

    private func add(_ item: ClipboardHistoryItem) {
        if items.first?.contentHash == item.contentHash { return }
        items.removeAll { $0.contentHash == item.contentHash }
        items.insert(item, at: 0)
        if items.count > maxItems {
            items.removeLast(items.count - maxItems)
        }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([ClipboardHistoryItem].self, from: data) else {
            return
        }
        items = Array(decoded.prefix(maxItems))
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: storageURL, options: [.atomic])
    }

    private static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private extension NSImage {
    var pngData: Data? {
        guard let tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffRepresentation) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }
}
