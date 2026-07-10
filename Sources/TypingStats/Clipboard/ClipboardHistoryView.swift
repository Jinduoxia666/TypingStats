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
    /// Set when a selection change comes from mouse hover: hover selection must
    /// only highlight the row — auto-scrolling (`scrollTo(.center)`) here would
    /// make the list slide around under the pointer. Keyboard moves still scroll.
    @State private var suppressNextAutoScroll = false
    /// Single source of truth for the hover preview: at most one row shows a
    /// popover. Per-cell preview state caused double-pops — moving between rows
    /// opened the new popover before the old one's delayed close fired, and a
    /// hover bounce on the presenting row closed-then-reopened its own popover.
    @State private var previewIndex: Int?
    @State private var previewOpenWorkItem: DispatchWorkItem?
    @State private var previewCloseWorkItem: DispatchWorkItem?

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
                                    isSelected: state.clipboardSelectionIndex == index,
                                    isPreviewPresented: previewBinding(for: index),
                                    onSelect: { state.pasteClipboardItem(item) },
                                    onPreviewHover: handlePreviewHover
                                )
                                .id(index)
                                .onHover { hovering in
                                    if hovering, state.clipboardSelectionIndex != index {
                                        suppressNextAutoScroll = true
                                        state.selectClipboardItem(at: index)
                                    }
                                    handleRowHover(hovering, index: index)
                                }
                            }
                        }
                    }
                    .frame(height: listHeight(for: visibleItems.count))
                    .onChange(of: state.clipboardSelectionIndex) { index in
                        if suppressNextAutoScroll {
                            suppressNextAutoScroll = false
                            return
                        }
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

    // MARK: - Hover preview coordination

    private func previewBinding(for index: Int) -> Binding<Bool> {
        Binding(
            get: { previewIndex == index },
            set: { shown in
                if !shown && previewIndex == index { previewIndex = nil }
            }
        )
    }

    private func handleRowHover(_ hovering: Bool, index: Int) {
        if hovering {
            previewCloseWorkItem?.cancel()
            previewCloseWorkItem = nil
            // Already showing this row's preview (e.g. a hover bounce as the
            // popover appears): don't close-and-reopen it.
            guard previewIndex != index else { return }
            // One shared pending-open: hovering a new row cancels the old
            // row's not-yet-fired open, so a stale popover can't appear late.
            previewOpenWorkItem?.cancel()
            let workItem = DispatchWorkItem {
                previewIndex = index
                previewOpenWorkItem = nil
            }
            previewOpenWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: workItem)
        } else {
            previewOpenWorkItem?.cancel()
            previewOpenWorkItem = nil
            schedulePreviewClose()
        }
    }

    private func handlePreviewHover(_ hovering: Bool) {
        if hovering {
            previewCloseWorkItem?.cancel()
            previewCloseWorkItem = nil
        } else {
            schedulePreviewClose()
        }
    }

    private func schedulePreviewClose() {
        guard previewIndex != nil else { return }
        previewCloseWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            previewIndex = nil
            previewCloseWorkItem = nil
        }
        previewCloseWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    private func listHeight(for count: Int) -> CGFloat {
        min(CGFloat(count) * ClipboardPickerConfig.rowHeight, ClipboardPickerConfig.maxListHeight)
    }
}

/// A row in the quick picker. Preview presentation is owned by the parent
/// (single popover across the list); the cell just renders and reports hover
/// over its popover content.
private struct QuickPickerCell: View {
    let index: Int
    let item: ClipboardHistoryItem
    let isSelected: Bool
    @Binding var isPreviewPresented: Bool
    let onSelect: () -> Void
    let onPreviewHover: (Bool) -> Void

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
        .popover(isPresented: $isPreviewPresented, arrowEdge: .trailing) {
            ClipboardHoverPreview(item: item, onHoverChanged: onPreviewHover)
        }
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
                .font(.system(size: 20, weight: .regular))
                .frame(width: 28, height: 28)
        case .image:
            if let data = item.thumbnailJPEGData, let image = NSImage(data: data) {
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
            if let data = item.thumbnailJPEGData, let image = NSImage(data: data) {
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
            if let data = item.thumbnailJPEGData, let image = NSImage(data: data) {
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
            if let data = item.thumbnailJPEGData, let image = NSImage(data: data) {
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
