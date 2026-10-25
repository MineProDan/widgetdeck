import CoreKit
import DesignSystem
import SwiftUI

/// Settings (P-08): iCloud status, classes, export, "Delete all data" and About.
struct SettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var exportURL: URL?
    @State private var isExporting = false
    @State private var isConfirmingDelete = false
    @State private var isDeleting = false
    @State private var deleteReport: DataEraser.Report?
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    /// Closes Settings and shows the Student tab, where the setup flow opens.
    private func dismissToStudent() {
        environment.show(.student)
        dismiss()
    }

    var body: some View {
        @Bindable var environment = environment
        Form {
            if let message = environment.account.status.userMessage {
                Section {
                    Label(message, systemImage: "icloud.slash")
                        .font(.subheadline)
                }
            }
            if let message = environment.cloudSync.userMessage {
                Section {
                    Label(message, systemImage: "exclamationmark.icloud")
                        .font(.subheadline)
                }
            }
            if let storeError = environment.storeErrorMessage {
                Section {
                    Label("\(storeError) Changes this session won't be saved.", systemImage: "exclamationmark.triangle")
                        .font(.subheadline)
                        .dsForeground(.warning)
                }
            }

            Section {
                NavigationLink {
                    ThemePickerView()
                } label: {
                    LabeledContent {
                        Text(WXDeck.deck(id: environment.deckID).name)
                    } label: {
                        Label("Theme", systemImage: "paintpalette")
                    }
                }
            } header: {
                Text("Look")
            } footer: {
                Text("Colours, fonts and shapes for the app and every widget.")
            }

            if let student = environment.studentStore {
                Section {
                    Button {
                        Task { await student.restartClassSetup() }
                        dismissToStudent()
                    } label: {
                        Label("Set up my classes again", systemImage: "sparkles")
                    }
                    Button {
                        Task { await student.restartCalendarSetup() }
                        dismissToStudent()
                    } label: {
                        Label("Redo calendar setup", systemImage: "calendar.badge.plus")
                    }
                    Toggle(isOn: Binding(get: { student.settings.inferWeeklyPatterns },
                                         set: { value in Task { await student.setInferWeeklyPatterns(value) } })) {
                        Label("Same time every week", systemImage: "repeat")
                    }
                } header: {
                    Text("Classes")
                } footer: {
                    Text("Asks the room, travel and heads-up questions again. Redoing calendar setup also lets you pick your school calendars again. Same time every week counts events with the same name at the same weekly time as classes, even when they aren't set to repeat.")
                }
            }

            // No in-app analytics toggle: nothing is sent anywhere (the sink is a no-op, and the App Privacy
            // answer is "Data Not Collected"). Launch metrics come from App Store Connect's opt-in App
            // Analytics, which users control in iOS Settings. Bring the toggle back only with a real sink.

            Section {
                Button {
                    Task { await export() }
                } label: {
                    HStack {
                        Label("Export my data", systemImage: "square.and.arrow.up")
                        Spacer()
                        if isExporting { ProgressView() }
                    }
                }
                .disabled(isExporting || environment.stack == nil)

                if let exportURL {
                    ShareLink(item: exportURL) {
                        Label("Share export file", systemImage: "doc.text")
                    }
                    // Leaving Settings ends the share; don't keep a readable copy of the data around.
                    .onDisappear { DataExporter.removeExports() }
                }

                Button(role: .destructive) {
                    isConfirmingDelete = true
                } label: {
                    HStack {
                        Label("Delete all my data", systemImage: "trash")
                        Spacer()
                        if isDeleting { ProgressView() }
                    }
                }
                .disabled(isDeleting)
                // Attached to the row so the confirmation points at Delete, not at the top of the form.
                .confirmationDialog("Delete all your Widgetdeck data?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                    Button("Delete everything", role: .destructive) { Task { await deleteAll() } }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Themes, widget settings and everything you've tracked will be removed from this iPhone and iCloud. This can't be undone.")
                }
            } header: {
                Text("Your data")
            } footer: {
                Text("Deleting removes everything Widgetdeck stored on this iPhone and in your iCloud.")
            }

            Section {
                LabeledContent("Version", value: Self.versionString)
                NavigationLink {
                    SyncLogView()
                } label: {
                    Label("Sync log", systemImage: "list.bullet.rectangle")
                }
                NavigationLink {
                    HobbyProjectView()
                } label: {
                    Label("A hobby project", systemImage: "heart")
                }
            } header: {
                Text("About")
            }
        }
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .alert("Data deleted", isPresented: Binding(get: { deleteReport != nil }, set: { if !$0 { deleteReport = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteReport.map(Self.message(for:)) ?? "")
        }
        .alert("Something went wrong", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("Different iCloud account", isPresented: Binding(
            get: { environment.account.accountChangeDetected }, set: { _ in })) {
            Button("Keep data on this iPhone") { Task { await environment.account.resolveAccountChange() } }
            Button("Start fresh", role: .destructive) {
                Task {
                    _ = await environment.deleteAllData()
                    await environment.account.resolveAccountChange()
                }
            }
        } message: {
            Text("You're signed in to a different iCloud account than before. Keep the data on this iPhone, or start fresh?")
        }
    }

    private func export() async {
        isExporting = true
        defer { isExporting = false }
        do {
            exportURL = try await environment.exportData()
        } catch {
            errorMessage = "Couldn't create the export file. Please try again."
        }
    }

    private func deleteAll() async {
        isDeleting = true
        defer { isDeleting = false }
        exportURL = nil
        deleteReport = await environment.deleteAllData()
    }


    private static func message(for report: DataEraser.Report) -> String {
        if report.isComplete { return "Everything was deleted." }
        var parts: [String] = []
        if !report.localDataDeleted { parts.append("Some data on this iPhone couldn't be deleted.") }
        if !report.filesDeleted { parts.append("Some cached files couldn't be removed.") }
        if !report.keychainCleared { parts.append("Saved sign-ins couldn't be removed.") }
        if let cloudError = report.cloudErrorMessage { parts.append(cloudError) }
        return parts.joined(separator: " ")
    }

    private static var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }
}
