import Foundation
import UniformTypeIdentifiers

@MainActor
final class DashboardStore: ObservableObject {
    @Published var folderURL: URL?
    @Published var databases: [String] = []
    @Published var selectedDatabase = "work-stops.json"
    @Published var records: [WorkStopRecord] = []
    @Published var unresolved: [WorkStopRecord] = []
    @Published var paySettings = PaySettings()
    @Published var payMappings = PayCatalog.defaultMappings
    @Published var payRules = PayCatalog.defaultRules
    @Published var status = "Choose the iCloud Drive folder that contains your Tech Pay JSON files."
    @Published var lastImportSummary: ImportSummary?
    @Published var isUsingLocalStorage = false

    private let bookmarkKey = "TechDashboardiOSFolderBookmark"
    private let localStorageKey = "TechDashboardiOSUsesLocalStorage"
    private let selectedDatabaseKey = "TechDashboardiOSSelectedDatabase"
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
    private let decoder = JSONDecoder()

    init() {
        selectedDatabase = UserDefaults.standard.string(forKey: selectedDatabaseKey) ?? "work-stops.json"
        restoreFolderBookmark()
    }

    var hasFolder: Bool {
        folderURL != nil
    }

    var folderName: String {
        isUsingLocalStorage ? "This iPhone" : folderURL?.lastPathComponent ?? "No folder selected"
    }

    func connectFolder(_ url: URL) {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess { url.stopAccessingSecurityScopedResource() }
        }

