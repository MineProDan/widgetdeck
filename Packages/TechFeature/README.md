# TechFeature

The Tech section (T-01..T-06): an honest system dashboard built only from public APIs, plus three
widgets. iOS 17+, Swift 6, no third-party code.

| Product | Linked by | Contains |
|---|---|---|
| `TechFeature` | app | `SystemMonitorService`, samplers, `ChargeRateEstimator`, Core Data sample store, `TechSnapshotBuilder`, the Tech screen views, `ChipCatalog.json` |
| `TechFeatureWidgetKit` | app + widget extension | Snapshot types, `TechFormat`/`BatteryCopy`, timeline entries/builders/providers, widget views |

Widgets are declared in `WidgetExtension/Tech/TechWidgets.swift`.

## Where every number comes from

| On screen | Source | Notes |
|---|---|---|
| Battery % and charging state | `UIDevice.batteryLevel` / `batteryState`, updated by `batteryLevelDidChange` / `batteryStateDidChange` notifications (no timer) | The Simulator reports no battery, so it shows "—" / "Not reported". |
| "est. 1h 10m" to full | **Our estimate.** Least-squares slope of the levels seen while charging (last 30 min, needs ≥ 3 min and ≥ 1 % rise); the part above 80 % is projected at half speed because iPhones slow down there | Always labelled "est." Until there's enough data it says "Charging · estimating". |
| Storage free / total | `URLResourceValues.volumeAvailableCapacityForImportantUsage` and `volumeTotalCapacity` | Whole device only. iOS doesn't say how much is apps, photos or system, so we don't. Decimal GB, like Settings. Required-reason API DiskSpace (85F4.1), already in the app manifest. |
| "−2.1 GB wk" | Current free space minus the oldest saved sample that's 6–7 days old | Only appears once a week of samples exists. |
| CPU load | Mach `host_processor_info(PROCESSOR_CPU_LOAD_INFO)`: busy ticks ÷ all ticks between two 5 s readings, all cores | **In-app, foreground, Tech screen visible only.** Behind flag T-03. |
| Memory used | Mach `host_statistics64(HOST_VM_INFO64)`: active + wired + compressed pages × page size; total = `ProcessInfo.physicalMemory` | Same limits as CPU. Binary GB. |
| Thermal state | `ProcessInfo.thermalState` | Nominal / Fair / Serious / Critical. |
| Device name + chip | `utsname.machine` (Simulator: `SIMULATOR_MODEL_IDENTIFIER`) looked up in the bundled `ChipCatalog.json` (iPhone XS → iPhone 17 family) | Unknown future models show "iPhone" and no chip rather than a guess. Update the JSON each September. |
| iOS version, cores | `UIDevice.systemVersion`, `ProcessInfo.processorCount` | |

**Not built, because iOS has no public API for them:** GPU usage, battery health %, other apps'
activity, per-category storage, passive network throughput. The screen copy doesn't mention them
(Platform Reality Rule 2). **Uptime is omitted:** the app's SystemBootTime reason (35F9.1) covers
measuring elapsed time, not showing uptime to the user.

## Sampling rules

- `SystemMonitorService` (`@MainActor @Observable`) samples every 5 s **only while the Tech screen
  is on screen and `scenePhase == .active`**. `TechSectionView` drives `setActive(_:)` from
  `onAppear`/`onDisappear`/`scenePhase`. Leaving the screen cancels the loop and switches battery
  monitoring off. No background work at all.
- Flag `T-03` (`TechFeatureFlags.cpuMemoryKey = "flag.T-03.cpuMemory"` in the App Group defaults,
  default on). Off → no Mach calls, CPU/Memory cards hidden, widgets show "—" for them.
- One `MetricSample` per minute is saved to CoreKit's **Local** store (entity
  `TechMetricSampleRecord`, never synced) and anything older than 7 days is pruned on each save and
  on start.

## Widgets (T-06)

| Widget | Families | Data |
|---|---|---|
| Battery | systemSmall (Paint Chip, mockup HomeScreen.png), accessoryCircular (capacity gauge), accessoryInline | Direct `UIDevice` read if the extension gets one, else `BatterySnapshot` |
| System Overview | systemMedium, systemLarge | `SystemOverviewSnapshot`: battery, storage, thermal, CPU/RAM **"As of" the last in-app sample** |
| Storage | systemSmall, accessoryRectangular | `StorageSnapshot` |

