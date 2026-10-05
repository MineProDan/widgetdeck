#if DEBUG
import SwiftUI

/// DEBUG-only fidelity check: each mockup artboard (docs/design/mockup/screens/*.png) rebuilt
/// from the Paint Chip components with the mockup's sample data. Nothing here ships.
///
/// Launch straight into one artboard with `-wxGallery <Artboard>` (e.g. `-wxGallery Tech`).
public enum GalleryArtboard: String, CaseIterable, Identifiable, Sendable {
    case home = "Home"
    case tech = "Tech"
    case student = "Student"
    case wellness = "Wellness"
    case themeSync = "ThemeSync"
    case homeScreen = "HomeScreen"
    case main = "Main"

    public var id: String { rawValue }

    /// The artboard requested by the `-wxGallery` launch argument, if any.
    public static var launchArgument: GalleryArtboard? {
        guard let name = UserDefaults.standard.string(forKey: "wxGallery") else { return nil }
        return GalleryArtboard(rawValue: name)
    }
}

/// Index of all artboards.
public struct DesignGalleryView: View {
    public init() {}

    public var body: some View {
        List(GalleryArtboard.allCases) { artboard in
            NavigationLink(artboard.rawValue) {
                GalleryArtboardView(artboard: artboard)
                    .toolbar(.hidden, for: .navigationBar)
            }
        }
        .navigationTitle("Design Gallery")
    }
}

/// One artboard, full screen.
public struct GalleryArtboardView: View {
    private let artboard: GalleryArtboard

    public init(artboard: GalleryArtboard) {
        self.artboard = artboard
    }

    public var body: some View {
        switch artboard {
        case .home: GalleryScreen(tab: .home) { HomeArtboard() }
        case .tech: GalleryScreen(tab: .tech) { TechArtboard() }
        case .student: GalleryScreen(tab: .student) { StudentArtboard() }
        case .wellness: GalleryScreen(tab: .wellness) { WellnessArtboard() }
        case .themeSync: GalleryScreen(tab: .aesthetic) { ThemeSyncArtboard() }
        case .homeScreen: HomeScreenArtboard()
        case .main: MainArtboard()
        }
    }
}

/// Paper ground, scrolling content with the 24 pt gutter, and the tab bar.
struct GalleryScreen<Content: View>: View {
    @State var tab: WXTab
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            content
                .padding(.horizontal, WXSpace.gutter)
                .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(WXColor.paperIvory.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            WXTabBar(selection: $tab)
        }
    }
}

// MARK: - Home

private struct HomeArtboard: View {
    private struct Deck: Identifiable {
        let id: Int
        let color: Color
        let paint: String
        let name: String
    }

    private let deck = [
        Deck(id: 0, color: WXColor.sageNoon, paint: "Sage Noon", name: "Habits"),
        Deck(id: 1, color: WXColor.beachSand, paint: "Beach Hour", name: "Palette"),
        Deck(id: 2, color: WXColor.deepTide, paint: "Deep Tide", name: "Battery"),
        Deck(id: 3, color: WXColor.coralHour, paint: "Coral Hour", name: "Next Class")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WXPageHeader(title: "Today", subtitle: "Thursday 24 September · Morning, Maya")

            PaintChip(color: WXSection.student.color, field: .fixed(190), punchHole: .large, shadow: .heroCard) {
                ZStack(alignment: .topTrailing) {
                    ClockGlyph().opacity(0.9).padding(20)
                    FillBar(value: 0.72, color: WXColor.labelIvory, height: 6, trackOpacity: 0.32)
                        .fieldBottomBar(horizontal: 20, bottom: 20)
                }
            } label: {
                ChipLabelBand(caption: "Flow · Next up · BIO 201 · Room 3B", value: "Coral Hour", trailingValue: "14 min",
                              trend: "WG 0914 · Leave by 8:40", trendColor: WXColor.clayLink, valueSize: 28,
                              padding: EdgeInsets(top: 14, leading: 18, bottom: 14, trailing: 18), spacing: 6)
            }
            .frame(minHeight: 292)
            .padding(.top, 18)

            WXSectionHeader("On your home screen · 4 live", accessory: "See it") {}
                .padding(.top, 24)

            FanDeck(deck, angles: [-27, -9, 9, 27], pivot: UnitPoint(x: 0.5, y: 2.15), cardSize: CGSize(width: 96, height: 138)) {
                DeckChip(color: $0.color, paint: $0.paint, name: $0.name)
            }
            .padding(.top, 4)
            .frame(maxWidth: .infinity)
            .frame(height: 160, alignment: .top)
            .padding(.top, -10)

            PaintChip(axis: .horizontal, color: WXSection.wellness.color, field: .fixed(64), punchHole: .deck,
                      cornerRadius: WXRadius.chip, shadow: .actionChip) {
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Exam week · 3 deadlines by Fri").wxLabel()
                        Text("Add a Focus chip?").wxGrotesk(17)
                        Text("Why am I seeing this").wxLabel().underline()
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    WXPillButton("Add") {}
                        .padding(.trailing, 14)
                }
            }
            .frame(minHeight: 76)
            .padding(.top, 24)
        }
    }
}

