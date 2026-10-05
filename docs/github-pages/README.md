# GitHub Pages site for Widgetdeck

Contents of the `mineprodan.github.io` repository: the flags file the app reads, plus the privacy
policy and support pages App Store Connect needs. Keep this folder as the source of truth and copy
it to that repo when it changes.

| File | Public URL | Used by |
|---|---|---|
| `flags.json` | https://mineprodan.github.io/flags.json | `CoreKit/Support/RemoteFlags.swift` (`remoteURL`) |
| `privacy/index.html` | https://mineprodan.github.io/privacy/ | App Store Connect → App Privacy → Privacy Policy URL |
| `support/index.html` | https://mineprodan.github.io/support/ | App Store Connect → Support URL |
| `index.html`, `style.css` | https://mineprodan.github.io/ | Landing page (Marketing URL, optional) |
| `.nojekyll` | none | Tells GitHub Pages to serve files as-is |

## Owner details (filled 2026-09-29)

Developer Daniel Radu Betiu · contact mineprodan@gmail.com · reply within 2 hours · policy effective
September 29, 2026. Update the effective date in `privacy/index.html` whenever the policy changes.

## Publish (one time)

1. On github.com, create a **public** repository named exactly `mineprodan.github.io`.
2. Upload everything in this folder (including `.nojekyll`) to the repo root, keeping the
   `privacy/` and `support/` folders.
3. Repo **Settings → Pages**: Source = "Deploy from a branch", branch `main`, folder `/ (root)`.
4. Wait a few minutes, then open https://mineprodan.github.io/flags.json. It should show
   `{"T-03.cpuMemory": true}`.

## Switching a feature off (e.g. if App Review objects to CPU/memory)

Edit `flags.json` in the repo on github.com, change `true` to `false`, commit. It's live within
about 1–10 minutes; each iPhone picks it up next time Widgetdeck opens or refreshes in the background.
Keep the file valid JSON (the app ignores a broken file and keeps its last good values).
