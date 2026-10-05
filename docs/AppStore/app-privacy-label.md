# App Privacy (nutrition label) answers

These are answers for App Store Connect → App Privacy, for the MVP build.

**Do you or your third-party partners collect data from this app?** → **No, we do not collect data from this app.**

The label will read **Data Not Collected**. Here's why that's accurate:

| Data | What happens | Collected? |
|---|---|---|
| Calendar events | Read on device (EventKit) to find classes. Only event IDs plus the user's own tags are stored, in the local store. Events are never uploaded | No |
| Photos | The user picks photos with PhotosPicker. Downsampled copies stay in the App Group on device | No |
| Courses, themes, reminder rules, widget settings | Synced through the user's **own iCloud private database** (CloudKit). We can't access it | No. Apple treats the user's private iCloud data as not collected by the developer |
| Battery, storage, CPU/RAM, thermal | Computed on device, shown on device | No |
| Purchases | None. The app is free and has no in-app purchases | No |
| Habits, mood check-ins and mood notes (Wellness) | Stored on the device and in the user's **own** iCloud private database (notes encrypted). We can't access them | No |
| Analytics | The `Analytics` facade has a no-op sink. MetricKit payloads are only logged locally (`os.Logger`) | No |
| Crash data | Only what Apple collects when the user opts in to share with developers. No SDK of ours | No |
| Remote flags | One anonymous GET of `flags.json` from our CDN. It sends no identifiers | No, as long as the CDN doesn't keep or link request logs (see below) |

**Tracking:** No. There's no ATT prompt, no IDFA, no ad SDKs and no data brokers.

## Re-answer this questionnaire if any of these change

- Analytics gets a real sink (any server). You'll likely need to declare *Usage Data → Product Interaction* and/or *Diagnostics*.
- Pinterest (Phase 2) ships. The OAuth token stays on device, but pin data comes from Pinterest's servers. Check whether we store anything server-side.
- A community gallery or any public CloudKit data ships (Phase 3 gate).
- The CDN host keeps access logs with IP addresses beyond short-term security use. Pick a host or setting that doesn't, or declare it.
