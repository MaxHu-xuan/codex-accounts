import Darwin
import Foundation

/// Handles only a session's temporary credential file. The caller owns the
/// durable store and decides when a successfully saved session can be removed.
enum RuntimeCredentials {
    static func load(from home: URL, required: Bool = false) throws -> Data? {
        let file = home.appendingPathComponent("auth.json")
        // Never follow a replacement symlink or adjust another file's access.
        let descriptor = Darwin.open(file.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        if descriptor < 0 {
            if errno == ENOENT {
                if required { throw ManagerError.message("未获得可保存的登录状态，请重新登录。") }
                return nil
            }
            throw ManagerError.message("无法读取受保护的本地登录状态，请检查目录权限后重试。")
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var attributes = stat()
        guard fstat(descriptor, &attributes) == 0,
              attributes.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
            throw ManagerError.message("登录状态文件异常，未修改已保存的账号。")
        }
        let data = try handle.readToEnd() ?? Data()
        guard (try? JSONSerialization.jsonObject(with: data)) is [String: Any] else {
            throw ManagerError.message("登录状态格式异常，需要重新登录。")
        }
        guard fchmod(descriptor, mode_t(0o600)) == 0 else {
            throw ManagerError.message("无法保护本地登录状态，请检查目录权限后重试。")
        }
        return data
    }

    @discardableResult
    static func persist(from home: URL, comparedTo baseline: Data?, required: Bool = false,
                        save: (Data) throws -> Void) throws -> Bool {
        guard let data = try load(from: home, required: required), data != baseline else { return false }
        try save(data)
        return true
    }
}