// MARK: - Tech

private struct TechArtboard: View {
    private struct Metric: Identifiable {
        let id: String
        let value: String
        let fill: Double
        let color: Color
        let trend: String
        let trendColor: Color
    }

    private let metrics = [
        Metric(id: "Battery", value: "82%", fill: 0.82, color: WXColor.beachSand, trend: "Charging · est. 1h 10m", trendColor: WXColor.mossPositive),
        Metric(id: "Storage free", value: "118 GB", fill: 0.54, color: WXColor.coralHour, trend: "Of 256 · −2.1 GB wk", trendColor: WXColor.clayLink),
        Metric(id: "CPU load", value: "23%", fill: 0.23, color: WXColor.sageNoon, trend: "Down from 31% · 1 min", trendColor: WXColor.mossPositive),
        Metric(id: "Memory", value: "3.1 GB", fill: 0.52, color: WXColor.shell, trend: "Of 6 GB · steady", trendColor: WXColor.inkSecondary)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WXPageHeader(title: "Tech", subtitle: "Live while the app is open, every 5 seconds")

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(metrics) { metric in
                    PaintChip(color: WXSection.tech.color, field: .fixed(78), shadow: .metricCard) {
                        FillBar(value: metric.fill, color: metric.color).fieldBottomBar()
                    } label: {
                        ChipLabelBand(caption: metric.id, value: metric.value, trend: metric.trend, trendColor: metric.trendColor,
                                      valueSize: 24, tabular: true)
                    }
                    .frame(minHeight: 176)
                }
            }
            .padding(.top, 22)

            VStack(alignment: .leading, spacing: 8) {
                Text("Thermal state").wxLabel()
                ThermalStrip(state: .nominal)
            }

            PaintChip(axis: .horizontal, color: WXSection.tech.color, field: .fixed(64), punchHole: nil,
                      cornerRadius: WXRadius.chip, shadow: .contact) {
                ChipGlyph()
            } label: {
                ChipLabelBand(value: "iPhone 14 Pro · A16 Bionic", trend: "iOS 26.5 · 6-core CPU · 6 GB", valueSize: 17,
                              padding: EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
            }
            .frame(minHeight: 72)
            .padding(.top, 24)

            Text("Estimates are labelled. iOS doesn’t share GPU use, battery health or other apps’ activity, so Widgetdeck doesn’t show them.")
                .wxBody(13, lineHeight: 1.45)
                .padding(.top, 16)
        }
    }
}

// MARK: - Student

private struct StudentArtboard: View {
    @State private var view = 0

    private struct Block: Identifiable {
        let id = UUID()
        let day: Int
        let start: Double
        let end: Double
        let code: String
        let color: Color
    }

