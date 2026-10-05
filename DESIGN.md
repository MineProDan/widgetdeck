---
name: Widgetdeck
description: One app for the whole home screen, where every widget is a paint chip in your theme.
colors:
  coral-hour: "#E07A5F"
  sage-noon: "#81B29A"
  beach-sand: "#F2CC8F"
  deep-tide: "#3D405B"
  plum-dusk: "#6D597A"
  paper-ivory: "#F7F3EA"
  label-ivory: "#FFFDF8"
  shell: "#F6DDB2"
  ink: "#22232E"
  ink-secondary: "#5B5D6B"
  ink-body: "#4A4C59"
  ink-inactive: "#6B6D7A"
  rule: "#E4DED1"
  clay-link: "#B2492F"
  moss-positive: "#4C7A62"
typography:
  display:
    fontFamily: "Bricolage Grotesque, -apple-system, sans-serif"
    fontSize: "40px"
    fontWeight: 700
    lineHeight: 1.05
    letterSpacing: "-0.02em"
  headline:
    fontFamily: "Bricolage Grotesque, -apple-system, sans-serif"
    fontSize: "28px"
    fontWeight: 700
    lineHeight: 1.05
    letterSpacing: "-0.02em"
  title:
    fontFamily: "Bricolage Grotesque, -apple-system, sans-serif"
    fontSize: "17px"
    fontWeight: 700
    lineHeight: 1.05
    letterSpacing: "-0.02em"
  body:
    fontFamily: "-apple-system, SF Pro Text, system-ui, sans-serif"
    fontSize: "15px"
    fontWeight: 400
    lineHeight: 1.4
  label:
    fontFamily: "Archivo, sans-serif"
    fontSize: "11px"
    fontWeight: 700
    lineHeight: 1.25
    letterSpacing: "0.08em"
    fontVariation: "'wdth' 75"
rounded:
  swatch: "8px"
  chip: "14px"
  card: "16px"
  widget: "22px"
  pill: "22px"
spacing:
  xs: "6px"
  sm: "10px"
  md: "14px"
  gutter: "24px"
components:
  button-primary:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.label-ivory}"
    rounded: "{rounded.chip}"
    height: "54px"
  button-pill:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.label-ivory}"
    rounded: "{rounded.pill}"
    height: "44px"
    padding: "0 16px"
  chip-label-band:
    backgroundColor: "{colors.label-ivory}"
    textColor: "{colors.ink}"
    padding: "10px 14px"
  chip-student:
    backgroundColor: "{colors.coral-hour}"
    rounded: "{rounded.widget}"
  chip-wellness:
    backgroundColor: "{colors.sage-noon}"
    rounded: "{rounded.widget}"
  chip-aesthetic:
    backgroundColor: "{colors.beach-sand}"
    rounded: "{rounded.widget}"
  chip-tech:
    backgroundColor: "{colors.deep-tide}"
    rounded: "{rounded.widget}"
  chip-evening:
    backgroundColor: "{colors.plum-dusk}"
    rounded: "{rounded.widget}"
  segmented-control:
    backgroundColor: "#ECE6DA"
    rounded: "10px"
    height: "36px"
  tab-bar:
    backgroundColor: "{colors.paper-ivory}"
    textColor: "{colors.ink-inactive}"
    height: "83px"
---

# Design System: Widgetdeck

## Overview

**Creative North Star: "The Paint Chip Deck"**

Every widget is a paint chip from a hardware-store swatch deck: a flat, matte field of colour with a punched hole, over an ivory label band that names it like a paint ("Coral Hour · WG 0914"). The app is the fan deck you shuffle through, and the home screen is the wall you've painted. The system is warm, tactile and confident. The colour does the talking and the type stays calm and exact. It deliberately rejects the category's grid of rounded, glassy, gradient widget tiles.

Density is widget-honest. A chip answers one question at a glance, then gives one line of context. Flow widgets, study timers and streak strips all use the same anatomy, so a user who has read one chip can read every chip.

