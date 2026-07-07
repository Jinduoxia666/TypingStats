import AppKit
import SwiftUI

struct ClipboardHistoryView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("剪贴板")
                        .font(.title2.bold())
                    Text("快捷键 \(state.clipboardShortcut.displayText) 呼出历史面板")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("清空") {
                    state.clearClipboardHistory()
                }
                .disabled(state.clipboardItems.isEmpty)
            }

            ClipboardHistoryList(items: state.clipboardItems) { item in
                state.pasteClipboardItem(item)
            }
        }
        .padding()
    }
}

struct ClipboardQuickPickerView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            let visibleItems = Array(state.clipboardItems.prefix(8))
            if visibleItems.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "clipboard")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("暂无剪贴板历史")
                        .font(.headline)
                    Text("复制文字或图片后再按 \(state.clipboardShortcut.displayText)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(visibleItems.enumerated()), id: \.element.id) { index, item in
                        QuickPickerCell(
                            index: index + 1,
                            item: item,
                            isSelected: state.clipboardSelectionIndex == index
                        ) {
                            state.pasteClipboardItem(item)
                        }
                        .onHover { hovering in
                            if hovering {
                                state.selectClipboardItem(at: index)
                            }
                        }
                    }
                }
            }
        }
        .padding(10)
        .frame(width: 460, height: pickerHeight)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
        )
    }

    private var pickerHeight: CGFloat {
        if state.clipboardItems.isEmpty { return 180 }
        return CGFloat(min(state.clipboardItems.count, 8) * 44 + 16)
    }
}

private struct QuickPickerCell: View {
    let index: Int
    let item: ClipboardHistoryItem
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Text("\(index)")
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? .white : .secondary)
                    .frame(width: 26, alignment: .trailing)

                itemPreview

                Text(title)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(isSelected ? .white : .primary)
            .padding(.horizontal, 14)
            .frame(height: 44)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.accentColor : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.secondary.opacity(0.16))
                .frame(height: 1)
        }
    }

    private var title: String {
        switch item.kind {
        case .text:
            return item.previewTitle
        case .image:
            return "图片"
        }
    }

    @ViewBuilder
    private var itemPreview: some View {
        switch item.kind {
        case .text:
            Image(systemName: "doc.text")
                .font(.system(size: 24, weight: .regular))
                .frame(width: 30, height: 30)
        case .image:
            if let data = item.imagePNGData, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 34, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.22), lineWidth: 1)
                    )
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 20, weight: .regular))
                    .frame(width: 30, height: 30)
            }
        }
    }
}

private struct ClipboardHistoryList: View {
    let items: [ClipboardHistoryItem]
    let onSelect: (ClipboardHistoryItem) -> Void

    var body: some View {
        Group {
            if items.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "clipboard")
                        .font(.system(size: 34))
                        .foregroundStyle(.secondary)
                    Text("暂无剪贴板历史")
                        .font(.headline)
                    Text("复制文字或图片后会自动出现在这里")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(items) { item in
                    ClipboardHistoryRow(item: item) {
                        onSelect(item)
                    }
                    .listRowSeparator(.visible)
                }
                .listStyle(.inset)
            }
        }
    }
}

private struct ClipboardHistoryRow: View {
    let item: ClipboardHistoryItem
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                thumbnail
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.previewTitle)
                        .font(.body)
                        .lineLimit(item.kind == .text ? 2 : 1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(timeText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "arrow.turn.down.left")
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var thumbnail: some View {
        switch item.kind {
        case .text:
            Image(systemName: "doc.text")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 58, height: 46)
                .background(.quaternary.opacity(0.45))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        case .image:
            if let data = item.imagePNGData, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 58, height: 46)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Image(systemName: "photo")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(width: 58, height: 46)
                    .background(.quaternary.opacity(0.45))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var timeText: String {
        Self.formatter.string(from: item.createdAt)
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()
}
