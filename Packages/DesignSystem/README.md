# DesignSystem

The **Paint Chip** system (`DESIGN.md`) as SwiftUI: tokens, bundled fonts, chip components, app
chrome and widget chrome. Built to match the approved mockup (`docs/design/mockup/`) exactly.
Depends only on CoreKit. No persistence.

**Rule for feature code:** build UI only from these tokens and components. Never hand-roll a chip,
pick a hex value, or set a font by name.

## Fonts

| Role | Font | File (in `Sources/DesignSystem/Resources/Fonts`) |
|---|---|---|
| Names and values ≤ 20 pt | Bricolage Grotesque Bold, optical size 16 | `BricolageGrotesque-Bold.ttf` |
| Display and headline ≥ 21 pt | Bricolage Grotesque Bold, optical size 36 | `BricolageGrotesqueDisplay-Bold.ttf` |
| Caps labels | Archivo Bold, width 75 (condensed) | `ArchivoCondensed-Bold.ttf` |
| Body | SF Pro (system) | |

- Licences: `OFL-BricolageGrotesque.txt`, `OFL-Archivo.txt` (SIL OFL 1.1, no reserved names).
- The statics were instanced from the Google Fonts variable fonts (`ofl/bricolagegrotesque`,
  `ofl/archivo`; google/fonts no longer ships `static/` folders) with fontTools `varLib.instancer`:
  Bricolage `wght=700 wdth=100 opsz=16|36`, Archivo `wght=700 wdth=75`. The two Bricolage optical
  sizes reproduce the browser's automatic optical sizing that the mockup was rendered with.
- **Registration:** `CTFontManagerRegisterFontsForURL(.process)` from the package bundle, run lazily
  by every `WXFont` accessor, so it works in the app **and inside the widget extension** without
  `UIAppFonts`. The app also calls `WXFonts.registerIfNeeded()` at launch. If registration fails,
  `Font.custom` falls back to the system font; text never disappears.

## Theme decks

`WXDeck` (in `Decks/`) is the user's theme: section paints, paper, band, display face, corner
roundness and punch-hole shape. Ten ship (`WXDeck.all`); the first, `.paintChip`, is the default.

- `WXDeck.current` is read from the App Group defaults, so the app and the widget extension agree.
  `WXDeck.select(_:)` writes it; the app calls it through `AppEnvironment.applyDeck(_:)`, which
  also clears any Theme Sync palette and reloads every widget.
- You don't need to do anything in feature code: `WXColor.coralHour/sageNoon/beachSand/deepTide/
  plumDusk/paperIvory/labelIvory`, `WXSection.color/paintName`, `WXFont.display/headline/title`,
  `wxGrotesk`, `wxRounded`, `wxShadow` and `PaintChip`'s punch hole all resolve through the active deck.
  Keep using role tokens; never hard-code a hex for a section.
- Pickers that show several decks at once draw from an explicit deck: `DeckStrip`, `DeckPicker`,
  `DeckPreview`, `WXFont.grotesk(_:relativeTo:deck:)`, `PunchHoleShape`.
- The app redraws after a change because `RootView` keys its tab content on `AppEnvironment.deckID`.
  A view that caches a colour in `@State` won't update; read the token in `body` instead.
- Adding a deck: append a `WXDeck` to `all`, bundle its face (static TTF + `OFL-<Family>.txt`) and
  add it to `WXFonts.fileNames`. `DeckTests` checks contrast, roles, fonts and licences.

## Tokens

```swift
WXColor.coralHour / sageNoon / beachSand / deepTide / plumDusk           // paints
WXColor.paperIvory / labelIvory / shell / ink / inkSecondary / inkBody / inkInactive / rule
WXColor.clayLink / mossPositive                                            // link/urgent, positive
WXColor.moodTints, .moodTintsOnPlum, .thermal, .segmentTrack, .pageDotInactive, .checkRing, .compareGround
WXThemePaint.launchThemes                                                  // onboarding paint strips (theme pickers only)

WXSection.student.color       // student=coral, wellness=sage, aesthetic=sand, tech=deepTide, evening=plum
WXSection(appSection)         // from CoreKit's AppSection; .paintName = "Coral Hour", …

