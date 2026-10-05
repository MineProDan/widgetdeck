# WellnessFeature

The Wellness section (W-01 to W-05): daily quotes and affirmations, habits with streaks, the mood check-in, breathing sessions with a Live Activity, and goals. Everything is free. Nothing is locked or labelled Premium, including the Streak widget.

## Products

| Product | Linked by | Contains |
|---|---|---|
| `WellnessFeatureWidgetKit` | app + widget extension | `DayKey`, `WellnessDayClock`, `StableID`, `Mood`, `Quote`/`Affirmation`/`DailyPicker` (with the bundled JSON), snapshots (`HabitsSnapshot`, `MoodSnapshot`, `WellnessFlowSnapshot`), `WellnessWidgetInbox` + `WellnessWidgetActions`, the timeline providers, the widget views, the breathing models, `BreathingActivityAttributes` and the Live Activity views, and `WellnessDeepLink` |
| `WellnessFeature` | app | `WellnessSectionView`, `WellnessStore`, `StreakCalculator`, `MoodTrends`, `GoalMath`, `CompletionMerge`, the repositories (`CoreDataWellnessRepository`, `FileWellnessRepository`), `WellnessModel` (Core Data contributor), `MoodReminderScheduler`, `BreathingSession`, `WellnessBackgroundRefresh` and `WellnessRequest` |

The App Intents are in `WidgetExtension/Intents/WellnessIntents.swift`: `ToggleHabitIntent`, `LogMoodIntent`, and the `QuoteWidgetConfigurationIntent` with its `QuoteCategoryOption`. The widget views are generic over the intent type, so the package never needs the extension's intent types.

## Data structures

| Record | Store | Notes |
|---|---|---|
| `Habit` | Cloud (`WellnessHabitRecord`) | name, `HabitSchedule` (`.daily`, `.weekdays(Set<Int>)`, `.timesPerWeek(n)`), sort order, archived flag |
| `HabitCompletion` | Cloud (`WellnessHabitCompletionRecord`) | habit + `DayKey` + time zone + `isDone`. Its **id is derived from (habit, day)** (`StableID`), so a tick is idempotent: two devices produce the same id and `DeduplicationService` collapses them. Unticking writes `isDone = false` instead of deleting, so the newest write wins. `CompletionMerge.resolve` also enforces one record per (habit, day) in memory |
| `MoodLog` | Cloud (`WellnessMoodRecord`, **payload cloud-encrypted**) | one per day (id derived from the day), mood 0…4 (awful…great, shown as Rough · Low · Okay · Good · Great), optional note (max 500 characters). Notes never reach widgets |
| `Goal` | Cloud (`WellnessGoalRecord`) | title, target, unit, and the progress entries in the same payload |
| `WellnessSettings` | App Group `Wellness/settings.json` (per device) | day-start hour (0–12), mood reminder on/off and hour (default 8 PM), quote category, the last breathing pattern/length, chime on/off |

**Days:** everything is stored per `DayKey` ("2026-09-29"), never as an instant. `WellnessDayClock` maps a date to a day using the local wall clock and the "day starts at" hour, so 2:30 AM with a 4 AM start still counts as the day before. Day arithmetic runs on a fixed GMT calendar, so DST days (23 h or 25 h) and time-zone travel can't split or merge days.

**Streaks** (`StreakCalculator`): for daily and weekday habits, a streak is the run of consecutive *due* days that are done. Days off neither count nor break it, and an open today doesn't break it yet ("open today"). For x-per-week habits, the streak counts weeks that met the target, and the current week counts once it's met. The calculator returns both `ifDone` and `ifOpen`, so a tick can flip the number without recomputing. Milestones are 7, 30 and 100.

## Widgets

