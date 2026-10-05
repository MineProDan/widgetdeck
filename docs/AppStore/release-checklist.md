# Release checklist (no TestFlight)

Tick in order. Everything marked **(owner)** needs a person with the Apple Developer account. None of it can be automated from this repo.

## 0. Name (renamed from WidgetX on 2026-10-04)

- [x] Name check: no "Widgetdeck" app in the US App Store (iTunes Search API, 2026-10-04) and no USPTO mark for "widgetdeck" or "widget deck" (tmsearch.uspto.gov, 2026-10-04). Not a legal clearance.
- [ ] **(owner)** Search "Widgetdeck" in the App Store app on the iPhone (catches region-only apps).
- [ ] **(owner)** Rename the reserved App Store Connect record from "WidgetX: Aesthetic Widgets" to `Widgetdeck: Aesthetic Widgets` (29 characters).

## 1. Before the first submission (one-time)

- [ ] **(owner)** The app is **free**: don't sign the Paid Apps agreement and don't create any IAPs. The Free Apps agreement accepted when you joined the Developer Program is enough.
- [ ] **(owner)** Create the app record: name `Widgetdeck: Aesthetic Widgets`, bundle ID `io.github.mineprodan.iospremium`, SKU of your choice, primary language English (U.S.).
- [ ] **(owner)** Check these capabilities on the App IDs in the developer portal: iCloud (CloudKit) with container `iCloud.io.github.mineprodan.iospremium`, App Groups `group.io.github.mineprodan.iospremium` (app + `…iospremium.widgets`), Push Notifications, Keychain Sharing.
- [ ] **(owner)** **Deploy the CloudKit schema to Production** (CloudKit Console → container → Schema → Deploy Schema Changes). First create every record type in Development: in Xcode, Product → Scheme → Edit Scheme → Run → Arguments, add `-WXInitCloudKitSchema YES`, run the Debug build once on the iPhone (signed into iCloud), check the console for "CloudKit schema initialized", then remove the argument. Without this step, sync silently fails for App Store users.
- [x] Privacy policy and support pages are live on GitHub Pages: https://mineprodan.github.io/privacy/ and https://mineprodan.github.io/support/. If you edit `privacy-policy.md` or `support.md`, update the live pages too.
- [ ] **(owner)** Enter both URLs in App Store Connect (Privacy Policy URL and Support URL). Set the policy's effective date to the day it goes live.
- [x] `flags.json` is live at https://mineprodan.github.io/flags.json, and `RemoteFlags.remoteURL` (`Packages/CoreKit/Sources/CoreKit/Support/RemoteFlags.swift`) points to it.
- [ ] **(owner)** App Privacy questionnaire: answer as in `app-privacy-label.md`.
- [ ] **(owner)** Age rating questionnaire: all "None", which gives 4+.
- [x] Export compliance: `ITSAppUsesNonExemptEncryption = NO` is in Info.plist (nothing to do in App Store Connect).
- [x] Quote licensing checked (2026-10-04): all 111 quotes come from works published before 1930 and translations by translators who died long ago (Long, Legge, Carter, Müller, Townsend, Gummere); the 1929 Dickinson poems are US public domain since 2025.
- [x] Privacy policy, App Privacy answers, review notes and support FAQ cover location (Apple Maps travel time), calendar notes (room suggestion), Reminders import and class setup; the live pages match (effective date October 3, 2026).

## 2. Every release: build and verify

