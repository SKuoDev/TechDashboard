import Foundation

struct WorkStopRecord: Identifiable, Codable, Hashable {
    var id: String
    var date: String
    var name: String
    var address: String
    var orderNumber: String
    var locationNumber: String?
    var timeStarted: String
    var timeCompleted: String
    var serviceType: String
    var payType: String
    var amount: Double?
    var rawText: String?
    var importedAt: String?
    var source: String?
    var updatedAt: String?
    var resolvedAt: String?
    var unresolvedAt: String?

    init(
        id: String = UUID().uuidString,
        date: String = DateFormatter.workDate.string(from: Date()),
        name: String = "",
        address: String = "",
        orderNumber: String = "",
        locationNumber: String? = "",
        timeStarted: String = "",
        timeCompleted: String = "",
        serviceType: String = "",
        payType: String = "",
        amount: Double? = nil,
        rawText: String? = "",
        importedAt: String? = ISO8601DateFormatter.techPay.string(from: Date()),
        source: String? = "TechDashboardiOS",
        updatedAt: String? = nil,
        resolvedAt: String? = nil,
        unresolvedAt: String? = nil
    ) {
        self.id = id
        self.date = date
        self.name = name
        self.address = address
        self.orderNumber = orderNumber
        self.locationNumber = locationNumber
        self.timeStarted = timeStarted
        self.timeCompleted = timeCompleted
        self.serviceType = serviceType
        self.payType = payType
        self.amount = amount
        self.rawText = rawText
        self.importedAt = importedAt
        self.source = source
        self.updatedAt = updatedAt
        self.resolvedAt = resolvedAt
        self.unresolvedAt = unresolvedAt
    }

    var missingFields: [String] {
        var fields: [String] = []
        if !Self.isWorkDate(date) { fields.append("date") }
        if name.trimmed.isEmpty { fields.append("name") }
        if address.trimmed.isEmpty { fields.append("address") }
        if orderNumber.trimmed.isEmpty { fields.append("orderNumber") }
        if timeStarted.trimmed.isEmpty { fields.append("timeStarted") }
        if timeCompleted.trimmed.isEmpty { fields.append("timeCompleted") }
        if !timeStarted.trimmed.isEmpty, !timeCompleted.trimmed.isEmpty, !Self.isChronological(started: timeStarted, completed: timeCompleted) {
            fields.append("timeCompleted")
        }
        if serviceType.trimmed.isEmpty { fields.append("serviceType") }
        if !PayCatalog.payTypes.contains(payType) { fields.append("payType") }
        if amount == nil { fields.append("amount") }
        return fields
    }

    var isComplete: Bool {
        missingFields.isEmpty
    }

    var finalized: WorkStopRecord {
        var record = self
        record.unresolvedAt = nil
        record.resolvedAt = unresolvedAt == nil ? resolvedAt : ISO8601DateFormatter.techPay.string(from: Date())
        return record
    }

    private static func isWorkDate(_ value: String) -> Bool {
        value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
    }

    static func minutesSinceMidnight(_ value: String) -> Int? {
        let normalized = value
            .trimmed
            .replacingOccurrences(of: #"\s*([AP]M)$"#, with: " $1", options: [.regularExpression, .caseInsensitive])
            .uppercased()

        guard normalized.range(of: #"^(\d{1,2}):(\d{2})\s*([AP]M)$"#, options: .regularExpression) != nil else {
            return nil
        }

        let parts = normalized.replacingOccurrences(of: ":", with: " ").split(separator: " ")
        guard parts.count == 3, var hour = Int(parts[0]), let minute = Int(parts[1]) else {
            return nil
        }

        let marker = String(parts[2])
        if marker == "PM", hour != 12 { hour += 12 }
        if marker == "AM", hour == 12 { hour = 0 }
        return hour * 60 + minute
    }

    private static func isChronological(started: String, completed: String) -> Bool {
        guard let startedMinutes = minutesSinceMidnight(started),
              let completedMinutes = minutesSinceMidnight(completed) else {
            return false
        }

        return completedMinutes > startedMinutes
    }
}

struct ImportBatch: Codable {
    var schema: String? = "tech-pay.import-batch.v1"
    var createdAt: String? = ISO8601DateFormatter.techPay.string(from: Date())
    var source: String? = "TechDashboardiOS"
    var records: [WorkStopRecord]?
    var imported: [WorkStopRecord]?

