import Foundation

struct QuotaRecord: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var usedPercent: Double
    var windowMinutes: Int?
    var resetsAt: Date?
    var remainingPercent: Double { max(0, min(100, 100 - usedPercent)) }
}

struct AccountRecord: Identifiable, Codable, Equatable {
    var id: UUID
    var label: String
    var email: String
    var plan: String
    var serverAccountID: String?
    var updatedAt: Date?
    var lastError: String?
    var needsLogin: Bool
    var quotas: [QuotaRecord]
    var credits: String?
    var planOverride: String? = nil
    var subscriptionExpiresAt: Date? = nil
    var subscriptionExpirySource: String? = nil

    // Compact names for the Pro subscription levels. Preserve the raw service
    // plan independently of any user-selected display override.
    var displayPlan: String {
        if let planOverride, ["Pro20X", "Pro5X"].contains(planOverride) { return planOverride }
        switch plan.lowercased() {
        case "pro": return "Pro20X"
        case "prolite": return "Pro5X"
        case "plus": return "Plus"
        case "free": return "Free"
        case "unknown", "": return "未识别"
        default: return plan
        }
    }

    // The compact balance is the ordinary Codex weekly allowance when supplied,
    // otherwise its primary window. Never substitute a reserve-model allowance.
    var summaryQuota: QuotaRecord? {
        let ordinary = quotas.filter { $0.id.hasPrefix("codex:") }
        return ordinary.first(where: { $0.windowMinutes == 10080 })
            ?? ordinary.first(where: { $0.id == "codex:primary" })
            ?? ordinary.first
    }
}

struct SavedState: Codable {
    var version = 1
    var accounts: [AccountRecord] = []
    var dailyHour = 9
    var automaticAttempts: [String: Int] = [:]
    var lastAttemptAt: [String: Date] = [:]
    var manualCurrentAccountID: UUID? = nil
    var manualCurrentConfirmedAt: Date? = nil
}

enum DailyPolicy {
    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    static func needsRefresh(updatedAt: Date?, now: Date, hour: Int, calendar: Calendar = .current) -> Bool {
        guard let updatedAt else { return true }
        guard !calendar.isDate(updatedAt, inSameDayAs: now) else { return false }
        if calendar.component(.hour, from: now) >= hour { return true }
        let start = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: start)!
        let previousDeadline = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: yesterday)!
        return updatedAt < previousDeadline
    }

    static func nextDate(after now: Date, hour: Int, calendar: Calendar = .current) -> Date {
        calendar.nextDate(after: now, matching: DateComponents(hour: hour, minute: 0), matchingPolicy: .nextTime) ?? now.addingTimeInterval(86_400)
    }
}

struct QuotaSnapshot {
    var accountID: String?
    var plan: String?
    var quotas: [QuotaRecord]
    var credits: String?
}

enum SnapshotParser {
    static func parse(_ value: JSONValue) -> QuotaSnapshot {
        let map = value["rateLimitsByLimitId"].objectValue
        let buckets: [(String, JSONValue)]
        if let map, !map.isEmpty {
            buckets = map.sorted { a, b in
                if a.key == "codex" { return true }
                if b.key == "codex" { return false }
                return a.key < b.key
            }.map { ($0.key, $0.value) }
        } else if value["rateLimits"].objectValue != nil {
            buckets = [(value["rateLimits"]["limitId"].stringValue ?? "codex", value["rateLimits"])]
        } else { buckets = [] }
        var quotas: [QuotaRecord] = []
        var plan: String?
        var credits: String?
        for (id, bucket) in buckets {
            plan = plan ?? bucket["planType"].stringValue
            let name = bucket["limitName"].stringValue ?? (id == "codex" ? "Codex" : id)
            for key in ["primary", "secondary"] {
                let window = bucket[key]
                guard let used = window["usedPercent"].doubleValue else { continue }
                let minutes = window["windowDurationMins"].intValue
                let label: String
                switch minutes {
                case 300: label = "5 小时"
                case 10080: label = "每周"
                case .some(let n) where n % 1440 == 0: label = "\(n / 1440) 天"
                case .some(let n) where n % 60 == 0: label = "\(n / 60) 小时"
                case .some(let n): label = "\(n) 分钟"
                case nil: label = key == "primary" ? "主要额度" : "次要额度"
                }
                quotas.append(QuotaRecord(id: "\(id):\(key)", name: "\(name) · \(label)", usedPercent: used, windowMinutes: minutes, resetsAt: window["resetsAt"].doubleValue.map(Date.init(timeIntervalSince1970:))))
            }
            if id == "codex" {
                if bucket["credits"]["unlimited"].boolValue == true { credits = "不限量" }
                else { credits = bucket["credits"]["balance"].stringValue }
            }
        }
        return QuotaSnapshot(accountID: value["accountId"].stringValue, plan: plan, quotas: quotas, credits: credits)
    }
}
