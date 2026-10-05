import CoreKit
import DesignSystem
import SwiftUI

@main
struct WidgetXApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var environment = AppEnvironment.shared

    init() {
        WXFonts.registerIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
                .environment(\.dsTheme, environment.theme)
                // Paint Chip colours are paint, not adaptive chrome; DESIGN.md defines no dark
                // appearance yet, so the app stays light (system bars match the paper ground).
                .preferredColorScheme(.light)
                .task { await environment.bootstrap() }
                .onOpenURL { environment.handle(url: $0) }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: environment.didBecomeActive()
            case .background: environment.didEnterBackground()
            default: break
            }
        }
    }
}
