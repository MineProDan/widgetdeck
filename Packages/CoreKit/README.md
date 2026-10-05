# CoreKit

Shared, UI-free foundation for the app, the widget extension and every feature package.
iOS 17+, Swift 6 language mode, zero third-party dependencies.

**CoreKit is frozen once merged.** If a feature needs a change here, describe it under
"CoreKit requests" in your own package README instead of editing CoreKit.

## Layout

| Folder | What it gives you |
|---|---|
| `Support/` | `AppIdentifiers` (bundle IDs, App Group, iCloud container, keychain group, URL scheme), `AppGroupContainer` (shared directories and `UserDefaults` suite) |
| `Models/` | `AppSection`, `WidgetKind`, `WidgetFamilyKind`, `Theme` (+ `RGBAColor`, `ColorRole`), `UserProfile`, `WidgetSettings` |
| `Persistence/` | `CoreDataStack` (Cloud + Local configurations), `PersistenceModel`, `PayloadEntity`, `RecordStore<T>` |
| `Sync/` | `CloudKitAccountMonitor`, `DeduplicationService`, `DataEraser` ("Delete all data"), `DataExporter` |
| `Snapshots/` | `WidgetSnapshot`, `SnapshotStore`, `WidgetReloadCoordinator` |
| `Networking/` | `HTTPClient` (retry, backoff + jitter, `Retry-After`), `RateLimiter` (token bucket) |
| `Security/` | `KeychainStore` (shared access group, `AfterFirstUnlockThisDeviceOnly`) |
| `Permissions/` | `PermissionManager` (Calendar full access, Reminders, Photos, Notifications, Location When In Use). No HealthKit. |
| `Imaging/` | `Downsampler` (ImageIO thumbnails at exact pixel size), `ImageCache` (App Group, 200 MB LRU) |
| `Analytics/` | `Analytics` facade (no-op by default, user opt-out), `MetricKitSubscriber` |

> `WidgetSettings` is the plan's "WidgetConfiguration" model. It's renamed so it doesn't clash with
> `WidgetKit.WidgetConfiguration` in widget code.

## Which process may use what

| API | Main app | Widget extension / App Intents |
|---|---|---|
| `SnapshotStore.read` | yes | **yes (this is how widgets get data)** |
| `SnapshotStore.write` | yes | App Intents only (one small record) |
| `WidgetReloadCoordinator` | yes | no (intents call `WidgetCenter.reloadTimelines(ofKind:)` directly) |
| `CoreDataStack.load(mode: .app)` (CloudKit) | yes | **never** |
| `CoreDataStack.load(mode: .extensionLocalOnly)` | no | App Intents only |
| `HTTPClient`, `CloudKitAccountMonitor`, `DataEraser` | yes | **never** |
| `KeychainStore` | yes | read only |
| `Downsampler` / `ImageCache.store` | yes (at import time) | no. Read the file at `ImageCache.fileURL(forKey:)` |

## Patterns

### 1. Widget snapshots (the key pattern)

```swift
// In your …FeatureWidgetKit target (shared by app + widget):
public struct NextClassSnapshot: WidgetSnapshot {
    public static var kind: WidgetKind { .nextClass }
    public var classes: [ClassSlot]          // ≤ 3 items. Keep the file < 50 KB.
    public var generatedAt: Date
}

// App side, after data changes:
try await reloadCoordinator.publish(snapshot)   // injected by the app; writes + reloads only if bytes changed, debounced ≥ 60 s

// Widget side (TimelineProvider):
let snapshot = SnapshotStore().read(NextClassSnapshot.self)  // nil → render placeholder / "—" state
```

- Bump `schemaVersion` when you change a snapshot's shape incompatibly. Old files then read as `nil`.
- Override `fileName` only if one kind needs several files.
- Emit timeline entries for known future moments and use `Text(date, style: .relative)` for countdowns. Don't ask for reloads to make things "live".

### 2. Persistence: payload entities + contributors

Each feature owns its schema. Add entities without touching CoreKit:

