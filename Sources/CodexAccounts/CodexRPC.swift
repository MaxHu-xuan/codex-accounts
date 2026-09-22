import Foundation
import Darwin

/// A Sendable JSON representation for the app-server protocol. Credentials must
/// never be interpolated into logs, diagnostics, or UI descriptions.
enum JSONValue: Sendable, Codable, Equatable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    subscript(_ key: String) -> JSONValue {
        guard case .object(let value) = self else { return .null }
        return value[key] ?? .null
    }

    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    var doubleValue: Double? {
        guard case .number(let value) = self else { return nil }
        return value
    }

    var intValue: Int? {
        guard let value = doubleValue, value.isFinite,
              value >= Double(Int.min), value < Double(Int.max),
              value.rounded(.towardZero) == value else { return nil }
        return Int(value)
    }

    var boolValue: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }

    var objectValue: [String: JSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    var arrayValue: [JSONValue]? {
        guard case .array(let value) = self else { return nil }
        return value
    }
}

enum CodexRPCError: Error, LocalizedError, Sendable, Equatable {
    case alreadyRunning
    case notRunning
    case notInitialized
    case unsafeHome
    case invalidBinary
    case launchFailed
    case transportClosed
    case malformedResponse
    case responseTooLarge
    case requestTimedOut
    case loginTimedOut
    case serverError(code: Int?)
    case unsupportedLoginMode
    case processExited(status: Int32)

    var errorDescription: String? {
        switch self {
        case .alreadyRunning: return "Codex 连接已经启动。"
        case .notRunning: return "Codex 连接尚未启动或正在关闭。"
        case .notInitialized: return "Codex 连接尚未完成初始化。"
        case .unsafeHome: return "账号必须使用独立的认证目录。"
        case .invalidBinary: return "找不到可执行的 Codex 程序。"
        case .launchFailed: return "无法启动 Codex 后台程序。"
        case .transportClosed: return "Codex 后台连接已关闭。"
        case .malformedResponse: return "Codex 返回了无法解析的响应。"
        case .responseTooLarge: return "Codex 返回的数据超出了大小限制。"
        case .requestTimedOut: return "读取 Codex 信息超时，请稍后重试。"
        case .loginTimedOut: return "登录等待超时，请重新登录。"
        case .serverError(let code):
            if let code { return "Codex 请求失败（错误码 \(code)）。" }
            return "Codex 请求失败，请重试或重新登录。"
        case .unsupportedLoginMode: return "此应用仅支持 Codex 托管的 ChatGPT 登录。"
        case .processExited(let status): return "Codex 后台程序已退出（状态 \(status)）。"
        }
    }
}

