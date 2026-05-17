import PhotosUI
import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = ImportViewModel()
    @State private var isExporting = false
    @State private var didCopyAllOCR = false

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
                        Task { await viewModel.processSelection() }
                    } label: {
                        Label("Extract fields", systemImage: "text.viewfinder")
                    }
                    .disabled(viewModel.selectedItems.isEmpty || viewModel.isProcessing)
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

                Section("Records") {
                    ForEach($viewModel.records) { $record in
                        NavigationLink {
                            RecordEditor(record: $record)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(record.name.isEmpty ? "Unnamed stop" : record.name)
                                        .font(.headline)
                                    Spacer()
                                    StatusBadge(isComplete: record.isComplete)
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
            .navigationTitle("Tech Pay")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            isExporting = true
                        } label: {
                            Label("Export JSON", systemImage: "square.and.arrow.up")
                        }

                        Button {
                            UIPasteboard.general.string = viewModel.allOCRText()
                            didCopyAllOCR = true
                        } label: {
                            Label("Copy all OCR", systemImage: "doc.on.doc")
                        }
                        .disabled(viewModel.records.isEmpty)
                    } label: {
                        Image(systemName: "ellipsis.circle")
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
                    viewModel.status = "Batch exported. Save it to iCloud Drive for the web app."
                case .failure(let error):
                    viewModel.status = error.localizedDescription
                }
            }
            .alert("OCR text copied", isPresented: $didCopyAllOCR) {
                Button("OK", role: .cancel) {}
            }
        }
    }
}

struct RecordEditor: View {
    @Binding var record: WorkStopRecord
    @State private var didCopyOCR = false

    var body: some View {
        Form {
            Section("Stop") {
                TextField("Name", text: $record.name)
                TextField("Address", text: $record.address, axis: .vertical)
                TextField("Order #", text: $record.orderNumber)
                TextField("Location #", text: $record.locationNumber)
            }

            Section("Time") {
                TextField("Started", text: $record.timeStarted)
                TextField("Completed", text: $record.timeCompleted)
            }

            Section("Service") {
                TextField("Service type", text: $record.serviceType)
                Picker("Pay type", selection: $record.payType) {
                    Text("Unmapped").tag("")
                    ForEach(payTypes, id: \.self) { payType in
                        Text(payType).tag(payType)
                    }
                }
                TextField("Amount", text: amountText)
                    .keyboardType(.decimalPad)
            }

            Section("OCR text") {
                Button {
                    UIPasteboard.general.string = record.rawText
                    didCopyOCR = true
                } label: {
                    Label("Copy OCR text", systemImage: "doc.on.doc")
                }

                Text(record.rawText)
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

    private var payTypes: [String] {
        ["Prod", "IS INI", "PS INI", "SENTRICON", "SEN INI", "TI", "ISR", "PM", "MSC", "MSS", "MISC NOPAY"]
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

struct StatusBadge: View {
    var isComplete: Bool

    var body: some View {
        Image(systemName: isComplete ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            .foregroundStyle(isComplete ? .green : .orange)
            .accessibilityLabel(isComplete ? "Complete" : "Needs review")
    }
}
