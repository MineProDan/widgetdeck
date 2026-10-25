# App Review notes (paste into App Store Connect → App Review Information → Notes, max 4000 characters)

```
Widgetdeck is a home-screen widget app with four sections: Student (class schedule from the user's calendar), Aesthetic (themes, Theme Sync from a user-picked wallpaper photo, photo widgets), Wellness (habits, mood, breathing) and Tech (battery, storage, thermal, CPU/RAM).

NO ACCOUNT IS NEEDED. There is no login. All features work on a fresh install.

TECH STATS (public APIs only)
- Battery level/state: UIDevice. "Time to full" is our own estimate from the observed charge rate while the app is open, labelled "est.".
- Storage: URLResourceValues volumeTotalCapacity / volumeAvailableCapacityForImportantUsage, device volume only. Privacy manifest: DiskSpace 85F4.1.
- Thermal state: ProcessInfo.thermalState.
- CPU load and memory used: Mach host_processor_info and host_statistics64, system-wide totals only, sampled every 5 s ONLY while the Tech tab is in the foreground. No background execution; nothing about other apps is read or shown.
- We do NOT show GPU usage, battery health, other apps or network activity.
Widgets are not real-time: they show the last saved values (with an "as of" time) plus system countdowns.

REMOTE FLAG
CPU/RAM is behind a remote flag ("T-03.cpuMemory") in a JSON file on our website. If you prefer it off, tell us and we will switch it off without a new build.

PERMISSIONS (each asked only when the user chooses the feature)
- Calendar (full access, read-only): to find class times. We never write to or upload events. Event notes are read on-device only to suggest a room name in class setup; the user confirms it; notes are not stored.
- Notifications: class, due-date and leave-by reminders.
- Photos: none. PhotosPicker, so the user picks individual photos.
- Location (When In Use only): asked only when the user picks "Leave by: Auto" for a class or turns on leave-by alerts. When the app syncs, it makes one Apple Maps travel-time estimate per class address (max 4 places per sync, cached 20 min). Location is never stored; no continuous or background tracking. The result is shown as an estimate ("Leave ~8:36 est.") on the Next Class widget and used for an optional notification. If refused, the feature stays off.
- Reminders (read-only): only when the user imports assignments.
- Live Activities: focus timer and breathing sessions show a countdown on the Lock Screen and Dynamic Island while running.

HOW TO TEST
1. Launch. Onboarding: pick a theme and sections, optionally allow Calendar, then "Later".
2. Student: without Calendar a sample week is shown. With a calendar, a short class setup opens (room, how you get there, heads-up); it can be skipped and rerun from Settings > Classes. Tap a course to change Room, Leave by (Off / Auto / Set time) and reminders. Due: add an assignment. Focus > Start shows the Live Activity.
3. Aesthetic: Theme Sync, pick any photo as the "wallpaper". Photo widget and Mood board: add photos.
4. Tech: values update while open.
5. Wellness: add and tick a habit, tap a mood, Breathe > Start for the Live Activity. Habits and Mood widgets are interactive (App Intents) and only write to the app's own storage. No medical claims.
6. Home screen: long-press, Edit, Add Widget, search "Widgetdeck".
7. The app is completely free: no purchases, no subscriptions, nothing locked.

No ads, no tracking, no ATT prompt, no third-party SDKs.
```

## Owner: fill in App Review Information

- **Contact:** name, phone and email are entered in App Store Connect → version → App Review Information (not shown publicly, and kept out of this repo).
- **Sign-in required:** No.
- **Attachment (optional):** a 30 s screen recording of the Tech tab showing that sampling pauses in the background. It helps if T-03 is questioned.
- If App Review rejects T-03 under 2.5.1 or 2.3: set `"T-03.cpuMemory": false` in the CDN `flags.json`, reply to the reviewer, and resubmit the **same build**. Don't block the release on it.
