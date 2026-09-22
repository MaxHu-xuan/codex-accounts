import SwiftUI

struct MenuContent: View {
    @Bindable var manager: AccountManager
    @Environment(\.openWindow) private var openWindow

    private let visibleRowCount = 8
    private let rowHeight: CGFloat = 58

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("账号")
                Spacer()
                Text("余额")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            if manager.accounts.isEmpty {
                Button(action: showManager) {
                    Text("暂无账号，请在主窗口添加")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 22)
                }
                .buttonStyle(.plain)
            } else if manager.accounts.count <= visibleRowCount {
                accountRows
            } else {
                ScrollView {
                    accountRows
                }
                .frame(height: rowHeight * CGFloat(visibleRowCount))
            }
        }
        .frame(width: 340)
    }

    private var accountRows: some View {
        VStack(spacing: 0) {
            ForEach(manager.accounts) { account in
                Button(action: showManager) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(account.label)
                                .font(.body.weight(.medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            HStack(spacing: 6) {
                                Text(account.displayPlan)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                if manager.manualCurrentAccountID == account.id {
                                    ManualCurrentBadge(confirmedAt: manager.manualCurrentConfirmedAt)
                                }
                            }
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(balanceText(account))
                                .font(.body.weight(.semibold).monospacedDigit())
                                .foregroundStyle(balanceColor(account))
                            Text(quotaResetText(account, includeLabel: true))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        .help(quotaDescription(account))
                    }
                    .padding(.horizontal, 16)
                    .frame(height: rowHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("标记为当前（手动确认）") {
                        manager.markCurrentAccount(account.id)
                    }
                    if manager.manualCurrentAccountID == account.id {
                        Button("清除当前标记", action: manager.clearCurrentAccount)
                    }
                }
                .accessibilityLabel("\(account.label)，\(account.displayPlan)，余额\(balanceText(account))，下次重置\(quotaResetText(account))\(manager.manualCurrentAccountID == account.id ? "，当前（手动确认）" : "")")
                .help("\(quotaDescription(account))\n打开账号管理；右键可手动标记当前账号")
            }
        }
    }

    private func showManager() {
        openWindow(id: "accounts")
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct ManagerWindow: View {
    @Bindable var manager: AccountManager
    @State private var renameTarget: AccountRecord?
    @State private var subscriptionTarget: AccountRecord?
    @State private var removalTarget: AccountRecord?
    @State private var showingRemoval = false
    @State private var showingSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text("Codex 账号").font(.title2.weight(.semibold))
                Spacer()
                if manager.isBusy {
                    ProgressView().controlSize(.small)
                }
                Button("刷新全部", systemImage: "arrow.clockwise", action: manager.refreshAll)
                    .disabled(manager.isBusy || manager.accounts.isEmpty)
                Button("添加账号", systemImage: "plus", action: manager.addAccount)
                    .buttonStyle(.borderedProminent)
                    .disabled(manager.loginPending)
            }
            .padding(24)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if manager.loginPending {
                        LoginStatus(manager: manager)
                    }

                    if manager.accounts.isEmpty {
                        EmptyAccounts(addAction: manager.addAccount)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                            .disabled(manager.loginPending)
                    } else {
                        VStack(spacing: 0) {
                            HStack(spacing: 16) {
                                Text("账号").frame(maxWidth: .infinity, alignment: .leading)
                                Text("余额 / 下次重置").frame(width: 150, alignment: .trailing)
                                Text("订阅到期").frame(width: 126, alignment: .trailing)
                                Color.clear.frame(width: 22, height: 1)
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 10)

                            VStack(spacing: 0) {
                                ForEach(manager.accounts) { account in
                                    AccountSummary(
                                        account: account,
                                        busy: manager.busyAccountIDs.contains(account.id),
                                        isManuallyCurrent: manager.manualCurrentAccountID == account.id,
                                        manualCurrentConfirmedAt: manager.manualCurrentConfirmedAt,
                                        markCurrent: { manager.markCurrentAccount(account.id) },
                                        clearCurrent: manager.clearCurrentAccount,
                                        refresh: { manager.refreshAccount(account.id) },
                                        switchAccount: { manager.switchAccount(account.id) },
                                        reauthenticate: { manager.reauthenticateAccount(account.id) },
                                        rename: { renameTarget = account },
                                        editSubscription: { subscriptionTarget = account },
                                        remove: {
                                            removalTarget = account
                                            showingRemoval = true
                                        }
                                    )
                                    if account.id != manager.accounts.last?.id {
                                        Divider().padding(.horizontal, 16)
                                    }
                                }
                            }
                            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                            }
                        }
                    }

                    DisclosureGroup("设置", isExpanded: $showingSettings) {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 10) {
                                Text("每日更新")
                                Picker("每日更新时间", selection: Binding(
                                    get: { manager.dailyHour },
                                    set: { manager.setDailyHour($0) }
                                )) {
                                    ForEach(0..<24) { hour in
                                        Text(String(format: "%02d:00", hour)).tag(hour)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 100)
                                Text("本地时间").foregroundStyle(.secondary)
                                Spacer()
                            }
                            Toggle("登录 Mac 时启动", isOn: Binding(
                                get: { manager.launchAtLogin },
                                set: { manager.setLaunchAtLogin($0) }
                            ))
                        }
                        .padding(.top, 12)
                        .padding(.bottom, 4)
                    }
                    .foregroundStyle(.secondary)
                }
                .padding(24)
            }

            if let error = manager.lastError, !error.isEmpty {
                Divider()
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
            }
        }
        .frame(minWidth: 660, idealWidth: 760, minHeight: 400, idealHeight: 550)
        .sheet(item: $renameTarget) { account in
            AccountRenameSheet(account: account) { value in
                manager.renameAccount(account.id, to: value)
            }
        }
        .sheet(item: $subscriptionTarget) { account in
            SubscriptionSheet(account: account) { plan, date in
                manager.updateSubscription(account.id, planOverride: plan, expiresAt: date)
            }
        }
        .alert("移除已保存的账号？", isPresented: $showingRemoval, presenting: removalTarget) { account in
            Button("取消", role: .cancel) {}
            Button("移除", role: .destructive) {
                manager.removeAccount(account.id)
                removalTarget = nil
            }
        } message: { account in
            Text("将从本机管理器移除“\(account.label)”及其保存的登录信息。不会删除你的 OpenAI 账号。")
        }
    }
}

