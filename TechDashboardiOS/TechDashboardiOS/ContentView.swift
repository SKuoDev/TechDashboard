import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var store: DashboardStore
    @State private var selectedDate = Date()
    @State private var showingImportPanel = false
    @State private var showingNewDatabase = false
    @State private var newDatabaseName = ""
    @State private var showingPayBreakdown = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    controls
                    summary
                    lastImport
                    if showingPayBreakdown {
                        payBreakdown
                    }
                    dayEntries
                }
                .padding(16)
            }
            .background(Color.techBackground.ignoresSafeArea())
            .navigationTitle("Tech Dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        ManageView()
                    } label: {
                        Label("Manage", systemImage: "slider.horizontal.3")
                    }
                }
            }
            .sheet(isPresented: $showingImportPanel) {
                ImportPanelView(initialDate: selectedDate)
                    .environmentObject(store)
            }
            .alert("New Save File", isPresented: $showingNewDatabase) {
                TextField("Name", text: $newDatabaseName)
                Button("Create") {
                    store.createDatabase(named: newDatabaseName)
                    newDatabaseName = ""
                }
                Button("Cancel", role: .cancel) {}
            }
            .onAppear {
                store.loadAll()
            }
        }
    }

    private var header: some View {
        Group {
            if let image = bundledHeaderImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .accessibilityLabel("Tech Dashboard")
            } else {
                Text("Tech Dashboard")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.techText)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private var bundledHeaderImage: UIImage? {
        guard let url = Bundle.main.url(forResource: "tech_dashboard_header_2", withExtension: "jpg") else {
            return nil
        }
        return UIImage(contentsOfFile: url.path)
    }

    private var controls: some View {
        VStack(spacing: 12) {
            DatePicker("Work day", selection: $selectedDate, displayedComponents: .date)
                .datePickerStyle(.compact)
                .foregroundStyle(Color.techText)

            HStack(spacing: 10) {
                Button {
                    showingImportPanel = true
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!store.hasFolder)

                Button {
                    showingNewDatabase = true
                } label: {
                    Image(systemName: "doc.badge.plus")
                }
                .buttonStyle(GlassIconButtonStyle())
                .disabled(!store.hasFolder)
            }
        }
        .techPanel()
    }

    private var summary: some View {
        let totals = store.totals(for: selectedDate)
        return VStack(spacing: 12) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                MetricCard(title: "MTD Production", value: totals.mtdProduction.money)
                MetricCard(title: "MTD Stops", value: "\(totals.mtdStops)")
                Button {
                    showingPayBreakdown.toggle()
                } label: {
                    MetricCard(title: "MTD Pay", value: totals.mtdPay.money, accessory: showingPayBreakdown ? "chevron.up" : "chevron.down")
                }
                .buttonStyle(.plain)
                MetricCard(title: "MTD Hourly", value: "\(totals.mtdHourly.money)/hr")
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                MetricCard(title: "Day Production", value: totals.dayProduction.money)
                MetricCard(title: "Day Stops", value: "\(totals.dayStops)")
                MetricCard(title: "Hours Worked", value: String(format: "%.2f", totals.dayHours))
                MetricCard(title: "Day Pay", value: totals.dayPay.money)
                MetricCard(title: "Day Hourly", value: "\(totals.dayHourly.money)/hr")
            }
        }
    }

    @ViewBuilder
    private var lastImport: some View {
        if let summary = store.lastImportSummary {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Last Import")
                        .font(.headline)
                        .foregroundStyle(Color.techText)
                    Spacer()
                    Text(summary.completedAt, style: .time)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.techMuted)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        StatusPill("Saved", "\(summary.saved)")
                        StatusPill("Unresolved", "\(summary.unresolved)")
                        StatusPill("Duplicates", "\(summary.duplicates)")
                        StatusPill("Work Date", summary.date)
                    }
                }
            }
            .techPanel()
        }
    }

    private var payBreakdown: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "MTD Pay Breakdown", subtitle: "\(store.payBreakdown(for: selectedDate).count) pay types")
            ForEach(store.payBreakdown(for: selectedDate)) { row in
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.payType)
                            .font(.headline)
                            .foregroundStyle(Color.techText)
                        Text("\(row.stops) stops - \(row.production.money) production")
                            .font(.caption)
                            .foregroundStyle(Color.techMuted)
                    }
                    Spacer()
                    Text(row.pay.money)
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(Color.techText)
                }
                .padding(.vertical, 8)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.techLine).frame(height: 1)
                }
            }
        }
        .techPanel()
    }

    private var dayEntries: some View {
        VStack(alignment: .leading, spacing: 10) {
            let records = store.dayRecords(for: selectedDate)
            SectionHeader(title: "Entries for \(DateFormatter.workDate.string(from: selectedDate))", subtitle: "\(records.count) records")

            if records.isEmpty {
                Text("No entries for this day.")
                    .foregroundStyle(Color.techMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 14)
            } else {
                ForEach(records) { record in
                    NavigationLink {
                        RecordEditorView(record: record, mode: .saved)
                    } label: {
                        RecordRow(record: record, pay: store.calculateRecordPay(record))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .techPanel()
    }
}

struct ManageView: View {
    @EnvironmentObject private var store: DashboardStore
    @State private var showingFolderPicker = false
    @State private var ratePercent = ""
    @State private var serviceType = ""
    @State private var payType = "Prod"

    var body: some View {
        List {
            Section("Storage") {
                Label(store.folderName, systemImage: store.isUsingLocalStorage ? "iphone" : store.hasFolder ? "icloud.fill" : "icloud.slash")

                Button {
                    showingFolderPicker = true
                } label: {
                    Label("Choose iCloud Folder", systemImage: "icloud")
                }

                Button {
                    store.useLocalStorage()
                } label: {
                    Label("Use This iPhone", systemImage: "iphone")
                }

                Text(store.status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Save Files") {
                Picker("Active save file", selection: Binding(get: {
                    store.selectedDatabase
                }, set: { database in
                    store.selectDatabase(database)
                })) {
                    ForEach(store.databases, id: \.self) { database in
                        Text(database).tag(database)
                    }
                }

                Button(role: .destructive) {
                    store.deleteCurrentDatabase()
                } label: {
                    Label("Delete Current Save File", systemImage: "trash")
                }
                .disabled(store.selectedDatabase == "work-stops.json")
            }

            Section("Unresolved") {
                NavigationLink {
                    UnresolvedView()
                } label: {
                    Label("Review Entries", systemImage: "exclamationmark.triangle")
                    Spacer()
                    Text("\(store.unresolved.count)")
                }
            }

            Section("Records") {
                NavigationLink {
                    AllRecordsView()
                } label: {
                    Label("Browse All Records", systemImage: "list.bullet.rectangle")
                }
            }

            Section("Pay Settings") {
                HStack {
                    TextField("Commission %", text: $ratePercent)
                        .keyboardType(.decimalPad)
                    Button("Save") {
                        let raw = Double(ratePercent) ?? (store.paySettings.commissionRate * 100)
                        store.savePaySettings(rate: raw / 100)
                    }
                }

                HStack {
                    TextField("Service type", text: $serviceType)
                    Picker("Pay type", selection: $payType) {
                        ForEach(PayCatalog.payTypes, id: \.self) { type in
                            Text(type).tag(type)
                        }
                    }
                    .labelsHidden()
                }
                Button {
                    store.saveMapping(serviceType: serviceType, payType: payType)
                    serviceType = ""
                } label: {
                    Label("Save Mapping", systemImage: "link")
                }
            }

            Section("Service Mappings") {
                ForEach(store.payMappings.keys.sorted(), id: \.self) { service in
                    HStack {
                        Text(service)
                        Spacer()
                        Text(store.payMappings[service] ?? "")
                            .foregroundStyle(.secondary)
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            store.deleteMapping(serviceType: service)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .navigationTitle("Manage")
        .onAppear {
            ratePercent = String(format: "%.1f", store.paySettings.commissionRate * 100)
        }
        .sheet(isPresented: $showingFolderPicker) {
            DocumentPicker(contentTypes: [.folder], asCopy: false) { urls in
                guard let url = urls.first else { return }
                store.connectFolder(url)
            }
        }
    }
}

struct AllRecordsView: View {
    @EnvironmentObject private var store: DashboardStore

    var body: some View {
        List {
            ForEach(store.records.sorted { $0.date > $1.date }) { record in
                NavigationLink {
                    RecordEditorView(record: record, mode: .saved)
                } label: {
                    RecordListLabel(record: record)
                }
            }
            .onDelete { offsets in
                let sorted = store.records.sorted { $0.date > $1.date }
                for index in offsets {
                    store.deleteRecord(sorted[index])
                }
            }
        }
        .navigationTitle("Records")
    }
}

struct UnresolvedView: View {
    @EnvironmentObject private var store: DashboardStore

    var body: some View {
        List {
            if store.unresolved.isEmpty {
                Text("No unresolved entries.")
                    .foregroundStyle(.secondary)
            }

            ForEach(store.unresolved) { record in
                NavigationLink {
                    RecordEditorView(record: record, mode: .unresolved)
                } label: {
                    RecordListLabel(record: record)
                }
            }
        }
        .navigationTitle("Unresolved")
    }
}

struct RecordEditorView: View {
    enum Mode {
        case saved
        case unresolved
    }

    @EnvironmentObject private var store: DashboardStore
    @Environment(\.dismiss) private var dismiss
    @State var record: WorkStopRecord
    var mode: Mode

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

            if let rawText = record.rawText, !rawText.isEmpty {
                Section("OCR Text") {
                    Text(rawText)
                        .font(.footnote)
                        .textSelection(.enabled)
                }
            }
        }
        .navigationTitle(mode == .saved ? "Edit Record" : "Resolve Entry")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(mode == .saved ? "Save" : "Resolve") {
                    if mode == .saved {
                        store.saveRecord(record)
                    } else {
                        store.resolve(record)
                    }
                    dismiss()
                }
            }
            if mode == .unresolved {
                ToolbarItem(placement: .bottomBar) {
                    Button(role: .destructive) {
                        store.skipUnresolved(record)
                        dismiss()
                    } label: {
                        Label("Skip", systemImage: "xmark.circle")
                    }
                }
            }
        }
    }

    private var amountText: Binding<String> {
        Binding {
            record.amount.map { String(format: "%.2f", $0) } ?? ""
        } set: { value in
            record.amount = Double(value.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: ""))
        }
    }
}

struct MetricCard: View {
    var title: String
    var value: String
    var accessory: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.techMuted)
                Spacer()
                if let accessory {
                    Image(systemName: accessory)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.techAccent)
                }
            }
            Text(value)
                .font(.system(size: 24, weight: .black, design: .rounded))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .foregroundStyle(Color.techText)
        }
        .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.techSurface2)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.techLine))
        )
    }
}