WXRadius.swatch 8 · .chip 14 · .card 16 · .widget 22 · .pill 22 · .deckChip 12
WXSpace.xs 6 · .sm 10 · .md 14 · .gutter 24
```

Colours are paint: they don't change in dark mode. DESIGN.md defines no dark appearance, so the
app shell sets `.preferredColorScheme(.light)`.

### Type

| Modifier | What it sets |
|---|---|
| `.wxGrotesk(size, tabular:, color:)` | Bricolage 700, −0.02 em, CSS line-height 1.05. 40 display · 22–34 headline · 15–18 title |
| `.wxLabel(size = 11, color:)` | Archivo Condensed 700, UPPERCASE, +0.08 em, line-height 1.25. 9–11 pt |
| `.wxBody(size = 15, lineHeight: 1.35, color:)` | SF Pro via the matching text style (17 body, 16 callout, 15 subheadline, 13 footnote) |
| `WXFont.display / headline / title / body / label` | The `Font`s alone |

All sizes scale with Dynamic Type (`relativeTo:`); tracking and line height scale too. The
line-height modifier emulates CSS so spacing matches the mockup's `1 CSS px = 1 pt` values.

### Shadows

`.wxShadow(.chipRest, cornerRadius:)`, or the named shorthands `.chipRest()`, `.widgetOnWallpaper()`,
`.chipLifted()`. CSS negative spread has no SwiftUI equivalent, so each layer is drawn as an inset,
offset, blurred copy of the shape (blur = CSS blur / 2). Presets from DESIGN.md: `chipRest`,
`widgetOnWallpaper`, `chipLifted`; from the mockup: `heroCard`, `metricCard`, `rowChip`,
`actionChip`, `actionCard`, `block`, `contact`, `hairline`, `preview`, `photo`, `segment`, `chipFanned`.

## Components

```swift
// A metric card (Tech)
PaintChip(color: WXSection.tech.color, field: .fixed(78), shadow: .metricCard) {
    FillBar(value: 0.82, color: WXColor.beachSand).fieldBottomBar()
} label: {
    ChipLabelBand(caption: "Battery", value: "82%", trend: "Charging · est. 1h 10m",
                  trendColor: WXColor.mossPositive, valueSize: 24, tabular: true)
}

