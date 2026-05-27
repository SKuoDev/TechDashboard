import PhotosUI
import SwiftUI
import UIKit
import Vision

@MainActor
final class ScreenshotImportViewModel: ObservableObject {
    @Published var selectedItems: [PhotosPickerItem] = []
    @Published var workDate = Date()
    @Published var records: [WorkStopRecord] = []
    @Published var isProcessing = false
    @Published var status = "Select work-stop screenshots."

    private let ocrService = OCRService()

    var completeCount: Int {
        records.filter(\.isComplete).count
    }

    var unresolvedCount: Int {
        records.count - completeCount
    }

    func processSelection(payMappings: [String: String]) async {
        guard !selectedItems.isEmpty else {
            status = "Select work-stop screenshots."
            return
        }

        isProcessing = true
        records.removeAll()
        status = "Reading \(selectedItems.count) screenshot\(selectedItems.count == 1 ? "" : "s")..."

        let parser = WorkStopParser(payMappings: payMappings)
        var parsedRecords: [WorkStopRecord] = []

        for item in selectedItems {
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data),
                      let cgImage = image.cgImage else {
                    continue
                }

                let text = try await ocrService.recognizeText(in: cgImage)
                parsedRecords.append(parser.parse(rawText: text, workDate: workDate))
            } catch {
                status = error.localizedDescription
            }
        }

        records = parsedRecords
        status = "Ready to submit: \(completeCount) complete, \(unresolvedCount) needs review."
        isProcessing = false
    }

    func batchDocument() -> BatchExportDocument {
        let batch = ImportBatch(
            createdAt: ISO8601DateFormatter.techPay.string(from: Date()),
            source: "TechDashboardiOS",
            records: records
        )
        return BatchExportDocument(batch: batch)
    }

    func exportFileName() -> String {
        "tech-pay-import-\(DateFormatter.fileStamp.string(from: Date())).json"
    }

    func allOCRText() -> String {
        records.enumerated().map { index, record in
            """
            --- Record \(index + 1) ---
            \(record.rawText ?? "")
            """
        }.joined(separator: "\n\n")
    }
}

struct ImportPanelView: View {
    @EnvironmentObject private var store: DashboardStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = ScreenshotImportViewModel()
    @State private var isExporting = false
    @State private var didCopyAllOCR = false
    @State private var showingBatchPicker = false
    @State private var submittedSummary: ImportSummary?

    var initialDate: Date