    private let blocks: [Block] = [
        Block(day: 0, start: 9, end: 10, code: "BIO 201", color: WXColor.coralHour),
        Block(day: 2, start: 9, end: 10, code: "BIO 201", color: WXColor.coralHour),
        Block(day: 4, start: 9, end: 10, code: "BIO 201", color: WXColor.coralHour),
        Block(day: 1, start: 9, end: 10, code: "ENG 110", color: WXColor.beachSand),
        Block(day: 3, start: 9, end: 10, code: "ENG 110", color: WXColor.beachSand),
        Block(day: 1, start: 10.5, end: 12, code: "CHEM 150", color: WXColor.deepTide),
        Block(day: 3, start: 10.5, end: 12, code: "CHEM 150", color: WXColor.deepTide),
        Block(day: 0, start: 13, end: 14, code: "PSY 101", color: WXColor.sageNoon),
        Block(day: 2, start: 13, end: 14, code: "PSY 101", color: WXColor.sageNoon),
        Block(day: 3, start: 14, end: 15.5, code: "CHEM LAB", color: WXColor.deepTide)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WXPageHeader(title: "Schedule")

            WXSegmentedControl(selection: $view, options: [(0, "Schedule"), (1, "Due"), (2, "Grades"), (3, "Focus")])
                .frame(height: 36)
                .padding(.top, 24)

            weekGrid.padding(.top, 26)

            VStack(alignment: .leading, spacing: 8) {
                WXSectionHeader("Due soon", accessory: "All 7") {}
                ListRowChip(color: WXColor.deepTide, title: "Lab report", meta: "CHEM 150 · Tomorrow 11:59 PM", metaColor: WXColor.clayLink) { CheckRing() }
                ListRowChip(color: WXColor.beachSand, title: "Reading response", meta: "ENG 110 · Fri 5:00 PM") { CheckRing() }
                ListRowChip(color: WXColor.coralHour, title: "Problem set 4", meta: "BIO 201 · Mon 9:00 AM") { CheckRing() }
            }
            .padding(.top, 18)
        }
    }

    /// Week grid geometry from the mockup: a 30 pt hour column, 5 day columns, 36 pt per hour.
    private var weekGrid: some View {
        GeometryReader { proxy in
            let columnWidth = (proxy.size.width - 30) / 5
            let hour: CGFloat = 36
            ZStack(alignment: .topLeading) {
                // Day labels
                ForEach(Array(["Mon", "Tue", "Wed", "Thu", "Fri"].enumerated()), id: \.offset) { index, day in
                    Text(day)
                        .wxLabel(color: index == 3 ? WXColor.labelIvory : WXColor.inkSecondary)
                        .padding(.vertical, 4).padding(.horizontal, 8)
                        .background(index == 3 ? WXColor.ink : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .frame(width: columnWidth)
                        .offset(x: 30 + CGFloat(index) * columnWidth)
                }
                ZStack(alignment: .topLeading) {
                    ForEach(Array(["8", "9", "10", "11", "12", "1", "2", "3"].enumerated()), id: \.offset) { index, label in
                        WXColor.rule.frame(height: 1).offset(y: CGFloat(index) * hour)
                        Text(label).wxLabel(10, color: WXColor.inkInactive).monospacedDigit()
                            .offset(y: CGFloat(index) * hour + 3)
                    }
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(WXColor.coralHour.opacity(0.08))
                        .frame(width: columnWidth - 0.4, height: 292)
                        .offset(x: 30 + 3 * columnWidth - 1)
                    ForEach(blocks) { block in
                        ClassBlock(code: block.code, color: block.color)
                            .frame(width: columnWidth - 4.4, height: (block.end - block.start) * hour - 4)
                            .offset(x: 32 + CGFloat(block.day) * columnWidth, y: (block.start - 8) * hour + 2)
                    }
                    WXColor.clayLink.frame(width: 70, height: 2).offset(x: 30 + 3 * columnWidth - 5, y: 27)
                    Circle().fill(WXColor.clayLink).frame(width: 10, height: 10).offset(x: 30 + 3 * columnWidth - 9, y: 23)
                }
                .offset(y: 30)
            }
        }
        .frame(height: 322)
        // A dense chart: the grid keeps its geometry; larger sizes use the list below instead.
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Week schedule")
    }
}

// MARK: - Wellness

