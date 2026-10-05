# AestheticFeature

The Aesthetic section, 1.0 scope: **A-01 Photo widget**, **A-02 Theme Sync + Palette widget**, **A-06 Mood board widget** and **A-07 borders and effects** (A-06/A-07 built 2026-10-01).
**After launch:** A-03 transparent wizard, A-04 curated feed, A-05 Pinterest.

| Product | Linked by | Contains |
|---|---|---|
| `AestheticFeature` | app | `AestheticSectionView`, `AestheticStore`, `PaletteExtractor`, `RoleAssigner`, `PhotoLibrary`, theme repositories |
| `AestheticFeatureWidgetKit` | widget extension | `PaletteSnapshot`, `PhotoSnapshot`, `AestheticFiles`, `PhotoWidgetSize`, timeline providers, `PaletteWidgetView`, `PhotoWidgetView` |

## Theme Sync (A-02)

Apps can't read the wallpaper, so the user picks the same photo with `PhotosPicker`. The picker runs out of process, so no photo-library permission is requested and no Info.plist key is needed.

1. **Extract** (`PaletteExtractor`): CoreKit `Downsampler` makes a 64 px thumbnail, so the full image is never decoded. Six seeds are chosen by farthest-point picking, which is deterministic. `CIKMeans` refines them in perceptual space, followed by a few Lloyd passes. The same Lloyd run from the seeds alone is the fallback when Core Image can't render, and whichever clustering is tighter wins. Clusters under 3 % of the image are dropped as edge blends, then five are kept (a small vivid accent such as a sun always stays). Flat or two-colour images are padded with lighter and darker mixes. No ML frameworks are used.
2. **Roles** (`RoleAssigner`, by HSB and luminance): Text = the darkest colour. Accent = the most vivid (saturation × brightness). Surface, Background and Primary = the remaining three, lightest to darkest.
3. **Contrast fix-up**: `textOnBackground` is nudged with DesignSystem `ContrastChecker` until it meets 4.5:1 on both background and surface, and `textOnAccent` until it meets 4.5:1 on the accent. The "Contrast checked · AA" label is shown only when every pair passes.
4. **Names**: each paint gets the nearest name (CIE Lab) from a fixed list that includes the mockup's paints (Shell, Dune, Coral Hour, Evening Sea, Deep Tide…), with no repeats. The theme name comes from the accent's hue family plus whether the background is light or dark ("Beach Hour", "Moss Field", "Plum Dusk"…).
5. **Apply**: `ThemeRepository.applyTheme` saves a CoreKit `Theme` (`source: .wallpaper`) and sets `UserProfile.activeThemeID`. The theme uses one stable ID from `Aesthetic/settings.json`, so re-syncing replaces it instead of piling up themes. The app then writes `PaletteSnapshot`, calls `onThemeApplied` and reloads every widget kind. The button says "Apply to N widgets", with N from `WidgetCenter.getCurrentConfigurations` (the iOS 17 API).

The screen keeps only a display-size wallpaper thumbnail (`Aesthetic/wallpaper.jpg`, 640 px max). The original photo is never stored.

## Photo widget (A-01)

- `PhotosPicker` (ordered, images only), up to **24 photos**.
- On import, each photo is downsampled once per family (small, medium, large) to the **exact pixel size of that widget on this device**: `PhotoWidgetSize` holds Apple's widget-size table × the screen scale. The results are JPEGs in `AppGroup/Library/Application Support/Aesthetic/Photos/`. They are not in Caches, because they're user content and must not be purged. The widget decodes an already-sized file and never resizes. Screens missing from the table use the smallest listed screen at least as large, so images are cropped slightly and never upscaled. Large on an iPhone 17 Pro Max is about 1092 × 1146 px (≈5 MB decoded), well under the ~30 MB widget limit.
- Rotation is **daily** (7 entries at local midnights) or **hourly** (24 entries on the hour), then `.after(next boundary)`. The photo for a period is `periodIndex mod count`, where periodIndex counts calendar days (× 24 + hour) from a fixed local origin. That keeps it DST-safe and the same in every timeline and in the app's "on the widget now" outline. With 0 or 1 photos there's a single entry with policy `.never`, and the app reloads the widget whenever the photo list changes.
- The widget design is the photo edge to edge with the Paper Ivory punch hole, and no text, so nothing sits on the photo. When the Home Screen is tinted (iOS 18+), the photo renders `.desaturated`.

## Mood board widget (A-06)