        do {
            let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
            UserDefaults.standard.set(false, forKey: localStorageKey)
            isUsingLocalStorage = false
            folderURL = url
            loadAll()
        } catch {
            status = "Could not save folder access: \(error.localizedDescription)"
        }
    }

    func useLocalStorage() {
        do {
            let url = try localStorageURL()
            UserDefaults.standard.set(true, forKey: localStorageKey)
            UserDefaults.standard.removeObject(forKey: bookmarkKey)
            isUsingLocalStorage = true
            folderURL = url
            loadAll()
            status = "Using files stored on this iPhone."
        } catch {
            status = "Could not create phone storage: \(error.localizedDescription)"
        }
    }

    func loadAll() {
        guard let folderURL else { return }
        let didAccess = folderURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess { folderURL.stopAccessingSecurityScopedResource() }
        }

        do {
            try ensureCoreFilesExist()
            databases = try listDatabases()
            if !databases.contains(selectedDatabase) {
                selectedDatabase = databases.first ?? "work-stops.json"
            }
            UserDefaults.standard.set(selectedDatabase, forKey: selectedDatabaseKey)
            records = try readArray(selectedDatabase)
            unresolved = try readArray(unresolvedFileName(for: selectedDatabase))
            paySettings = try readObject("pay-settings.json", fallback: PaySettings())
            payMappings = PayCatalog.defaultMappings.merging(try readObject("pay-type-mappings.json", fallback: PayCatalog.defaultMappings)) { _, new in new }
            payRules = normalizedPayRules(try readObject("pay-rules.json", fallback: PayCatalog.defaultRules))
            try writeObject(paySettings, to: "pay-settings.json")
            try writeObject(payMappings, to: "pay-type-mappings.json")
            try writeObject(payRules, to: "pay-rules.json")
            status = "Loaded \(selectedDatabase)."
        } catch {
            status = "Could not load files: \(error.localizedDescription)"
        }
    }

    func selectDatabase(_ database: String) {
        selectedDatabase = database
        UserDefaults.standard.set(database, forKey: selectedDatabaseKey)
        loadAll()
    }

    func createDatabase(named name: String) {
        let database = cleanDatabaseName(name)
        guard !database.isEmpty else { return }

        performFileWrite {
            if self.databases.contains(database) {
                self.status = "\(database) already exists."
                return
            }

            try self.writeArray([WorkStopRecord](), to: database)
            try self.writeArray([WorkStopRecord](), to: self.unresolvedFileName(for: database))
            self.selectedDatabase = database
            self.loadAll()
            self.status = "Created \(database)."
        }
    }

    func deleteCurrentDatabase() {
        guard selectedDatabase != "work-stops.json" else {
            status = "The default save file cannot be deleted."
            return
        }

        performFileWrite {
            try self.fileURL(self.selectedDatabase).remove()
            try? self.fileURL(self.unresolvedFileName(for: self.selectedDatabase)).remove()
            self.selectedDatabase = "work-stops.json"
            self.loadAll()
            self.status = "Deleted save file."
        }
    }

    func saveRecord(_ record: WorkStopRecord) {
        guard record.isComplete else {
            status = "Fill in all required fields before saving."
            return
        }

        performFileWrite {
            var updated = record.finalized
            updated.updatedAt = ISO8601DateFormatter.techPay.string(from: Date())
            guard !self.records.contains(where: { $0.id != updated.id && !$0.orderNumber.isEmpty && $0.orderNumber == updated.orderNumber }) else {
                self.status = "Order #\(updated.orderNumber) already exists in this save file."
                return
            }

            if let index = self.records.firstIndex(where: { $0.id == updated.id }) {
                self.records[index] = updated
            } else {
                self.records.append(updated)
            }
            self.payMappings[updated.serviceType] = updated.payType
            try self.writeArray(self.records, to: self.selectedDatabase)
            try self.writeObject(self.payMappings, to: "pay-type-mappings.json")
            self.status = "Saved \(updated.name.isEmpty ? "record" : updated.name)."
        }
    }

    func deleteRecord(_ record: WorkStopRecord) {
        performFileWrite {
            self.records.removeAll { $0.id == record.id }
            try self.writeArray(self.records, to: self.selectedDatabase)
            self.status = "Deleted record."
        }
    }

    func resolve(_ record: WorkStopRecord) {
        guard record.isComplete else {
            status = "Fill in the required fields before resolving."
            return
        }

        performFileWrite {
            let finalized = record.finalized
            guard !self.records.contains(where: { !$0.orderNumber.isEmpty && $0.orderNumber == finalized.orderNumber }) else {
                self.status = "Order #\(finalized.orderNumber) already exists in this save file."
                return
            }

            self.records.append(finalized)
            self.unresolved.removeAll { $0.id == record.id }
            self.payMappings[finalized.serviceType] = finalized.payType
            try self.writeArray(self.records, to: self.selectedDatabase)
            try self.writeArray(self.unresolved, to: self.unresolvedFileName(for: self.selectedDatabase))
            try self.writeObject(self.payMappings, to: "pay-type-mappings.json")
            self.status = "Resolved entry."
        }
    }

    func skipUnresolved(_ record: WorkStopRecord) {
        performFileWrite {
            self.unresolved.removeAll { $0.id == record.id }
            try self.writeArray(self.unresolved, to: self.unresolvedFileName(for: self.selectedDatabase))
            self.status = "Skipped unresolved entry."
        }
    }

    func importBatch(from url: URL, fallbackDate: Date) {
        performFileWrite {
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess { url.stopAccessingSecurityScopedResource() }
            }

            let data = try Data(contentsOf: url)
            let payload = try self.decoder.decode(ImportBatch.self, from: data)
            let fallbackDateText = DateFormatter.workDate.string(from: fallbackDate)
            let incoming = payload.batchRecords.map { self.normalizedBatchRecord($0, fallbackDate: fallbackDateText) }
            guard !incoming.isEmpty else {
                self.status = "That import batch did not contain any records."
                return
            }

            var saved = 0
            var unresolvedCount = 0
            var duplicates = 0
            var seen = Set(self.records.map(\.orderNumber).filter { !$0.isEmpty } + self.unresolved.map(\.orderNumber).filter { !$0.isEmpty })

            for record in incoming {
                let orderNumber = record.orderNumber.trimmed
                if !orderNumber.isEmpty, seen.contains(orderNumber) {
                    duplicates += 1
                    continue
                }
                if !orderNumber.isEmpty {
                    seen.insert(orderNumber)
                }

                if record.isComplete {
                    self.records.append(record.finalized)
                    saved += 1
                } else {
                    var unresolvedRecord = record
                    unresolvedRecord.unresolvedAt = ISO8601DateFormatter.techPay.string(from: Date())
                    self.unresolved.append(unresolvedRecord)
                    unresolvedCount += 1
                }
            }

            try self.writeArray(self.records, to: self.selectedDatabase)
            try self.writeArray(self.unresolved, to: self.unresolvedFileName(for: self.selectedDatabase))
            self.lastImportSummary = ImportSummary(database: self.selectedDatabase, date: fallbackDateText, saved: saved, unresolved: unresolvedCount, duplicates: duplicates, completedAt: Date())
            self.status = "Imported \(saved) saved, \(unresolvedCount) unresolved, \(duplicates) duplicates."
        }
    }

    func submitImportedRecords(_ importedRecords: [WorkStopRecord], fallbackDate: Date) -> ImportSummary? {
        var summary: ImportSummary?
        performFileWrite {
            let fallbackDateText = DateFormatter.workDate.string(from: fallbackDate)
            let incoming = importedRecords.map { self.normalizedBatchRecord($0, fallbackDate: fallbackDateText) }
            guard !incoming.isEmpty else {
                self.status = "No import records to submit."
                return
            }

            var saved = 0
            var unresolvedCount = 0
            var duplicates = 0
            var seen = Set(self.records.map(\.orderNumber).filter { !$0.isEmpty } + self.unresolved.map(\.orderNumber).filter { !$0.isEmpty })

            for record in incoming {
                let orderNumber = record.orderNumber.trimmed
                if !orderNumber.isEmpty, seen.contains(orderNumber) {
                    duplicates += 1
                    continue
                }
                if !orderNumber.isEmpty {
                    seen.insert(orderNumber)
                }

                if record.isComplete {
                    self.records.append(record.finalized)
                    saved += 1
                } else {
                    var unresolvedRecord = record
                    unresolvedRecord.unresolvedAt = ISO8601DateFormatter.techPay.string(from: Date())
                    self.unresolved.append(unresolvedRecord)
                    unresolvedCount += 1
                }
            }

            try self.writeArray(self.records, to: self.selectedDatabase)
            try self.writeArray(self.unresolved, to: self.unresolvedFileName(for: self.selectedDatabase))
            summary = ImportSummary(database: self.selectedDatabase, date: fallbackDateText, saved: saved, unresolved: unresolvedCount, duplicates: duplicates, completedAt: Date())
            self.lastImportSummary = summary
            self.status = "Submitted \(saved) saved, \(unresolvedCount) unresolved, \(duplicates) duplicates."
        }
        return summary
    }

    func savePaySettings(rate: Double) {
        performFileWrite {
            self.paySettings = PaySettings(commissionRate: max(0, min(rate, 1)))
            try self.writeObject(self.paySettings, to: "pay-settings.json")
            self.status = "Pay settings saved."
        }
    }

    func saveMapping(serviceType: String, payType: String) {
        let service = serviceType.trimmed
        guard !service.isEmpty, PayCatalog.payTypes.contains(payType) else { return }

        performFileWrite {
            self.payMappings[service] = payType
            try self.writeObject(self.payMappings, to: "pay-type-mappings.json")
            self.status = "Mapping saved."
        }
    }

    func deleteMapping(serviceType: String) {
        performFileWrite {
            self.payMappings.removeValue(forKey: serviceType)
            try self.writeObject(self.payMappings, to: "pay-type-mappings.json")
            self.status = "Mapping removed."
        }
    }

    func totals(for date: Date) -> DashboardTotals {
        let selectedDate = DateFormatter.workDate.string(from: date)
        let selectedMonth = String(selectedDate.prefix(7))
        let dayRecords = records.filter { $0.date == selectedDate }
        let mtdRecords = records.filter { $0.date.prefix(7) == selectedMonth && $0.date <= selectedDate }
        let dayPay = payTotal(dayRecords)
        let mtdPay = payTotal(mtdRecords)
        let dayHours = hoursWorked(dayRecords)
        let mtdHours = totalWorkedHours(mtdRecords)

        return DashboardTotals(
            mtdProduction: productionTotal(mtdRecords),
            mtdStops: mtdRecords.count,
            mtdPay: mtdPay,
            mtdHours: mtdHours,
            dayProduction: productionTotal(dayRecords),
            dayStops: dayRecords.count,
            dayPay: dayPay,
            dayHours: dayHours
        )
    }

    func dayRecords(for date: Date) -> [WorkStopRecord] {
        let selectedDate = DateFormatter.workDate.string(from: date)
        return records
            .filter { $0.date == selectedDate }
            .sorted { $0.timeStarted < $1.timeStarted }
    }

    func payBreakdown(for date: Date) -> [PayBreakdownRow] {
        let selectedDate = DateFormatter.workDate.string(from: date)
        let selectedMonth = String(selectedDate.prefix(7))
        let mtdRecords = records.filter { $0.date.prefix(7) == selectedMonth && $0.date <= selectedDate }
        var rows: [String: PayBreakdownRow] = [:]

        for record in mtdRecords {
            let payType = record.payType.isEmpty ? "Unassigned" : record.payType
            var row = rows[payType] ?? PayBreakdownRow(payType: payType, stops: 0, production: 0, pay: 0)
            row.stops += 1
            row.production += record.amount ?? 0
            row.pay += calculateRecordPay(record)
            rows[payType] = row
        }

        return rows.values.sorted { $0.payType < $1.payType }
    }

    func calculateRecordPay(_ record: WorkStopRecord) -> Double {
        let amount = record.amount ?? 0
        let ruleKey = payRules[record.payType]?.rule ?? "noPay"
        let calculation = PayCatalog.ruleDefinitions[ruleKey]?.calculation ?? .none

        switch calculation {
        case .commission(let multiplier):
            return amount * paySettings.commissionRate * multiplier
        case .percent(let rate):
            return amount * rate
        case .flat(let amount):
            return amount
        case .none:
            return 0
        }
    }

    private func restoreFolderBookmark() {
        if UserDefaults.standard.bool(forKey: localStorageKey) {
            do {
                folderURL = try localStorageURL()
                isUsingLocalStorage = true
                loadAll()
            } catch {
                status = "Could not open phone storage: \(error.localizedDescription)"
            }
            return
        }

        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return }

        do {
            var stale = false
            let url = try URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
            isUsingLocalStorage = false
            folderURL = url
            if stale {
                connectFolder(url)
            } else {
                loadAll()
            }
        } catch {
            status = "Choose your iCloud Drive folder again."
        }
    }

    private func localStorageURL() throws -> URL {
        let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let url = documents.appendingPathComponent("Tech Pay Data", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func performFileWrite(_ action: () throws -> Void) {
        guard let folderURL else {
            status = "Choose an iCloud Drive folder first."
            return
        }

        let didAccess = folderURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess { folderURL.stopAccessingSecurityScopedResource() }
        }

        do {
            try action()
            loadAll()
        } catch {
            status = "Could not save: \(error.localizedDescription)"
        }
    }

    private func ensureCoreFilesExist() throws {
        if !FileManager.default.fileExists(atPath: fileURL("work-stops.json").path) {
            try writeArray([WorkStopRecord](), to: "work-stops.json")
        }
        if !FileManager.default.fileExists(atPath: fileURL("unresolved-work-stops.json").path) {
            try writeArray([WorkStopRecord](), to: "unresolved-work-stops.json")
        }
        if !FileManager.default.fileExists(atPath: fileURL("pay-settings.json").path) {
            try writeObject(PaySettings(), to: "pay-settings.json")
        }
        if !FileManager.default.fileExists(atPath: fileURL("pay-type-mappings.json").path) {
            try writeObject(PayCatalog.defaultMappings, to: "pay-type-mappings.json")
        }
        if !FileManager.default.fileExists(atPath: fileURL("pay-rules.json").path) {
            try writeObject(PayCatalog.defaultRules, to: "pay-rules.json")
        }
    }

    private func listDatabases() throws -> [String] {
        guard let folderURL else { return [] }
        let entries = try FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)
        let excluded = Set(["pay-type-mappings.json", "pay-settings.json", "pay-rules.json", "package.json", "package-lock.json"])
        var names: [String] = []

        for url in entries where url.pathExtension == "json" {
            let name = url.lastPathComponent
            guard !name.hasPrefix("unresolved-"), !excluded.contains(name) else { continue }
            if (try? readArray(name) as [WorkStopRecord]) != nil {
                names.append(name)
            }
        }

        return names.sorted()
    }

    private func normalizedPayRules(_ source: [String: PayRule]) -> [String: PayRule] {
        var rules = PayCatalog.defaultRules
        for payType in PayCatalog.payTypes {
            if let rule = source[payType], PayCatalog.ruleDefinitions[rule.rule] != nil {
                rules[payType] = rule
            }
        }
        return rules
    }

    private func normalizedBatchRecord(_ source: WorkStopRecord, fallbackDate: String) -> WorkStopRecord {
        var record = source
        if record.date.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) == nil {
            record.date = fallbackDate
        }
        record.name = record.name.trimmed
        record.address = record.address.trimmed
        record.orderNumber = record.orderNumber.trimmed
        record.locationNumber = record.locationNumber?.trimmed
        record.timeStarted = normalizeTime(record.timeStarted)
        record.timeCompleted = normalizeTime(record.timeCompleted)
        record.serviceType = record.serviceType.trimmed
        record.payType = record.payType.trimmed.isEmpty ? payMappings[record.serviceType] ?? "" : record.payType.trimmed
        record.importedAt = record.importedAt ?? ISO8601DateFormatter.techPay.string(from: Date())
        record.source = record.source ?? "ios-batch"
        return record
    }

    private func normalizeTime(_ value: String) -> String {
        value
            .trimmed
            .replacingOccurrences(of: #"\s*([AP]M)$"#, with: " $1", options: [.regularExpression, .caseInsensitive])
            .uppercased()
    }

    private func cleanDatabaseName(_ name: String) -> String {
        let base = name
            .replacingOccurrences(of: ".json", with: "", options: .caseInsensitive)
            .lowercased()
            .components(separatedBy: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789 _-").inverted)
            .joined()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: "-")
        return "\(base.isEmpty ? "work-stops" : base).json"
    }

    private func unresolvedFileName(for database: String) -> String {
        "unresolved-\(database.replacingOccurrences(of: ".json", with: ""))" + ".json"
    }

    private func fileURL(_ name: String) -> URL {
        folderURL!.appendingPathComponent(name)
    }

    private func readArray<T: Decodable>(_ name: String) throws -> [T] {
        let url = fileURL(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try decoder.decode([T].self, from: Data(contentsOf: url))
    }

    private func readObject<T: Decodable>(_ name: String, fallback: T) throws -> T {
        let url = fileURL(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return fallback }
        return (try? decoder.decode(T.self, from: Data(contentsOf: url))) ?? fallback
    }

    private func writeArray<T: Encodable>(_ values: [T], to name: String) throws {
        try encoder.encode(values).write(to: fileURL(name), options: [.atomic])
    }

    private func writeObject<T: Encodable>(_ value: T, to name: String) throws {
        try encoder.encode(value).write(to: fileURL(name), options: [.atomic])
    }

    private func productionTotal(_ records: [WorkStopRecord]) -> Double {
        records.reduce(0) { $0 + ($1.amount ?? 0) }
    }

    private func payTotal(_ records: [WorkStopRecord]) -> Double {
        records.reduce(0) { $0 + calculateRecordPay($1) }
    }

    private func totalWorkedHours(_ records: [WorkStopRecord]) -> Double {
        Dictionary(grouping: records, by: \.date).values.reduce(0) { $0 + hoursWorked(Array($1)) }
    }

    private func hoursWorked(_ records: [WorkStopRecord]) -> Double {
        let starts = records.compactMap { WorkStopRecord.minutesSinceMidnight($0.timeStarted) }
        let completions = records.compactMap { WorkStopRecord.minutesSinceMidnight($0.timeCompleted) }
        guard let firstStart = starts.min(), let lastCompletion = completions.max() else { return 0 }
        return max(0, Double(lastCompletion - firstStart) / 60)
    }
}

extension URL {
    func remove() throws {
        try FileManager.default.removeItem(at: self)
    }
}
