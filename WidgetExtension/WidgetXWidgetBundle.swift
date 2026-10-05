import SwiftUI
import WidgetKit

/// Every widget the app ships. Each section contributes its own bundle from its folder
/// (`Tech/TechWidgets.swift`, …) so feature packages never edit this file.
///
/// Rules (Platform Reality Rules 1, 6, 7): widgets read App Group snapshots only:
/// no CloudKit, no network, no full-size image decoding.
@main
struct WidgetXWidgetBundle: WidgetBundle {
    var body: some Widget {
        WelcomeWidget()
        TechWidgets().body
        StudentWidgets().body
        AestheticWidgets().body
        WellnessWidgets().body
    }
}
