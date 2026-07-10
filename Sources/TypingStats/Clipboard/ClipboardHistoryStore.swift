import AppKit
import Foundation
import CryptoKit
import ImageIO
import os.log

private let clipboardLogger = Logger(subsystem: "com.jinduoxia.TypingStats", category: "clipboard")

@MainActor
final class ClipboardHistoryStore: ObservableObject {
    @Published private(set) var items: [ClipboardHistoryItem] = []

    private let pasteboard: NSPasteboard
    private let maxItems = 50
    private let maxTextBytes = 2 * 1_024 * 1_024
    private var timer: Timer?
    private var lastChangeCount: Int
    private let storageURL: URL
    private let imagesDirectory: URL
    /// Image capture (TIFF→PNG conversion, hashing, thumbnailing, file writes)
    /// runs here so a big screenshot never stalls the main thread.
    private let processingQueue = DispatchQueue(label: "com.jinduoxia.TypingStats.clipboard", qos: .utility)
    private enum ImagePayload {
        case png(Data)
        case tiff(Data)
    }
    private var isProcessingImage = false
    private var pendingImage: ImagePayload?
    private var imageProcessingGeneration = 0

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
        self.lastChangeCount = pasteboard.changeCount

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("TypingStats", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.storageURL = dir.appendingPathComponent("clipboard-history.json")
        self.imagesDirectory = dir.appendingPathComponent("ClipboardImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
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
        imageProcessingGeneration += 1
        pendingImage = nil
        let files = items.compactMap(\.imageFileName)
        let dir = imagesDirectory
        processingQueue.async {
            for file in files {
                try? FileManager.default.removeItem(at: dir.appendingPathComponent(file))
            }
        }
        items.removeAll()
        save()
    }

    func writeToPasteboard(_ item: ClipboardHistoryItem) {
        pasteboard.clearContents()

        switch item.kind {
        case .text:
            pasteboard.setString(item.text ?? "", forType: .string)
        case .image:
            guard let fileName = item.imageFileName,
                  let data = try? Data(contentsOf: imagesDirectory.appendingPathComponent(fileName)),
                  let image = NSImage(data: data) else { return }
            pasteboard.writeObjects([image])
        }

        lastChangeCount = pasteboard.changeCount
    }

    private func pollPasteboard() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        if let string = pasteboard.string(forType: .string) {
            let textBytes = string.utf8.count
            guard textBytes <= maxTextBytes else {
                clipboardLogger.notice("Clipboard text skipped: \(textBytes, privacy: .public) bytes exceeds history limit")
                return
            }
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            add(ClipboardHistoryItem(
                id: UUID(),
                kind: .text,
                createdAt: Date(),
                text: string,
                imageFileName: nil,
                thumbnailJPEGData: nil,
                contentHash: clipboardContentHash(Data(string.utf8))
            ))
            return
        }

        // Grab the raw pasteboard bytes on the main thread (NSPasteboard isn't
        // thread-safe), then do all the heavy work in the background.
        if let pngData = pasteboard.data(forType: .png) {
            enqueueImage(.png(pngData))
        } else if let tiffData = pasteboard.data(forType: .tiff) {
            enqueueImage(.tiff(tiffData))
        }
    }

    private func enqueueImage(_ payload: ImagePayload) {
        guard !isProcessingImage else {
            // Keep only the latest waiting image, so repeated large screenshots
            // cannot build an unbounded queue of captured Data values.
            pendingImage = payload
            return
        }
        processImage(payload)
    }

    private func processImage(_ payload: ImagePayload) {
        isProcessingImage = true
        let dir = imagesDirectory
        let generation = imageProcessingGeneration
        processingQueue.async {
            let item: ClipboardHistoryItem? = autoreleasepool {
                let png: Data
                switch payload {
                case .png(let data):
                    png = data
                case .tiff(let data):
                    guard let rep = NSBitmapImageRep(data: data),
                          let converted = rep.representation(using: .png, properties: [:]) else {
                        return nil
                    }
                    png = converted
                }

                let id = UUID()
                let fileName = "\(id.uuidString).png"
                do {
                    try png.write(to: dir.appendingPathComponent(fileName), options: .atomic)
                } catch {
                    return nil
                }
                return ClipboardHistoryItem(
                    id: id,
                    kind: .image,
                    createdAt: Date(),
                    text: nil,
                    imageFileName: fileName,
                    thumbnailJPEGData: clipboardThumbnailJPEG(from: png),
                    contentHash: clipboardContentHash(png)
                )
            }
            Task { @MainActor [weak self] in
                self?.finishImageProcessing(item, generation: generation)
            }
        }
    }

