# Screenshot plan (MVP)

Adapted from `docs/plan/08-go-to-market.md` §2.2, using only features in the 1.0 build (Tech, Student, Aesthetic, Wellness). S-08 (study timer) is now 1.0 scope (2026-09-30): once built, #3 goes back to the plan's study-timer Dynamic Island shot. Until then the breathing Live Activity holds that slot.

**Required size:** 6.9" (1320 × 2868 or 1290 × 2796). App Store Connect scales it down for smaller iPhones. The app is iPhone-only, so no iPad set is needed.
**Rule:** show the home screen, not the app UI, in the first three.

| # | Screenshot | Caption | How to capture |
|---|---|---|---|
| 1 | Themed home screen: Next Class (medium), Palette (small), Battery (small), Photo (small) on the beach wallpaper | "Your home screen, beautiful *and* useful" | Real device or 17 Pro Max simulator. Use the demo schedule so no personal events appear |
| 2 | Theme Sync before and after | "Matches your wallpaper in one tap" | Aesthetic tab, compare slider at 50% |
| 3 | Lock screen: Next Class (rectangular) + Battery (circular) | "Next class, right on your lock screen" | Device lock screen, `LockScreen.png` layout |
| 4 | Onboarding vibe picker (fan deck) | "Pick a vibe. Every widget follows." | Onboarding step 1 (`docs/design/mockup/built/onboarding/1-vibe.png`) |
| 5 | Tech tab + System Overview widget | "Battery, storage and heat, beautifully" | Tech tab on a device (the simulator shows fake battery values) |
| 6 | Student week grid | "Your classes, from your own calendar" | Student tab with the demo week |
| 7 | Habits (small) + Mood (small) widgets on the home screen | "Tick a habit without opening the app" | Add a few habits in Wellness first; no personal notes visible |
| 8 | Breathing Live Activity in the Dynamic Island + Lock Screen | "Breathe along from your Lock Screen" | Physical iPhone with a Dynamic Island (the simulator can't show it cleanly) |
| 9 | Class setup "How do you get there?" (walk / drive / transit tiles) | "Set up each class in seconds" | Simulator with a sample calendar class; Student tab right after connecting |
| 10 | Next Class (medium) with "Leave ~12:06 PM est." and a room | "Know when to leave" | Course set to Auto with a real address; demo-safe course name |

**Checks:**
- No "live" or "real-time" wording about widgets anywhere (Platform Reality Rule 1).
- No stats iOS doesn't provide (GPU, battery health).
- Status bar: 9:41, full battery. Use `xcrun simctl status_bar booted override --time 9:41 --batteryLevel 100 --batteryState charged` on the simulator.
- Never show real calendar events or personal photos. Use the sample schedule and the bundled sample art.

**Custom Product Pages** (plan §2.3): `/study` leads with #6 then #1, `/aesthetic` with #2, `/tech` with #5, `/habits` with #7 then #8.

**App preview video (optional, 15–30 s):** screen recording of onboarding, then adding a widget, then the finished home screen. The first 3 seconds must show the finished home screen.
