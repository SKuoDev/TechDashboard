import PhotosUI
import SwiftUI
import UIKit
import Vision

@MainActor
final class ImportViewModel: ObservableObject {
    @Published var selectedItems: [PhotosPickerItem] = []
    @Published var workDate = Date()
    @Published var records: [WorkStopRecord] = []
    @Published var isProcessing = false
    @Published var status = "Select work-stop screenshots."

    private let ocrService = OCRService()
    private let parser = WorkStopParser()

    var completeCount: Int {
        records.filter(\.isComplete).count
    }

    var unresolvedCount: Int {
        records.count - completeCount
    }

    func processSelection() async {
        guard !selectedItems.isEmpty else {
            status = "Select work-stop screenshots."
            return
        }

        isProcessing = true
        records.removeAll()
        status = "Reading \(selectedItems.count) screenshot\(selectedItems.count == 1 ? "" : "s")..."

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
        status = "Ready to export: \(completeCount) complete, \(unresolvedCount) needs review."
        isProcessing = false
    }

    func update(_ record: WorkStopRecord) {
        guard let index = records.firstIndex(where: { $0.id == record.id }) else { return }
        records[index] = record
    }

    func batchDocument() -> BatchExportDocument {
        let batch = ImportBatch(
            createdAt: ISO8601DateFormatter.techPay.string(from: Date()),
            records: records
        )
        return BatchExportDocument(batch: batch)
    }

    func exportFileName() -> String {
        "tech-pay-import-\(DateFormatter.fileStamp.string(from: Date())).json"
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
