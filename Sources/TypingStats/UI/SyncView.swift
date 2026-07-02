import SwiftUI

struct SyncView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if state.syncAvailable {
                Label("iCloud 同步已启用", systemImage: "checkmark.icloud")
                    .font(.headline)
                Text("每台 Mac 把统计写入 iCloud Drive 的 TypingStats 文件夹并互相合并求和。同步有几秒到几分钟延迟,不是实时。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                deviceList

                Button("立即同步") { state.syncNow() }
            } else {
                Label("iCloud 同步不可用", systemImage: "xmark.icloud")
                    .font(.headline)
                Text("请在「系统设置 → Apple ID → iCloud → iCloud 云盘」中开启 iCloud Drive,然后重启 TypingStats。开启前数据只保存在本机。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }

    private var deviceList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("已同步的设备").font(.subheadline).foregroundStyle(.secondary)
            ForEach(state.syncedDevices) { device in
                HStack(spacing: 10) {
                    Image(systemName: device.isSelf ? "desktopcomputer" : "laptopcomputer")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(device.name + (device.isSelf ? "(本机)" : ""))
                            .fontWeight(.medium)
                        Text("今日 \(device.todayKeystrokes) 次 · 更新于 \(device.updatedAt.formatted(date: .omitted, time: .shortened))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
            }
            if state.syncedDevices.count <= 1 {
                Text("还没检测到其它设备。在另一台 Mac 上安装并登录同一 iCloud 账号即可自动出现。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
