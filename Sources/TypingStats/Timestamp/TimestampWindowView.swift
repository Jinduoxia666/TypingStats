import SwiftUI

struct TimestampWindowView: View {
    @ObservedObject var model: TimestampViewModel
    @AppStorage("timestampWindowPinned") private var pinned = false
    @FocusState private var inputFocused: Bool
    let close: () -> Void
    let setPinned: (Bool) -> Void
    let onSelectItem: (TimestampConversionItem) -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Label("时间戳转换", systemImage: "clock.arrow.circlepath")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 24)
                    .overlay { WindowDragRegion().accessibilityHidden(true) }
                Button {
                    pinned.toggle()
                    setPinned(pinned)
                } label: {
                    Image(systemName: pinned ? "pin.fill" : "pin")
                        .foregroundStyle(pinned ? Color.accentColor : Color.secondary)
                }
                .help(pinned ? "取消固定" : "固定窗口")
                .accessibilityLabel(pinned ? "取消固定" : "固定窗口")
                Button(action: close) { Image(systemName: "xmark") }
                    .help("关闭时间戳转换").accessibilityLabel("关闭时间戳转换")
            }
            .buttonStyle(.plain)
            .frame(height: 24)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("输入秒／毫秒时间戳或日期时间", text: $model.input)
                    .accessibilityLabel("时间戳或日期时间")
                    .textFieldStyle(.plain)
                    .focused($inputFocused)
                if !model.input.isEmpty {
                    Button {
                        model.input = ""
                        inputFocused = true
                    } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).accessibilityLabel("清空输入")
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))

            VStack(spacing: 0) {
                ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                    TimestampToolRow(item: item, isSelected: model.selectionIndex == index) {
                        model.select(at: index)
                        onSelectItem(item)
                    }
                    .onHover { hovering in
                        if hovering {
                            model.select(at: index)
                        }
                    }
                    .help(pinned || !model.canPasteBack ? "点击复制：\(item.value)" : "点击粘贴：\(item.value)")
                }
                Spacer(minLength: 0)
            }

            HStack {
                if let copiedValue = model.copiedValue {
                    Label("已复制 \(copiedValue)", systemImage: "checkmark")
                } else if !model.input.isEmpty && !TimestampConversionItem.isConvertibleInput(model.input) {
                    Text("未识别输入，请输入时间戳或 yyyy-MM-dd HH:mm:ss")
                } else if !pinned && model.canPasteBack {
                    Text("回车或点击粘贴 · Esc 关闭 · \(TimeZone.current.identifier)")
                } else {
                    Text("点击结果或回车复制 · Esc 关闭 · \(TimeZone.current.identifier)")
                }
                Spacer(minLength: 0)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(16)
        .frame(width: 500, height: 374)
        .background { WindowDragRegion().accessibilityHidden(true) }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.secondary.opacity(0.25)))
        .onAppear { inputFocused = true }
        .onChange(of: model.focusToken) {
            inputFocused = true
        }
        .onChange(of: model.input) {
            model.select(at: 0)
            model.copiedValue = nil
        }
    }
}

struct TimestampToolRow: View {
    let item: TimestampConversionItem
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(systemName: iconName)
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 24)
                    .foregroundStyle(isSelected ? .white : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 14, weight: .semibold))
                    Text(item.subtitle)
                        .font(.caption2)
                        .foregroundStyle(isSelected ? .white.opacity(0.78) : .secondary)
                        .lineLimit(1)
                }

                Spacer()

                Text(item.value)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isSelected ? .white : .primary)
            .padding(.horizontal, 12)
            .frame(height: 42)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.accentColor : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.secondary.opacity(0.14))
                .frame(height: 1)
        }
    }

    private var iconName: String {
        item.id.contains("string") ? "calendar" : "number"
    }
}