    var body: some View {
        NavigationStack {
            List {
                Section {
                    DatePicker("Work date", selection: $viewModel.workDate, displayedComponents: .date)

                    PhotosPicker(
                        selection: $viewModel.selectedItems,
                        maxSelectionCount: 50,
                        matching: .images
                    ) {
                        Label("Select screenshots", systemImage: "photo.on.rectangle.angled")
                    }

                    Button {
                        Task { await viewModel.processSelection(payMappings: store.payMappings) }
                    } label: {
                        Label("Read Screenshots", systemImage: "text.viewfinder")
                    }
                    .disabled(viewModel.selectedItems.isEmpty || viewModel.isProcessing)

                    Button {
                        showingBatchPicker = true
                    } label: {
                        Label("Import Batch File", systemImage: "doc.badge.arrow.up")
                    }
                }

                Section {
                    HStack {
                        Label("Complete", systemImage: "checkmark.circle")
                        Spacer()
                        Text("\(viewModel.completeCount)")
                    }

                    HStack {
                        Label("Needs review", systemImage: "exclamationmark.triangle")
                        Spacer()
                        Text("\(viewModel.unresolvedCount)")
                    }

                    Text(viewModel.status)
                        .foregroundStyle(.secondary)
                }

                Section("Preview") {
                    if viewModel.records.isEmpty {
                        Text("No extracted records yet.")
                            .foregroundStyle(.secondary)
                    }

                    ForEach($viewModel.records) { $record in
                        NavigationLink {
                            ImportRecordEditor(record: $record)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(record.name.isEmpty ? "Unnamed stop" : record.name)
                                        .font(.headline)
                                    Spacer()
                                    ImportStatusBadge(isComplete: record.isComplete)
                                }
                                Text(record.serviceType.isEmpty ? "No service found" : record.serviceType)
                                    .foregroundStyle(.secondary)
                                Text(record.orderNumber.isEmpty ? "No order number" : "Order #\(record.orderNumber)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") {
                        submittedSummary = store.submitImportedRecords(viewModel.records, fallbackDate: viewModel.workDate)
                        if let summary = submittedSummary {
                            viewModel.status = "Submitted \(summary.saved) saved, \(summary.unresolved) unresolved, \(summary.duplicates) duplicates."
                        }
                    }
                    .disabled(viewModel.records.isEmpty || viewModel.isProcessing || !store.hasFolder)
                }

                ToolbarItem(placement: .bottomBar) {
                    Menu {
                        Button {
                            isExporting = true
                        } label: {
                            Label("Create Batch", systemImage: "square.and.arrow.up")
                        }

                        Button {
                            UIPasteboard.general.string = viewModel.allOCRText()
                            didCopyAllOCR = true
                        } label: {
                            Label("Copy OCR Text", systemImage: "doc.on.doc")
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                    .disabled(viewModel.records.isEmpty)
                }
            }
            .overlay {
                if viewModel.isProcessing {
                    ProgressView("Reading screenshots...")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .fileExporter(
                isPresented: $isExporting,
                document: viewModel.batchDocument(),
                contentType: .json,
                defaultFilename: viewModel.exportFileName()
            ) { result in
                switch result {
                case .success:
                    viewModel.status = "Batch exported."
                case .failure(let error):
                    viewModel.status = error.localizedDescription
                }
            }
            .sheet(isPresented: $showingBatchPicker) {
                DocumentPicker(contentTypes: [.json, .data], asCopy: false) { urls in
                    guard let url = urls.first else { return }
                    store.importBatch(from: url, fallbackDate: viewModel.workDate)
                    viewModel.status = store.status
                }
            }
            .alert("OCR text copied", isPresented: $didCopyAllOCR) {
                Button("OK", role: .cancel) {}
            }
            .onAppear {
                viewModel.workDate = initialDate
            }
        }
    }
}

struct ImportRecordEditor: View {
    @Binding var record: WorkStopRecord
    @State private var didCopyOCR = false

    var body: some View {
        Form {
            Section("Stop") {
                TextField("Date", text: $record.date)
                TextField("Name", text: $record.name)
                TextField("Address", text: $record.address, axis: .vertical)
                TextField("Order #", text: $record.orderNumber)
                TextField("Location #", text: Binding(get: {
                    record.locationNumber ?? ""
                }, set: { value in
                    record.locationNumber = value
                }))
            }

            Section("Time") {
                TextField("Started", text: $record.timeStarted)
                TextField("Completed", text: $record.timeCompleted)
            }

            Section("Service") {
                TextField("Service type", text: $record.serviceType)
                Picker("Pay type", selection: $record.payType) {
                    Text("Unmapped").tag("")
                    ForEach(PayCatalog.payTypes, id: \.self) { payType in
                        Text(payType).tag(payType)
                    }
                }
                TextField("Amount", text: amountText)
                    .keyboardType(.decimalPad)
            }

            if !record.missingFields.isEmpty {
                Section("Needs Review") {
                    Text(record.missingFields.joined(separator: ", "))
                        .foregroundStyle(.orange)
                }
            }

            Section("OCR Text") {
                Button {
                    UIPasteboard.general.string = record.rawText ?? ""
                    didCopyOCR = true
                } label: {
                    Label("Copy OCR Text", systemImage: "doc.on.doc")
                }

                Text(record.rawText ?? "")
                    .font(.footnote)
                    .textSelection(.enabled)
            }
        }
        .navigationTitle(record.isComplete ? "Ready" : "Review")
        .navigationBarTitleDisplayMode(.inline)
        .alert("OCR text copied", isPresented: $didCopyOCR) {
            Button("OK", role: .cancel) {}
        }
    }

    private var amountText: Binding<String> {
        Binding {
            record.amount.map { String(format: "%.2f", $0) } ?? ""
        } set: { value in
            let cleaned = value.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "")
            record.amount = Double(cleaned)
        }
    }
}

struct ImportStatusBadge: View {
    var isComplete: Bool

    var body: some View {
        Image(systemName: isComplete ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            .foregroundStyle(isComplete ? .green : .orange)
            .accessibilityLabel(isComplete ? "Complete" : "Needs review")
    }
}

struct OCRService {
    func recognizeText(in image: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let text = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                continuation.resume(returning: text)
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US"]

            let handler = VNImageRequestHandler(cgImage: image)
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

struct WorkStopParser {
    var payMappings: [String: String]

    func parse(rawText: String, workDate: Date) -> WorkStopRecord {
        let text = normalize(rawText)
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let locationIndex = lines.firstIndex { $0.range(of: #"^Location #"#, options: [.regularExpression, .caseInsensitive]) != nil }
        let servicesIndex = lines.firstIndex {
            $0.range(of: #"^SERVICES?\b"#, options: [.regularExpression, .caseInsensitive]) != nil
        }
        let service = parseService(lines: lines, servicesIndex: servicesIndex, fullText: text)
        let addressLines = locationIndex.map { index in
            [lines[safe: index + 2], lines[safe: index + 3]].compactMap { $0 }
        } ?? []
        let statusTimes = parseStatusTimes(lines: lines)

        return WorkStopRecord(
            date: DateFormatter.workDate.string(from: workDate),
            name: locationIndex.flatMap { lines[safe: $0 + 1] } ?? "",
            address: addressLines.joined(separator: ", "),
            orderNumber: firstMatch(in: text, pattern: #"Order\s*#\s*(\d+)"#),
            locationNumber: firstMatch(in: text, pattern: #"Location\s*#\s*(\d+)"#),
            timeStarted: statusTimes.started ?? normalizeTime(firstMatch(in: text, pattern: #"Time Started\s+([0-9:]+\s*[AP]M)"#)),
            timeCompleted: statusTimes.completed ?? normalizeTime(firstMatch(in: text, pattern: #"Time Completed\s+([0-9:]+\s*[AP]M)"#)),
            serviceType: service.name,
            payType: payMappings[service.name] ?? "",
            amount: service.amount ?? parseTotalAmount(text),
            rawText: text,
            importedAt: ISO8601DateFormatter.techPay.string(from: Date())
        )
    }

    private func normalize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseService(lines: [String], servicesIndex: Int?, fullText: String) -> (name: String, amount: Double?) {
        let serviceLines = serviceBlock(lines: lines, servicesIndex: servicesIndex)
        let serviceText = serviceLines.joined(separator: " ")

        if let knownName = bestKnownServiceName(in: serviceText) ?? bestKnownServiceName(in: fullText) {
            return (knownName, firstServiceAmount(in: serviceText) ?? parseTotalAmount(fullText))
        }

        let candidateLines = serviceLines + adjacentPairs(from: serviceLines)
        for line in candidateLines {
            let service = parseServiceLine(line)
            if !service.name.isEmpty {
                return service
            }
        }

        if let serviceName = firstServiceNameOnly(in: serviceLines) {
            return (serviceName, firstServiceAmount(in: serviceText) ?? parseTotalAmount(fullText))
        }

        return ("", parseTotalAmount(fullText))
    }

    private func serviceBlock(lines: [String], servicesIndex: Int?) -> [String] {
        guard let servicesIndex else { return [] }
        var block: [String] = []

        let headerLine = lines[servicesIndex]
        let serviceOnHeader = headerLine
            .replacingOccurrences(of: #"^SERVICES?\b[:\s-]*"#, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !serviceOnHeader.isEmpty {
            block.append(serviceOnHeader)
        }

        for line in lines.dropFirst(servicesIndex + 1) {
            if line.range(of: #"^(Collect Payment|Re-Open|Report|STATUS|Order #|Location #)\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
                break
            }
            block.append(line)
        }

        return block
    }

    private func adjacentPairs(from lines: [String]) -> [String] {
        guard lines.count > 1 else { return [] }
        return (0..<(lines.count - 1)).map { "\(lines[$0]) \(lines[$0 + 1])" }
    }

    private func parseServiceLine(_ line: String) -> (name: String, amount: Double?) {
        guard let captures = captures(in: line, pattern: #"^(.*?)\s+\$?\s*([\dO,]+\.[\dO]{2})\s*[x×]?\s*\d+"#) else {
            return ("", nil)
        }

        let name = bestKnownServiceName(in: captures[0]) ?? captures[0].trimmingCharacters(in: .whitespacesAndNewlines)
        if name.range(of: #"^(Tax|Total):?$"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return ("", nil)
        }

        return (name, parseMoney(captures[1]))
    }

    private func firstServiceNameOnly(in lines: [String]) -> String? {
        for line in lines {
            let cleaned = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if cleaned.range(of: #"^(Tax|Total):?$"#, options: [.regularExpression, .caseInsensitive]) != nil {
                continue
            }

            if cleaned.range(of: #"^\$?\s*[\dO,]+\.[\dO]{2}\s*([x×]\s*\d+)?$"#, options: [.regularExpression, .caseInsensitive]) != nil {
                continue
            }

            if cleaned.range(of: #"^(Collect Payment|Re-Open|Report)$"#, options: [.regularExpression, .caseInsensitive]) != nil {
                continue
            }

            return bestKnownServiceName(in: cleaned) ?? cleaned
        }

        return nil
    }

    private func bestKnownServiceName(in text: String) -> String? {
        let normalizedText = serviceComparable(text)
        guard !normalizedText.isEmpty else { return nil }

        return payMappings.keys.sorted { $0.count > $1.count }.first { service in
            let normalizedService = serviceComparable(service)
            return normalizedText.contains(normalizedService) || normalizedService.contains(normalizedText)
        }
    }

    private func serviceComparable(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func firstMatch(in text: String, pattern: String) -> String {
        captures(in: text, pattern: pattern)?.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func parseStatusTimes(lines: [String]) -> (started: String?, completed: String?) {
        let directStarted = parseLabeledTime(lines: lines, label: "Time Started")
        let directCompleted = parseLabeledTime(lines: lines, label: "Time Completed")

        if let directStarted,
           let directCompleted,
           directStarted != directCompleted,
           isChronological(started: directStarted, completed: directCompleted) {
            return (directStarted, directCompleted)
        }

        let stacked = parseStackedStatusTimes(lines: lines)
        if let stackedStarted = stacked.started,
           let stackedCompleted = stacked.completed,
           stackedStarted != stackedCompleted,
           isChronological(started: stackedStarted, completed: stackedCompleted) {
            return (stackedStarted, stackedCompleted)
        }

        let started = directStarted ?? stacked.started
        let completed = directCompleted ?? stacked.completed
        guard let started, let completed else {
            return (started, completed)
        }

        if started == completed || !isChronological(started: started, completed: completed) {
            return (nil, nil)
        }

        return (started, completed)
    }

    private func parseLabeledTime(lines: [String], label: String) -> String? {
        guard let labelIndex = lines.firstIndex(where: { $0.range(of: #"^\#(label)$"#, options: [.regularExpression, .caseInsensitive]) != nil }) else {
            return nil
        }

        for line in lines.dropFirst(labelIndex + 1).prefix(5) {
            if line.range(of: #"^(SERVICES|Tax|Total|Time Started|Time Completed|Scheduled Arrival)$"#, options: [.regularExpression, .caseInsensitive]) != nil {
                break
            }

            let time = firstMatch(in: line, pattern: #"([0-9]{1,2}:[0-9]{2}\s*[AP]M)"#)
            if !time.isEmpty {
                return normalizeTime(time)
            }
        }

        return nil
    }

    private func parseStackedStatusTimes(lines: [String]) -> (started: String?, completed: String?) {
        guard let statusIndex = lines.firstIndex(where: { $0.range(of: #"^STATUS$"#, options: [.regularExpression, .caseInsensitive]) != nil }) else {
            return (nil, nil)
        }

        let statusLines = Array(lines
            .dropFirst(statusIndex + 1)
            .prefix { $0.range(of: #"^SERVICES$"#, options: [.regularExpression, .caseInsensitive]) == nil })
        let labelNames = ["Scheduled Arrival", "Actual Duration", "Time Started", "Time Completed"]
        var labels: [String] = []
        var values: [String] = []

        for line in statusLines {
            if let labelName = labelNames.first(where: { line.range(of: #"^\#($0)$"#, options: [.regularExpression, .caseInsensitive]) != nil }) {
                labels.append(labelName)
            } else {
                values.append(line)
            }
        }

        return (
            stackedValue(labels: labels, values: values, label: "Time Started"),
            stackedValue(labels: labels, values: values, label: "Time Completed")
        )
    }

    private func stackedValue(labels: [String], values: [String], label: String) -> String? {
        guard let valueIndex = labels.firstIndex(where: { $0.caseInsensitiveCompare(label) == .orderedSame }),
              let alignedValue = values[safe: valueIndex] else {
            return nil
        }

        let time = firstMatch(in: alignedValue, pattern: #"([0-9]{1,2}:[0-9]{2}\s*[AP]M)"#)
        return time.isEmpty ? nil : normalizeTime(time)
    }

    private func captures(in text: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1 else { return nil }

        return (1..<match.numberOfRanges).compactMap { index in
            guard let captureRange = Range(match.range(at: index), in: text) else { return nil }
            return String(text[captureRange])
        }
    }

    private func parseMoney(_ value: String) -> Double? {
        let cleaned = value
            .replacingOccurrences(of: "O", with: "0")
            .replacingOccurrences(of: "o", with: "0")
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: " ", with: "")
        return Double(cleaned)
    }

    private func parseTotalAmount(_ text: String) -> Double? {
        parseMoney(firstMatch(in: text, pattern: #"Total:?\s*\$?\s*([\dO,]+\.\d{2}|[\dO,]+\.O{2})"#))
    }

    private func firstServiceAmount(in text: String) -> Double? {
        parseMoney(firstMatch(in: text, pattern: #"\$?\s*([\dO,]+\.[\dO]{2})\s*[x×]\s*\d+"#))
    }

    private func normalizeTime(_ value: String) -> String {
        value.replacingOccurrences(of: #"\s*([AP]M)$"#, with: " $1", options: [.regularExpression, .caseInsensitive])
            .uppercased()
    }

    private func isChronological(started: String, completed: String) -> Bool {
        guard let startedMinutes = minutesSinceMidnight(started),
              let completedMinutes = minutesSinceMidnight(completed) else {
            return false
        }
        return completedMinutes > startedMinutes
    }

    private func minutesSinceMidnight(_ value: String) -> Int? {
        guard let captures = captures(in: normalizeTime(value), pattern: #"^(\d{1,2}):(\d{2})\s*([AP]M)$"#),
              captures.count == 3,
              var hour = Int(captures[0]),
              let minute = Int(captures[1]) else {
            return nil
        }

        let marker = captures[2].uppercased()
        if marker == "PM", hour != 12 { hour += 12 }
        if marker == "AM", hour == 12 { hour = 0 }
        return hour * 60 + minute
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
