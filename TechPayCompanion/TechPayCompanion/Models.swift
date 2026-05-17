import Foundation

struct WorkStopRecord: Identifiable, Codable, Hashable {
    var id = UUID().uuidString
    var date: String
    var name: String
    var address: String
    var orderNumber: String
    var locationNumber: String
    var timeStarted: String
    var timeCompleted: String
    var serviceType: String
    var payType: String
    var amount: Double?
    var rawText: String
    var importedAt: String
    var source = "TechPayCompanion-iOS"

    var missingFields: [String] {
        var fields: [String] = []
        if !Self.isWorkDate(date) { fields.append("date") }
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { fields.append("name") }
        if address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { fields.append("address") }
        if orderNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { fields.append("orderNumber") }
        if timeStarted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { fields.append("timeStarted") }
        if timeCompleted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { fields.append("timeCompleted") }
        if !timeStarted.isEmpty, !timeCompleted.isEmpty, !Self.isChronological(started: timeStarted, completed: timeCompleted) {
            fields.append("timeCompleted")
        }
        if serviceType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { fields.append("serviceType") }
        if payType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { fields.append("payType") }
        if amount == nil { fields.append("amount") }
        return fields
    }

    var isComplete: Bool {
        missingFields.isEmpty
    }

    private static func isWorkDate(_ value: String) -> Bool {
        value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
    }

    private static func isChronological(started: String, completed: String) -> Bool {
        guard let startedMinutes = minutesSinceMidnight(started),
              let completedMinutes = minutesSinceMidnight(completed) else {
            return false
        }

        return completedMinutes > startedMinutes
    }

    private static func minutesSinceMidnight(_ value: String) -> Int? {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s*([AP]M)$"#, with: " $1", options: [.regularExpression, .caseInsensitive])
            .uppercased()
        guard let match = normalized.range(of: #"^(\d{1,2}):(\d{2})\s*([AP]M)$"#, options: .regularExpression) else {
            return nil
        }

        let parts = String(normalized[match])
            .replacingOccurrences(of: ":", with: " ")
            .split(separator: " ")
        guard parts.count == 3,
              var hour = Int(parts[0]),
              let minute = Int(parts[1]) else {
            return nil
        }

        let marker = String(parts[2])
        if marker == "PM", hour != 12 { hour += 12 }
        if marker == "AM", hour == 12 { hour = 0 }
        return hour * 60 + minute
    }
}

struct ImportBatch: Codable {
    var schema = "tech-pay.import-batch.v1"
    var createdAt: String
    var source = "TechPayCompanion-iOS"
    var records: [WorkStopRecord]
}

struct ServicePayMapping {
    static let values: [String: String] = [
        "Taexx Pest Control Service": "Prod",
        "Taexx (HBIS) Pest Control Service": "Prod",
        "HBTI Service": "TI",
        "Builder Taexx Initial Service": "Prod",
        "Termite Bait Sentricon Installation AA": "SEN INI",
        "Integrated Pest Control Service": "Prod",
        "Pest Control Service": "Prod",
        "Taexx Service Request": "ISR",
        "Sentricon Monitoring AA": "SENTRICON",
        "Pest Control Miscellaneous": "PM",
        "Mosquito Control Service": "MSC",
        "Bait Inspection Outside Only": "MISC NOPAY",
        "Miscellaneous Pest Ongoing Service": "Prod"
    ]
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

    static let fileStamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter
    }()
}
