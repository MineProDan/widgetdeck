# App Store metadata (US English, MVP)

Based on `docs/plan/08-go-to-market.md` §2.1 and cut down to what version 1.0 actually ships: **Tech, Student, Aesthetic and Wellness** (decided 2026-09-30: launch with Wellness). Guideline 2.3.1 says metadata must not advertise features the build doesn't have. Assignments, grades/GPA, focus timers and leave-by travel times are built and in 1.0 (2026-10-01); Pinterest, the curated feed and transparent widgets are not, so they stay out. The ten theme decks (2026-10-06) are in 1.0.

| Field (limit) | Value | Length |
|---|---|---|
| **Name (30)** | `Widgetdeck: Aesthetic Widgets` | 29 |
| **Subtitle (30)** | `Class Schedule, Themes & Stats` | 30 |
| **Keywords (100)** | `home screen,theme,schedule,class,student,wallpaper,habit,mood,gpa,pomodoro,battery,calendar,planner` | 99 |
| **Promotional text (170)** | `Ten looks, from Old Library to Pocket Arcade, and every widget follows yours. Next class and when to leave, habits, mood, battery and your photos.` | 146 |
| **Category** | Primary: Productivity · Secondary: Lifestyle | |
| **Age rating** | 9+ because "Health or Wellness Topics" = Yes (habits, mood, breathing); everything else None/No (no user-generated content, no web browsing, no mature themes) | |
| **Price** | **Free. No in-app purchases** | |
| **Copyright** | `2026 Daniel Radu Betiu` | |
| **Support URL** | `https://mineprodan.github.io/support/` (source: `docs/github-pages/support/`) | |
| **Privacy Policy URL** | `https://mineprodan.github.io/privacy/` (source: `docs/github-pages/privacy/`) | |

Title words ("Aesthetic", "Widgets") aren't repeated in the keywords, since the name is already indexed. Keywords use commas with no spaces.

`gpa,pomodoro` replaced `palette,photo` (2026-10-04) now that grades and focus timers ship; `storage` was dropped earlier to fit `habit,mood`. Put the extra UK/MX-locale keywords (`aesthetic,kawaii,y2k,dark academia,system monitor,cpu,...`) in those locales' fields.

## Description (draft, 4000 max)

```
One app for your whole home screen: widgets that look good and are actually useful.

PICK A VIBE
Choose one of ten theme decks, from Old Library and Matcha Café to Pocket Arcade and Lo-fi Study, each with its own colors, fonts and shapes. The app and every Widgetdeck widget follow it. Or use Theme Sync: pick your wallpaper photo and Widgetdeck builds a matching palette, checked for readable contrast.

STUDENT
• Next Class and Today's Schedule widgets, built from the calendars you choose
• Set up each class in seconds: the room you actually call it, how you get there, and the heads-up you want
• "Leave by" times on the Next Class widget, estimated from Apple Maps travel time or set by you
• Countdowns that stay current on your home and lock screen
• Class reminders 15 minutes to 1 day before, and optional leave-by alerts
• Assignments with due-date reminders (import from Reminders if you like)
• Grades and GPA, plus what you need on the final
• Focus timers with a countdown on your Lock Screen and in the Dynamic Island
Widgetdeck only reads your calendar. It never changes or uploads your events.

AESTHETIC
• Photo widget: rotate the photos you pick, hourly or daily
• Mood board widget: a grid of your favourite photos
• Palette widget: your current theme's colors on your home screen
• Theme Sync: match widgets to your wallpaper

WELLNESS
• Habits with streaks: tick them off right from the widget
• Mood check-ins with a two-week view, logged from a widget in one tap
• Box and 4-7-8 breathing, with a timer on your Lock Screen and in the Dynamic Island
• A daily quote and affirmation
Widgetdeck is for everyday wellness. It isn't medical advice.

TECH
• Battery level and charging state, with an estimated time to full
• Storage: total, used and free
• Thermal state, plus CPU and memory while the app is open

PRIVATE BY DESIGN
No ads. No tracking. No account. Your data stays on your iPhone and in your own iCloud.

COMPLETELY FREE
Every widget, theme and feature is free. No subscriptions, no in-app purchases, nothing locked.

Privacy Policy: https://mineprodan.github.io/privacy/
```

Widget refresh wording is deliberately modest ("stay current", "while the app is open"). Per the Platform Reality Rules, never say "real-time" or "live" about widgets.

**The app is 100% free** (the app is free). Don't mention Premium, prices, trials or purchases anywhere in the listing.
