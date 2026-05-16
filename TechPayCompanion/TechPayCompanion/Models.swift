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
