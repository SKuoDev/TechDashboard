import Foundation

struct WorkStopParser {
    func parse(rawText: String, workDate: Date) -> WorkStopRecord {
        let text = normalize(rawText)
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let locationIndex = lines.firstIndex { $0.range(of: #"^Location #"#, options: [.regularExpression, .caseInsensitive]) != nil }
        let servicesIndex = lines.firstIndex { $0.uppercased() == "SERVICES" }
        let serviceLine = servicesIndex.flatMap { lines[safe: $0 + 1] } ?? ""
        let service = parseService(serviceLine)
        let addressLines = locationIndex.map { index in
            [lines[safe: index + 2], lines[safe: index + 3]].compactMap { $0 }
        } ?? []

        return WorkStopRecord(
            date: DateFormatter.workDate.string(from: workDate),
            name: locationIndex.flatMap { lines[safe: $0 + 1] } ?? "",
            address: addressLines.joined(separator: ", "),
            orderNumber: firstMatch(in: text, pattern: #"Order\s*#\s*(\d+)"#),
            locationNumber: firstMatch(in: text, pattern: #"Location\s*#\s*(\d+)"#),
            timeStarted: normalizeTime(firstMatch(in: text, pattern: #"Time Started\s+([0-9:]+\s*[AP]M)"#)),
            timeCompleted: normalizeTime(firstMatch(in: text, pattern: #"Time Completed\s+([0-9:]+\s*[AP]M)"#)),
            serviceType: service.name,
            payType: ServicePayMapping.values[service.name] ?? "",
            amount: service.amount ?? parseMoney(firstMatch(in: text, pattern: #"Total:\s*\$?([\d,]+\.\d{2})"#)),
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

    private func parseService(_ line: String) -> (name: String, amount: Double?) {
        guard let captures = captures(in: line, pattern: #"^(.*?)\s+\$?([\d,]+\.\d{2})\s*x\s*\d+"#) else {
            return ("", nil)
        }

        let name = captures[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let amount = parseMoney(captures[1])
        return (name, amount)
    }

    private func firstMatch(in text: String, pattern: String) -> String {
        captures(in: text, pattern: pattern)?.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
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
        let cleaned = value.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "")
        return Double(cleaned)
    }

    private func normalizeTime(_ value: String) -> String {
        value.replacingOccurrences(of: #"\s*([AP]M)$"#, with: " $1", options: [.regularExpression, .caseInsensitive])
            .uppercased()
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