```swift
enum StudentModel: PersistenceModelContributor {
    static func makeEntities() -> [StoreConfiguration: [NSEntityDescription]] {
        [.cloud: [PayloadEntity.make(name: "CourseRecord"),
                  PayloadEntity.make(name: "GradeEntryRecord", encryptPayload: true)],   // 🔒 Allows Cloud Encryption
         .local: [PayloadEntity.make(name: "CourseEventLinkRecord")]]
    }
}
extension Course: PersistableRecord { static var entityName: String { "CourseRecord" } }

let courses = try await RecordStore<Course>(stack: stack).fetchAll()
```

Contributors are passed to `CoreDataStack.load(mode:contributors:)` by the app target (a CoreKit
request to wire yours in is a one-line change in `App/AppEnvironment.swift`).
`PersistenceModel.make` **validates CloudKit rules** for `.cloud` entities: optional/defaulted
attributes, no unique constraints, relationships optional with inverses and unordered.
`RecordStore` reads return the newest copy per `id`. Register your synced entity names with
`DeduplicationService(stack:entityNames:)` so CloudKit duplicates are cleaned up.

Stores live in `AppGroup/Library/Application Support/Stores/{Cloud,Local}.sqlite` with persistent history on.

### 3. Networking

```swift
let limiter = RateLimiter(capacity: 10, refillRate: 1)            // per token / per host
let client = HTTPClient(retryPolicy: .default, rateLimiter: limiter)
let manifest = try await client.send(URLRequest(url: manifestURL), decoding: Manifest.self)
```

GET/HEAD/PUT/DELETE retry on 408/429/5xx and transient network errors (3 attempts, exponential
backoff with jitter). POST retries only on 429/503. `Retry-After` (seconds or HTTP date) is
honored up to 120 s, and anything longer throws `HTTPError.rateLimited`. Offline fails fast.
`HTTPError.errorDescription` is user-friendly.

### 4. Keychain

```swift
let keychain = KeychainStore(service: "pinterest")      // shared access group from Info.plist
try keychain.setCodable(tokens, for: "oauth")
let tokens = try keychain.codable(OAuthTokens.self, for: "oauth")
try keychain.deleteAll()                                  // on disconnect
```

Tests and previews: `KeychainStore(accessGroup: nil, backend: InMemoryKeychainBackend())`.
Hostless package tests have no keychain entitlement (-34018).

### 6. Permissions

Always show DesignSystem's `PermissionPrimer` first, then `await permissions.request(.calendar)`.
`PermissionStatus.needsSettings` → offer `PermissionManager.settingsURL`. Required Info.plist keys
are already in `App/Info.plist`. Prefer `PhotosPicker` (no permission) over `.photos`.

### 7. Images for widgets

```swift
let size = PixelSize(points: CGSize(width: 170, height: 170), scale: 3)
let image = try Downsampler.downsample(data: pickedData, toFill: size)       // exact pixels, EXIF-rotated
let key = ImageCache.key(assetID: id, family: .systemSmall, pixelSize: size)
try await ImageCache().store(Downsampler.encode(image, format: .heic), forKey: key)
// widget: Image(uiImage: UIImage(contentsOfFile: ImageCache().fileURL(forKey: key).path())!)
```

Never decode a full-size image in the widget: the extension has a ~30 MB memory ceiling.

### 8. Analytics

`Analytics.shared.track(AnalyticsEvent("habit_completed", parameters: ["streak_bucket": "7+"]))`.
No user content, no identifiers. The default sink is a no-op, and there is no ATT.

## Tests

```bash
cd Packages/CoreKit
xcodebuild test -scheme CoreKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Covers: snapshot round-trip, atomicity, size cap, schema versioning; reload-coordinator debounce,
coalescing and hash-based skipping; HTTP retry/backoff/`Retry-After` (URLProtocol mock); rate
limiter; Keychain CRUD (in-memory backend); account monitor;
persistence rules, CRUD, dedupe, export, delete-all; downsampler dimensions/EXIF; image-cache LRU.

Real-Keychain tests need an app host, so they live in
`/AppTests` (target `WidgetXTests`, scheme `WidgetX`).
