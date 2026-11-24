import AppKit
import SwiftUI

struct TimestampWindowView: View {
    @ObservedObject var model: TimestampViewModel
    @AppStorage("timestampWindowPinned") private var pinned = false
    @FocusState private var inputFocused: Bool
    @State private var copiedValue: String?
    let close: () -> Void
    let setPinned: (Bool) -> Void

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
                } label: { Image(systemName: pinned ? "pin.fill" : "pin") }
                .help(pinned ? "取消置顶" : "始终置顶")
                .accessibilityLabel(pinned ? "取消置顶" : "始终置顶")
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
                    .onSubmit {
                        if model.items.indices.contains(model.selectionIndex) { copy(model.items[model.selectionIndex]) }
                    }
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
                        copy(item)
                    }
                    .help("点击复制：\(item.value)")
                }
                Spacer(minLength: 0)
            }

            HStack {
                if let copiedValue {
                    Label("已复制 \(copiedValue)", systemImage: "checkmark")
                } else if !model.input.isEmpty && !TimestampConversionItem.isConvertibleInput(model.input) {
                    Text("未识别输入，请输入时间戳或 yyyy-MM-dd HH:mm:ss")
                } else {
                    Text("点击结果或回车复制 · \(TimeZone.current.identifier)")
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
        .onChange(of: model.input) { _ in
            model.select(at: 0)
            copiedValue = nil
        }
    }

    private func copy(_ item: TimestampConversionItem) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.value, forType: .string)
        copiedValue = item.value
    }
}