- Picked with `PhotosPicker` (ordered, images only, no library permission), up to **12 photos**, in the section's "Mood board" panel. Touch and hold a thumbnail to **Move earlier / Move later / Remove** (also VoiceOver actions). A live preview shows the medium grid as it looks today.
- Layouts (`MoodBoardLayout`): **medium** 2 × 2; **large** 3 × 2 (`large6`), or 4 × 2 (`large8`) once the board has 8+ photos. 3 pt gaps on Label Ivory, punch hole top-left.
- `MoodBoardLibrary` downsamples each photo once **per layout to the exact tile pixel size** (`MoodBoardLayout.tilePixels`, from `PhotoWidgetSize` × scale, rounded up) into `Aesthetic/MoodBoard/`. The widget never resizes. Largest board (large8 on a Pro Max): 8 tiles ≈ 4 MB decoded, far under the ~30 MB ceiling.
- **Shuffle daily** (off by default): 7 entries at local midnights, each a deterministic per-day shuffle (SplitMix64 seeded by the day index), so the app preview and every timeline agree. Off, or ≤ 1 photo: one entry, `.never`.
- Fewer photos than tiles: remaining tiles are flat Paint Chip paints. No photos: a horizontal Paint Chip "Mood board / Add photos". Never blank.

## Borders and effects (A-07)

Per widget (Photo, Mood board, Palette) in the "Borders and effects" panel, flat paint only (no gradients, glass or blur):

| Option | Values | Applies to |
|---|---|---|
| Border | off (default) / on | all three |
| Border colour | Label Ivory, Paper Ivory, Ink, Coral Hour, Sage Noon, Beach Sand, Deep Tide, Plum Dusk, Theme accent, Theme primary (from `ActiveThemeStore`; falls back to Coral Hour / Deep Tide) | all three |
| Width | 4 / 8 / 12 pt | all three |
| Corners | rounded (concentric `ContainerRelativeShape`, tiles 8 pt) / square | Photo, Mood board (the outer widget corner belongs to the system) |
| Dim | none / light 15 % / medium 30 % flat Ink veil | Photo, Mood board |

The border is a mat: content is clipped and inset, the paint shows around it. In tinted/clear/vibrant modes the border becomes an accentable tint band and dim is skipped (photos already render `.desaturated`).

