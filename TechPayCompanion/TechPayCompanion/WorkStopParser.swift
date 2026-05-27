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
            payType: ServicePayMapping.values[service.name] ?? "",
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

        return ("", parseTotalAmount(fullText))
    }

    private func serviceBlock(lines: [String], servicesIndex: Int?) -> [String] {
        guard let servicesIndex else { return [] }
        var block: [String] = []

        for line in lines.dropFirst(servicesIndex + 1) {
            if line.range(of: #"^(Re-Open|Report|STATUS|Order #|Location #)\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
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

        let amount = parseMoney(captures[1])
        return (name, amount)
    }

    private func bestKnownServiceName(in text: String) -> String? {
        let normalizedText = serviceComparable(text)
        guard !normalizedText.isEmpty else { return nil }

        return ServicePayMapping.values.keys.sorted { $0.count > $1.count }.first { service in
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

        let started = stackedValue(labels: labels, values: values, label: "Time Started")
        let completed = stackedValue(labels: labels, values: values, label: "Time Completed")
        return (started, completed)
    }

    private func stackedValue(labels: [String], values: [String], label: String) -> String? {
        guard let valueIndex = labels.firstIndex(where: { $0.caseInsensitiveCompare(label) == .orderedSame }) else {
            return nil
        }

        if let alignedValue = values[safe: valueIndex] {
            let time = firstMatch(in: alignedValue, pattern: #"([0-9]{1,2}:[0-9]{2}\s*[AP]M)"#)
            if !time.isEmpty {
                return normalizeTime(time)
            }
        }

        return nil
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
        let total = firstMatch(in: text, pattern: #"Total:?\s*\$?\s*([\dO,]+\.\d{2}|[\dO,]+\.O{2})"#)
        return parseMoney(total)
    }

    private func firstServiceAmount(in text: String) -> Double? {
        let value = firstMatch(in: text, pattern: #"\$?\s*([\dO,]+\.[\dO]{2})\s*[x×]\s*\d+"#)
        return parseMoney(value)
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