private struct WellnessArtboard: View {
    @State private var habits = [true, true, false]
    @State private var mood: Int? = 3
    private let names = ["Read 20 min", "Water, 8 glasses", "Stretch"]
    private let streaks = ["23-day streak · +1 today", "9-day streak · +1 today", "3-day streak · open today"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WXPageHeader(title: "Wellness", subtitle: "\(habits.filter { $0 }.count) of 3 habits done today")

            VStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { index in
                    PaintChip(axis: .horizontal, color: WXSection.wellness.color, field: .fixed(68), punchHole: nil,
                              cornerRadius: WXRadius.chip, shadow: .rowChip) {
                        Button { habits[index].toggle() } label: { CheckKey(isOn: habits[index]) }
                            .buttonStyle(.plain)
                            .accessibilityLabel(names[index])
                            .accessibilityAddTraits(habits[index] ? .isSelected : [])
                    } label: {
                        ChipLabelBand(value: names[index], trend: streaks[index], trendColor: WXColor.mossPositive, valueSize: 18,
                                      padding: EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14), spacing: 5)
                    }
                    .frame(minHeight: 76)
                }
            }
            .padding(.top, 22)

            VStack(alignment: .leading, spacing: 10) {
                WXSectionHeader("Mood · last 14 days", accessory: "Mostly good", accessoryColor: WXColor.plumDusk)
                MoodHistoryBars(values: [2, 3, 3, 1, 2, 3, 4, 3, 2, 3, 3, 4, 3, 3])
                MoodKeys(selection: mood) { mood = $0 }
                    .padding(.top, 4)
            }
            .padding(.top, 14)

            PaintChip(axis: .horizontal, color: WXColor.plumDusk, field: .fixed(112), shadow: .actionCard) {
                BoxBreathGlyph()
            } label: {
                HStack(spacing: 0) {
                    ChipLabelBand(caption: "Box breathing", value: "3 minutes", padding: EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14), spacing: 5)
                    WXPillButton("Start", horizontalPadding: 18) {}
                        .padding(.trailing, 14)
                }
            }
            .frame(minHeight: 112)
            .padding(.top, 64)
        }
    }
}

// MARK: - ThemeSync

private struct ThemeSyncArtboard: View {
    @State private var before = 0.44

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WXPageHeader(title: "Match my wallpaper", subtitle: "Theme Sync reads the photo you pick", titleSize: 36)

            HStack(alignment: .top, spacing: 16) {
                WallpaperArt(style: .thumbnail)
                    .frame(width: 112, height: 206)
                    .wxRounded(WXRadius.card)
                    .wxShadow(.photo, cornerRadius: WXRadius.card)
                VStack(alignment: .leading) {
                    SwatchRow(color: WXColor.shell, role: "Surface", name: "Shell")
                    Spacer(minLength: 6)
                    SwatchRow(color: WXColor.beachSand, role: "Background", name: "Dune")
                    Spacer(minLength: 6)
                    SwatchRow(color: WXColor.coralHour, role: "Accent", name: "Coral Hour")
                    Spacer(minLength: 6)
                    SwatchRow(color: GalleryPaint.eveningSea, role: "Primary", name: "Evening Sea")
                    Spacer(minLength: 6)
                    SwatchRow(color: WXColor.deepTide, role: "Text", name: "Deep Tide")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 24)

            WXSectionHeader("Before · after", accessory: "\(Int(before * 100))% before", accessoryColor: WXColor.inkSecondary)
                .monospacedDigit()
                .padding(.top, 20)

            CompareWell(before: before)
                .padding(.top, 10)

            VStack(alignment: .leading, spacing: 4) {
                Text("Drag to compare").wxLabel()
                WXSlider(value: $before, label: "Drag to compare")
            }
            .padding(.top, 10)

            HStack(spacing: 10) {
                WXPrimaryButton("Apply to 6 widgets", height: 52) {}
                Text("Contrast checked · AA").wxLabel(color: WXColor.mossPositive).frame(width: 76, alignment: .leading)
            }
            .padding(.top, 22)
        }
    }
}

