# Release checklist (no TestFlight)

_Updated 2026-10-06. The 2026-10-04 test and Release-build ticks were reset: 16 commits landed since (theme decks with nine new fonts, export of Student/Wellness data, sync log, hardening, fixes)._

Tick in order. Everything marked **(owner)** needs a person with the Apple Developer account. None of it can be automated from this repo.

## 0. Name (renamed from WidgetX on 2026-10-04)

- [x] Name check: no "Widgetdeck" app in the US App Store (iTunes Search API, 2026-10-04) and no USPTO mark for "widgetdeck" or "widget deck" (tmsearch.uspto.gov, 2026-10-04). Not a legal clearance.
- [ ] **(owner)** Search "Widgetdeck" in the App Store app on the iPhone (catches region-only apps).
- [x] **(owner)** Rename the reserved App Store Connect record from "WidgetX: Aesthetic Widgets" to `Widgetdeck: Aesthetic Widgets` (29 characters). Checked 2026-10-06.

## 1. Before the first submission (one-time)

- [x] **(owner)** The app is **free**: no IAPs, no subscriptions, price tier Free (checked 2026-10-14). The Paid Apps agreement is already signed; leave it, but never use it.
- [x] **(owner)** Create the app record: name `Widgetdeck: Aesthetic Widgets`, bundle ID `io.github.mineprodan.iospremium`, SKU of your choice, primary language English (U.S.). Exists (Apple ID 6816573831, SKU `widgeter-ios-001`).
- [x] **(owner)** Check these capabilities on the App IDs in the developer portal: iCloud (CloudKit) with container `iCloud.io.github.mineprodan.iospremium`, App Groups `group.io.github.mineprodan.iospremium` (app + `…iospremium.widgets`), Push Notifications, Keychain Sharing. Confirmed 2026-10-06 from the signed archive's entitlements (app: iCloud/CloudKit, App Group, Keychain, push; widget: App Group, Keychain).
- [x] **(owner)** **CloudKit schema deployed to Production** (2026-10-06): 13 record types, initialized from a Debug build with `-WXInitCloudKitSchema YES`. Repeat the init + deploy whenever a release adds a synced entity or attribute.
- [x] Privacy policy and support pages are live on GitHub Pages: https://mineprodan.github.io/privacy/ and https://mineprodan.github.io/support/. If you edit `privacy-policy.md` or `support.md`, update the live pages too.
- [x] **(owner)** Enter both URLs in App Store Connect (Privacy Policy URL and Support URL). Set the policy's effective date to the day it goes live. Both set (checked 2026-10-06).
- [x] `flags.json` is live at https://mineprodan.github.io/flags.json, and `RemoteFlags.remoteURL` (`Packages/CoreKit/Sources/CoreKit/Support/RemoteFlags.swift`) points to it.
- [x] **(owner)** App Privacy questionnaire: answer as in `app-privacy-label.md`. Answered "Data Not Collected" (2026-10-06). Published 2026-10-06.
- [x] **(owner)** Age rating questionnaire: **9+** (2026-10-06). Everything is None/No except "Health or Wellness Topics" = Yes (habits, mood, breathing, affirmations); that one answer raises 4+ to 9+. Apple's new social media questions are all No.
- [x] Export compliance: `ITSAppUsesNonExemptEncryption = NO` is in Info.plist (nothing to do in App Store Connect).
- [x] Quote licensing checked (2026-10-04): all 111 quotes come from works published before 1930 and translations by translators who died long ago (Long, Legge, Carter, Müller, Townsend, Gummere); the 1929 Dickinson poems are US public domain since 2025.
- [x] Privacy policy, App Privacy answers, review notes and support FAQ cover location (Apple Maps travel time), calendar notes (room suggestion), Reminders import and class setup; the live pages match (effective date October 3, 2026; October 6 once the sync log and export update is published).

## 2. Every release: build and verify

