# PrivacyInfo.xcprivacy audit

Audited 2026-09-28 against the code on `main` (grep of every required-reason API in `App/`, `WidgetExtension/` and `Packages/*/Sources`). No third-party SDKs are linked, so these two manifests are the whole story.

## App (`App/PrivacyInfo.xcprivacy`)

| Category | Reason | Where it's used | Verdict |
|---|---|---|---|
| UserDefaults | `CA92.1` (app-only) | Onboarding completion, Tech flag reads, CloudKit account cache | OK |
| UserDefaults | `1C8F.1` (App Group) | `AppGroupContainer.userDefaults`: remote flags, shared with the widget | OK |
| DiskSpace | `85F4.1` (shown to user) | `TechFeature/Samplers.swift`, `volumeAvailableCapacityForImportantUsage` for the Storage card and widget | OK |
| DiskSpace | `E174.1` (check before writing) | `CoreKit/ImageCache.purgeIfLowStorage` | OK |
| FileTimestamp | `C617.1` (own container) | `ImageCache` LRU eviction via `contentModificationDate` | OK |
| SystemBootTime | `35F9.1` (elapsed time) | `RateLimiter` uses `ContinuousClock` for token refill. Not shown to the user | Kept. Probably not strictly required (`ContinuousClock` isn't on Apple's list), but the reason is accurate and costs nothing |

- **Uptime:** not shown anywhere. Tech has no uptime tile, per Platform Reality Rule 10.
- **Tracking:** `NSPrivacyTracking = false` and there are no tracking domains. There is no ATT prompt and no IDFA.
- **Collected data types:** none (see `app-privacy-label.md`).
- **Mach `host_processor_info` / `host_statistics64`** (CPU and memory, T-03) aren't required-reason APIs. They're covered in the review notes instead.

## Widget extension (`WidgetExtension/PrivacyInfo.xcprivacy`)

| Category | Reason | Where | Verdict |
|---|---|---|---|
| UserDefaults | `1C8F.1` | Reads remote flags from the App Group | OK |
| FileTimestamp | `C617.1` | Snapshot and image files inside the App Group | OK. Declared defensively, since CoreKit is linked |

- **DiskSpace** isn't declared, and that's correct: the Storage widget only reads the app-written `StorageSnapshot`. It never queries the volume.

## Gaps found and fixed

None in the manifests. Two related fixes landed in this pass:
- `PersistenceError.storeLoadFailed` used to show a raw system error string to the user in Settings. It now shows a plain sentence, and the detail goes to the log only.
- The onboarding footer copied "Premium unlocks 30+ [themes]" from the mockup. The app ships 6 launch themes plus Theme Sync, so the claim couldn't be backed up. It now points to Theme Sync instead.

## For the owner to check before submission

- **Decided 2026-09-29: keep them.** `Info.plist` contains `NSLocationWhenInUseUsageDescription` and `NSRemindersFullAccessUsageDescription` for S-07 travel alerts and S-05 Reminders import. Both are now in 1.0 (2026-09-30), so the app will request them when the user turns those features on. Re-audit this file once they're built.
- In Xcode, run **Product → Archive → Generate Privacy Report** on the release archive and confirm it lists only the entries above.