    private func finishImageProcessing(_ item: ClipboardHistoryItem?, generation: Int) {
        if let item {
            if generation == imageProcessingGeneration {
                add(item)
            } else {
                deleteImageFile(of: item)
            }
        }
        isProcessingImage = false
        guard let next = pendingImage else { return }
        pendingImage = nil
        processImage(next)
    }

    private func add(_ item: ClipboardHistoryItem) {
        if items.first?.contentHash == item.contentHash {
            // Re-copy of the newest entry: keep the old item, drop the new file.
            deleteImageFile(of: item)
            return
        }
        let duplicates = items.filter { $0.contentHash == item.contentHash }
        items.removeAll { $0.contentHash == item.contentHash }
        duplicates.forEach(deleteImageFile(of:))
        items.insert(item, at: 0)
        while items.count > maxItems {
            deleteImageFile(of: items.removeLast())
        }
        save()
    }

    private func deleteImageFile(of item: ClipboardHistoryItem) {
        guard let fileName = item.imageFileName else { return }
        let url = imagesDirectory.appendingPathComponent(fileName)
        processingQueue.async {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Persistence

    /// On-disk shape. `imagePNGData` is the legacy (pre-file-storage) inline
    /// image; when present it's migrated to a file on first load.
    private struct StoredItem: Codable {
        let id: UUID
        let kind: ClipboardContentKind
        let createdAt: Date
        let text: String?
        let imageFileName: String?
        let thumbnailJPEGData: Data?
        let imagePNGData: Data?
        let contentHash: String
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([StoredItem].self, from: data) else {
            pruneOrphanImageFiles(referenced: [])
            return
        }

        var migratedLegacy = false
        var loaded: [ClipboardHistoryItem] = []
        for stored in decoded.prefix(maxItems) {
            var fileName = stored.imageFileName
            var thumbnail = stored.thumbnailJPEGData
            if let legacyPNG = stored.imagePNGData {
                fileName = "\(stored.id.uuidString).png"
                try? legacyPNG.write(to: imagesDirectory.appendingPathComponent(fileName!), options: .atomic)
                thumbnail = clipboardThumbnailJPEG(from: legacyPNG)
                migratedLegacy = true
            }
            loaded.append(ClipboardHistoryItem(
                id: stored.id,
                kind: stored.kind,
                createdAt: stored.createdAt,
                text: stored.text,
                imageFileName: fileName,
                thumbnailJPEGData: thumbnail,
                contentHash: stored.contentHash
            ))
        }
        items = loaded
        if migratedLegacy { save() }
        pruneOrphanImageFiles(referenced: Set(loaded.compactMap(\.imageFileName)))
    }

    private func save() {
        let stored = items.map { item in
            StoredItem(
                id: item.id,
                kind: item.kind,
                createdAt: item.createdAt,
                text: item.text,
                imageFileName: item.imageFileName,
                thumbnailJPEGData: item.thumbnailJPEGData,
                imagePNGData: nil,
                contentHash: item.contentHash
            )
        }
        guard let data = try? JSONEncoder().encode(stored) else { return }
        let url = storageURL
        processingQueue.async {
            try? data.write(to: url, options: [.atomic])
        }
    }

    /// Delete image files no history item references (e.g. left behind by a
    /// crash between the file write and the JSON save).
    private func pruneOrphanImageFiles(referenced: Set<String>) {
        let dir = imagesDirectory
        processingQueue.async {
            guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return }
            for file in files where !referenced.contains(file) {
                try? FileManager.default.removeItem(at: dir.appendingPathComponent(file))
            }
        }
    }
}

// MARK: - Image helpers (nonisolated: called from the processing queue)

private func clipboardContentHash(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

/// Downscaled JPEG preview via ImageIO, which decodes at thumbnail size
/// instead of decompressing the full image first.
private func clipboardThumbnailJPEG(from data: Data, maxPixel: Int = 640) -> Data? {
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        kCGImageSourceCreateThumbnailWithTransform: true
    ]
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
        return nil
    }
    let rep = NSBitmapImageRep(cgImage: cgImage)
    return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
}
