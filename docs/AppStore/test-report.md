# Test and performance report (2026-09-28, tests re-run 2026-10-06)

These results come from the iPhone 17 Pro simulator (iOS 26.2 SDK, Xcode 26.3) running on an Intel MacBook Pro 2019.

> **2026-10-12:** the dev Mac is now an M5 MacBook Air with Xcode 27.0 (iOS 27.0 SDK, iOS 27.0 iPhone 17 Pro simulator). **2026-10-13:** all 315 tests pass there. **2026-10-19:** Xcode 27.1 / iOS 27.1 SDK: all 318 pass (after the Student sync-window fix). **2026-10-24:** 320 pass after the Lock Screen, small deck/Wellness and security fixes (iPhone 17 Pro simulator, iOS 27.0) with 0 warnings in our code. The performance numbers below are still the Intel-era simulator numbers until they are re-measured.

**NEEDS DEVICE** marks numbers that can only be measured on a physical iPhone. None of those numbers were estimated.

## Tests

| Target | Command (run from) | Result |
|---|---|---|
| CoreKit | `xcodebuild test -scheme CoreKit` (Packages/CoreKit) | 63 passed (2026-10-24; StoreKit tests removed 2026-10-04) |
| DesignSystem | `-scheme DesignSystem` | 40 passed (2026-10-24, incl. DeckTests) |
| TechFeature | `-scheme TechFeature-Package` | 29 passed (2026-10-24) |
| StudentFeature | `-scheme StudentFeature-Package` | 86 passed (2026-10-24, incl. weekly-pattern, Monday sync-window and leave-alert address tests) |
| AestheticFeature | `-scheme AestheticFeature-Package` | 37 passed (2026-10-24) |
| WellnessFeature | `-scheme WellnessFeature-Package` | 31 passed (2026-10-24, incl. habit-caption tests) |
| App (`WidgetXTests`, hosted) | `xcodebuild test -project App.xcodeproj -scheme WidgetX` (repo root) | 34 passed (2026-10-24, integration suites incl. Keychain) |

The destination for all of them is `-destination 'id=<simulator>'`.

**Integration tests** live in `AppTests/Integration/`, not `Tests/IntegrationTests`. That's because the existing `WidgetXTests` target is hosted in the app and uses a synchronized folder, so new files there are picked up with no project edits.
- `OnboardingIntegrationTests`: section rules, widget detection (ours only / none / failure), completion persisted, and every launch theme feeding `ActiveThemeSnapshot` with contrast ≥ 4.5.
- `PipelineIntegrationTests`: all sections open on one Core Data stack; a theme applied in Aesthetic is visible through the CoreKit profile; Tech data change → snapshot → reload of only the changed kinds; Student and Aesthetic snapshot round trips; active theme → widgets; remote flags keep defaults when the CDN fails; `flags.json` keys match the compiled keys; store errors show friendly text.
- **Permission grant/deny/revoke**: StudentFeature's own tests cover the demo-week fallback. System permission prompts can't be driven from unit tests. They're checked by hand on a device (see `release-checklist.md` §2).

**Widget matrix** (`WidgetRenderMatrixTests`): 7 widgets × their families (16 widget/family pairs) × light/dark × Dynamic Type XS/L/AX3 = **96 renders**. Each one must render, be non-blank, and stay under 8 MB as an @3x bitmap.
- This is a *structural* test, not a pixel-snapshot test. `\.widgetFamily` and `\.widgetRenderingMode` are read-only, so `ImageRenderer` always takes the `.systemSmall` / `.fullColor` branch at each family's frame size.
- Family-specific layouts and the accented/vibrant (tinted/clear) modes need a manual check in the home-screen widget gallery or on a device.
- swift-snapshot-testing wasn't added. The project has no test-only SPM dependency, and reference images are tied to one Mac and Xcode version, so they break on Xcode Cloud or after a toolchain update.

**Warnings:** our code has 0 warnings.

## Performance

| Metric | Target | Result |
|---|---|---|
| Timeline generation: Today's Schedule (40 classes, read snapshot from disk + build entries) | < 50 ms | **3.6 ms** median (simulator) |
| Timeline generation: Photo (24 photos, hourly) | < 50 ms | **3.7 ms** median (simulator) |
| Snapshot size: Next Class (40 classes) | < 50 KB | **3,884 B** |
| Snapshot size: Photo (24 photos × 3 sizes) | < 50 KB | **5,631 B** |
| Snapshot size: Palette / System Overview | < 50 KB | **385 B / 316 B** |
| Downsample 4032×3024 JPEG → large widget @3x | exact pixel size | **1080×1137**, 88.6 ms, 6.9 MB decoded, 32.6 KB JPEG |
| Largest widget view bitmap (@3x, large family) | well under the ~30 MB ceiling | ≈ 5.0 MB |
| Active app memory | < 100 MB | **22.8 MB** on the Tech tab, 36.0 MB peak after a deck change (iPhone 14 Pro, iOS 26.5, Instruments Activity Monitor, 2026-10-24) |
| Widget extension memory | < 20 MB | **7.3–10.5 MB** with 4 widgets (Paint Chip and Saturday Cartoons' bundled font; iPhone 14 Pro, 2026-10-24) |
| Battery drain, active use | < 2%/hr | Marked OK by the owner (2026-10-24); no measured figure recorded |
| Timeline generation on device | < 50 ms | **NEEDS DEVICE** (simulator numbers above suggest a large margin) |
