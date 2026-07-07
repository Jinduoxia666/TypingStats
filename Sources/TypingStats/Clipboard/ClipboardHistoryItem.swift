import Foundation

enum ClipboardContentKind: String, Codable {
    case text
    case image
}

struct ClipboardHistoryItem: Identifiable, Codable, Equatable {
    let id: UUID
    let kind: ClipboardContentKind
    let createdAt: Date
    let text: String?
    let imagePNGData: Data?
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
