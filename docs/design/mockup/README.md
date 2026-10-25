# Widgetdeck Paint Chip mockup (visual source of truth)

The approved mockup. **Built UI must match it identically**: same layout, colours, type, spacing, radii, shadows and copy style. `DESIGN.md` has the rules and tokens, and this folder holds the exact screens.

| File | What it is |
|---|---|
| `screens/*.png` | 2× renders of each artboard (390×844 pt phone frames, captured at 780×1688 px) |
| `source/*.dc.html` | The artboard sources. **Read these for exact numbers**: every position, size, colour, radius, shadow and font size is written inline |

## How to translate the source to SwiftUI

- **1 CSS px = 1 pt.** The phone artboards are 390×844 pt (iPhone 14/15/16 logical size).
- `.nm` class = **Bricolage Grotesque Bold**, letter-spacing −0.02em, line-height 1.05.
- `.cap` class = **Archivo Condensed Bold** (width 75), 11 pt unless overridden, letter-spacing +0.08em, uppercase.
- Body text (no class) = SF Pro (system font).
- `.num` = tabular numerals (`.monospacedDigit()`).
- `box-shadow: 0 1px 2px A, 0 Y B -S C` = two shadows: a hairline contact shadow plus a soft drop (the `DESIGN.md` Elevation section maps each one).
- `border-radius` → `RoundedRectangle(cornerRadius:, style: .continuous)`.
- Absolute `top/left` values are the layout. Reproduce the spacing, but lay screens out with stacks, not absolute positioning, so Dynamic Type still works.
- Everything in `renderVals()` (names, classes, numbers) is **sample data**. Use it for previews only.
- The canvas-only artefacts (no status bar, flat SVG wallpaper) are presentation. Real screens use the iOS status bar and safe areas.

## Screen map

| Artboard | Screen / component | Built by |
|---|---|---|
| `Main` | Onboarding: "Pick your vibe" fan of paint strips | Integration (P-06) |
| `Home` | Home tab: Flow hero chip, fan deck "On your home screen", suggestion chip | Integration / shared |
| `HomeScreen` | **Widgets on the home screen**: Flow (medium), Habits, Battery, Palette, Mood (small), and the app icon | Each feature: its own widgets |
| `FlowDay` | Flow widget at 5 times of day | Phase 2 (P-11) |
| `ThemeSync` | Aesthetic tab: Theme Sync palette and before/after | AestheticFeature |
| `Student` | Student tab: week grid and Due soon chips | StudentFeature |
| `Wellness` | Wellness tab: habit chips, mood strip, breathe chip | WellnessFeature |
| `Tech` | Tech tab: 4 metric chips, thermal strip, device chip | TechFeature |
| `LockScreen` | Lock-screen accessories, Live Activity chip, Dynamic Island states | Student (S-08) / Wellness (W-04) |

The tab bar (5 tabs with stroke icons and 10 pt condensed caps labels) and the page header (40 pt Bricolage title plus a 15 pt subtitle) are identical on every tab. Build them once in the app shell.
