import Foundation
import Security

enum ManagerError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let text): return text }
    }
}

struct LocalStore {
    let root: URL
    var stateURL: URL { root.appendingPathComponent("state.json") }
    var runtimes: URL { root.appendingPathComponent("runtime", isDirectory: true) }

    init(root: URL? = nil) throws {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("CodexAccounts", isDirectory: true)
        try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.createDirectory(at: runtimes, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }

    func load() throws -> SavedState {
        guard FileManager.default.fileExists(atPath: stateURL.path) else { return SavedState() }
        return try JSONDecoder().decode(SavedState.self, from: Data(contentsOf: stateURL))
    }

    func save(_ state: SavedState) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: stateURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stateURL.path)
    }

    func home(for id: UUID) throws -> URL {
        let home = runtimes.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return home
    }

    func discardUnregisteredRuntimes(knownIDs: Set<UUID>) throws {
        for entry in try FileManager.default.contentsOfDirectory(at: runtimes, includingPropertiesForKeys: nil) {
            guard let id = UUID(uuidString: entry.lastPathComponent), !knownIDs.contains(id) else { continue }
            try FileManager.default.removeItem(at: entry)
        }
    }
}

struct CredentialVault {
    let service = "local.codex.accounts.credentials.v1"
    func query(_ id: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: id.uuidString]
    }

    func read(_ id: UUID) throws -> Data? {
        var q = query(id)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw vaultError(status) }
        return data
    }

    func write(_ data: Data, for id: UUID) throws {
        let q = query(id)
        var status = SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = q
            item[kSecValueData as String] = data
            item[kSecAttrLabel as String] = "Codex Accounts · \(id.uuidString.prefix(8))"
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw vaultError(status) }
    }

    func delete(_ id: UUID) throws {
        let status = SecItemDelete(query(id) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw vaultError(status) }
    }

    private func vaultError(_ status: OSStatus) -> ManagerError {
        .message("无法访问本机钥匙串（\(status)）。请解锁钥匙串后重试。")
    }
}