- Snapshots are written through `WidgetReloadCoordinator` (atomic, ≥ 60 s debounce, reload only
  changed kinds), and only when something a widget shows changes (1 % battery, 0.1 GB, thermal,
  charging state), plus once when sampling stops. This protects the ~40–70 reloads/day budget.
- While charging, the Battery timeline precomputes entries every 5 min that count the "est." time
  down; the level shown is always the last one actually read, never projected.
- No configuration options are needed, so all three use `StaticConfiguration`.
- Rendering modes: `PaintChipWidget` handles fullColor / accented / vibrant; accessories use system
  styling with `widgetAccentable()`.
- Every widget deep-links to the Tech tab. No data → "—" plus "Open Widgetdeck to update", never blank.

## Spike: can the widget extension read the battery level directly?

Implemented as *try, then fall back*. `BatteryTimelineProvider` enables
`UIDevice.isBatteryMonitoringEnabled` on the main actor in the extension and reads `batteryLevel`.
If it returns `-1` (Simulator, or iOS not providing it to the extension), the timeline uses the
app-written `BatterySnapshot` and labels the value "As of 3:40 PM".

- Simulator: `UIDevice` returns `-1` (verified in the app process), so the fallback path runs there.
- Physical iPhone: **not verified in this step** (no device attached to this session). Third-party
  battery widgets on the App Store indicate the extension does get a real level. Verify on device:
  add the Battery widget, unplug, wait for a reload, and check the trend line says "On battery"
  (live) rather than "As of …" (snapshot). Either way the widget is correct; the direct read only
  makes it fresher.

## Views

`TechSectionView` (root; `init(stack:)` or `init(monitor:)`), `MetricCard`, `CPUGaugeView`,
`StorageView`, `ThermalIndicator`, `DeviceChipView`, built only from DesignSystem Paint Chip
components (`PaintChip`, `ChipLabelBand`, `FillBar`, `ThermalStrip`, `ChipGlyph`, `WXColor`,
`WXSection.tech`). `CPUGaugeView` is a flat animated fill bar, as in the mockup and DESIGN.md
(no rings outside Lock Screen gauges); the fill animation is off with Reduce Motion.

**Deviation from the mockup:** the footnote. The mockup says iOS doesn't share GPU use, battery
health or other apps' activity. Platform Reality Rule 2 forbids mentioning those in UI copy, so it
reads "Estimates are labelled. CPU and memory are measured only while this screen is open."

## Tests

```bash
cd Packages/TechFeature
xcodebuild test -scheme TechFeature-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

29 tests: `ChargeRateEstimator` (evidence thresholds, slope, taper, session reset, window),
formatting (%, bytes, durations, "est." wording, card trends), chip lookup + unknown models,
snapshot builder + App Group round-trip + signature, timelines (charging countdown, live
re-projection, empty state), Core Data 7-day prune, and `SystemMonitorService` (sampling pauses
when backgrounded and resumes, flag off skips Mach reads, charging estimate, publish-on-change).
Tests live in the package's own test target (`Packages/TechFeature/Tests/TechFeatureTests`).

## CoreKit requests

1. **Wire the Tech store:** done. Originally: pass `TechPersistenceModel.self` to
   `CoreDataStack.load(mode:contributors:)` in `App/AppEnvironment.swift`, and have `RootView` build
   `TechSectionView(stack: environment.stack)`. Until then samples are kept in memory, so the
   weekly storage trend never appears.
2. **Remote flags:** done (`CoreKit.RemoteFlags`, run at launch; CDN URL still to set). Originally: a loader that fetches the CDN flags JSON and writes `flag.T-03.cpuMemory` (Bool)
   to the App Group defaults. The Tech section reads it at every sampling start.
3. **URL scheme:** done, now `widgetx`.
4. **DataEraser:** "Delete all data" removes Core Data objects and App Group files, which covers the
   Tech samples and snapshots; no change needed if the contributor is wired (request 1).