// A habit row (Wellness)
PaintChip(axis: .horizontal, color: WXSection.wellness.color, field: .fixed(68), punchHole: nil,
          cornerRadius: WXRadius.chip, shadow: .rowChip) {
    Button { toggle() } label: { CheckKey(isOn: done) }.buttonStyle(.plain)
} label: {
    ChipLabelBand(value: "Read 20 min", trend: "23-day streak · +1 today", trendColor: WXColor.mossPositive,
                  valueSize: 18, padding: EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14), spacing: 5)
}
.frame(minHeight: 76)
```

| Component | Notes |
|---|---|
| `PaintChip(axis:color:field:punchHole:cornerRadius:shadow:field:label:)` | Colour field + Label Ivory band. `field: .fixed(pt)` or `.ratio(x)`; also `PaintChip(axis:color:fieldRatio:punchHole:)`. Free height → chip grows with Dynamic Type; fixed height → field shrinks, band clips at its own edge (never over the field). Adapts to widget accented/vibrant rendering. |
| `PunchHole` | `.small` 8/8 · `.deck` 9/9 · `.regular` 9/10 · `.medium` 11/13 · `.large` 12/14 · `.strip` centred |
| `ChipLabelBand(caption:value:trailingValue:trend:trendColor:captionSize:valueSize:tabular:padding:spacing:)` | Caps / display / caps. Two sizes max. `trailingValue` = right-aligned second value (Home hero). |
| `FanDeck(items, angles:, pivot:, cardSize:, selectedID:, onSelect:) { card }` | Rotation about a shared pivot below; selected lifts −34 pt, comes to front, 0.45 s curve (off with Reduce Motion). Home: `[-27,-9,9,27]`, pivot `(0.5, 2.15)`, 96×138. Main: `[-24,-14.5,-5,5,14.5,24]`, pivot `(0.5, 1.18)`, 96×300. |
| `DeckChip(color:paint:name:)` | The 96×138 fan chip (Home). |
| `PaintStrip(steps:code:name:)` / `PaintStrip(WXThemePaint)` | 4 steps × 58 pt + 68 pt band, centred hole. |
| `FillBar(value:color:height:trackOpacity:)` + `.fieldBottomBar()` | Flat bar on a field. 12/.16 cards, 14/.18 widgets, 6/.32 hero. `nil` = unknown. |
| `ThermalStrip(state:)` | `ThermalStrip.Level(ProcessInfo.thermalState)`. |
| `CheckKey(isOn:size:)` | Ivory ring check, 44 app / 38 widget. |
| `MoodKeys(selection:style:onSelect:)` | `.keys` (Wellness, on paper) or `.capsules` (Mood widget, on plum). `MoodHistoryBars(values:)`, `MoodScale.words`. |
| `ClassBlock(code:color:)` | Week-grid block (radius 8, 20 pt band, no hole). |
| `ListRowChip(color:title:meta:metaColor:) { CheckRing() }` | Due-soon rows. |
| `SwatchRow(color:role:name:)`, `WXSlider(value:label:)` | Theme Sync palette rows and compare slider. |
| Glyphs: `ClockGlyph`, `BoltGlyph`, `ChipGlyph`, `BoxBreathGlyph` | The mockup's field drawings. |
| `WXTabBar(selection:)` | 5 tabs (`WXTab`), stroke icons, 10 pt caps. Attach with `.safeAreaInset(edge: .bottom)`. Labels don't scale (like the system tab bar); Large Content Viewer on long-press. |
| `WXPageHeader(title:subtitle:titleSize:)` | 40 pt title + 15 pt subtitle. No eyebrow. 36 for long titles. |
| `WXSectionHeader(_:accessory:accessoryColor:action:)` | Caps label + caps link (44 pt target when tappable). |
| `WXSegmentedControl(selection:options:)` | #ECE6DA track, ivory selected segment. |
| `WXPrimaryButton` / `.buttonStyle(.wxPrimary)` | Ink, 54 pt, radius 14, 17 semibold. |
| `WXPillButton` / `.buttonStyle(.wxPill)` | Ink, 44 pt, radius 22, 15 semibold. |
| `WXPageDots(count:current:)` | Onboarding progress. |

Legacy (pre-Paint-Chip) components still compile and now use the Paint Chip semantic palette:
`ThemedCard`, `GaugeRing`, `StatTile`, `TrendLine`, `ChipPicker`, `ThemedToggle`, `ThemedSlider`,
`SectionHeader`, `EmptyState`, `PermissionPrimer`, `ShimmerLoader`, `Space`, `Radius`,
`SemanticPalette`, `@SemanticColors`, `dsForeground`. New UI should not use them (GaugeRing in
particular: DESIGN.md draws progress as flat bars, except native lock-screen gauges).

## Widgets

```swift
StaticConfiguration(kind: …, provider: …) { entry in
    PaintChipWidget(color: WXSection.tech.color, field: .fixed(76)) {
        FillBar(value: entry.level, color: WXColor.beachSand, height: 14, trackOpacity: 0.18).fieldBottomBar()
    } label: {
        ChipLabelBand(caption: "Battery · charging", value: "82%", trend: "Est. 1h 10m to full", tabular: true)
    }
}
.contentMarginsDisabled()        // required: the chip runs edge to edge
```

- `PaintChipWidget` = `PaintChip` without its own radius/shadow (the system draws the widget), a
  Label Ivory `containerBackground` (`.paintChipWidgetBackground()`), and
  `.paintChipWidgetTypeLimits()` (Dynamic Type capped at xxLarge, text may shrink to 75 %).
- Rendering modes: fullColor draws paints; accented (iOS 18 tinted / iOS 26 clear) turns the field
  into a `widgetAccentable` block and drops the ivory band; vibrant (Lock Screen/StandBy) uses
  translucent primary. `DSRenderingMode` wraps `widgetRenderingMode`, so no `#available` is needed.
- Lock Screen accessories keep system styling (`AccessoryWidgetBackground`); the old
  `widgetChrome()` / `WidgetUnavailableView` still work.
- Home-screen widget sizes in the mockup: medium 338×158 (field 128), small 158×158 (field 76–96).