struct RecordRow: View {
    var record: WorkStopRecord
    var pay: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(record.name.isEmpty ? "Unnamed stop" : record.name)
                    .font(.headline)
                    .foregroundStyle(Color.techText)
                Spacer()
                Text(pay.money)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(Color.techText)
            }
            HStack(spacing: 8) {
                Text("\(record.timeStarted) - \(record.timeCompleted)")
                Text("Order #\(record.orderNumber)")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.techMuted)
            Text("\(record.serviceType) - \(record.payType) - \((record.amount ?? 0).money)")
                .font(.caption)
                .foregroundStyle(Color.techMuted)
        }
        .padding(.vertical, 8)
    }
}

struct RecordListLabel: View {
    var record: WorkStopRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(record.name.isEmpty ? "Unnamed stop" : record.name)
                .font(.headline)
            Text("\(record.date) - Order #\(record.orderNumber)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !record.isComplete {
                Text(record.missingFields.joined(separator: ", "))
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }
}

struct SectionHeader: View {
    var title: String
    var subtitle: String

    var body: some View {
        HStack {
            Text(title)
                .font(.headline)
                .foregroundStyle(Color.techText)
            Spacer()
            Text(subtitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.techMuted)
        }
    }
}

struct StatusPill: View {
    var label: String
    var value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        Text("\(label): \(value)")
            .font(.caption.weight(.bold))
            .foregroundStyle(Color.techText)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Capsule().fill(Color.techSurface3).overlay(Capsule().stroke(Color.techLine)))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.techAccent.opacity(configuration.isPressed ? 0.72 : 0.9))
                    .overlay(
                        LinearGradient(colors: [.white.opacity(0.32), .clear], startPoint: .top, endPoint: .center)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    )
            )
    }
}

