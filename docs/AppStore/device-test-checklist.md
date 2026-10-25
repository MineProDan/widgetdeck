# Device test and screenshot checklist (iPhone 14 Pro, Release build)

_Created 2026-10-13 for the signed Release build installed fresh on "Dan's iPhone" (iOS 26.5).
Tick items here as you go; record results in `LAUNCH-TODO.md` and `release-checklist.md` §2._

Do it in this order: earlier steps set up what the screenshots need.

## 0. Prep (5 min)

- [x] **Status bar:** charge to 100% before the screenshots. For 9:41: Settings → General → Date & Time → turn off
      Set Automatically. **Turn it back on afterwards**, or reminders and Smart Stack timing will be off.
- [x] **Demo-safe calendar:** in the Calendar app, make a calendar called "School" with a few fake classes
      (course codes like BIO 201, ENG 110, with rooms; one weekly recurring). Put one ~40 min from now with a real
      nearby address for the leave-by shot. Screenshots must never show your real events.

## 1. Onboarding (on screen now)

- [x] Tap a theme card at the side; it should select.
- [x] Allow Calendar and pick only the "School" calendar. (2026-10-24)
- [x] Add a widget when the onboarding asks, then come back. You should see "Nice. It's on."
- [x] Force-quit and reopen; it should go straight to the tabs. (2026-10-24)

## 2. Student

- [x] **Class setup (2026-10-24):** room suggestion, travel tiles, heads-up. Try Skip once. Then Settings → Classes →
      "Set up my classes again" and "Redo calendar setup".
- [x] **Leave by (2026-10-24, Auto + Walk; alert arrived):** one course on Auto with each travel mode, one on Set time. The Next Class widget shows the
      leave time. Leave-by alerts and class reminders arrive. A "No thanks" course gets nothing.
- [x] **Calendar permissions (2026-10-24):** allow → deny in Settings → back in the app. Student falls back to the demo week.
      Then allow again.

## 3. Widgets (all of them)

- [x] Add each widget (2026-10-24: all 15 widgets, every Lock Screen family). Check the home screen in light, dark, tinted and clear (long-press the home screen →
      Edit → Customize), plus the lock screen accessories.
- [x] **Battery:** the Battery widget shows a real percentage (100% · Full · Plugged in, 2026-10-24).
- [x] **Smart Stack (over a few days):** Next Class rises about an hour before class; Mood rises after 20:00
      until you log.

## 4. Theme decks

- [x] Pick each of the 10 decks (onboarding or Settings → Theme). Done 2026-10-24 on the iPhone; three small font findings logged in LAUNCH-TODO.md (Pocket Arcade %, Butterfly Clip squat, Lo-fi Study edges). The app and every widget follow. The deck's
      display font renders **inside widgets** (not the system font); punch-hole shapes and corner roundness look
      right; text stays readable in tinted and clear modes.
- [x] Theme Sync after picking a deck recolours it and keeps its fonts. (2026-10-24: Old Library + beach palette: slate and coral fields, serif font and keyhole punch holes kept.)

## 5. Wellness

- [x] Add and tick a habit and log a mood in the app; then do both again from the Habits and Mood widgets. (2026-10-24: app 1 of 2 + Good; widgets 2 of 2 + "Logged: Great".)
- [x] Run a breathing session: Lock Screen Live Activity and the **expanded** Dynamic Island (long-press it). (2026-10-24)
- [x] Turn on the evening mood reminder; it doesn't fire on a day you've already logged.

## 6. Settings and data

- [x] **Export my data:** one file that includes Student and Wellness data. (2026-10-24: file saved to Files.)
- [x] **Settings → About → Sync log:** opens and shares. (2026-10-24)
- [x] **Free-app check (2026-10-24, owner):** no Premium section, every widget works (including System Overview), nothing offers a
      purchase.

## 7. iCloud (needs the Simulator signed in to your Apple ID)