Settings are one App Group file, `Snapshots/aesthetic-styles.json` (`AestheticStyleSnapshot`, `fileName` override of the `photo` kind so it doesn't collide with `photo.json`). Each field decodes with defaults, so missing or unknown values never break a widget. The views read it at render time (like `ActiveThemeStore`); changing a style reloads only that widget kind. Settings are app-wide per widget type, not per placed instance: an `AppIntentConfiguration` per instance was left out to keep the hookup to zero (possible follow-up).

## Widgets

| Widget | Kind | Families | Empty state |
|---|---|---|---|
| Palette | `WidgetKind.palette` | systemSmall (Paint Chip, 5 paint stripes as the field, "From your wallpaper / Beach Hour"), accessoryRectangular (caption, stripe row, name) | "Theme Sync / Pick a wallpaper" |
| Photo | `WidgetKind.photo` | systemSmall, systemMedium, systemLarge | "Photo widget / Add photos" chip |
| Mood board | `WidgetKind.moodBoard` | systemMedium, systemLarge | "Mood board / Add photos" chip; gallery preview = flat paint tiles |

Both link to `widgetx://section/aesthetic`. In tinted, clear and vibrant modes the palette stripes become a ramp of the system tint, ordered by each paint's darkness. **Gallery previews** don't depend on the clock: the Palette preview is `PaletteSnapshot.sample` (the mockup's Beach Hour, fixed date), and the Photo preview is the drawn `SampleBeachArt`. Neither shows any time-relative text.

## Data

| Item | Where | Synced |
|---|---|---|
| Theme | Core Data Cloud config (CoreKit `Theme` via `RecordStore`) | yes |
| `UserProfile.activeThemeID` | Core Data Cloud config | yes |
| `PaletteSnapshot`, `PhotoSnapshot`, `MoodBoardSnapshot`, `AestheticStyleSnapshot` | App Group `Snapshots/palette.json`, `photo.json`, `moodBoard.json`, `aesthetic-styles.json` (each well under 50 KB) | no |
| Photo JPEGs, mood-board tiles (`MoodBoard/`), wallpaper thumbnail, `settings.json` | App Group `Application Support/Aesthetic/` | no |

Photos stay on the device. They're sized for this device's widgets, so syncing them wouldn't help.

## Cache policy

The MVP has no network content, so CoreKit `ImageCache` (200 MB LRU) is not used yet. Everything the user picked lives in Application Support until they remove it. Removing a photo deletes all three of its files, and `PhotoLibrary.removeOrphans(keeping:)` clears leftovers from an interrupted import. A-04's CDN images will go through `ImageCache`.

## CoreKit / app requests

**A-06 / A-07 (2026-10-01): none required.** `WidgetKind.moodBoard` already existed, `MoodBoardWidget` is listed inside `WidgetExtension/Aesthetic/AestheticWidgets.swift` (already in `WidgetXWidgetBundle`), and the new panels live inside `AestheticSectionView`. Full app + widget build succeeds unchanged. Please only confirm during hookup:
1. `DataEraser` (Delete All Data) removes the whole `Application Support/Aesthetic/` folder, including the new `MoodBoard/`, and `Snapshots/moodBoard.json` + `Snapshots/aesthetic-styles.json` (it should if it clears the App Group folders).
2. Nothing to gate: every widget is free.

### Earlier requests (A-01, A-02)

All five are done (2026-09-28): the store and header are wired, Delete All Data clears every App Group feature folder, themes recolour every widget through CoreKit `ActiveThemeStore` + DesignSystem `WidgetThemePaint` (dark paints → primary, warm paints → accent), and `ThemeSyncPaint` / `.paintChipPunchHole(_:)` now live in DesignSystem. The original requests are kept below for reference.

The package works without these: it falls back to `NoPersistenceThemeRepository`, and the widgets still update. The following wiring mirrors Tech and Student.

1. **`App/AppEnvironment`**: add `private(set) var aestheticStore: AestheticStore?`. In `makeSectionStores()`, create it:
   ```swift
   aestheticStore = AestheticStore(
       themes: stack.map { CoreDataThemeRepository(stack: $0) } ?? NoPersistenceThemeRepository(),
       onThemeApplied: { [weak self] in await self?.loadActiveTheme() })
   ```
   `Theme` and `UserProfile` are CoreKit entities, so no persistence contributor or extra dedupe names are needed.
2. **`App/RootView`**: pass the store, and use the mockup's header:
   ```swift
   case .aesthetic:
       SectionScreen(title: "Match my wallpaper", subtitle: "Theme Sync reads the photo you pick") {
           if let store = environment.aestheticStore { AestheticSectionView(store: store) } else { ShimmerLoader().frame(height: 320) }
       }
   ```
   `WXPageHeader` should use `titleSize: 36` there, as in the ThemeSync artboard, so the title fits on one line. `SectionScreen` would need a `titleSize` parameter.
3. **Delete All Data**: `DataEraser` already removes App Group files. Confirm it covers `Application Support/Aesthetic/`, then reload the `photo` and `palette` kinds (`deleteAllData` already reloads every kind).
4. **Themed widgets (other sections)**: "Apply to N widgets" saves the active theme and reloads every kind. For Tech and Student widgets to change colour, they need the active theme in a widget-readable place. **CoreKit request:** an `ActiveThemeSnapshot` (the resolved `Theme` palette), written by `AppEnvironment.loadActiveTheme()`, which each section's widget views read, or else a DesignSystem `paintChipWidgetBackground(theme:)`. Until that exists, only the Palette widget visibly changes.
5. **DesignSystem (optional)**: a public punch-hole overlay modifier (`.paintChipPunchHole(_:)`), so the full-bleed Photo widget doesn't need its own `Circle` (it uses `PunchHole` sizes and `WXColor.paperIvory`). `GalleryPaint` could also be made public: `ThemeSyncPaint` duplicates its mockup "before" and wallpaper hex values.

## Tests

```bash
cd Packages/AestheticFeature
xcodebuild test -scheme AestheticFeature-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

37 tests. A-06/A-07 (`MoodBoardTests.swift`): grid shapes and tile frames, exact tile pixel sizes (iPhone 390 × 844 @3x medium tile = 503 × 233 px) and written JPEG sizes per layout, memory budget, limit and junk data, unshuffled/empty timelines `.never`, 7-day deterministic shuffle, store add/move/shuffle/remove/relaunch, style defaults, encode/decode round-trip, unknown values fall back to defaults, style file reloads only its kind. A-01/A-02 tests cover the following:
- Palette extraction on a beach fixture: the five mockup colours within tolerance, determinism, the Lloyd fallback, padding a two-colour image, unreadable data.
- Roles, the mockup names and "Beach Hour", the accent and text picks, contrast fix-up to AA on mid-tones, unique names, the `Theme` roles and source.
- The snapshot round-trip and size.
- Daily and hourly timelines, midnight boundaries across the US DST fall-back, stable per-period picks, and `.never` for 0 or 1 photos.
- The widget-size table, including unknown screens, and exact per-slot JPEG pixel sizes at import. Deleting a photo removes its files. The 24-photo limit and junk data.
- Store flows: pick then apply saves the theme, writes the snapshot and reloads every kind; a re-sync reuses the theme ID; the palette is restored on relaunch; bad wallpaper data shows an error; photo publish, rotation and remove.