struct GlassIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color.techText)
            .frame(width: 48, height: 48)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.techSurface2.opacity(configuration.isPressed ? 0.75 : 1))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.techLine))
            )
    }
}

extension View {
    func techPanel() -> some View {
        self
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.techSurface)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.techLine))
            )
    }
}

extension Color {
    static let techBackground = Color(red: 0.051, green: 0.067, blue: 0.09)
    static let techSurface = Color(red: 0.082, green: 0.106, blue: 0.137)
    static let techSurface2 = Color(red: 0.105, green: 0.141, blue: 0.188)
    static let techSurface3 = Color(red: 0.125, green: 0.169, blue: 0.22)
    static let techLine = Color(red: 0.184, green: 0.231, blue: 0.294)
    static let techText = Color(red: 0.91, green: 0.93, blue: 0.95)
    static let techMuted = Color(red: 0.604, green: 0.659, blue: 0.729)
    static let techAccent = Color(red: 0.165, green: 0.631, blue: 0.596)
}

extension Double {
    var money: String {
        Self.moneyFormatter.string(from: NSNumber(value: self)) ?? "$0.00"
    }

    private static let moneyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter
    }()
}

extension UTType {
    static let json = UTType(filenameExtension: "json") ?? .data
}

struct DocumentPicker: UIViewControllerRepresentable {
    var contentTypes: [UTType]
    var asCopy: Bool
    var onPick: ([URL]) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let controller = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: asCopy)
        controller.allowsMultipleSelection = false
        controller.delegate = context.coordinator
        controller.shouldShowFileExtensions = true
        return controller
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        var onPick: ([URL]) -> Void

        init(onPick: @escaping ([URL]) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls)
        }
    }
}
