import AppKit
import Foundation
import Observation
import ServiceManagement

@MainActor @Observable
final class AccountManager {
    var accounts: [AccountRecord] = []
    var statusMessage = "每天自动更新一次；也可以手动刷新。"
    var lastError: String?
    var loginURL: URL?
    var loginPending = false
    var busyAccountIDs: Set<UUID> = []
    var batchRefreshing = false
    var isBusy: Bool { loginPending || batchRefreshing || !busyAccountIDs.isEmpty }
    var desktopAccountLabel = "当前账号以 Codex 内显示为准"
    var dailyHour = 9
    var launchAtLogin = false
    var integrationNote = "辅助切换会打开 Codex 设置。请先结束正在运行的任务，再退出当前账号并登录目标账号。"
    var manualCurrentAccountID: UUID?
    var manualCurrentConfirmedAt: Date?

    @ObservationIgnored private var store: LocalStore?
    @ObservationIgnored private let vault = CredentialVault()
    @ObservationIgnored private var state = SavedState()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var loginTask: Task<Void, Never>?
    @ObservationIgnored private var loginRPC: CodexRPC?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var cancelRequested = false
    @ObservationIgnored private var pendingDailyCheck = false

    init(storage suppliedStore: LocalStore? = nil) {
        do {
            let local = try suppliedStore ?? LocalStore()
            store = local
            state = try local.load()
            accounts = state.accounts
            dailyHour = max(0, min(23, state.dailyHour))
            if let id = state.manualCurrentAccountID, accounts.contains(where: { $0.id == id }) {
                manualCurrentAccountID = id
                manualCurrentConfirmedAt = state.manualCurrentConfirmedAt
            }
        } catch {
            lastError = "无法读取本地账号资料。为防止覆盖原数据，请检查应用支持目录后重新打开。"
            store = nil
        }
        launchAtLogin = suppliedStore == nil && SMAppService.mainApp.status == .enabled
    }

