import AestheticFeature
import CoreKit
import DesignSystem
import StudentFeature
import SwiftUI
import TechFeature
import WellnessFeature

/// App chrome from the mockup: five tabs (Home, Student, Aesthetic, Wellness, Tech) in the Paint
/// Chip `WXTabBar`, each screen on Paper Ivory under a `WXPageHeader`.
struct RootView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var tab: WXTab = .home
    @State private var isShowingSettings = false
    @AppStorage(OnboardingModel.completedKey) private var hasCompletedOnboarding = false

    var body: some View {
        @Bindable var environment = environment
        Group {
            #if DEBUG
            if let artboard = GalleryArtboard.launchArgument {
                GalleryArtboardView(artboard: artboard)
            } else {
                main
            }
            #else
            main
            #endif
        }
        .sheet(isPresented: $isShowingSettings) {
            NavigationStack { SettingsView() }
        }
    }

    @ViewBuilder
    private var main: some View {
        if hasCompletedOnboarding {
            tabs
        } else {
            OnboardingView { hasCompletedOnboarding = true }
        }
    }

    private var tabs: some View {
        ZStack {
            WXColor.paperIvory.ignoresSafeArea()
            screen(for: tab)
                .id(tab)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            // Paper band behind the status bar so scrolled content doesn't run under it.
            Color.clear.frame(height: 0).background(WXColor.paperIvory.ignoresSafeArea(edges: .top))
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            WXTabBar(selection: $tab)
        }
        .onChange(of: environment.deepLinkCount) {
            tab = WXTab(environment.selectedSection)
        }
        .onChange(of: environment.selectedSection) { _, section in
            // Deep links (widgets, notifications) select a section.
            tab = WXTab(section)
        }
        .onChange(of: tab) { _, newTab in
            if let section = newTab.section {
                environment.selectedSection = section
                Analytics.shared.track(.sectionOpened(section))
            }
        }
    }

    @ViewBuilder
    private func screen(for tab: WXTab) -> some View {
        @Bindable var environment = environment
        switch tab {
        case .home:
            HomeView(open: { self.tab = $0 }, showSettings: { isShowingSettings = true })
        case .student:
            SectionScreen(title: "Student", subtitle: nil) {
                if let store = environment.studentStore {
                    StudentSectionView(store: store, requestedCourseID: $environment.requestedCourseID)
                } else {
                    ShimmerLoader().frame(height: 320)
                }
            }
        case .aesthetic:
            SectionScreen(title: "Match my wallpaper", subtitle: "Theme Sync reads the photo you pick", titleSize: 36) {
                if let store = environment.aestheticStore {
                    AestheticSectionView(store: store)
                } else {
                    ShimmerLoader().frame(height: 320)
                }
            }
        case .wellness:
            SectionScreen(title: "Wellness", subtitle: environment.wellnessStore?.subtitle) {
                if let store = environment.wellnessStore {
                    WellnessSectionView(store: store, request: $environment.wellnessRequest)
                } else {
                    ShimmerLoader().frame(height: 320)
                }
            }
        case .tech:
            SectionScreen(title: "Tech", subtitle: "Live while the app is open, every 5 seconds") {
                if let monitor = environment.techMonitor {
                    TechSectionView(monitor: monitor)
                } else {
                    ShimmerLoader().frame(height: 320)
                }
            }
        }
    }
}

/// A section tab: page header plus the feature's content, on paper, 24 pt gutters.
private struct SectionScreen<Content: View>: View {
    let title: String
    let subtitle: String?
    var titleSize: CGFloat = 40
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                WXPageHeader(title: title, subtitle: subtitle, titleSize: titleSize)
                content
                    .frame(maxWidth: .infinity, minHeight: 320, alignment: .top)
            }
            .padding(.horizontal, WXSpace.gutter)
            .padding(.bottom, WXSpace.gutter)
        }
        .scrollIndicators(.hidden)
    }
}

private extension WXTab {
    init(_ section: AppSection) {
        switch section {
        case .student: self = .student
        case .aesthetic: self = .aesthetic
        case .wellness: self = .wellness
        case .tech: self = .tech
        }
    }

    var section: AppSection? {
        switch self {
        case .home: nil
        case .student: .student
        case .aesthetic: .aesthetic
        case .wellness: .wellness
        case .tech: .tech
        }
    }
}
