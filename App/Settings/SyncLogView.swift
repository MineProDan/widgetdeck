import CoreKit
import SwiftUI

/// Settings → About → Sync log: the on-device `SyncTrace`, newest first, to share when widgets stop
/// updating. Contains timings and counts only, no calendar contents.
struct SyncLogView: View {
    @State private var text = ""

    var body: some View {
        ScrollView {
            Text(text.isEmpty ? "Nothing logged yet." : text)
                .font(.system(.caption2, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle("Sync log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                ShareLink(item: text) { Image(systemName: "square.and.arrow.up") }
                    .disabled(text.isEmpty)
                Button("Clear") {
                    SyncTrace.clear()
                    load()
                }
            }
        }
        .onAppear(perform: load)
        .refreshable { load() }
    }

    private func load() {
        text = SyncTrace.read().split(separator: "\n").reversed().joined(separator: "\n")
    }
}
