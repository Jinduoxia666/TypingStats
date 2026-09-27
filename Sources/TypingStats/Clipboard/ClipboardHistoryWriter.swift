import Foundation

/// Coalesces history saves without queuing a full JSON buffer for every change.
final class ClipboardHistoryWriter: @unchecked Sendable {
    private let storageURL: URL
    private let queue: DispatchQueue
    private let writeData: (Data, URL) throws -> Void
    private let lock = NSLock()
    // Both fields are protected by lock. Only one drain runs at a time.
    private var pendingItems: [ClipboardHistoryItem]?
    private var isWriting = false

    init(
        storageURL: URL,
        queue: DispatchQueue,
        writeData: @escaping (Data, URL) throws -> Void = { data, url in
            try data.write(to: url, options: .atomic)
        }
    ) {
        self.storageURL = storageURL
        self.queue = queue
        self.writeData = writeData
    }

    func save(_ items: [ClipboardHistoryItem]) {
        lock.lock()
        pendingItems = items
        guard !isWriting else {
            lock.unlock()
            return
        }
        isWriting = true
        lock.unlock()

        queue.async { self.drain() }
    }

    private func drain() {
        while true {
            lock.lock()
            guard let items = pendingItems else {
                isWriting = false
                lock.unlock()
                return
            }
            pendingItems = nil
            lock.unlock()

            autoreleasepool {
                guard let data = try? JSONEncoder().encode(items) else { return }
                try? writeData(data, storageURL)
            }
        }
    }
}
