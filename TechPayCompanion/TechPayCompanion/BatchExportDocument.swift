import SwiftUI
import UniformTypeIdentifiers

struct BatchExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    static var writableContentTypes: [UTType] { [.json] }

    var batch: ImportBatch

    init(batch: ImportBatch) {
        self.batch = batch
    }

    init(configuration: ReadConfiguration) throws {
        let data = configuration.file.regularFileContents ?? Data()
        batch = try JSONDecoder().decode(ImportBatch.self, from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(batch)
        return FileWrapper(regularFileWithContents: data)
    }
}