/// Before/after well: the themed chips, with the un-themed "before" look masked over the left.
private struct CompareWell: View {
    let before: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                pair(themed: true, width: proxy.size.width)
                pair(themed: false, width: proxy.size.width)
                    .background(GalleryPaint.beforeGround)
                    .frame(width: proxy.size.width * before, alignment: .leading)
                    .clipped()
                    .overlay(alignment: .trailing) { WXColor.ink.frame(width: 2) }
            }
        }
        .frame(height: 184)
        .background(WXColor.compareGround)
        .wxRounded(WXRadius.card)
    }

    private func pair(themed: Bool, width: CGFloat) -> some View {
        HStack(spacing: 14) {
            previewChip(themed: themed, color: WXColor.coralHour, caption: themed ? "Coral Hour" : "NEXT CLASS", value: "BIO 201")
            previewChip(themed: themed, color: WXColor.deepTide, caption: themed ? "Deep Tide" : "BATTERY", value: "82%")
        }
        .padding(12)
        .frame(width: width, alignment: .leading)
    }

    @ViewBuilder
    private func previewChip(themed: Bool, color: Color, caption: String, value: String) -> some View {
        if themed {
            PaintChip(color: color, field: .fixed(92), cornerRadius: 18, shadow: .preview) {
                ChipLabelBand(caption: caption, value: value, captionSize: 10, valueSize: 18,
                              padding: EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12), alignment: .topLeading)
            }
            .frame(width: 157, height: 160)
        } else {
            // The generic, un-themed widget look this feature replaces (mockup "before" state).
            VStack(alignment: .leading, spacing: 0) {
                GalleryPaint.beforeField.frame(height: 92)
                VStack(alignment: .leading, spacing: 4) {
                    Text(caption).font(.system(size: 11)).foregroundStyle(GalleryPaint.beforeCaption)
                    Text(value).font(.system(size: 18, weight: .semibold)).foregroundStyle(GalleryPaint.beforeValue)
                }
                .padding(.vertical, 10).padding(.horizontal, 12)
                Spacer(minLength: 0)
            }
            .frame(width: 157, height: 160)
            .background(Color.white)
            .wxRounded(18)
        }
    }
}

// MARK: - Home screen widgets

private struct HomeScreenArtboard: View {
    @State private var habits = [true, true, false]
    @State private var mood: Int?

    var body: some View {
        ZStack(alignment: .top) {
            WallpaperArt(style: .homeScreen).ignoresSafeArea()
            VStack(spacing: 24) {
                flowWidget.frame(width: 338, height: 158).paintChipWidgetTypeLimits()
                HStack(spacing: 22) {
                    habitsWidget.frame(width: 158, height: 158).paintChipWidgetTypeLimits()
                    batteryWidget.frame(width: 158, height: 158).paintChipWidgetTypeLimits()
                }
                HStack(spacing: 22) {
                    paletteWidget.frame(width: 158, height: 158).paintChipWidgetTypeLimits()
                    moodWidget.frame(width: 158, height: 158).paintChipWidgetTypeLimits()
                }
                appRow.padding(.top, 8)
                Spacer()
                HStack(spacing: 8) {
                    Circle().fill(WXColor.labelIvory).frame(width: 7, height: 7)
                    Circle().fill(WXColor.labelIvory.opacity(0.45)).frame(width: 7, height: 7)
                }
                .padding(.bottom, 62)
            }
            .padding(.top, 10)
        }
    }

