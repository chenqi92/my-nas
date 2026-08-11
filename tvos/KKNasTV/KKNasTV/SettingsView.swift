import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var showingSignOutConfirmation = false

    private let bitrateOptions = [
        20_000_000: "20 Mbps",
        40_000_000: "40 Mbps",
        80_000_000: "80 Mbps",
        120_000_000: "120 Mbps",
    ]

    var body: some View {
        Form {
            Section("服务器") {
                LabeledContent("名称", value: appModel.session?.serverName ?? "—")
                LabeledContent("类型", value: appModel.session?.kind.title ?? "—")
                LabeledContent("地址", value: appModel.session?.baseURL.absoluteString ?? "—")
                LabeledContent("账号", value: appModel.session?.username ?? "—")
                LabeledContent("服务端版本", value: appModel.session?.serverVersion ?? "—")
            }

            Section("播放") {
                Toggle("优先直接播放兼容格式", isOn: $appModel.preferDirectPlay)
                Picker("最高串流码率", selection: $appModel.maxStreamingBitrate) {
                    ForEach(bitrateOptions.keys.sorted(), id: \.self) { value in
                        Text(bitrateOptions[value] ?? "\(value)").tag(value)
                    }
                }
                Text("Apple TV 不兼容的封装格式会自动请求 Jellyfin 或 Emby 转码为 HLS。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("应用") {
                LabeledContent("版本", value: "1.2.3 (15)")
                Button("退出当前服务器", role: .destructive) {
                    showingSignOutConfirmation = true
                }
            }
        }
        .navigationTitle("设置")
        .confirmationDialog("退出当前服务器？", isPresented: $showingSignOutConfirmation, titleVisibility: .visible) {
            Button("退出登录", role: .destructive) {
                Task { await appModel.signOut() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("Apple TV 上保存的服务器令牌会被删除。")
        }
    }
}
