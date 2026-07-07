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
            let visibleItems = Array(state.clipboardItems.prefix(ClipboardPickerConfig.maxItems))
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
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(visibleItems.enumerated()), id: \.element.id) { index, item in
                                QuickPickerCell(
                                    index: index + 1,
                                    item: item,
                                    isSelected: state.clipboardSelectionIndex == index
                                ) {
                                    state.pasteClipboardItem(item)
                                }
                                .id(index)
                                .onHover { hovering in
                                    if hovering {
                                        state.selectClipboardItem(at: index)
                                    }
                                }
                            }
                        }
                    }
                    .frame(height: listHeight(for: visibleItems.count))
                    .onChange(of: state.clipboardSelectionIndex) { index in
                        withAnimation(.easeOut(duration: 0.12)) {
                            proxy.scrollTo(index, anchor: .center)
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
        let count = min(state.clipboardItems.count, ClipboardPickerConfig.maxItems)
        return listHeight(for: count) + 16
    }

    private func listHeight(for count: Int) -> CGFloat {
        min(CGFloat(count) * ClipboardPickerConfig.rowHeight, ClipboardPickerConfig.maxListHeight)
    }
}

private struct QuickPickerCell: View {
    let index: Int
    let item: ClipboardHistoryItem
    let isSelected: Bool
    let onSelect: () -> Void
    @State private var showsPreview = false
    @State private var previewOpenWorkItem: DispatchWorkItem?
    @State private var previewCloseWorkItem: DispatchWorkItem?

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
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(isSelected ? .white : .primary)
            .padding(.horizontal, 12)
            .frame(height: ClipboardPickerConfig.rowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.accentColor : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                schedulePreviewOpen()
            } else {
                cancelPreviewOpen()
                schedulePreviewClose()
            }
        }
        .popover(isPresented: $showsPreview, arrowEdge: .trailing) {
            ClipboardHoverPreview(
                item: item,
                onHoverChanged: { hovering in
                    if hovering {
                        showPreview()
                    } else {
                        schedulePreviewClose()
                    }
                }
            )
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.secondary.opacity(0.16))
                .frame(height: 1)
        }
    }

    private func showPreview() {
        cancelPreviewOpen()
        previewCloseWorkItem?.cancel()
        previewCloseWorkItem = nil
        showsPreview = true
    }

    private func schedulePreviewOpen() {
        previewCloseWorkItem?.cancel()
        previewCloseWorkItem = nil
        previewOpenWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            showsPreview = true
            previewOpenWorkItem = nil
        }
        previewOpenWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: workItem)
    }

    private func cancelPreviewOpen() {
        previewOpenWorkItem?.cancel()
        previewOpenWorkItem = nil
    }

    private func schedulePreviewClose() {
        cancelPreviewOpen()
        previewCloseWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            showsPreview = false
            previewCloseWorkItem = nil
        }
        previewCloseWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
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
                .font(.system(size: 20, weight: .regular))
                .frame(width: 28, height: 28)
        case .image:
            if let data = item.imagePNGData, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 30, height: 26)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.secondary.opacity(0.22), lineWidth: 1)
                    )
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 18, weight: .regular))
                    .frame(width: 28, height: 28)
            }
        }
    }
}

private struct ClipboardHoverPreview: View {
    let item: ClipboardHistoryItem
    let onHoverChanged: (Bool) -> Void

    var body: some View {
        switch item.kind {
        case .text:
            ScrollView {
                Text(item.previewTitle)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
            .frame(width: 360, height: 260)
            .onHover(perform: onHoverChanged)
        case .image:
            if let data = item.imagePNGData, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 360, height: 260)
                    .padding(10)
                    .onHover(perform: onHoverChanged)
            } else {
                Text("图片不可预览")
                    .foregroundStyle(.secondary)
                    .frame(width: 220, height: 120)
                    .onHover(perform: onHoverChanged)
            }
        }
    }
}

private struct ClipboardHistoryList: View {
    let items: [ClipboardHistoryItem]
    let onSelect: (ClipboardHistoryItem) -> Void
    @State private var detailItem: ClipboardHistoryItem?

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
                        detailItem = item
                    }
                    .listRowSeparator(.visible)
                }
                .listStyle(.inset)
            }
        }
        .sheet(item: $detailItem) { item in
            ClipboardDetailView(item: item) {
                detailItem = nil
                onSelect(item)
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
                Image(systemName: "chevron.right")
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

private struct ClipboardDetailView: View {
    let item: ClipboardHistoryItem
    let onPaste: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(title, systemImage: item.kind == .text ? "doc.text" : "photo")
                    .font(.headline)
                Spacer()
                Text(timeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            detailContent

            HStack {
                Button("关闭") {
                    dismiss()
                }
                Spacer()
                Button("粘贴") {
                    onPaste()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 520, height: 420)
    }

    private var title: String {
        item.kind == .text ? "剪贴板文字" : "剪贴板图片"
    }

    @ViewBuilder
    private var detailContent: some View {
        switch item.kind {
        case .text:
            ScrollView {
                Text(item.previewTitle)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.quaternary.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        case .image:
            if let data = item.imagePNGData, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.quaternary.opacity(0.35))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "photo")
                        .font(.system(size: 34))
                        .foregroundStyle(.secondary)
                    Text("图片不可预览")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