    private var flowWidget: some View {
        PaintChip(axis: .horizontal, color: WXSection.student.color, field: .fixed(128), punchHole: .medium,
                  cornerRadius: WXRadius.widget, shadow: .widgetOnWallpaper) {
            ClockGlyph(size: 46, lineWidth: 2.6)
        } label: {
            ChipLabelBand(caption: "Coral Hour · Flow", value: "BIO 201\nin 14 min", trend: "Room 3B · leave by 8:40",
                          trendColor: WXColor.clayLink, valueSize: 25, tabular: true,
                          padding: EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
        }
    }

    private var habitsWidget: some View {
        PaintChip(color: WXSection.wellness.color, field: .fixed(86), cornerRadius: WXRadius.widget, shadow: .widgetOnWallpaper) {
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { index in
                    Button { habits[index].toggle() } label: { CheckKey(isOn: habits[index], size: 38) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.top, 8)
        } label: {
            ChipLabelBand(caption: "Water · Read · Stretch", value: "\(habits.filter { $0 }.count) of 3 today", tabular: true)
        }
    }

    private var batteryWidget: some View {
        PaintChip(color: WXSection.tech.color, field: .fixed(76), cornerRadius: WXRadius.widget, shadow: .widgetOnWallpaper) {
            ZStack(alignment: .topTrailing) {
                BoltGlyph().padding(.top, 8).padding(.trailing, 12)
                FillBar(value: 0.82, color: WXColor.beachSand, height: 14, trackOpacity: 0.18).fieldBottomBar()
            }
        } label: {
            ChipLabelBand(caption: "Battery · charging", value: "82%", trend: "Est. 1h 10m to full", tabular: true,
                          padding: EdgeInsets(top: 9, leading: 13, bottom: 9, trailing: 13), spacing: 3)
        }
    }

    private var paletteWidget: some View {
        PaintChip(color: WXColor.beachSand, field: .fixed(96), cornerRadius: WXRadius.widget, shadow: .widgetOnWallpaper) {
            HStack(spacing: 0) {
                ForEach(Array([WXColor.shell, WXColor.beachSand, WXColor.coralHour, GalleryPaint.eveningSea, WXColor.deepTide].enumerated()),
                        id: \.offset) { _, color in color }
            }
        } label: {
            ChipLabelBand(caption: "From your wallpaper", value: "Beach Hour", valueSize: 20,
                          padding: EdgeInsets(top: 9, leading: 13, bottom: 9, trailing: 13))
        }
    }

    private var moodWidget: some View {
        PaintChip(color: WXSection.evening.color, field: .fixed(96), cornerRadius: WXRadius.widget, shadow: .widgetOnWallpaper) {
            MoodKeys(selection: mood, style: .capsules) { mood = $0 }
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 16)
        } label: {
            ChipLabelBand(caption: "Plum Dusk · Mood", value: mood.map { "Logged: \(MoodScale.words[$0])" } ?? "How was today?",
                          valueSize: 20, padding: EdgeInsets(top: 9, leading: 13, bottom: 9, trailing: 13))
        }
    }

    private var appRow: some View {
        HStack(spacing: 18) {
            appIcon("Calendar", background: WXColor.labelIvory) { AppGlyph(kind: .calendar).stroke(WXColor.coralHour, style: glyphStroke) }
            appIcon("Photos", background: WXColor.labelIvory) { AppGlyph(kind: .photos).stroke(WXColor.plumDusk, style: glyphStroke) }
            appIcon("Messages", background: WXColor.sageNoon) { AppGlyph(kind: .messages).stroke(WXColor.labelIvory, style: glyphStroke) }
            appIcon("Widgetdeck", background: nil) { FanIconArt() }
        }
        .frame(width: 338)
    }

    private var glyphStroke: StrokeStyle { StrokeStyle(lineWidth: 1.9 * 30 / 24, lineCap: .round, lineJoin: .round) }

    private func appIcon(_ name: String, background: Color?, @ViewBuilder glyph: () -> some View) -> some View {
        VStack(spacing: 6) {
            ZStack {
                if let background {
                    background
                    glyph().frame(width: 30, height: 30)
                } else {
                    glyph()
                }
            }
            .frame(width: 62, height: 62)
            .wxRounded(15)
            .shadow(color: .black.opacity(0.25), radius: 5, y: 4)
            Text(name).font(.system(size: 12)).foregroundStyle(WXColor.labelIvory)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct AppGlyph: Shape {
    enum Kind { case calendar, photos, messages }
    let kind: Kind

    func path(in rect: CGRect) -> Path {
        let s = rect.width / 24
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
        var path = Path()
        switch kind {
        case .calendar:
            path.addRect(CGRect(origin: p(4, 6), size: CGSize(width: 16 * s, height: 14 * s)))
            path.move(to: p(4, 10)); path.addLine(to: p(20, 10))
            path.move(to: p(8, 3)); path.addLine(to: p(8, 7))
            path.move(to: p(16, 3)); path.addLine(to: p(16, 7))
        case .photos:
            path.addRect(CGRect(origin: p(4, 5), size: CGSize(width: 16 * s, height: 14 * s)))
            path.move(to: p(4, 16)); path.addLine(to: p(9, 11)); path.addLine(to: p(13, 15)); path.addLine(to: p(16, 12)); path.addLine(to: p(20, 16))
        case .messages:
            path.move(to: p(4, 5)); path.addLine(to: p(20, 5)); path.addLine(to: p(20, 16)); path.addLine(to: p(9, 16))
            path.addLine(to: p(4, 20)); path.closeSubpath()
        }
        return path
    }
}

/// The Widgetdeck app icon artwork (fan of four chips on sand), redrawn for the home-screen artboard.
private struct FanIconArt: View {
    var body: some View {
        Canvas { context, size in
            let s = size.width / 180
            // Icon ground: the app icon's own sand fade (app-icon artwork, not UI chrome).
            context.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .linearGradient(Gradient(colors: [Color(wxHex: 0xFBEBCB), WXColor.beachSand]),
                                               startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            let cards: [(Double, UInt32, UInt32)] = [(-28, 0x4E3F58, 0x6D597A), (-9.5, 0x3E6652, 0x81B29A), (9.5, 0x2F3148, 0x3D405B), (28, 0xB2492F, 0xE07A5F)]
            for (angle, dark, light) in cards {
                var ctx = context
                ctx.translateBy(x: 90 * s, y: 100 * s)
                ctx.scaleBy(x: 0.78, y: 0.78)
                ctx.translateBy(x: -90 * s, y: -100 * s)
                ctx.translateBy(x: 90 * s, y: 178 * s)
                ctx.rotate(by: .degrees(angle))
                ctx.translateBy(x: -90 * s, y: -178 * s)
                ctx.fill(Path(roundedRect: CGRect(x: 63 * s, y: 34 * s, width: 54 * s, height: 96 * s), cornerRadius: 9 * s), with: .color(Color(wxHex: dark)))
                ctx.fill(Path(roundedRect: CGRect(x: 63 * s, y: 34 * s, width: 54 * s, height: 68 * s), cornerRadius: 9 * s), with: .color(Color(wxHex: light)))
                ctx.fill(Path(CGRect(x: 63 * s, y: 92 * s, width: 54 * s, height: 10 * s)), with: .color(Color(wxHex: light)))
            }
        }
    }
}

// MARK: - Main (onboarding)

private struct MainArtboard: View {
    @State private var picked = WXThemePaint.launchThemes[1].id

    private var pickedPaint: WXThemePaint {
        WXThemePaint.launchThemes.first { $0.id == picked } ?? WXThemePaint.launchThemes[1]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    WXPageDots(count: 4, current: 0)
                    Spacer()
                    Text("Skip").wxLabel().padding(.vertical, 12).padding(.leading, 12)
                }
                Text("Pick your vibe.").wxGrotesk(40).accessibilityAddTraits(.isHeader)
                Text("One theme runs every widget you add. You can change it any time.")
                    .wxBody(16, lineHeight: 1.4)
                    .frame(maxWidth: 300, alignment: .leading)
            }
            .padding(.horizontal, WXSpace.gutter)

            FanDeck(WXThemePaint.launchThemes, angles: [-24, -14.5, -5, 5, 14.5, 24], pivot: UnitPoint(x: 0.5, y: 1.18),
                    cardSize: CGSize(width: 96, height: 300), selectedID: picked, onSelect: { picked = $0.id }) { paint in
                PaintStrip(paint, shadow: paint.id == picked ? .chipLifted : .chipFanned)
            }
            .padding(.top, 20)
            .frame(maxWidth: .infinity)
            .frame(height: 360, alignment: .top)
            .padding(.top, 19)

            VStack(alignment: .leading, spacing: 6) {
                Text("\(pickedPaint.code) · \(pickedPaint.mood)").wxLabel()
                Text(pickedPaint.name).wxGrotesk(28)
            }
            .padding(.horizontal, WXSpace.gutter)
            .padding(.top, 24)

            Spacer(minLength: 16)

            VStack(spacing: 8) {
                WXPrimaryButton("Use \(pickedPaint.name)") {}
                Text("Every theme is free. Change it any time.")
                    .wxBody(13, color: WXColor.inkSecondary)
                    .padding(.vertical, 6)
            }
            .padding(.horizontal, WXSpace.gutter)
            .padding(.bottom, 6)
        }
        .background(WXColor.paperIvory.ignoresSafeArea())
    }
}

// MARK: - Shared artwork

typealias GalleryPaint = ThemeSyncPaint

/// The flat beach-sunset wallpaper from the HomeScreen and ThemeSync artboards.
private struct WallpaperArt: View {
    enum Style { case homeScreen, thumbnail }
    let style: Style

    var body: some View {
        Canvas { context, size in
            switch style {
            case .thumbnail:
                // viewBox 390 × 718, slice.
                let s = max(size.width / 390, size.height / 718)
                func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> Path { Path(CGRect(x: x * s, y: y * s, width: w * s, height: h * s)) }
                context.fill(r(0, 0, 390, 718), with: .color(WXColor.beachSand))
                context.fill(r(0, 0, 390, 260), with: .color(WXColor.shell))
                context.fill(Path(ellipseIn: CGRect(x: (276 - 128) * s, y: (470 - 128) * s, width: 256 * s, height: 256 * s)), with: .color(WXColor.coralHour))
                context.fill(r(0, 494, 390, 224), with: .color(WXColor.deepTide))
                context.fill(r(0, 528, 390, 14), with: .color(GalleryPaint.eveningSea))
                var dune = Path()
                dune.move(to: CGPoint(x: 0, y: 660 * s))
                dune.addQuadCurve(to: CGPoint(x: 390 * s, y: 660 * s), control: CGPoint(x: 195 * s, y: 620 * s))
                dune.addLine(to: CGPoint(x: 390 * s, y: 718 * s)); dune.addLine(to: CGPoint(x: 0, y: 718 * s)); dune.closeSubpath()
                context.fill(dune, with: .color(GalleryPaint.wallpaperSand))
            case .homeScreen:
                // viewBox 390 × 844, stretched to the screen.
                let sx = size.width / 390, sy = size.height / 844
                func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> Path { Path(CGRect(x: x * sx, y: y * sy, width: w * sx, height: h * sy)) }
                context.fill(r(0, 0, 390, 844), with: .color(WXColor.beachSand))
                context.fill(r(0, 0, 390, 300), with: .color(WXColor.shell))
                context.fill(Path(ellipseIn: CGRect(x: (276 - 128) * sx, y: (560 - 128) * sy, width: 256 * sx, height: 256 * sx)), with: .color(WXColor.coralHour))
                context.fill(r(0, 584, 390, 260), with: .color(WXColor.deepTide))
                context.fill(r(0, 618, 390, 14), with: .color(GalleryPaint.eveningSea))
                context.fill(r(0, 664, 390, 8), with: .color(GalleryPaint.eveningSea))
                context.fill(r(180, 600, 190, 6), with: .color(WXColor.coralHour.opacity(0.7)))
                var dune = Path()
                dune.move(to: CGPoint(x: 0, y: 770 * sy))
                dune.addQuadCurve(to: CGPoint(x: 390 * sx, y: 770 * sy), control: CGPoint(x: 195 * sx, y: 724 * sy))
                dune.addLine(to: CGPoint(x: 390 * sx, y: 844 * sy)); dune.addLine(to: CGPoint(x: 0, y: 844 * sy)); dune.closeSubpath()
                context.fill(dune, with: .color(GalleryPaint.wallpaperSand))
            }
        }
        .accessibilityLabel("Wallpaper: a flat beach sunset")
    }
}

#Preview("Gallery · Home") { GalleryArtboardView(artboard: .home) }
#endif
