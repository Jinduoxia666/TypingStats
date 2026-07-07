import SwiftUI

struct TimestampToolPickerView: View {
    @EnvironmentObject private var state: AppState
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(.secondary)
                TextField("输入时间戳或时间字符串", text: $state.timestampInput)
                    .textFieldStyle(.plain)
                    .focused($inputFocused)
                    .onChange(of: state.timestampInput) { _ in
                        state.selectTimestampItem(at: 0)
                    }
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(.quaternary.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(spacing: 0) {
                ForEach(Array(state.timestampItems.enumerated()), id: \.element.id) { index, item in
                    TimestampToolRow(
                        item: item,
                        isSelected: state.timestampSelectionIndex == index
                    ) {
                        state.selectTimestampItem(at: index)
                        state.pasteTimestampItem(item)
                    }
                    .onHover { hovering in
                        if hovering {
                            state.selectTimestampItem(at: index)
                        }
                    }
                }
            }
        }
        .padding(10)
        .frame(width: 460, height: 274)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
        )
        .onAppear {
            inputFocused = true
        }
    }
}

private struct TimestampToolRow: View {
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
