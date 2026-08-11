import Foundation
import Security

protocol TokenStoring {
    func read() throws -> String?
    func write(_ value: String) throws
    func delete() throws
}

enum KeychainError: LocalizedError {
    case status(OSStatus)

    var errorDescription: String? {
        switch self {
        case .status(let status):
            return "无法访问安全存储（\(status)）"
        }
    }
}

struct KeychainTokenStore: TokenStoring {
    private let service = "com.kkape.mynas.tvos"
    private let account = "media-server-access-token"

    func read() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.status(status) }
        guard let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func write(_ value: String) throws {
        guard let data = value.data(using: .utf8) else { return }
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        if updateStatus != errSecItemNotFound { throw KeychainError.status(updateStatus) }

        var query = baseQuery
        query[kSecValueData as String] = data
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw KeychainError.status(addStatus) }
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.status(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

struct ServerAccountStore {
    private struct Metadata: Codable {
        let kind: MediaServerKind
        let baseURL: URL
        let userID: String
        let username: String
        let serverName: String
        let serverVersion: String
        let deviceID: String
    }

    private let defaults: UserDefaults
    private let tokenStore: TokenStoring
    private let metadataKey = "tvos.server.metadata"
    private let deviceIDKey = "tvos.device.id"

    init(defaults: UserDefaults = .standard, tokenStore: TokenStoring = KeychainTokenStore()) {
        self.defaults = defaults
        self.tokenStore = tokenStore
    }

    func load() throws -> ServerSession? {
        guard let data = defaults.data(forKey: metadataKey),
              let token = try tokenStore.read(),
              !token.isEmpty else { return nil }
        let metadata = try JSONDecoder().decode(Metadata.self, from: data)
        return ServerSession(
            kind: metadata.kind,
            baseURL: metadata.baseURL,
            userID: metadata.userID,
            username: metadata.username,
            serverName: metadata.serverName,
            serverVersion: metadata.serverVersion,
            deviceID: metadata.deviceID,
            accessToken: token
        )
    }

    func save(_ session: ServerSession) throws {
        let metadata = Metadata(
            kind: session.kind,
            baseURL: session.baseURL,
            userID: session.userID,
            username: session.username,
            serverName: session.serverName,
            serverVersion: session.serverVersion,
            deviceID: session.deviceID
        )
        try tokenStore.write(session.accessToken)
        defaults.set(try JSONEncoder().encode(metadata), forKey: metadataKey)
    }

    func clear() throws {
        defaults.removeObject(forKey: metadataKey)
        try tokenStore.delete()
    }

    func deviceID() -> String {
        if let stored = defaults.string(forKey: deviceIDKey), !stored.isEmpty {
            return stored
        }
        let value = "kknas-tvos-\(UUID().uuidString.lowercased())"
        defaults.set(value, forKey: deviceIDKey)
        return value
    }
}