| Widget | Families | Notes |
|---|---|---|
| Habits (`.habits`) | small (3 keys), medium (5 keys) | Interactive: each CheckKey is `Button(intent: ToggleHabitIntent)` with `.invalidatableContent()`. The timeline has entries for now and for the next day boundary (projected: everything unticked, streaks rolled), so it resets at the user's day-start hour without the app |
| Mood (`.mood`) | small, accessoryCircular | Five rising Plum Dusk capsules, each `Button(intent: LogMoodIntent)`. The caption reads "Plum Dusk · Mood" only while no theme recolours the field |
| Streak (`.streak`) | accessoryCircular ("23" under the leaf), accessoryInline ("Read 20 min · 23-day streak") | Reads the Habits snapshot |
| Daily Quote (`.quote`) | small, medium, accessoryRectangular | `AppIntentConfiguration` with a category (All, Calm, Focus, Courage, Growth, Kindness, Nature). No snapshot is needed: the pick is deterministic from the bundled JSON, and three days of entries are built ahead |
| Affirmation (`.affirmation`) | small, accessoryInline | Same deterministic daily pick |
| Breathe (`.breathe`) | small | Static. Tap opens `widgetx://section/wellness?breathe=box` |
| Breathing Live Activity | Lock Screen + Dynamic Island (compact, minimal, expanded) | See below |

All Home Screen widgets use `PaintChipWidget`, so they follow the active theme. Gallery and placeholder entries use fixed sample content (`WellnessSamples`), and nothing in them is compared with the real clock.

**Interactive widgets and Platform Rule 6:** `WellnessWidgetActions` runs in the extension. It updates the App Group snapshot in place, so the widget redraws at once. It appends one small record to `Wellness/widget-inbox.json`, using `NSFileCoordinator` because the app and the extension are separate processes, and it refreshes `wellness-flow.json`. It never touches CloudKit. The app drains the inbox in `WellnessStore.load()`. A widget tap only wins over an in-app change if the tap is newer.

## Quotes and affirmations (W-01)

- `Sources/WellnessFeatureWidgetKit/Resources/quotes.json` has **111 public-domain quotes**, each with `author`, `source` (the work, and the public-domain translation where one applies: George Long's Marcus Aurelius, Gummere's Seneca, Carter's Epictetus, Legge's Lao Tzu and Confucius, and Müller's Dhammapada), `category` and `license`. Only authors and works long out of copyright are included. Quotes with doubtful attribution (the usual misattributed Emerson, Twain and Lincoln lines) and modern translations (for example Hays's Marcus Aurelius) are deliberately left out.
- `affirmations.json` has **54 affirmations written in-house**, all in plain wellness language with no medical or therapy claims.
- `DailyPicker` walks a shuffled order (SplitMix64 seeded by the category and the cycle number), so nothing repeats until the filtered list is used up, and every device shows the same item on the same day.

## Mood reminder (W-03)

The reminder is optional and off by default. Notification permission is requested only when the user turns it on. It schedules a rolling week of one-off notifications at the chosen hour and skips days that are already logged, so it uses at most 7 of the 64 pending-notification slots (Student uses up to 48). The identifiers start with `wellness.mood.`, and `userInfo["url"]` is the mood deep link.

## Breathing (W-04)

- Patterns: box (4-4-4-4) and 4-7-8. Lengths: 3, 5 or 10 minutes, rounded to whole cycles. `BreathingPlan` precomputes every phase with absolute dates.
- In the app, a `TimelineView` animates the dot around the square once per cycle. With Reduce Motion on, the square stays still and only the words change. Haptics mark each phase. The soft chime is off by default, is generated in memory (no bundled audio), uses the `.ambient` session, and is created only after the user taps Start. Nothing autoplays.
- Live Activity: the countdown is `Text(timerInterval:)`, and the Lock Screen progress bar is `ProgressView(timerInterval:)`, so both tick without updates. The app updates the phase label ("Hold · 4") at each boundary while it runs. Every update carries `staleDate = phaseEnd`, and a stale activity shows "Keep breathing" instead of a wrong phase (Platform Rule 1). The activity ends when the session ends or the user taps End.
- No HealthKit. Mindful minutes are Phase 3.

## Goals (W-05)

