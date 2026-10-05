# Widgetdeck

One app for your whole home screen: beautiful *and* useful iOS widgets across four sections.

- **Tech:** battery, storage, thermal state and an in-app CPU/RAM snapshot (public APIs only)
- **Student:** class schedule from your calendar, "leave by" travel times, reminders, assignments, grades, focus timers
- **Aesthetic:** photo and mood-board widgets, Theme Sync from your wallpaper, borders and effects
- **Wellness:** habits with streaks, mood logging, daily quotes and affirmations, breathing sessions

Widgetdeck is a **free, non-commercial hobby project**: no purchases, subscriptions, ads, analytics or tracking.

## Building

- Xcode 26.3 (iOS 26.2 SDK), deployment target iOS 17.0, Swift 6
- Open `App.xcodeproj`, choose the `WidgetX` scheme (code identifiers keep the app's earlier name) and run
- All code lives in local Swift packages under `Packages/`; no third-party dependencies
- Signing, App Group, iCloud container and bundle IDs are the original developer's (`io.github.mineprodan.iospremium`). To run on your own device, change them in the project and in `Packages/CoreKit/Sources/CoreKit/Support/AppIdentifiers.swift`

## Tests

```bash
xcodebuild test -project App.xcodeproj -scheme WidgetX -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Each package also has its own tests (`xcodebuild test -scheme <Package>-Package` inside `Packages/<Package>`).

## Docs

- `PRODUCT.md`: who it's for · `DESIGN.md`: the Paint Chip visual system
- `docs/plan/`: the original plan · `docs/AppStore/`: privacy policy, privacy label and release checklist

## License

[MIT](LICENSE). Bundled fonts (Bricolage Grotesque, Archivo) are under the SIL Open Font License; see the `OFL-*.txt` files in `Packages/DesignSystem/Sources/DesignSystem/Resources/Fonts/`. Quotes are public domain.