- [x] Every package's tests pass and the `WidgetX` scheme's tests pass, 0 warnings in our code (2026-10-24 on Xcode 27.1 / iOS 27.1 SDK: CoreKit 63, DesignSystem 40, TechFeature 29, StudentFeature 86, AestheticFeature 37, WellnessFeature 31, app 34 = 320; iPhone 17 Pro simulator, iOS 27.0).
- [x] `MARKETING_VERSION` is 1.0.0 (app and widgets). Bump `CURRENT_PROJECT_VERSION` for each upload.
- [x] Release configuration builds for device and Simulator with 0 warnings (2026-10-24 on Xcode 27.1; signed device build). Re-check before archiving: **build the Release configuration** (`xcodebuild build -configuration Release`). A Debug-only file once broke Release while every Debug build and test passed.
- [ ] **Dev install on the iPhone** (it has a Dynamic Island) with Xcode → Run, Release configuration:
  - [ ] Class setup flow with your real calendar: room suggestion, travel tiles, heads-up; Skip; Settings → Classes → "Set up my classes again" and "Redo calendar setup".
  - [ ] Leave by: Auto with each travel mode and Set time on the Next Class widget; leave-by alerts and class reminders arrive; a "No thanks" course gets nothing. With no location fix, syncing still finishes (travel-time lookups time out after 12 s; the location fix after 6 s).
  - [ ] Smart Stack over a few days: Next Class rises an hour before class, Mood after 20:00 until logged.
  - [ ] Fresh install shows onboarding once; a relaunch goes straight to the tabs.
  - [ ] Add each widget; check light, dark, tinted and clear (iOS 26) home screens; lock screen accessories.
  - [ ] Theme decks: pick each of the 10 decks (onboarding step 1 and Settings → Theme). The app and every widget follow; the deck's display font renders **inside widgets** (not the system fallback); punch-hole shapes and corner roundness look right; text stays readable in tinted/clear modes. Theme Sync after a deck recolours it and keeps its fonts. Check widget memory with a deck that has a bundled font.
  - [ ] Settings → Export my data: the one file includes Student and Wellness data. Settings → About → Sync log opens and shares.
  - [ ] iCloud: sign the Simulator into the **same Apple ID**, run Widgetdeck on both, change a theme, course, habit or mood on the iPhone and see it in the Simulator (relaunch the Simulator app if it doesn't appear; it may not get push notifications). Then delete and reinstall the app on the iPhone: the data must come back from iCloud. Then test signed out of iCloud, and iCloud storage full.
  - [ ] Calendar allow / deny / revoke in Settings. Student falls back to the demo week.
  - [ ] Free app check: Settings has no Premium section, every widget works (including System Overview), and nothing anywhere offers a purchase.
  - [ ] Wellness: add and tick a habit, log a mood, then tick/log again from the Habits and Mood widgets; run a breathing session and check the Lock Screen Live Activity and the **expanded** Dynamic Island; turn on the evening mood reminder and check it skips a day you already logged.
  - [ ] Delete All Data, then relaunch. Pending class and mood reminders are cancelled too.
  - [ ] Record the NEEDS DEVICE numbers in `test-report.md` (memory, widget memory, battery drain).
- [ ] Product → Archive (Release) → **Generate Privacy Report** and compare with `privacy-audit.md`.
  - 2026-10-06: a local Release archive (signed, team X5348DDA36) holds exactly the manifests in `privacy-audit.md`: app = UserDefaults CA92.1/1C8F.1, DiskSpace 85F4.1/E174.1, FileTimestamp C617.1, SystemBootTime 35F9.1; widget = UserDefaults 1C8F.1, FileTimestamp C617.1; no tracking, no collected data, no embedded third-party frameworks. Still generate Xcode's report on the archive you upload.
- [x] Font licences (2026-10-06): all 11 bundled fonts have an `OFL-*.txt` next to them in `Packages/DesignSystem/Sources/DesignSystem/Resources/Fonts/`, which is copied into the bundle whole.
- [x] Privacy policy (2026-10-06): added the on-device sync log row and an "Exporting your data" section; effective date October 6, 2026. The repo copies in `docs/github-pages/` were behind the live site and now match it plus these edits.
- [x] Updated privacy page pushed to `mineprodan.github.io` (2026-10-06, commit 9bede41).
- [ ] Validate the archive, then Distribute → App Store Connect → Upload. This is the only upload; nothing goes to TestFlight testers.
  - Upload from the M5 MacBook Air (Xcode 27.0, iOS 27.0 SDK, since 2026-10-12). It already meets the expected ~April 2027 iOS 27 SDK requirement.

## 3. Submission

- [ ] Metadata from `metadata.md`, screenshots from `screenshot-plan.md`, review notes from `review-notes.md`.
  - [x] 6.9" (1320 × 2868) screenshots from a Release build in `screenshots/`: #2 Theme Sync and #4 theme decks (retaken 2026-10-06), #6 student week (sample and live), #7 Habits + Mood widgets (2026-10-13, iPhone 18 Pro Max Simulator), #9 class setup (intro, room, travel, heads-up).
  - [x] Metadata (2026-10-06): the description's PICK A VIBE block and the promo text (146/170) mention the ten theme decks, and both are saved in App Store Connect. Keywords, subtitle, support URL, copyright (2026) and review notes there already match the repo.
  - [ ] Upload screenshots to App Store Connect (1.0.0 → iPhone 6.9" display): none are uploaded yet. Drag in the files from `screenshots/` in the order of `screenshot-plan.md`.
  - [ ] **(owner, iPhone)** #1 themed home screen, #3 Lock Screen, #5 Tech tab (the Simulator has no battery reading), #8 breathing Live Activity, #10 Next Class with a leave time. Adding widgets crashed SpringBoard in the iOS 26 Simulator on the Intel Mac (Apple bug in `SBHRippleSimulation`). **It works in the iOS 27 Simulator on the M5 (2026-10-13)**, so #7 was taken there and the widget part of #1 can be too; #3, #5, #8 and #10 still need the device.
- [x] **Version Release: Manually release this version**, so you control the soft-launch timing. Set (checked 2026-10-06).
- [ ] **Phased Release for automatic updates: ON** (7-day rollout, can be paused). This is for updates; the first version goes to everyone in the chosen territories.

- [x] Submitted 1.0.0 (4) for review on 2026-10-24 (Waiting for Review).

## 4. Soft launch (~2 weeks)

- [x] Pricing and Availability: price **Free**; **Canada, Australia, New Zealand, Ireland only**. Set: $0.00, available only in CAN/AUS/NZL/IRL, new territories off (checked 2026-10-06).
- [ ] Release. Keep `flags.json` ready: if T-03 causes trouble, set `"T-03.cpuMemory": false`. No new build is needed.
- [ ] Watch the gates: **crash-free ≥ 99.5%** (Xcode Organizer / App Store Connect), **onboarding → first widget ≥ 55%**, **rating ≥ 4.5**.
  - **Decided 2026-09-30: use App Store Connect's opt-in App Analytics** (App Store Connect → Analytics: sessions, active devices, retention, crashes; only from users who share analytics with developers). There's no in-app analytics and no in-app toggle, so the privacy label stays "Data Not Collected". App Analytics can't see "first widget added", so judge that gate from day-1/day-7 retention and sessions per active device instead.

## 5. Full launch

- [ ] Gates met, then add US, UK and the other territories in Pricing and Availability.
- [ ] Custom Product Pages `/study`, `/aesthetic`, `/tech`.

## 6. Updates and hotfixes

- [ ] Tag the submitted build (`v1.0.0`) and run `scripts/sync-open-source.sh` if the public repo should match.
- [ ] Keep a `hotfix/x.y.z` branch from the released tag.
- [ ] Crash fix: ship with **Request Expedited Review**. Phased release stays on; pause it if the crash rate rises.
- [ ] If App Review objects to a flagged feature: switch the flag off in `flags.json` and resubmit the same build. Don't block the release.