    func start() {
        guard !started else { return }
        started = true
        do { try store?.discardUnregisteredRuntimes(knownIDs: Set(accounts.map(\.id))) }
        catch { lastError = "无法清理上次未完成的登录，请检查本地目录权限。" }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.runDailyUpdate() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSNotification.Name.NSSystemClockDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.runDailyUpdate() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSNotification.Name.NSSystemTimeZoneDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.runDailyUpdate() }
        })
        runDailyUpdate()
    }

    func addAccount() { beginLogin(existing: nil) }

    func reauthenticateAccount(_ id: UUID) {
        guard let record = accounts.first(where: { $0.id == id }) else { return }
        beginLogin(existing: record)
    }

    func cancelLogin() {
        cancelRequested = true
        loginTask?.cancel()
        if let rpc = loginRPC { Task { await rpc.stop() } }
        statusMessage = "正在取消登录…"
    }

    private func beginLogin(existing: AccountRecord?) {
        guard !isBusy else { return }
        guard store != nil else { return }
        let id = existing?.id ?? UUID()
        loginPending = true
        cancelRequested = false
        lastError = nil
        statusMessage = "正在打开官方登录页面…"
        loginTask = Task {
            var rpc: CodexRPC?
            var home: URL?
            var loginAccepted = false
            do {
                let session = try await openSession(id: id, requireCredentials: false, forLogin: true)
                rpc = session.0
                home = session.1
                loginRPC = session.0
                let response = try await session.0.request(method: "account/login/start", params: .object(["type": .string("chatgpt")]))
                guard let loginId = response["loginId"].stringValue,
                      let text = response["authUrl"].stringValue,
                      let url = URL(string: text), url.scheme == "https", url.host == "auth.openai.com" || url.host == "auth0.openai.com" else {
                    throw ManagerError.message("未获得有效的官方登录地址，请更新 Codex 后重试。")
                }
                try Task.checkCancellation()
                loginURL = url
                statusMessage = "请在浏览器完成登录；完成后这里会自动更新。"
                NSWorkspace.shared.open(url)
                let completion = try await session.0.waitForLoginCompletion(loginId: loginId)
                guard completion["success"].boolValue == true else { throw ManagerError.message("登录未完成，请重试。") }
                try Task.checkCancellation()
                let identity = try await session.0.request(method: "account/read", params: .object(["refreshToken": .bool(false)]))
                guard let email = identity["account"]["email"].stringValue else { throw ManagerError.message("无法确认登录账号，请重试。") }
                if let existing, email.lowercased() != existing.email.lowercased() {
                    throw ManagerError.message("登录账号与所选账号不一致。请在浏览器选择 \(existing.email)。")
                }
                var snapshot: QuotaSnapshot?
                var quotaError: String?
                do {
                    let result = try await session.0.request(method: "account/rateLimits/read", params: .object(["excludeResetCreditDetails": .bool(true)]))
                    snapshot = SnapshotParser.parse(result)
                } catch is CancellationError { throw CancellationError() }
                catch { quotaError = "登录成功，暂时无法获取额度。可稍后手动刷新。" }
                if let oldID = existing?.serverAccountID {
                    guard let newID = snapshot?.accountID else {
                        throw ManagerError.message("暂时无法确认工作区身份，未替换原登录状态。请稍后重新登录。")
                    }
                    guard oldID == newID else {
                        throw ManagerError.message("登录到了不同的账号或工作区。请重新选择原账号，或使用“添加账号”。")
                    }
                }
                let duplicate = accounts.contains { item in
                    guard item.id != id else { return false }
                    if let a = item.serverAccountID, let b = snapshot?.accountID { return a == b }
                    return item.email.lowercased() == email.lowercased()
                }
                guard !duplicate else { throw ManagerError.message("这个账号已经添加过了。请在原账号上选择重新登录。") }
                await session.0.stop()
                try Task.checkCancellation()
                guard !cancelRequested else { throw CancellationError() }
                do { try persistCredentials(id: id, home: session.1, required: true) }
                catch { throw ManagerError.message("无法将这次登录保存到钥匙串，原账号保持不变。请解锁钥匙串后重新登录。") }
                loginAccepted = true
                let record = AccountRecord(id: id,
                    label: existing?.label ?? email.components(separatedBy: "@").first ?? email,
                    email: email, plan: snapshot?.plan ?? identity["account"]["planType"].stringValue ?? "unknown",
                    serverAccountID: snapshot?.accountID ?? existing?.serverAccountID,
                    updatedAt: snapshot == nil ? existing?.updatedAt : Date(), lastError: quotaError, needsLogin: false,
                    quotas: snapshot?.quotas ?? existing?.quotas ?? [], credits: snapshot?.credits ?? existing?.credits,
                    planOverride: existing?.planOverride, subscriptionExpiresAt: existing?.subscriptionExpiresAt,
                    subscriptionExpirySource: existing?.subscriptionExpirySource)
                if let index = accounts.firstIndex(where: { $0.id == id }) { accounts[index] = record }
                else { accounts.append(record) }
                persistState()
                statusMessage = "已添加 \(record.label)。额度每天自动更新一次。"
            } catch {
                if cancelRequested || Task.isCancelled { statusMessage = "已取消登录。" }
                else { lastError = friendlyError(error); statusMessage = "登录未完成。" }
            }
            if let rpc { await rpc.stop() }
            if let home {
                // Rejected/cancelled login must not replace a previously saved credential.
                try? removeRuntime(home)
            }
            if !loginAccepted, existing == nil { try? vault.delete(id) }
            loginRPC = nil
            loginURL = nil
            loginPending = false
            loginTask = nil
            scheduleNextUpdate()
        }
    }

    func refreshAll() {
        guard !isBusy else { return }
        batchRefreshing = true
        lastError = nil
        Task {
            for id in accounts.map(\.id) { await refresh(id) }
            batchRefreshing = false
            statusMessage = "刷新完成。每个账号的更新时间已保存在列表中。"
            scheduleNextUpdate()
        }
    }

    func refreshAccount(_ id: UUID) {
        guard !isBusy else { return }
        batchRefreshing = true
        Task { await refresh(id); batchRefreshing = false; scheduleNextUpdate() }
    }

    private func refresh(_ id: UUID) async {
        guard !busyAccountIDs.contains(id), let initial = accounts.first(where: { $0.id == id }) else { return }
        guard !initial.needsLogin else { statusMessage = "\(initial.label) 需要重新登录。"; return }
        busyAccountIDs.insert(id)
        statusMessage = "正在更新 \(initial.label)…"
        var session: (CodexRPC, URL, Data?)?
        var fetched: (JSONValue, QuotaSnapshot)?
        var failure: Error?
        do {
            let opened = try await openSession(id: id, requireCredentials: true)
            session = opened
            // Let managed authentication refresh only when it needs to. A quota
            // read should not proactively rotate credentials on every click.
            let identity = try await opened.0.request(method: "account/read", params: .object(["refreshToken": .bool(false)]))
            guard let email = identity["account"]["email"].stringValue else { throw ManagerError.message("需要重新登录。") }
            guard email.lowercased() == initial.email.lowercased() else { throw ManagerError.message("认证账号不一致，需要重新登录。") }
            let result = try await opened.0.request(method: "account/rateLimits/read", params: .object(["excludeResetCreditDetails": .bool(true)]))
            let snapshot = SnapshotParser.parse(result)
            if let expected = initial.serverAccountID, let actual = snapshot.accountID, expected != actual {
                throw ManagerError.message("认证工作区不一致，需要重新登录。")
            }
            fetched = (identity, snapshot)
        } catch { failure = error }

        if let session {
            await session.0.stop()
            // Finalize exactly once, even if the quota request failed: managed
            // OAuth may already have rotated the credential during that request.
            do {
                try persistCredentials(id: id, home: session.1, baseline: session.2)
                try removeRuntime(session.1)
            } catch {
                // Leave the protected runtime intact when persistence fails.
                // It may contain the only current refresh credential.
                failure = ManagerError.message("登录状态保存未完成，已保留受保护的本地副本。请解锁钥匙串后手动刷新。")
            }
        }

        if let index = accounts.firstIndex(where: { $0.id == id }) {
            if let failure {
                let message = friendlyError(failure)
                accounts[index].lastError = message
                if message.contains("重新登录") { accounts[index].needsLogin = true }
                statusMessage = "\(initial.label) 更新失败，保留上次数据。"
            } else if let (identity, snapshot) = fetched {
                accounts[index].quotas = snapshot.quotas
                accounts[index].credits = snapshot.credits
                accounts[index].serverAccountID = snapshot.accountID ?? initial.serverAccountID
                accounts[index].plan = snapshot.plan ?? identity["account"]["planType"].stringValue ?? initial.plan
                accounts[index].updatedAt = Date()
                accounts[index].lastError = nil
                accounts[index].needsLogin = false
                statusMessage = "\(initial.label) 已更新。"
            }
        }
        busyAccountIDs.remove(id)
        persistState()
    }

    private func openSession(id: UUID, requireCredentials: Bool, forLogin: Bool = false) async throws -> (CodexRPC, URL, Data?) {
        guard let store else { throw ManagerError.message("本地存储不可用。") }
        let binary = try codexBinary()
        // Login has a throwaway home so an interrupted, unverified login can
        // never be recovered into an existing account's vault entry.
        let home = try store.home(for: forLogin ? UUID() : id)
        let authFile = home.appendingPathComponent("auth.json")
        var baseline: Data?
        if !forLogin {
            baseline = try vault.read(id)
            // Recover a saved session after a prior interrupted run. Do not
            // rewrite an identical Keychain value or delete recovery data first.
            if let recovered = try RuntimeCredentials.load(from: home) {
                if recovered != baseline { try vault.write(recovered, for: id) }
                baseline = recovered
            }
        }
        if let data = baseline {
            try data.write(to: authFile, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: authFile.path)
        } else if requireCredentials { throw ManagerError.message("登录状态已丢失，需要重新登录。") }
        let rpc = CodexRPC()
        do { try await rpc.start(home: home, binary: binary) }
        catch {
            await rpc.stop()
            if forLogin { try? removeRuntime(home) }
            else {
                do {
                    try persistCredentials(id: id, home: home, baseline: baseline)
                    try removeRuntime(home)
                } catch {
                    throw ManagerError.message("后台启动失败，登录状态已保留在受保护目录。请解锁钥匙串后重试。")
                }
            }
            throw error
        }
        return (rpc, home, baseline)
    }

    private func persistCredentials(id: UUID, home: URL, baseline: Data? = nil, required: Bool = false) throws {
        _ = try RuntimeCredentials.persist(from: home, comparedTo: baseline, required: required) {
            try vault.write($0, for: id)
        }
    }

    private func removeRuntime(_ home: URL) throws {
        guard let store, home.deletingLastPathComponent().standardizedFileURL == store.runtimes.standardizedFileURL else { return }
        if FileManager.default.fileExists(atPath: home.path) { try FileManager.default.removeItem(at: home) }
    }

    private func codexBinary() throws -> URL {
        let locations = ["/Applications/ChatGPT.app/Contents/Resources/codex", "/Applications/Codex.app/Contents/Resources/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
        guard let path = locations.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw ManagerError.message("未找到可用的 Codex。请先安装或更新 Codex 桌面版或 Codex CLI。")
        }
        return URL(fileURLWithPath: path)
    }

    private func friendlyError(_ error: Error) -> String {
        if let error = error as? ManagerError { return error.localizedDescription }
        if let error = error as? CodexRPCError {
            switch error {
            case .serverError(let code) where code == 401 || code == 403:
                return "登录状态已失效，需要重新登录。"
            default: return error.localizedDescription
            }
        }
        return "操作未完成。请检查网络连接后重试。"
    }

    private func persistState() {
        state.accounts = accounts
        state.dailyHour = dailyHour
        state.manualCurrentAccountID = manualCurrentAccountID
        state.manualCurrentConfirmedAt = manualCurrentConfirmedAt
        do { try store?.save(state) }
        catch { lastError = "无法保存账号资料。请检查磁盘空间和目录权限。" }
    }

    func renameAccount(_ id: UUID, to name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let index = accounts.firstIndex(where: { $0.id == id }) else { return }
        accounts[index].label = String(clean.prefix(80))
        persistState()
    }

    func updateSubscription(_ id: UUID, planOverride: String?, expiresAt: Date?) {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { return }
        accounts[index].planOverride = planOverride.flatMap { ["Pro20X", "Pro5X"].contains($0) ? $0 : nil }
        accounts[index].subscriptionExpiresAt = expiresAt.map { Calendar.current.startOfDay(for: $0) }
        accounts[index].subscriptionExpirySource = expiresAt == nil ? nil : "manual"
        persistState()
    }

    func markCurrentAccount(_ id: UUID) {
        guard let account = accounts.first(where: { $0.id == id }) else { return }
        manualCurrentAccountID = id
        manualCurrentConfirmedAt = Date()
        statusMessage = "已手动确认当前使用：\(account.label)。"
        persistState()
    }

    func clearCurrentAccount() {
        manualCurrentAccountID = nil
        manualCurrentConfirmedAt = nil
        statusMessage = "已清除当前账号标记。"
        persistState()
    }

    func removeAccount(_ id: UUID) {
        guard !isBusy else { return }
        do {
            try vault.delete(id)
            if let store { try removeRuntime(store.home(for: id)) }
            accounts.removeAll { $0.id == id }
            if manualCurrentAccountID == id {
                manualCurrentAccountID = nil
                manualCurrentConfirmedAt = nil
            }
            persistState()
            scheduleNextUpdate()
        } catch { lastError = friendlyError(error) }
    }

    func switchAccount(_ id: UUID) {
        guard let record = accounts.first(where: { $0.id == id }) else { return }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "在 Codex 中切换到“\(record.label)”"
        alert.informativeText = "目标账号：\(record.email)\n\n1. 先完成或暂停 Codex 中正在运行的任务。\n2. 在 Codex 个人资料菜单退出当前账号。\n3. 重新登录，并在浏览器选择上面的账号。\n\n打开设置后会清除旧的手动标记。完成切换后，请在本管理器中将对应账号标记为当前。"
        alert.addButton(withTitle: "打开 Codex 设置")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "codex://settings"), NSWorkspace.shared.open(url) {
                clearCurrentAccount()
                statusMessage = "请在 Codex 中完成登录：\(record.email)"
            } else { lastError = "无法打开 Codex 设置，请手动打开 Codex。" }
        }
    }

    func openCodex() {
        if let url = URL(string: "codex://") { NSWorkspace.shared.open(url) }
    }

    func setDailyHour(_ hour: Int) {
        dailyHour = max(0, min(23, hour))
        persistState()
        scheduleNextUpdate()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            if enabled && !launchAtLogin {
                SMAppService.openSystemSettingsLoginItems()
                statusMessage = "请在系统设置中允许登录时启动。"
            }
        } catch { lastError = "无法更改登录启动设置。请在系统设置 → 通用 → 登录项中配置。" }
    }

    private func attemptKey(_ id: UUID, now: Date) -> String { "\(id.uuidString):\(DailyPolicy.dayKey(now))" }

    func runDailyUpdate() {
        guard !isBusy else { pendingDailyCheck = true; return }
        pendingDailyCheck = false
        let now = Date()
        let due = accounts.filter { account in
            guard !account.needsLogin, DailyPolicy.needsRefresh(updatedAt: account.updatedAt, now: now, hour: dailyHour) else { return false }
            let key = attemptKey(account.id, now: now)
            guard (state.automaticAttempts[key] ?? 0) < 2 else { return false }
            if let previous = state.lastAttemptAt[key], now.timeIntervalSince(previous) < 1800 { return false }
            return true
        }.map(\.id)
        guard !due.isEmpty else { scheduleNextUpdate(); return }
        batchRefreshing = true
        Task {
            for id in due {
                let key = attemptKey(id, now: Date())
                state.automaticAttempts[key, default: 0] += 1
                state.lastAttemptAt[key] = Date()
                persistState()
                await refresh(id)
            }
            batchRefreshing = false
            scheduleNextUpdate()
        }
    }

    private func scheduleNextUpdate() {
        timer?.invalidate()
        if pendingDailyCheck && !isBusy {
            pendingDailyCheck = false
            runDailyUpdate()
            return
        }
        let now = Date()
        let todaySuffix = ":\(DailyPolicy.dayKey(now))"
        state.automaticAttempts = state.automaticAttempts.filter { $0.key.hasSuffix(todaySuffix) }
        state.lastAttemptAt = state.lastAttemptAt.filter { $0.key.hasSuffix(todaySuffix) }
        var next = DailyPolicy.nextDate(after: now, hour: dailyHour)
        for account in accounts where !account.needsLogin {
            let key = attemptKey(account.id, now: now)
            if DailyPolicy.needsRefresh(updatedAt: account.updatedAt, now: now, hour: dailyHour),
               (state.automaticAttempts[key] ?? 0) == 1, let last = state.lastAttemptAt[key] {
                next = min(next, max(now.addingTimeInterval(5), last.addingTimeInterval(1800)))
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: max(1, next.timeIntervalSince(now)), repeats: false) { [weak self] _ in
            Task { @MainActor in self?.runDailyUpdate() }
        }
        timer?.tolerance = 60
    }
}
