# StudentFeature

The Student section for 1.0: S-01 to S-04 (calendar connection, class and deadline detection, the Next Class and Today's Schedule widgets, class reminders) and the 1.0 additions S-05 to S-08 (assignments + read-only Reminders import + the Assignments Due widget, grades/GPA and the final-exam predictor, "leave by" travel alerts, and the focus timer with a Live Activity). The tab has four segments, as in Student.png: Schedule, Due, Grades, Focus.

## Products

| Product | Linked by | Contains |
|---|---|---|
| `StudentFeatureWidgetKit` | app + widget extension | `ClassSlot`, `CoursePaint`, `NextClassSnapshot`, `TodayScheduleSnapshot`, `ScheduleTimeline`, `StudentScheduleProvider`, `NextClassWidgetView`, `TodayScheduleWidgetView`, `StudentDeepLink`; S-05: `DueSlot`, `AssignmentsSnapshot`, `AssignmentsProvider`, `AssignmentsWidgetView`; S-08: `FocusPreset`, `FocusPlan`, `FocusActivityAttributes`, `FocusLockScreenView`, `FocusIsland`, `FocusDeepLink` |
| `StudentFeature` | app | `StudentSectionView`, `StudentStore`, `EventClassifier`, `ScheduleBuilder`, `ReminderPlanner`/`ReminderScheduler`, `EventKitCalendarProvider`, repositories, `StudentBackgroundRefresh`; S-05: `Assignment`, `AssignmentPlanner`, `ReminderImporter`, `EventKitRemindersProvider`; S-06: `GradeCategory`, `GradeEntry`, `GradeScale`, `GradeMath`; S-07: `LeaveByPlanner`, `MapKitTravelTimeEstimator`; S-08: `FocusTimer`, `FocusNotifications` |

## Permission setup (S-01)

- Calendar: `PermissionPrimer` first, then CoreKit `PermissionManager.request(.calendar)`, which calls `requestFullAccessToEvents()` on iOS 17. After access is granted, the user picks their "school" calendars, and only those calendars are read.
- If access is denied, or the user taps "Not now", the section shows the mockup's sample week with a "Sample week / Connect" card. If access was denied, that card links to Settings. Sample data never reaches widgets or notifications.
- Notifications are requested only when the user turns on class reminders, due reminders or leave-by alerts, or starts a focus timer.
- Reminders (S-05): the same `PermissionPrimer` as the calendar ("Bring in your assignments") first, then `PermissionManager.request(.reminders)` (`requestFullAccessToReminders()`), then the user picks one list.
- Location (S-07): `PermissionManager.request(.locationWhenInUse)` only when the user turns leave-by alerts on. Refused = the feature stays off with a message.
- **Info.plist keys (app target, all already present):** `NSCalendarsFullAccessUsageDescription`, `NSRemindersFullAccessUsageDescription`, `NSLocationWhenInUseUsageDescription`, `NSSupportsLiveActivities = YES`. Local notifications don't need a key. The widget extension needs no keys.
- The section is read-only towards Apple data: no EventKit save or remove call exists anywhere, so it never writes to the user's calendar or reminders. No Health permission, no background or continuous location.

## Sync and classification (S-02)

- Window: from the start of yesterday to 15 days from today (`SyncWindow`). Sync runs when the view appears, when the scene becomes active, on `EKEventStoreChanged`, and in `BGAppRefreshTask` (via `StudentBackgroundRefresh.run()`).
- Events live in memory only. We store identifiers and annotations, never titles, times or notes, and nothing is mirrored to CloudKit.
- Classifier priority: user tag > weekly recurrence = class > all-day or keyword (`due`, `submit`, `exam`, `quiz`, whole words) = deadline > course code `[A-Z]{2,4}\s?\d{3}` = class > other. The course code is extracted for every category, and a new code creates a `Course` with a rotating paint (coral, sand, tide, sage).
- Corrections are keyed by the series key (`calendarItemExternalIdentifier`), so a correction applies to the whole recurring series.

## Data

| Record | Store | Notes |
|---|---|---|
| `Course` | Cloud config (`StudentCourseRecord`) | code, optional name, paint |
| `ReminderRule` | Cloud config (`StudentReminderRuleRecord`) | `courseID == nil` = global rule; a course rule overrides it |
| `CourseEventLink` | **Local** config (`StudentCourseEventLinkRecord`) | series key, course, user tag, completed deadline occurrences. S-02 requires it local. Because it's keyed by the external identifier, moving it to Cloud later is a one-line change in `StudentModel` |
| `Assignment` | Cloud config (`StudentAssignmentRecord`) | title, due, optional course, done, Reminders external id + list id for imports |
| `GradeCategory` | Cloud config (`StudentGradeCategoryRecord`), **payload cloud-encrypted** | course, name, weight % |
| `GradeEntry` | Cloud config (`StudentGradeEntryRecord`), **payload cloud-encrypted** | course, optional category, title, score, out of |
| `Course.credits` | (inside `Course`) | optional; `nil` counts as 1 credit |
| `StudentSettings` | App Group `Student/settings.json` | chosen calendars, "connect later", Reminders list, due-reminder offset, grade scale, leave-by on/mode/extra minutes, last focus preset. Every key decodes optionally, so older files load |
| Focus session | App Group `Student/focus.json` | the running/paused session only; deleted when it ends |
| ETA memory | App Group `Student/eta.json` | hashed place keys → seconds, 7-day prune |

**Why this storage:** CoreKit stores every record as an `id / updatedAt / payload` entity that the feature contributes (`PayloadEntity.make`), and the app already loads `StudentModel` as a contributor and dedupes `StudentModel.syncedEntityNames`. So the three new entities are added in `StudentModel.makeEntities()` with no CoreKit change: an additive model change (new entities only), which Core Data migrates lightly and CloudKit accepts. The CloudKit schema needs a re-deploy to Production before release. `FileStudentRepository` (no Core Data) stores the same records in `Student/records.json` and still reads files written before these keys existed.

## Widgets (S-03)

- **Next Class:** small, medium (the mockup's Flow chip: horizontal, 128 pt field, `ClockGlyph`), and accessoryRectangular (Lock Screen "BIO 201 · ROOM 3B / in 14 min").
- **Today's Schedule:** medium and large.
- Timeline entries at every class start and end, plus each midnight (DST-safe). Countdowns update themselves: iOS 18+ uses `Text(.currentDate, format: .reference(to:allowedFields: [.hour, .minute]))`, and iOS 17 falls back to `Text(date, style: .relative)`. The reload policy is `.after` the last class end, capped at 24 h.
- Tapping a widget opens `widgetx://section/student?course=<uuid>`. `StudentDeepLink.courseID(from:)` parses the course.
- If there's no snapshot, the widget shows "Connect your calendar". A snapshot older than 36 h adds "Open Widgetdeck to refresh".

## Assignments (S-05)

- Due tab: "Coming up" lists calendar deadlines and assignments together (`AssignmentPlanner.merged`). "Add" opens the assignment sheet (title, due date and time, optional course, done, delete). Tapping an assignment edits it. Ticking the ring marks it done.
- Assignments work in every mode, including the sample week (they're the user's real data; the sample deadlines are not mixed into widgets or notifications).
- **Reminders import** (read-only): on every sync, the chosen list's reminders that have a due date are merged in (`ReminderImporter`). New ones become assignments (course guessed from a code like "BIO 201" in the title). For existing imports the title and due date follow Reminders, completing a reminder marks the assignment done (never the other way round), and the user's course and done flag are kept. A reminder deleted from the list (or that lost its due date) removes its imported assignment. Imported assignments can't be deleted in Widgetdeck; the sheet says to delete them in Reminders. Date-only due dates count as 23:59 that day.
- **Due reminders:** Off / 1 hr / 1 day before, through the same rolling scheduler (`student.due.` prefix; the fire time is part of the id so a changed due date replaces the request).
- **Assignments Due widget** (`WidgetKind.assignments`): medium (3 rows), large (7 rows), accessoryRectangular (next item + "+N more"). Snapshot = open, not-yet-due items (≤ 20). Timeline entries now + each due time in the next 24 h, so passed items drop off without the app.

## Grades (S-06)

- Grades tab: a GPA chip (credit-weighted, on the chosen scale, "—" with no grades) with a "Scale" button, and every course with "92.4% · A− · 3 cr". Tapping a course opens its grades sheet: credits, weighted categories ("Exams 50%"; the header shows the weight total, moss at 100), graded items (score / out of, optional category) and "What do I need on the final?".
- Maths (`GradeMath`, pure): no categories = total points; with categories = weighted average of each category's points %, with empty categories left out and the rest re-normalised ("grade so far"); uncategorised items take the weight not given to any category (100 − Σ), and don't count when that's 0. Letters/points from `GradeScale` (`plusMinus` 4.0, `simple` 4.0, `plusMinus43` 4.3 with A+), rounded to 2 decimals before banding. Final: `needed = (target − current × (1 − w)) / w`, reported as secured (≤ 0), needs x, out of reach (> 100) or invalid weight.
- Courses come from the calendar classifier, so grades need a connected calendar. Deleting a category keeps its items (they become uncategorised).

## Leave by (S-07)

- Per course (course sheet → "Leave by"): Off, or 10/15/20/30/45/60 min before class. `Course.leaveMinutesBefore` (synced) → `ClassSlot.leaveBy` in the widget snapshots. Next Class shows "Leave by 8:40" until that time (timeline entry at the leave time), then reverts to the room. Not set = nothing shown. Separate from the ETA alerts below.
- **Auto** (course sheet → "Leave by" → Auto): asks for location (when in use). On each widget publish, `LeaveByPlanner.applyAuto` sets `leaveBy` = start − MapKit ETA − the leave-by extra minutes, with `leaveByIsEstimate` → the widget shows "Leave ~8:36 est.". Uses the same ETA lookup/cache as the alerts (next 18 h, 4 places, 20 min cache, 12 h memory), the travel mode from Leave-by alerts, and works whether or not alerts are on. No ETA (no address match, no location) = the room is shown instead.

- Courses section → "Leave-by alerts": Off/On, walking / driving / transit, 0/5/10/15 min extra.
- On each sync with the feature on and location allowed: for classes in the next 18 h with a location, up to 4 distinct places are looked up (`MKLocalSearch` → one `MKDirections.calculateETA` from `MKMapItem.forCurrentLocation()`). ETAs are cached 20 min in memory and remembered for 12 h in `Student/eta.json` (keys are SHA-256 hashes; locations are never stored in clear), so a background refresh without a location fix keeps a recent leave-by time.
- Notification: "Leave by 8:36 for BIO 201 / About 19 min on foot to …" at start − ETA − extra time, rounded down to the minute (`student.leave.` prefix).
- Fallbacks: no address match (e.g. "Room 3B"), no permission, MapKit error, or an ETA over 3 h → a plain "BIO 201 in 15 min" reminder, unless the class already has a normal class reminder. Leave times already past are skipped.
- The ETA is worked out when reminders are scheduled, not live; the sheet says so.

## Focus timer (S-08)

- Focus tab: Pomodoro (4 × 25/5), Deep work (2 × 50/10) or Custom (focus 5–180, break 0–60, 1–8 rounds); "Working on" text or one of the next open deadlines; optional course (its paint colours the chip). The last preset is remembered.
- `FocusPlan` precomputes every block with absolute dates. The in-app chip, the Lock Screen chip and the Dynamic Island all count down with `Text(timerInterval:)` and fill with `ProgressView(timerInterval:)`. No timers, no background code.
- Local notifications at every block end ("Break time", "Back to focus", "Focus session done"), prefix `studentfocus.` so a Student sync never cancels them.
- Pause / Resume / Stop in the app. Pausing cancels the pending notifications and freezes the Live Activity at the remaining time; resuming shifts the rest of the plan by the pause length.
- The session is saved in the App Group (`Student/focus.json`), so it survives the app being closed; `FocusTimer.restore()` runs when the section appears and on every return to the foreground (ends finished sessions and stray activities, moves the Live Activity to the current block).
- Live Activity (`FocusActivityAttributes`, LockScreen.png): Lock Screen = course-paint field with progress bar + "FOCUS · SESSION 2 OF 4 / 18:20 / CHEM LAB REPORT"; island compact = paint key + countdown, minimal = paint key, expanded = key, "FOCUS · 2 OF 4", title, large countdown, progress bar. The app moves it to the next block while it's open; otherwise each update has `staleDate = blockEnd` and a stale activity reads "Focus block done / Open Widgetdeck for the next block" instead of a wrong phase. Deep Tide reads as Label Ivory on the black island. Tapping opens `widgetx://section/student?tab=focus`.
- Not built: the mockup's pause button inside the Lock Screen chip (it would need a `LiveActivityIntent` that changes app state while the app isn't running; pause is in the app instead).

## Reminders (S-04)

Offsets are 15 min, 30 min, 1 hr and 1 day, set globally or per course. "1 day" keeps the same wall-clock time across DST. The plan is a rolling window of the soonest reminders, 48 by default. That leaves room for other sections under iOS's cap of 64 pending notifications. The scheduler also counts other sections' pending requests and never exceeds 64. Class, assignment and leave-by reminders are merged into that one window (`ReminderPlanner.combine`). Only `student.class.*`, `student.due.*` and `student.leave.*` identifiers are touched, and the whole window is replanned on every sync.

## CoreKit / app requests

### For S-05..S-08 (new, 2026-10-01)

Small on purpose. The new widget and the Live Activity are already in `WidgetExtension/Student/StudentWidgets.swift`, which the bundle includes via `StudentWidgets().body`, so **the widget bundle and the project file need no change**. No CoreKit change is needed.

1. **Focus deep link** (`App/AppEnvironment.handle(url:)`): after selecting the Student tab, add
   `if FocusDeepLink.isFocus(url) { studentStore?.showFocus() }` so tapping the Live Activity / Dynamic Island opens the Focus segment. (Without it the link still opens the Student tab.)
2. **CloudKit schema:** deploy the new record types `CD_StudentAssignmentRecord`, `CD_StudentGradeCategoryRecord`, `CD_StudentGradeEntryRecord` to Production before submission (they appear in Development after the first sync on a dev build).
3. **Delete All Data / export:** check `DataEraser` wipes the App Group `Student/` folder (it now also holds `focus.json` and `eta.json`), ends any `Activity<FocusActivityAttributes>`, and removes pending `studentfocus.*` notifications; check `DataExporter` includes the three new entities (they're in `StudentModel.syncedEntityNames`).
4. **Privacy manifest / App Privacy label:** location is used on-device only (MapKit ETA, never stored or sent to us); grades sync via the user's private iCloud database (encrypted). Update `docs/AppStore/` answers if they list data types per feature.
5. **App Review notes:** mention the leave-by feature uses When In Use location only while the app is open, and the focus Live Activity.
6. **Notification tap routing:** focus notifications carry `userInfo["url"]` (the Student deep link, with the course if any); the existing delegate handles it.

### For S-01..S-04

All six are done (2026-09-28). `CourseEventLink` stays in the Local config by decision.

The package works without these (it falls back to the App Group JSON repository), but for synced courses and reminder rules:

1. `App/AppEnvironment.bootstrap`: `CoreDataStack.load(mode: .app, contributors: [StudentModel.self])`, and register `StudentModel.syncedEntityNames` with `DeduplicationService`.
2. In `RootView`, pass the store: `StudentSectionView(store: StudentStore(repository: CoreDataStudentRepository(stack: stack)))`.
3. Call `await StudentBackgroundRefresh.run(...)` from `AppEnvironment.performBackgroundRefresh()`.
4. `AppEnvironment.handle(url:)`: forward `StudentDeepLink.courseID(from:)` to open the course sheet (today the link only selects the tab).
5. The notification delegate should open `userInfo["url"]` when a reminder is tapped.
6. DesignSystem: `PermissionPrimer` is still the legacy (pre-Paint-Chip) style. A Paint Chip primer would match the mockup better.

## Tests

```bash
cd Packages/StudentFeature
xcodebuild test -scheme StudentFeature-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

63 tests (Swift Testing; parameterised letter bands count once) cover, for S-05..S-08: grade maths (points %, weighted categories with re-normalising, the uncategorised bucket, letter bands on all three scales incl. float edges, credit-weighted GPA, the final predictor's secured / needs / out-of-reach / invalid cases), assignments (deadline mapping, merge order, widget snapshot filter + size cap, provider entries dropping passed items, due reminders across DST, id changes with the due date), the Reminders import (new, skipped, updated, completion, removal), leave-by (fire time + buffer + rounding, fallback rules, past/far/no-location skips, lookup cap, hashed ETA memory), the combined reminder window and that a sync never touches focus notifications, the focus plan (layout, clamping, resume shift, paused state, notifications) and the `FocusTimer` lifecycle (start/pause/relaunch/resume/finish with a fake notification centre), repository round-trips, decoding pre-S-05 files, and the CloudKit encryption flags. The original 26 cover: the table-driven classifier, series corrections, the course auto-create and paint rotation, deadlines, snapshot contents, size cap and round-trip, timeline boundaries, midnight rollover, DST fall-back, time zones, the reload date, reminder offsets and course overrides, the 64 cap and rolling window, sharing the cap with other sections, 1-day reminders across DST, repository persistence, the CloudKit model rules, and week-grid layout.
