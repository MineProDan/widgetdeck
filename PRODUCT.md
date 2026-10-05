# Product

<!-- impeccable:product-schema 1 -->

## Platform

ios

## Users
Primary: students and aesthetic-minded young people (roughly 16–30) who want a home screen that is both beautiful and useful. They currently cobble together a widget designer, a planner, a habit tracker and a battery widget whose styles clash. Their job: see what's next (class, deadline, habit) at a glance, and have a phone that "looks like me".
Secondary: tech enthusiasts (honest system dashboard) and wellness users (one-tap habits, mood, breathing).
Launch hero persona: Student × Aesthetic (confirmed 2026-09-26). Personas: `docs/plan/13-user-personas.md`.

## Product Purpose
One app that runs the whole home screen: themed widgets across four sections (Student, Aesthetic, Wellness, Tech) under one theme. Success means users keep at least one widget on their home screen and act from it daily (north star: weekly widget-active users).

## Positioning
Four apps in one (Tech, Student, Aesthetic and Wellness all ship in 1.0), **completely free**: no purchases, no subscriptions, no ads. It's a non-commercial hobby project with no revenue, now or later. The mechanism a neighbor can't honestly copy: one theme model spans live personal data across four domains. That powers the Flow widget (context that changes through the day), Theme Sync (every widget restyles from a wallpaper the user picks) and shareable setup codes.

## Operating Context
- Mostly used *through* widgets (home screen, lock screen, Dynamic Island/Live Activities, StandBy). The app itself is for setup, planning and streaks.
- Daily rhythm: morning class countdown, midday habits, afternoon deadlines and focus, evening mood check-in.
- Growth is organic: TikTok home-screen tours, Reddit r/iOSsetups, share cards.

## Capabilities and Constraints
- Native SwiftUI, iOS 17+ minimum, built with Xcode 26.3 / iOS 26.2 SDK. Interactive widgets, Live Activities.
- Widgets refresh on a system budget and are never real-time. Countdowns tick through self-updating text.
- No GPU, battery health, active-apps or per-category storage data. Apps can't read the wallpaper; the user picks it from Photos.
- No true widget transparency: it is simulated by cropping a user-provided screenshot.
- Pinterest is limited to the user's own boards. Curated/licensed content is primary.
- Everything is free: every widget and theme, no limits.
- App name: **Widgetdeck**, reserved in App Store Connect on 2026-09-27. "Widgeter" was already taken on the App Store and "TechFlow" was rejected. Trademark check still recommended.

## Brand Commitments
Nothing fixed yet: no logo, palette, type or voice. Name placeholder "Widgetdeck". Voice principle from the plan: honest (free means free: nothing locked; estimates labelled as estimates).

## Evidence on Hand
No users, testimonials, press or real screenshots yet. Don't fabricate ratings, download counts or reviews. The plan lives in `docs/plan/`.

## Product Principles
1. Beautiful *and* useful: every surface should pass "would someone screenshot this?" and "did it save a tap?".
2. The home screen is the product; the app exists to set it up.
3. One theme rules everything.
4. Honest by default: no fake stats, no promised real-time, no paywalls (the app is free).
5. Private by default: on-device and iCloud only, and the lock screen hides sensitive data.

## Accessibility & Inclusion
WCAG 2.1 AA: contrast enforced in the theme editor, Dynamic Type up to AX5 in-app, VoiceOver labels on every widget, and Reduce Motion/Transparency honored.
