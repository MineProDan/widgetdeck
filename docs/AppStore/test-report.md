# Test and performance report (2026-09-28)

These results come from the iPhone 17 Pro simulator (iOS 26.2 SDK, Xcode 26.3) running on an Intel MacBook Pro 2019. **NEEDS DEVICE** marks numbers that can only be measured on a physical iPhone. None of those numbers were estimated.

## Tests

| Target | Command (run from) | Result |
|---|---|---|
| CoreKit | `xcodebuild test -scheme CoreKit` (Packages/CoreKit) | 69 passed |
| DesignSystem | `-scheme DesignSystem` | 28 passed |
| TechFeature | `-scheme TechFeature-Package` | 29 passed |
| StudentFeature | `-scheme StudentFeature-Package` | 26 passed |
| AestheticFeature | `-scheme AestheticFeature-Package` | 23 passed |
| App (`WidgetXTests`, hosted) | `xcodebuild test -project App.xcodeproj -scheme WidgetX` (repo root) | 23 passed (integration suites incl. Keychain); 32 after the StoreKit tests were removed 2026-10-04 |

The destination for all of them is `-destination 'id=<simulator>'`.

**Integration tests** live in `AppTests/Integration/`, not `Tests/IntegrationTests`. That's because the existing `WidgetXTests` target is hosted in the app and uses a synchronized folder, so new files there are picked up with no project edits.
- `OnboardingIntegrationTests`: section rules, widget detection (ours only / none / failure), completion persisted, and every launch theme feeding `ActiveThemeSnapshot` with contrast ≥ 4.5.
- `PipelineIntegrationTests`: all sections open on one Core Data stack; a theme applied in Aesthetic is visible through the CoreKit profile; Tech data change → snapshot → reload of only the changed kinds; Student and Aesthetic snapshot round trips; active theme → widgets; remote flags keep defaults when the CDN fails; `flags.json` keys match the compiled keys; store errors show friendly text.
- **Permission grant/deny/revoke**: StudentFeature's own tests cover the demo-week fallback. System permission prompts can't be driven from unit tests. They're checked by hand on a device (see `release-checklist.md` §2).

**Widget matrix** (`WidgetRenderMatrixTests`): 7 widgets × their families (16 widget/family pairs) × light/dark × Dynamic Type XS/L/AX3 = **96 renders**. Each one must render, be non-blank, and stay under 8 MB as an @3x bitmap.
- This is a *structural* test, not a pixel-snapshot test. `\.widgetFamily` and `\.widgetRenderingMode` are read-only, so `ImageRenderer` always takes the `.systemSmall` / `.fullColor` branch at each family's frame size.
- Family-specific layouts and the accented/vibrant (tinted/clear) modes need a manual check in the home-screen widget gallery or on a device.
- swift-snapshot-testing wasn't added. The project has no test-only SPM dependency, and reference images recorded on an Intel simulator wouldn't match an Apple-silicon Mac or Xcode Cloud.

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
| Active app memory | < 100 MB | **NEEDS DEVICE** (Xcode memory gauge / Instruments Allocations) |
| Widget extension memory | < 20 MB | **NEEDS DEVICE** (Instruments, attach to `WidgetXWidgets`) |
| Battery drain, active use | < 2%/hr | **NEEDS DEVICE** (Xcode Energy Log + MetricKit, 1 h on the Tech tab) |
| Timeline generation on device | < 50 ms | **NEEDS DEVICE** (simulator numbers above suggest a large margin) |