/// Owns one isolated, short-lived app-server process. It never connects to the
/// desktop app's server or alters the parent process's environment.
actor CodexRPC {
    private struct PendingRequest {
        let continuation: CheckedContinuation<JSONValue, any Error>
        let timeout: Task<Void, Never>
    }

    private struct LoginWaiter {
        let loginId: String?
        let continuation: CheckedContinuation<JSONValue, any Error>
        let timeout: Task<Void, Never>
    }

    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var readerTask: Task<Void, Never>?
    private var generation = UUID()
    private var initialized = false
    private var stopping = false
    private var stopTask: Task<Void, Never>?
    private var buffer = Data()
    private var nextID = 1
    private var pending: [Int: PendingRequest] = [:]
    private var loginWaiters: [UUID: LoginWaiter] = [:]
    private var completedLogins: [JSONValue] = []
    private let maximumLineBytes = 8 * 1_024 * 1_024

    func start(home: URL, binary: URL) async throws {
        guard process == nil, !stopping else { throw CodexRPCError.alreadyRunning }
        let resolvedHome = home.standardizedFileURL.resolvingSymlinksInPath()
        let userHome = FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath()
        let defaultHome = userHome.appendingPathComponent(".codex").resolvingSymlinksInPath()
        guard home.isFileURL, resolvedHome.path != "/", resolvedHome != userHome,
              resolvedHome != defaultHome,
              !resolvedHome.path.hasPrefix(defaultHome.path + "/") else { throw CodexRPCError.unsafeHome }
        guard binary.isFileURL, FileManager.default.isExecutableFile(atPath: binary.path) else {
            throw CodexRPCError.invalidBinary
        }
        try FileManager.default.createDirectory(at: resolvedHome, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: resolvedHome.path)

        let child = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let run = UUID()
        generation = run
        buffer.removeAll(keepingCapacity: false)
        completedLogins.removeAll()
        initialized = false
        child.executableURL = binary
        child.arguments = ["-c", "cli_auth_credentials_store=\"file\"", "app-server", "--listen", "stdio://"]
        child.currentDirectoryURL = resolvedHome
        var environment = ProcessInfo.processInfo.environment
        // Inherited credentials/state paths must never override this account.
        // Preserve the documented custom CA bundle, plus ordinary proxy/SSL
        // variables, so corporate TLS environments keep working.
        for key in Array(environment.keys) where
            (key.hasPrefix("OPENAI_") || key.hasPrefix("CODEX_")) && key != "CODEX_CA_CERTIFICATE" {
            environment.removeValue(forKey: key)
        }
        environment["CODEX_HOME"] = resolvedHome.path
        child.environment = environment
        child.standardInput = stdinPipe
        child.standardOutput = stdoutPipe
        // Do not retain or surface stderr: upstream errors may contain tokens,
        // callback URLs, or authentication details.
        child.standardError = FileHandle.nullDevice
        input = stdinPipe.fileHandleForWriting
        output = stdoutPipe.fileHandleForReading
        process = child

        // A single consumer preserves byte order even when actor scheduling
        // differs from FileHandle callback scheduling.
        let (chunks, chunkContinuation) = AsyncStream<Data>.makeStream()
        readerTask = Task { [weak self] in
            for await chunk in chunks {
                guard !Task.isCancelled else { break }
                await self?.receive(chunk, generation: run)
            }
        }
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            // read(upToCount:) may wait for more bytes on a pipe; availableData
            // reads the currently available chunk, so short JSON lines do not
            // stall the initialization handshake.
            let chunk = handle.availableData
            chunkContinuation.yield(chunk)
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                chunkContinuation.finish()
            }
        }
        child.terminationHandler = { [weak self] child in
            let status = child.terminationStatus
            Task { await self?.didExit(status: status, generation: run) }
        }

        do {
            try child.run()
        } catch {
            closeHandles()
            process = nil
            throw CodexRPCError.launchFailed
        }

        do {
            _ = try await request(method: "initialize", params: .object([
                "clientInfo": .object([
                    "name": .string("codex_accounts_local"),
                    "title": .string("Codex Accounts"),
                    "version": .string("0.1.0")
                ])
            ]), timeout: 20)
            try write(.object(["method": .string("initialized"), "params": .object([:])]))
            initialized = true
        } catch {
            await stop()
            throw error
        }
    }

    func request(method: String, params: JSONValue? = nil, timeout: TimeInterval = 30) async throws -> JSONValue {
        try Task.checkCancellation()
        guard let process, process.isRunning, !stopping else { throw CodexRPCError.notRunning }
        guard initialized || method == "initialize" else { throw CodexRPCError.notInitialized }
        if method == "account/login/start" {
            let mode = params?["type"].stringValue
            guard mode == "chatgpt" || mode == "chatgptDeviceCode" else {
                throw CodexRPCError.unsupportedLoginMode
            }
            completedLogins.removeAll()
        }
        let id = nextID
        nextID += 1
        let run = generation
        var message: [String: JSONValue] = ["method": .string(method), "id": .number(Double(id))]
        if let params { message["params"] = params }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let timeoutTask = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(Self.boundedTimeout(timeout))) }
                    catch { return }
                    await self?.failRequest(id, generation: run, error: CodexRPCError.requestTimedOut)
                }
                pending[id] = PendingRequest(continuation: continuation, timeout: timeoutTask)
                do { try write(.object(message)) }
                catch { failRequest(id, generation: run, error: CodexRPCError.transportClosed) }
            }
        } onCancel: {
            Task { await self.failRequest(id, generation: run, error: CancellationError()) }
        }
    }

    /// Handles the common race where login/completed arrives before the UI starts
    /// waiting. The returned payload includes success and the optional loginId;
    /// callers should not display its raw error string (it may contain secrets).
    func waitForLoginCompletion(loginId: String?, timeout: TimeInterval = 300) async throws -> JSONValue {
        try Task.checkCancellation()
        guard !stopping, let process, process.isRunning else { throw CodexRPCError.notRunning }
        if let index = completedLogins.firstIndex(where: { Self.loginMatches($0, loginId: loginId) }) {
            return completedLogins.remove(at: index)
        }
        let waiterID = UUID()
        let run = generation
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let timeoutTask = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(Self.boundedTimeout(timeout))) }
                    catch { return }
                    await self?.failLoginWaiter(waiterID, generation: run, error: CodexRPCError.loginTimedOut)
                }
                loginWaiters[waiterID] = LoginWaiter(loginId: loginId, continuation: continuation, timeout: timeoutTask)
            }
        } onCancel: {
            Task { await self.failLoginWaiter(waiterID, generation: run, error: CancellationError()) }
        }
    }

    /// Returns only after the child has exited. The caller can safely vault the
    /// final auth.json and remove the temporary credentials after this completes.
    func stop() async {
        if let stopTask { await stopTask.value; return }
        guard let child = process else { return }
        stopping = true
        initialized = false
        failAll(CodexRPCError.transportClosed)
        try? input?.close()
        input = nil
        if child.isRunning { child.terminate() }
        let waitTask = Task.detached(priority: .utility) {
            let deadline = Date().addingTimeInterval(2)
            while child.isRunning, Date() < deadline {
                try? await Task.sleep(for: .milliseconds(25))
            }
            if child.isRunning { Darwin.kill(child.processIdentifier, SIGKILL) }
            child.waitUntilExit()
        }
        stopTask = waitTask
        await waitTask.value
        closeHandles()
        child.terminationHandler = nil
        process = nil
        stopTask = nil
        stopping = false
        buffer.removeAll(keepingCapacity: false)
        completedLogins.removeAll()
    }

    private static func boundedTimeout(_ timeout: TimeInterval) -> Double {
        timeout.isFinite ? min(max(timeout, 0.05), 3_600) : 30
    }

    private func write(_ message: JSONValue) throws {
        guard let input else { throw CodexRPCError.transportClosed }
        var data = try JSONEncoder().encode(message)
        data.append(0x0A)
        try input.write(contentsOf: data)
    }

    private func receive(_ chunk: Data, generation run: UUID) {
        guard generation == run, !stopping else { return }
        guard !chunk.isEmpty else {
            failAll(CodexRPCError.transportClosed)
            output?.readabilityHandler = nil
            return
        }
        buffer.append(chunk)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer.prefix(upTo: newline)
            guard line.count <= maximumLineBytes else { protocolFailure(.responseTooLarge); return }
            let message: JSONValue
            do {
                if line.allSatisfy({ $0 == 0x0D || $0 == 0x20 || $0 == 0x09 }) {
                    buffer.removeSubrange(...newline)
                    continue
                }
                message = try JSONDecoder().decode(JSONValue.self, from: Data(line))
            } catch { protocolFailure(.malformedResponse); return }
            buffer.removeSubrange(...newline)
            handle(message)
        }
        if buffer.count > maximumLineBytes { protocolFailure(.responseTooLarge) }
    }

    private func handle(_ message: JSONValue) {
        if let method = message["method"].stringValue {
            let id = message["id"]
            if id != .null {
                // Managed ChatGPT login does not require us to implement any
                // server-initiated requests. Reject unsupported ones explicitly.
                try? write(.object(["id": id, "error": .object([
                    "code": .number(-32601), "message": .string("Method not supported by this client")
                ])]))
            } else if method == "account/login/completed", message["params"] != .null {
                var params = message["params"]
                if var values = params.objectValue, values["error"] != nil, values["error"] != .null {
                    values["error"] = .string("登录未完成，请重试。")
                    params = .object(values)
                }
                let matches = loginWaiters.filter { Self.loginMatches(params, loginId: $0.value.loginId) }
                if matches.isEmpty {
                    completedLogins.append(params)
                    if completedLogins.count > 16 { completedLogins.removeFirst() }
                }
                for (id, waiter) in matches {
                    loginWaiters.removeValue(forKey: id)
                    waiter.timeout.cancel()
                    waiter.continuation.resume(returning: params)
                }
            }
            return
        }
        guard let id = message["id"].intValue,
              let request = pending.removeValue(forKey: id) else { return }
        request.timeout.cancel()
        let error = message["error"]
        if error != .null {
            // Do not forward arbitrary upstream messages or data; they can
            // contain credentials or OAuth callback URLs.
            request.continuation.resume(throwing: CodexRPCError.serverError(code: error["code"].intValue))
        } else if let result = message.objectValue?["result"] {
            request.continuation.resume(returning: result)
        } else {
            request.continuation.resume(throwing: CodexRPCError.malformedResponse)
        }
    }

    private static func loginMatches(_ params: JSONValue, loginId: String?) -> Bool {
        params["loginId"].stringValue == loginId
    }

    private func failRequest(_ id: Int, generation run: UUID, error: any Error) {
        guard generation == run, let request = pending.removeValue(forKey: id) else { return }
        request.timeout.cancel()
        request.continuation.resume(throwing: error)
    }

    private func failLoginWaiter(_ id: UUID, generation run: UUID, error: any Error) {
        guard generation == run, let waiter = loginWaiters.removeValue(forKey: id) else { return }
        waiter.timeout.cancel()
        waiter.continuation.resume(throwing: error)
    }

    private func failAll(_ error: any Error) {
        let requests = pending.values
        let waiters = loginWaiters.values
        pending.removeAll()
        loginWaiters.removeAll()
        for request in requests {
            request.timeout.cancel()
            request.continuation.resume(throwing: error)
        }
        for waiter in waiters {
            waiter.timeout.cancel()
            waiter.continuation.resume(throwing: error)
        }
    }

    private func didExit(status: Int32, generation run: UUID) {
        guard generation == run, !stopping else { return }
        initialized = false
        failAll(CodexRPCError.processExited(status: status))
        // Keep the Process until stop() reaps it; credential cleanup may then
        // safely run knowing no writer remains.
    }

    private func protocolFailure(_ error: CodexRPCError) {
        failAll(error)
        buffer.removeAll(keepingCapacity: false)
        if let process, process.isRunning { process.terminate() }
    }

    private func closeHandles() {
        output?.readabilityHandler = nil
        readerTask?.cancel()
        readerTask = nil
        try? input?.close()
        try? output?.close()
        input = nil
        output = nil
    }
}
