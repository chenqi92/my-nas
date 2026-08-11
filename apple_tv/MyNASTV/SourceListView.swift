import SwiftUI

struct SourceListView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showAddSheet = false

    var body: some View {
        NavigationStack {
            VStack {
                if appState.sources.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(appState.sources) { source in
                            NavigationLink {
                                LibraryListView(source: source)
                                    .environmentObject(appState)
                            } label: {
                                sourceRow(source)
                            }
                        }
                        .onDelete { appState.deleteSource(at: $0) }
                    }
                }
            }
            .navigationTitle("我的 NAS")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("添加源", systemImage: "plus") {
                        showAddSheet = true
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddSourceView()
                    .environmentObject(appState)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "externaldrive.badge.questionmark")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("还没有源")
                .font(.title3)
            Button("添加第一个源", action: { showAddSheet = true })
                .buttonStyle(.borderedProminent)
        }
    }

    private func sourceRow(_ source: TVSource) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(source.name)
                .font(.headline)
            Text(source.type.displayName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

struct AddSourceView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var selectedType: TVSourceType = .webdav
    @State private var endpoint: String = ""
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var token: String = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("源名称", text: $name)
                Picker("类型", selection: $selectedType) {
                    ForEach(TVSourceType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                TextField("服务器地址", text: $endpoint)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                TextField("用户名", text: $username)
                    .textInputAutocapitalization(.never)

                if selectedType == .webdav {
                    SecureField("密码", text: $password)
                } else {
                    SecureField("Token", text: $token)
                }
            }
            .navigationTitle("添加源")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: { dismiss() })
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save)
                        .disabled(name.isEmpty || endpoint.isEmpty || username.isEmpty)
                }
            }
        }
    }

    private func save() {
        let source = TVSource(
            id: UUID().uuidString,
            name: name,
            type: selectedType,
            endpoint: endpoint,
            username: username
        )
        let pwd = selectedType == .webdav ? password : nil
        let tok = selectedType != .webdav ? token : nil
        appState.addSource(source, password: pwd, token: tok)
        dismiss()
    }
}

extension TVSourceType {
    var displayName: String {
        switch self {
        case .webdav: "WebDAV"
        case .jellyfin: "Jellyfin"
        case .emby: "Emby"
        case .plex: "Plex"
        }
    }
}