- [x] (2026-10-24: habits + today's ticks + mood phone → Simulator in ~1 min; mood Low Simulator → phone in under a minute.) Sign the Simulator in to the same Apple ID and run Widgetdeck on both. Change a theme, course, habit or mood
      on the phone and see it in the Simulator (relaunch the Simulator app if it doesn't appear).
- [x] Delete and reinstall on the phone; the data comes back from iCloud. (2026-10-24: habits, today's ticks, streaks and mood back within a minute; home and Lock Screen widgets kept by iOS; Photo/Mood Board picks need re-picking.)
- [x] Repeat signed out of iCloud, then with iCloud storage full.

## 8. Last test: Delete All Data

- [x] Settings → Delete All Data, then relaunch. Pending class and mood reminders are cancelled too.

## Results log (2026-10-24 session)

- Remaining items (Smart Stack, mood reminder, other travel modes, iCloud signed out/full, Delete All Data, battery drain, theme-card tap) marked working by the owner; not run in this session.

- Tide Pool, Old Library, Matcha Café: font, paints, punch shapes and corners render in widgets; readable. Pass.
- iCloud: both directions sync (phone → Simulator: new habits, today's ticks, mood Great; Simulator → phone: mood changed to Low). Note: a hand-set date on one device files ticks under that day, so both need the real date. Pass.
- Leave-by alert: arrived on time ("Leave by 10:06 AM for BIO 201 · About 19 min on foot · Class starts 10:30 AM"), on the Lock Screen with the Widgetdeck icon. ENG 110 ("No thanks") gets no alert. Pass.
- Class setup again: ENG 110 set to "No thanks" → Leave by Off, Custom reminders with none ("No reminders for this course"); MATH 140 skipped, unchanged; Redo calendar setup switched calendars. Pass.
- Other home widgets: Storage (25 GB of 127 GB), Assignments ("All caught up"), Today's Schedule (Today · Monday, BIO 201 10:30, ENG 110 1:00), Daily Quote (Wordsworth, credited), Affirmation, Breathe ("Tap to start"), Welcome ("Set up widgets") and Mood Board (empty "Add photos" until its own photos are picked, then a 4-photo grid) all render. Pass. Lock Screen: Storage (rectangular, 25 GB + bar), Streak (circular, leaf + 1), Mood (circular, "Great" ring), Battery (inline, "100% · full"), plus Next Class (rectangular) and Battery (circular) earlier. Pass.
- Student: fake "School" calendar via Redo calendar setup; week grid shows only BIO 201, ENG 110, MATH 140. Next Class (medium) shows "Leave ~10:06 AM est." + room once the class is far enough ahead (the leave time hides once it's past, by design). Pass.
- Breathing Live Activity: compact Dynamic Island (plum chip + session countdown) and expanded (box progress, "Box Breathing · 1:44 left", phase "Hold · 4") work. Lock Screen view (plum chip, "Box Breathing · 0:37 left", "Hold · 4") also works. Pass. iOS showed its one-time "Allow Live Activities from Widgetdeck?" prompt on the Lock Screen.
- Rendering modes (Paint Chip): light, dark (bands stay light by design), tinted (chip structure kept, all text readable) and clear (white text and keys on glass; System Overview over the brightest part of the wallpaper is lower contrast but readable, iOS-controlled). Pass. Lock screen accessories still to check.
- Game Day, Cosmic Sleepover: font, punch shapes and paints render in widgets; readable. Pass.
- Lo-fi Study: handwriting font, heart punch holes and paints render in widgets; pass, with one finding: text nearly touches the right edge and starts indented from the labels.
- Butterfly Clip: font, sparkle punch holes and paints render in widgets; pass, with one finding: headlines look squat (tight tracking + wide font).
- Pocket Arcade: pixel font renders in widgets; pass, with one finding: Silkscreen's "%" reads like "Z" ("100Z").
- Saturday Cartoons deck: app and widgets restyle (star punch holes, deck colours, "Grape Soda · Mood"); the deck's rounded display font renders inside widgets (zoomed check). Pass.
- Widgets: Battery (small) shows 100% · Full · Plugged in (fills in on device); System Overview (medium) shows battery, 25 GB free, CPU, memory, "as of" time, thermal; Mood and Habits (empty state "Add a habit") render. Widget extension memory 10.5 MB peak with the Paint Chip deck (target < 20 MB). Pass.
- Tech tab: battery 100% Full · Plugged in, storage 25 GB of 127 GB, CPU and memory fill in, iPhone 14 Pro · A16 Bionic · iOS 26.5, thermal Nominal. Pass.

## 9. Numbers for `test-report.md`

- [x] App memory (target < 100 MB): **22.8 MB** peak on the Tech tab (2026-10-24, Instruments Activity Monitor, 12 s, 0.1% CPU idle).
- [x] Widget extension memory (target < 20 MB): **10.5 MB** peak (Paint Chip), **7.3 MB** with Saturday Cartoons'
      bundled font (2026-10-24, 4 widgets). App peak 36.0 MB just after a deck change.
- [x] Battery drain over 1 hour on the Tech tab (target < 2%/hr).

Memory numbers can be read while the phone is connected: note when you are on the Tech tab.

## Screenshots (iPhone 14 Pro, then scale to 6.9")

| # | What | How | Done |
|---|---|---|---|
| 1 | Themed home screen: Next Class (medium), Palette, Battery, Photo | AirDrop `docs/AppStore/assets/beach-wallpaper.png` and set it as the wallpaper. Run Theme Sync with the same image so Palette fills in. Pick it for the Photo widget too. | [ ] |
| 3 | Lock screen: Next Class (rectangular) + Battery (circular) | Edit the lock screen and add both. | [ ] |
| 5 | Tech tab + System Overview widget | Tech tab with real battery, storage and thermal readings. | [ ] |
| 8 | Breathing Live Activity | Start a breathing session. Dynamic Island shot and Lock Screen shot. | [ ] |
| 10 | Next Class (medium) with "Leave ~… est." and a room | The fake class with the real address, set to Auto. | [ ] |

Rules for all of them:
- Only the fake "School" calendar. No real events, personal photos or notes.
- No "live" or "real-time" wording about widgets.

Then AirDrop the shots to the Mac and scale each one (14 Pro 1179 × 2556 → 6.9" 1290 × 2796, same shape):

```bash
sips -z 2796 1290 IMG_1234.PNG --out 1-home-screen.png
```

Put them in `docs/AppStore/screenshots/`, scaled and named as in the list above.
If App Store Connect won't mix 1290 × 2796 with the 1320 × 2868 shots in one set, scale to 1320 × 2868 instead.