- [x] Every package's tests pass (CoreKit 72, DesignSystem 28, TechFeature 29, StudentFeature 74, AestheticFeature 37, WellnessFeature 28) and the `WidgetX` scheme's tests pass (35), 2026-10-04. 0 warnings in our code. Re-run before each upload; see `test-report.md` for the commands.
- [x] `MARKETING_VERSION` is 1.0.0 (app and widgets). Bump `CURRENT_PROJECT_VERSION` for each upload.
- [x] Release configuration builds for device and Simulator with 0 warnings (2026-10-04). Re-check before archiving: **build the Release configuration** (`xcodebuild build -configuration Release`). A Debug-only file once broke Release while every Debug build and test passed.
- [ ] **Dev install on the iPhone** (it has a Dynamic Island) with Xcode → Run, Release configuration:
  - [ ] Class setup flow with your real calendar: room suggestion, travel tiles, heads-up; Skip; Settings → Classes → "Set up my classes again" and "Redo calendar setup".
  - [ ] Leave by: Auto with each travel mode and Set time on the Next Class widget; leave-by alerts and class reminders arrive; a "No thanks" course gets nothing. With no location fix, syncing still finishes (travel-time lookups time out after 12 s; the location fix after 6 s).
  - [ ] Smart Stack over a few days: Next Class rises an hour before class, Mood after 20:00 until logged.
  - [ ] Fresh install shows onboarding once; a relaunch goes straight to the tabs.
  - [ ] Add each widget; check light, dark, tinted and clear (iOS 26) home screens; lock screen accessories.
  - [ ] iCloud: sign the Simulator into the **same Apple ID**, run Widgetdeck on both, change a theme, course, habit or mood on the iPhone and see it in the Simulator (relaunch the Simulator app if it doesn't appear; it may not get push notifications). Then delete and reinstall the app on the iPhone: the data must come back from iCloud. Then test signed out of iCloud, and iCloud storage full.
  - [ ] Calendar allow / deny / revoke in Settings. Student falls back to the demo week.
  - [ ] Free app check: Settings has no Premium section, every widget works (including System Overview), and nothing anywhere offers a purchase.
  - [ ] Wellness: add and tick a habit, log a mood, then tick/log again from the Habits and Mood widgets; run a breathing session and check the Lock Screen Live Activity and the **expanded** Dynamic Island; turn on the evening mood reminder and check it skips a day you already logged.
  - [ ] Delete All Data, then relaunch. Pending class and mood reminders are cancelled too.
  - [ ] Record the NEEDS DEVICE numbers in `test-report.md` (memory, widget memory, battery drain).
- [ ] Product → Archive (Release) → **Generate Privacy Report** and compare with `privacy-audit.md`.
- [ ] Validate the archive, then Distribute → App Store Connect → Upload. This is the only upload; nothing goes to TestFlight testers.
  - This Mac (Intel, Xcode 26.3) can upload **until Apple requires the iOS 27 SDK (expected ~April 2027)**. After that, use Xcode Cloud or an Apple silicon Mac.

## 3. Submission

- [ ] Metadata from `metadata.md`, screenshots from `screenshot-plan.md`, review notes from `review-notes.md`.
  - [x] 6.9" (1320 × 2868) screenshots from a Release build in `screenshots/`: #2 Theme Sync, #4 vibe picker, #6 student week (sample and live), #9 class setup (intro, room, travel, heads-up).
  - [ ] **(owner, iPhone)** #1 themed home screen, #3 Lock Screen, #5 Tech tab (the Simulator has no battery reading), #7 Habits + Mood widgets, #8 breathing Live Activity, #10 Next Class with a leave time. Adding widgets crashes SpringBoard in the iOS 26 Simulator (Apple bug in `SBHRippleSimulation`), so take these on the device.
- [ ] **Version Release: Manually release this version**, so you control the soft-launch timing.
- [ ] **Phased Release for automatic updates: ON** (7-day rollout, can be paused). This is for updates; the first version goes to everyone in the chosen territories.

## 4. Soft launch (~2 weeks)

- [ ] Pricing and Availability: price **Free**; **Canada, Australia, New Zealand, Ireland only**.
- [ ] Release. Keep `flags.json` ready: if T-03 causes trouble, set `"T-03.cpuMemory": false`. No new build is needed.
- [ ] Watch the gates: **crash-free ≥ 99.5%** (Xcode Organizer / App Store Connect), **onboarding → first widget ≥ 55%**, **rating ≥ 4.5**.
  - **Decided 2026-09-30: use App Store Connect's opt-in App Analytics** (App Store Connect → Analytics: sessions, active devices, retention, crashes; only from users who share analytics with developers). There's no in-app analytics and no in-app toggle, so the privacy label stays "Data Not Collected". App Analytics can't see "first widget added", so judge that gate from day-1/day-7 retention and sessions per active device instead.

## 5. Full launch

- [ ] Gates met, then add US, UK and the other territories in Pricing and Availability.
- [ ] Custom Product Pages `/study`, `/aesthetic`, `/tech`.

## 6. Updates and hotfixes

- [ ] Keep a `hotfix/x.y.z` branch from the released tag.
- [ ] Crash fix: ship with **Request Expedited Review**. Phased release stays on; pause it if the crash rate rises.
- [ ] If App Review objects to a flagged feature: switch the flag off in `flags.json` and resubmit the same build. Don't block the release.
