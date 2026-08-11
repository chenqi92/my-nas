import SwiftUI

struct ConnectionView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var kind: MediaServerKind = .jellyfin
    @State private var address = "http://"
    @State private var username = ""
    @State private var password = ""
    @FocusState private var focusedField: Field?

    private enum Field { case address, username, password }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.02, green: 0.08, blue: 0.12), Color.black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            HStack(spacing: 90) {
                brandPanel
                connectionForm
            }
            .padding(.horizontal, 90)
        }
        .alert("连接失败", isPresented: errorPresented) {
            Button("知道了", role: .cancel) { appModel.errorMessage = nil }
        } message: {
            Text(appModel.errorMessage ?? "未知错误")
        }
        .onChange(of: kind) { _, newValue in
            if !newValue.supportsQuickConnect { appModel.cancelQuickConnect() }
        }
        .onDisappear { appModel.cancelQuickConnect() }
    }

    private var brandPanel: some View {
        VStack(alignment: .leading, spacing: 28) {
            Image(systemName: "externaldrive.connected.to.line.below")
                .font(.system(size: 92, weight: .light))
                .foregroundStyle(.cyan)
            Text("KKNas")
                .font(.system(size: 72, weight: .bold, design: .rounded))
            Text("把 NAS 里的电影和剧集带到大屏幕。")
                .font(.title2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Label("原生 Apple TV 播放体验", systemImage: "play.tv.fill")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: 580, alignment: .leading)
    }

    private var connectionForm: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("连接媒体服务器")
                .font(.largeTitle.bold())

            Picker("服务器类型", selection: $kind) {
                ForEach(MediaServerKind.allCases) { serverKind in
                    Text(serverKind.title).tag(serverKind)
                }
            }
            .pickerStyle(.segmented)

            TextField("服务器地址，例如 http://192.168.1.10:8096", text: $address)
                .textContentType(.URL)
                .focused($focusedField, equals: .address)
                .onSubmit { focusedField = .username }

            HStack(spacing: 20) {
                TextField("用户名", text: $username)
                    .textContentType(.username)
                    .focused($focusedField, equals: .username)
                    .onSubmit { focusedField = .password }
                SecureField("密码", text: $password)
                    .textContentType(.password)
                    .focused($focusedField, equals: .password)
                    .onSubmit { signIn() }
            }

            HStack(spacing: 22) {
                Button(action: signIn) {
                    Label("登录", systemImage: "arrow.right.circle.fill")
                }
                .disabled(appModel.isAuthenticating || username.isEmpty)

                if kind.supportsQuickConnect {
                    Button {
                        appModel.startQuickConnect(address: address)
                    } label: {
                        Label("快速连接", systemImage: "number.square.fill")
                    }
                    .disabled(appModel.isAuthenticating)
                }
            }

            if let code = appModel.quickConnectCode {
                quickConnectPanel(code: code)
            } else if appModel.isAuthenticating {
                HStack(spacing: 18) {
                    ProgressView()
                    Text("正在连接服务器…")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(48)
        .frame(maxWidth: 760)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
    }

    private func quickConnectPanel(code: String) -> some View {
        HStack(spacing: 28) {
            VStack(alignment: .leading, spacing: 8) {
                Text("快速连接代码")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text(code)
                    .font(.system(size: 48, weight: .bold, design: .monospaced))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 12) {
                Text(appModel.quickConnectStatus ?? "等待授权…")
                    .foregroundStyle(.secondary)
                Button("取消", role: .cancel) { appModel.cancelQuickConnect() }
            }
        }
        .padding(24)
        .background(Color.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 20))
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { appModel.errorMessage != nil },
            set: { if !$0 { appModel.errorMessage = nil } }
        )
    }

    private func signIn() {
        Task {
            await appModel.login(kind: kind, address: address, username: username, password: password)
        }
    }
}