private struct AccountSummary: View {
    let account: AccountRecord
    let busy: Bool
    let isManuallyCurrent: Bool
    let manualCurrentConfirmedAt: Date?
    let markCurrent: () -> Void
    let clearCurrent: () -> Void
    let refresh: () -> Void
    let switchAccount: () -> Void
    let reauthenticate: () -> Void
    let rename: () -> Void
    let editSubscription: () -> Void
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(account.label)
                            .font(.body.weight(.semibold))
                            .lineLimit(1)
                        Text(account.displayPlan)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.quaternary, in: Capsule())
                            .fixedSize()
                    }
                    if !account.email.isEmpty, account.email != account.label {
                        Text(account.email)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .textSelection(.enabled)
                    }
                    if isManuallyCurrent {
                        ManualCurrentBadge(confirmedAt: manualCurrentConfirmedAt)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 5) {
                    Text(balanceText(account))
                        .font(.body.weight(.semibold).monospacedDigit())
                        .foregroundStyle(balanceColor(account))
                    Text(quotaResetText(account))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(width: 150, alignment: .trailing)
                .help(quotaDescription(account))

                Button(action: editSubscription) {
                    Text(account.subscriptionExpiresAt.map(expiryDate) ?? "未设置")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(account.subscriptionExpiresAt == nil ? Color.secondary : Color.primary)
                        .frame(width: 126, alignment: .trailing)
                }
                .buttonStyle(.plain)
                .help("编辑订阅到期时间")
                .disabled(busy)

                Menu {
                    Button("标记为当前（手动确认）", action: markCurrent)
                    if isManuallyCurrent {
                        Button("清除当前标记", action: clearCurrent)
                    }
                    Divider()
                    Button("编辑订阅", action: editSubscription)
                    Button("修改备注", action: rename)
                    Divider()
                    Button("刷新额度", action: refresh)
                    Button("辅助切换到 Codex", action: switchAccount)
                    Button("重新登录", action: reauthenticate)
                    Divider()
                    Button("移除账号", role: .destructive, action: remove)
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 22, height: 22)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .disabled(busy)
                .accessibilityLabel("\(account.label)的操作")
            }

            HStack(spacing: 6) {
                if busy {
                    ProgressView().controlSize(.mini)
                    Text("正在更新…")
                } else {
                    Text(account.updatedAt.map { "更新于 \(displayDate($0))" } ?? "尚未更新")
                }
                if account.subscriptionExpirySource == "manual", account.subscriptionExpiresAt != nil {
                    Text("· 到期时间手动填写")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            if account.needsLogin {
                Button("登录已失效，点击重新登录", action: reauthenticate)
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .disabled(busy)
            } else if let error = account.lastError, !error.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ManualCurrentBadge: View {
    let confirmedAt: Date?

    var body: some View {
        Text("当前（手动确认）")
            .font(.caption2.weight(.medium))
            .foregroundStyle(.blue)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.blue.opacity(0.09), in: Capsule())
            .fixedSize()
            .help(helpText)
    }

    private var helpText: String {
        let explanation = "由你手动确认，管理器不会自动识别 Codex 当前登录的账号。"
        guard let confirmedAt else { return explanation }
        return "\(explanation)\n确认于 \(displayDate(confirmedAt))"
    }
}

private struct EmptyAccounts: View {
    let addAction: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("还没有账号").font(.headline)
            Text("添加后，每天自动更新一次额度。")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("添加账号", systemImage: "plus", action: addAction)
                .buttonStyle(.borderedProminent)
        }
    }
}