    var batchRecords: [WorkStopRecord] {
        records ?? imported ?? []
    }
}

struct PaySettings: Codable, Hashable {
    var commissionRate: Double = 0.2
}

struct PayRule: Codable, Hashable {
    var label: String
    var rule: String
}

struct PayRuleDefinition: Hashable {
    var name: String
    var equation: String
    var calculation: PayCalculation
}

enum PayCalculation: Hashable {
    case commission(multiplier: Double)
    case percent(rate: Double)
    case flat(amount: Double)
    case none
}

struct ImportSummary: Hashable {
    var database: String
    var date: String
    var saved: Int
    var unresolved: Int
    var duplicates: Int
    var completedAt: Date
}

struct DashboardTotals {
    var mtdProduction: Double = 0
    var mtdStops: Int = 0
    var mtdPay: Double = 0
    var mtdHours: Double = 0
    var dayProduction: Double = 0
    var dayStops: Int = 0
    var dayPay: Double = 0
    var dayHours: Double = 0

    var mtdHourly: Double {
        mtdHours > 0 ? mtdPay / mtdHours : 0
    }

    var dayHourly: Double {
        dayHours > 0 ? dayPay / dayHours : 0
    }
}

struct PayBreakdownRow: Identifiable {
    var id: String { payType }
    var payType: String
    var stops: Int
    var production: Double
    var pay: Double
}

enum PayCatalog {
    static let payTypes = ["Prod", "IS INI", "PS INI", "SENTRICON", "SEN INI", "TI", "ISR", "PM", "MSC", "MSS", "MISC NOPAY"]

    static let defaultMappings = [
        "Taexx Pest Control Service": "Prod"
    ]

    static let defaultRules: [String: PayRule] = [
        "Prod": PayRule(label: "Production", rule: "commission"),
        "IS INI": PayRule(label: "Inside Initial", rule: "initialCommission"),
        "PS INI": PayRule(label: "Premium Service Initial", rule: "initialCommission"),
        "SENTRICON": PayRule(label: "Sentricon", rule: "sentriconEightPercent"),
        "SEN INI": PayRule(label: "Sentricon Initial", rule: "flat45"),
        "TI": PayRule(label: "Termite Inspection", rule: "flat10"),
        "ISR": PayRule(label: "Inside Sales Referral", rule: "noPay"),
        "PM": PayRule(label: "Production Management", rule: "commission"),
        "MSC": PayRule(label: "MSC", rule: "commission"),
        "MSS": PayRule(label: "MSS", rule: "commission"),
        "MISC NOPAY": PayRule(label: "Misc No Pay", rule: "noPay")
    ]

    static let ruleDefinitions: [String: PayRuleDefinition] = [
        "commission": PayRuleDefinition(name: "Commission", equation: "Amount x Commission Rate", calculation: .commission(multiplier: 1)),
        "initialCommission": PayRuleDefinition(name: "Initial Service", equation: "Amount x Commission Rate x 1.5", calculation: .commission(multiplier: 1.5)),
        "sentriconEightPercent": PayRuleDefinition(name: "Sentricon", equation: "Amount x 8%", calculation: .percent(rate: 0.08)),
        "flat10": PayRuleDefinition(name: "Flat Rate", equation: "$10.00", calculation: .flat(amount: 10)),
        "flat45": PayRuleDefinition(name: "Flat Rate", equation: "$45.00", calculation: .flat(amount: 45)),
        "noPay": PayRuleDefinition(name: "No Pay", equation: "$0.00", calculation: .none)
    ]
}

extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension ISO8601DateFormatter {
    static let techPay: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

extension DateFormatter {
    static let workDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static let shortWorkDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter
    }()

    static let fileStamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter
    }()
}