A goal has a target, a unit and progress entries. The percentage is total ÷ target. The ETA is linear from the average daily rate over the last 14 days (or since the first entry, if that's more recent), and it's hidden when the goal is done or the recent rate is zero.

## CoreKit / app requests

**Done 2026-09-30** (Wellness ships in 1.0): 1–6 are wired in `App/AppEnvironment.swift` and `App/RootView.swift` (Core Data store + dedupe, subtitle, deep links, background refresh, notification taps). 7 needed nothing. 8: Delete All Data already clears every App Group folder and now cancels all pending notifications. 9 (Flow widget) is still open for when the Flow widget is built. The original requests are kept below.

The package works without any of these: `WellnessSectionView()` falls back to App Group JSON storage, and that's how the tab runs today. For sync and deep links:

1. **Persistence** (`App/AppEnvironment.swift`): add `WellnessModel.self` to `persistenceContributors()`, and add `WellnessModel.syncedEntityNames` to `dedupeEntityNames`.
2. **Store:** in `makeSectionStores()`, create `wellnessStore = WellnessStore(repository: stack.map { CoreDataWellnessRepository(stack: $0) } ?? FileWellnessRepository())`. Existing local data in `Wellness/wellness.json` isn't migrated automatically. Before a device that already has local data switches to Core Data, copy it across once, or accept losing that data, since the app hasn't shipped yet.
3. **RootView:** pass the store and a request binding: `SectionScreen(title: "Wellness", subtitle: wellnessStore.subtitle) { WellnessSectionView(store: wellnessStore, request: $environment.wellnessRequest) }`. The subtitle ("2 of 3 habits done today", from Wellness.png) comes from `WellnessStore.subtitle`. The shell currently passes `nil`, so the header has no subtitle.
4. **Deep links:** in `AppEnvironment.handle(url:)`, set `wellnessRequest = WellnessRequest(url: url)` when the section is `.wellness`. This opens a breathing session (`?breathe=box`), highlights a habit (`?habit=<uuid>`) or goes to the mood keys (`?mood=log`).
5. **Background refresh:** call `await WellnessBackgroundRefresh.run(repository: …)` from `performBackgroundRefresh()`. This folds in widget taps, rolls the day over and republishes snapshots.
6. **Notification tap:** the notification delegate should open `userInfo["url"]` (Student asked for the same).
7. **Widget registration:** nothing is needed. `WidgetXWidgetBundle` already includes `WellnessWidgets().body`, and `WidgetExtension/Intents/` is picked up by the synchronized folder group.
8. **Data eraser/export:** `DataEraser` should also delete the App Group `Wellness/` folder (settings, the JSON store and the widget inbox), and remove pending `wellness.mood.*` notifications.
9. **CoreKit (Flow widget):** `WellnessFlowSnapshot` (`wellness-flow.json`: habits due/done, open habit names, mood logged today) lives in this package, because features can't import each other. When the shell's Flow widget is built, move this type, or a copy with the same JSON shape, into CoreKit.
10. **Privacy manifest:** there are no new required-reason APIs. UserDefaults isn't used. Settings are a JSON file.
11. **Info.plist:** `NSSupportsLiveActivities` is already in the app. No new usage strings are needed (no HealthKit or microphone).

## Tests

```bash
cd Packages/WellnessFeature
xcodebuild test -scheme WellnessFeature-Package -destination 'id=BF0223FC-42F7-42FC-8F07-BA39705A891A'
```

There are 28 tests (33 cases). They cover:

- day keys, the midnight and custom day-start boundaries, 23 h and 25 h DST days, a day-start hour inside the spring-forward gap, and time-zone travel keeping a streak
- daily, weekday and x-per-week streaks, and milestones
- the widget's day-rollover projection checked against the calculator across five weeks, for four schedules
- deduplication of completions and moods, and widget taps merging into the store idempotently (older taps never override newer changes)
- the content counts and fields, deterministic rotation, no repeats within a cycle, and category filters
- mood trends, goal percentage and ETA, breathing plans (whole cycles, phase lookup), and mood reminder planning
- the snapshot size cap, deep links, and the CloudKit model rules
