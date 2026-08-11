import Foundation
import Security

/// 凭证存 tvOS Keychain。
///
/// 与 Flutter 端的约定一致：**明文偏好设置里绝不放凭证**。
/// tvOS 上 kSecClassGenericPassword 可用，但注意两点：
/// - tvOS 没有 keychain sharing UI，条目是 App 私有的；
/// - 不加 kSecAttrAccessible 时默认 WhenUnlocked，tvOS 无锁屏概念，
///   这里显式用 AfterFirstUnlock，避免后台同步任务取不到值。
public struct KeychainCredentialStore: Sendable {
    private let service: String

    public init(service: String = "com.mynas.tv.sources") {
        self.service = service
    }

    public enum Slot: String, Sendable {
        /// WebDAV 密码
        case password
        /// 媒体服务器 API token / access token
        case token
    }

    public func save(_ secret: String, for sourceID: UUID, slot: Slot) throws {
        let account = key(sourceID, slot)
        let data = Data(secret.utf8)

        // 先尝试更新，不存在再插入。直接 add 会在已有条目上返回 errSecDuplicateItem。
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(updateStatus)
        }

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainError.unexpectedStatus(addStatus)
        }
    }

    public func read(for sourceID: UUID, slot: Slot) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key(sourceID, slot),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func delete(for sourceID: UUID, slot: Slot) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key(sourceID, slot),
        ]
        // 不存在也算完成，不抛
        SecItemDelete(query as CFDictionary)
    }

    /// 删源时把两个槽都清掉，避免 Keychain 里留下孤儿条目
    public func deleteAll(for sourceID: UUID) {
        for slot in [Slot.password, .token] {
            delete(for: sourceID, slot: slot)
        }
    }

    private func key(_ sourceID: UUID, _ slot: Slot) -> String {
        "\(sourceID.uuidString)/\(slot.rawValue)"
    }
}

public enum KeychainError: Error, Equatable {
    case unexpectedStatus(OSStatus)
}
