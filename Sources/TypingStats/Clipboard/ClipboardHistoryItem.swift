import Foundation

enum ClipboardContentKind: String, Codable {
    case text
    case image
}

/// One clipboard entry. Image originals live as files on disk (see
/// ClipboardHistoryStore); the item carries only a small JPEG thumbnail, so a
/// screenshot-heavy history doesn't pin hundreds of MB of PNG data in memory.
struct ClipboardHistoryItem: Identifiable, Codable, Equatable {
    let id: UUID
    let kind: ClipboardContentKind
    let createdAt: Date
    let text: String?
    /// File name of the full-size PNG inside the store's images directory.
    let imageFileName: String?
    /// Downscaled preview used everywhere the UI shows the image.
    let thumbnailJPEGData: Data?
    let contentHash: String

    var previewTitle: String {
        switch kind {
        case .text:
            let trimmed = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "空文本" : trimmed
        case .image:
            return "图片"
        }
    }
}