## Mockup → component map

| Artboard | Built from |
|---|---|
| Home | `WXPageHeader`, hero `PaintChip` (`.large` hole, `ClockGlyph`, `FillBar` 6 pt, `ChipLabelBand` with `trailingValue`, `.heroCard`), `WXSectionHeader`, `FanDeck` + `DeckChip`, horizontal `PaintChip` + `WXPillButton`, `WXTabBar` |
| Tech | 2×2 `PaintChip` + `FillBar` (`.metricCard`), `ThermalStrip`, horizontal `PaintChip` + `ChipGlyph` (no hole) |
| Student | `WXSegmentedControl`, `ClassBlock` (grid layout is StudentFeature's), `WXSectionHeader`, `ListRowChip` + `CheckRing` |
| Wellness | horizontal `PaintChip` + `CheckKey`, `MoodHistoryBars`, `MoodKeys(.keys)`, horizontal `PaintChip` + `BoxBreathGlyph` + pill |
| ThemeSync | `WXPageHeader(titleSize: 36)`, `SwatchRow`, preview `PaintChip`s (radius 18, `.preview`), `WXSlider`, `WXPrimaryButton(height: 52)` |
| HomeScreen | `PaintChip`/`PaintChipWidget`: Flow (horizontal, `.medium` hole), Habits (`CheckKey` 38), Battery (`BoltGlyph` + `FillBar` 14), Palette (5-stripe field), Mood (`MoodKeys(.capsules)`) |
| Main | `WXPageDots`, `FanDeck` + `PaintStrip` (`.chipLifted` / `.chipFanned`), `WXPrimaryButton` |
| FlowDay, LockScreen | Not in the gallery (Phase 2 / S-08, W-04). Same `PaintChip` anatomy. |

## Design Gallery (DEBUG only)

`DesignGalleryView` (Home tab → "Design gallery (debug)") renders each artboard from these
components with the mockup's sample data. Launch straight into one for screenshots:

```bash
xcrun simctl launch booted io.github.mineprodan.iospremium -wxGallery Tech   # Home, Tech, Student, Wellness, ThemeSync, HomeScreen, Main
xcrun simctl io booted screenshot Tech.png
```

Reviewed screenshots live in `docs/design/mockup/built/`.

## Tests

```bash
cd Packages/DesignSystem
xcodebuild test -scheme DesignSystem -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Paint Chip suites: every DESIGN.md colour, section mapping, ramps, radii/spacing, shadow values,
WCAG AA for every chip text pair, font registration + PostScript names + licences, condensed width,
and chip layout growth (including AX3). Plus the original contrast/theme-resolver suites.

## Feature follow-ups

Changes feature packages should make (this step didn't touch feature packages):

- **All features:** replace the placeholder `EmptyState` section views with Paint Chip screens. The
  app shell already draws `WXPageHeader` above each section view (titles: Schedule, Aesthetic,
  Wellness, Tech); a feature that needs a dynamic subtitle ("2 of 3 habits done today") should ask
  Integration to move the header into the feature view or pass the subtitle up.
- **All widgets:** switch to `PaintChipWidget` + `.contentMarginsDisabled()`; drop `widgetChrome()`
  for system families. Don't use `GaugeRing`/`StatTile` in new UI.
- **Tech:** thermal uses `ThermalStrip.Level(ProcessInfo.thermalState)`; the mockup's device chip is
  a horizontal `PaintChip` with `ChipGlyph` and no punch hole.
- **Student:** build the week grid (30 pt hour column, 36 pt per hour, Thursday column tint
  `coralHour.opacity(0.08)`, 2 pt Clay Link "now" line) from `ClassBlock`; cap its Dynamic Type
  (the gallery uses `...xLarge`) and offer the list for larger sizes.
- **Aesthetic:** theme hues (`WXThemePaint`, the user's palette) stay inside theme pickers and
  user-themed widgets ("The Theme Stays in the Theme").
- **Wellness:** mood index 0…4 maps to `MoodScale.words` and both tint ramps.
- **Integration (P-06):** onboarding = the Main artboard; Home hero + fan deck = the Home artboard.
  Settings is reachable from a Home-tab link for now (the mockup has no Settings tab).