private struct LoginStatus: View {
    @Bindable var manager: AccountManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("等待浏览器登录完成").font(.headline)
            }
            Text("请在官方登录页面完成验证，成功后这里会自动更新。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                if let url = manager.loginURL {
                    Link("打开登录页面", destination: url)
                }
                Spacer()
                Button("取消", action: manager.cancelLogin)
            }
            .controlSize(.small)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct SubscriptionSheet: View {
    let account: AccountRecord
    let save: (String?, Date?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var plan = "auto"
    @State private var hasExpiry = false
    @State private var expiresAt = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("编辑订阅").font(.title2.weight(.semibold))
            Text(account.label).foregroundStyle(.secondary)
            Picker("套餐", selection: $plan) {
                Text("自动").tag("auto")
                Text("Pro20X").tag("Pro20X")
                Text("Pro5X").tag("Pro5X")
            }
            Text("自动识别不到套餐档位时，可手动选择。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider()
            Toggle("设置订阅到期时间", isOn: $hasExpiry)
            if hasExpiry {
                DatePicker("到期日期", selection: $expiresAt, displayedComponents: .date)
            }
            Text("订阅到期日需手动填写，可在订阅账单中查看。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("保存") {
                    save(plan == "auto" ? nil : plan, hasExpiry ? expiresAt : nil)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 380)
        .onAppear {
            plan = account.planOverride ?? "auto"
            hasExpiry = account.subscriptionExpiresAt != nil
            expiresAt = account.subscriptionExpiresAt ?? Date()
        }
    }
}

private struct AccountRenameSheet: View {
    let account: AccountRecord
    let save: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var value = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("修改账号备注").font(.title2.weight(.semibold))
            Text(account.email).foregroundStyle(.secondary)
            TextField("例如：个人、工作", text: $value)
                .textFieldStyle(.roundedBorder)
                .onSubmit(saveAndDismiss)
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("保存", action: saveAndDismiss)
                    .keyboardShortcut(.defaultAction)
                    .disabled(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 360)
        .onAppear { value = account.label }
    }

    private func saveAndDismiss() {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        save(String(trimmed.prefix(100)))
        dismiss()
    }
}

private func balanceText(_ account: AccountRecord) -> String {
    guard let quota = account.summaryQuota else { return "—" }
    return "\(quota.remainingPercent.formatted(.number.precision(.fractionLength(0...1))))%"
}

private func balanceColor(_ account: AccountRecord) -> Color {
    guard let remaining = account.summaryQuota?.remainingPercent else { return .secondary }
    if remaining <= 10 { return .red }
    if remaining <= 25 { return .orange }
    return .primary
}

private func quotaDescription(_ account: AccountRecord) -> String {
    guard let quota = account.summaryQuota else { return "暂未获取额度" }
    if let resetsAt = quota.resetsAt {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm z"
        return "\(quota.name)，额度重置时间：\(formatter.string(from: resetsAt))"
    }
    return "\(quota.name)，额度重置时间未提供"
}

private func quotaResetText(_ account: AccountRecord, includeLabel: Bool = false) -> String {
    guard let resetsAt = account.summaryQuota?.resetsAt else { return "未提供" }
    guard resetsAt > Date() else { return "重置时间待刷新" }
    let formatter = DateFormatter()
    formatter.dateFormat = "MM-dd HH:mm"
    let date = formatter.string(from: resetsAt)
    return includeLabel ? "重置 \(date)" : date
}

private func expiryDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
}

private func displayDate(_ date: Date) -> String {
    date.formatted(date: .abbreviated, time: .shortened)
}