**Key Characteristics:**
- Chip anatomy: a colour field on top or left, an ivory label band holding all text, and a punch hole at the top-left.
- Each section keeps its colour everywhere: Student coral, Wellness sage, Aesthetic sand, Tech ink, plus plum for evening and mood.
- Hierarchy comes from weight and case: condensed caps labels against grotesk display numerals.
- Warm paper ground, flat fields, soft offset shadows. No glass, no gradients.

## Colors

Four named section colours and one evening colour, all matte and mid-saturation, sitting on warm paper.

### Primary
- **Coral Hour** (#E07A5F): Student and "next up" moments. Class chips, the Flow widget before class, focus timers and Live Activities.

### Secondary
- **Sage Noon** (#81B29A): Wellness habits, midday Flow, positive completion fields.
- **Beach Sand** (#F2CC8F): Aesthetic and theme surfaces, the morning Flow, the battery fill on ink.

### Tertiary
- **Deep Tide** (#3D405B): Tech chips, afternoon focus, and heavier academic blocks (CHEM).
- **Plum Dusk** (#6D597A): Evening and mood only. Mood logging, breathing, the 21:00 Flow. Its tints (#A99BB3 → #6D597A) encode the mood scale.

### Neutral
- **Paper Ivory** (#F7F3EA): the app ground and the punch-hole fill.
- **Label Ivory** (#FFFDF8): chip label bands and card surfaces.
- **Shell** (#F6DDB2): quiet data fills on ink (the memory bar) and palette surfaces.
- **Ink** (#22232E): primary text, primary buttons, active tab.
- **Ink Secondary** (#5B5D6B): caps labels. **Ink Body** (#4A4C59): subtitles and body. **Ink Inactive** (#6B6D7A): inactive tabs and axis labels.
- **Rule** (#E4DED1): hairlines, the tab-bar top border, grid lines.
- **Clay Link** (#B2492F): links, urgent caps (a due date or "leave now"), the "now" line. **Moss Positive** (#4C7A62): streaks and positive trends.

### Named Rules
**The Colour Is Law Rule.** A section's colour means that section everywhere: widgets, class blocks, list chips, Live Activities. Never use coral for a wellness element or sage for a class.

**The Pure Field Rule.** Text never sits on a colour field. The field holds only geometry: the punch hole, a fill bar, a drawn glyph or a control. Every word lives on the ivory label band.

**The Theme Stays in the Theme Rule.** User-theme hues (Chrome Lilac, Library Oak and so on) appear only in theme pickers and user-themed widgets, never in system chrome.

## Typography

**Display Font:** Bricolage Grotesque (fallback: -apple-system)
**Body Font:** SF Pro via -apple-system (native iOS body)
**Label Font:** Archivo, condensed (width 75), uppercase

**Character:** A friendly, slightly quirky grotesk carries names and numbers like paint names on a chip. Condensed caps do the cataloguing, and SF handles the reading.

### Hierarchy
- **Display** (700, 40px, 1.05): screen titles (Today, Schedule, Wellness).
- **Headline** (700, 22–34px, 1.05): key values inside chips (14 min, 82%, 18:20), with tabular numerals.
- **Title** (700, 15–18px, 1.05): chip and list item names.
- **Body** (400, 15–16px, 1.4): subtitles and explanations. Maximum measure is about 320px on a phone.
- **Label** (700, 9–11px, +0.08em, uppercase, condensed): paint codes, categories, context lines and trends.

### Named Rules
**The Two Sizes Rule.** A chip uses at most two type sizes: one label size and one display size. Rank inside a chip comes from weight, case and colour, never a third size.

**The Plain Subtitle Rule.** No caps labels sit above screen titles. Context goes in a plain body subtitle below the title.

## Layout

Native iPhone structure: 390pt width, a 24px side gutter, a large title at the top, and a 5-item tab bar (83px) at the bottom. Content stacks in chip rows with 10–14px gaps within a group and about 24px between groups. Home-screen widgets follow the iOS grid exactly: medium 338×158, small 158×158, with 22px gaps. Section headers are a caps label on the left with an optional link on the right. The **fan deck** layout (chips rotated about a shared pivot below the row, overlapping, front chip on top) is the system's signature arrangement for sets of chips (onboarding themes, "on your home screen").

## Elevation & Depth

Surfaces are flat and matte. Depth comes from paper-like offset shadows: a card rests on the paper and doesn't glow. Every chip carries a hairline contact shadow plus one soft drop shadow offset downward.

### Shadow Vocabulary
- **Chip rest** (`box-shadow: 0 1px 2px rgba(34,35,46,.08), 0 10px 22px -12px rgba(34,35,46,.4)`): chips and cards in the app.
- **Widget on wallpaper** (`box-shadow: 0 12px 30px -14px rgba(34,35,46,.45)`): widgets over the home-screen wallpaper.
- **Lifted chip** (`… 0 14px 30px -12px rgba(34,35,46,.55)` plus translateY -34px): the selected chip in a fan.

### Named Rules
**The Paper Rule.** No glass, blur or glow. Materials are flat paint on paper, and system materials appear only where iOS itself draws them.

## Shapes

Softly rounded rectangles: chips 14px, large cards 16px, widgets 22px (matching iOS), swatches 8px, and pills only for small actions (44px tall, radius 22px). The **punch hole** (a 9–12px ivory circle 9–14px in from the top-left of the colour field) is the one recurring silhouette, and it marks every chip. Progress is drawn as flat rounded bars (6–14px tall) in a colour field, not as rings, except where iOS draws gauges natively (lock screen circular accessories).

## Components

### Buttons
- **Shape:** rounded 14px for full-width actions, 22px pill for inline actions.
- **Primary:** ink fill with ivory 17px semibold text, 54px tall, full width ("Use Soft Coral", "Apply to 6 widgets").
- **Pill:** ink fill, 44px tall, 16–18px horizontal padding ("Add", "Start").
- **Focus:** a 2px ink outline, offset 3px.

### Chips (the signature component)
- **Anatomy:** colour field (top or left) → ivory label band. The band holds a caps label (paint name, context or code), then a display value or name, then an optional caps trend or urgency line.
- **Controls on colour:** interactive checks and mood keys may sit on the field as ivory rings or keys (at least 38–44px).
- **Variants:** vertical (small widget, deck chip), horizontal (medium widget, list row, Live Activity), and the paint strip (4 stacked steps, onboarding).

### Cards / Containers
- **Corner Style:** 16px. **Background:** Label Ivory. **Shadow:** Chip rest. **Border:** none. **Padding:** 12–18px.

### Navigation
- **Tab bar:** Paper Ivory with a 1px Rule top border. Stroke icons (1.9px) over 10px condensed caps labels; the active tab is Ink and inactive tabs are Ink Inactive.
- **Segmented control:** a #ECE6DA track with the selected segment in Label Ivory and a light shadow, 13px labels.

### Live Activity / Dynamic Island
A horizontal chip on the lock screen (coral field with a progress bar, ivory band with the timer). In the Island it's a black capsule where the section colour carries the timer digits and a small chip mark with a black punch hole.

## Do's and Don'ts

### Do:
- **Do** give every chip a punch hole and keep every word on the label band.
- **Do** use each section's colour for that section only, and plum only for evening and mood.
- **Do** set values in Bricolage Grotesque with tabular numerals, and categories in condensed Archivo caps (11px, +0.08em).
- **Do** use the fan deck when showing a set of chips together.
- **Do** label estimates honestly ("Est. 1h 10m to full").

### Don't:
- **Don't** put text on a colour field.
- **Don't** use more than two type sizes in one chip.
- **Don't** put caps labels above screen titles; use a plain subtitle below.
- **Don't** use glass, gradients, glow or hard zero-blur shadows.
- **Don't** use coloured left-border stripes for list rows. Use a chip with a real colour block.
