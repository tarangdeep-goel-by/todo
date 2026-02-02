# VOKL — Maximalist Voice-First Todo App

## Design Brief v2 (Bolder)

---

## Identity

**What it is**: A speech-first, AI-native task manager with a nested tree structure. You push, you talk, it organizes. No typing, no tapping through forms.

**Who it's for**: Designers and high-agency creatives who are repulsed by bland productivity tools. People who use Things 3 but wish it had personality. People who think Notion is mid.

**What makes it unforgettable**: Every pixel has opinion. The app feels like an instrument, not a spreadsheet. Scrolling through your tasks feels like browsing a physical art installation — things grow, shrink, pulse, and breathe.

**The one-liner**: "Your todo list, but it moves."

---

## Personality

| Mode | Vibe | Reference |
|------|------|-----------|
| Light | Controlled chaos — Memphis Design meets Swiss precision. Saturated colors on warm off-white. Shapes feel physical, almost paper-like. | Karl Gerstner + Camille Walala |
| Dark | Cinematic intensity — deep blacks with vivid color eruptions. Things glow from within, not on top. | Blade Runner UI + James Turrell light art |
| Both | Playful energy in micro-interactions — things overshoot, settle, breathe. Not bouncy (cheap). Exponential easing with character. | |

---

## Data Architecture

```
Root (max 5 parent nodes)
├── Work (default)                    ← "Domain"
│   ├── Ship landing page             ← Level 1 task
│   │   ├── Write copy                ← Level 2
│   │   │   └── Hero section          ← Level 3
│   │   └── Design mockups
│   └── Client call prep
├── Personal (default)                ← "Domain"
│   └── ...
├── [User-defined domain]
├── [User-defined domain]
└── [User-defined domain]
```

- Max 5 root-level domains (2 defaults + 3 user-created)
- Tasks nest infinitely, practically ~4-5 levels deep
- Each domain has a permanent color identity that cascades everywhere

---

## Typography

### Font Stack: Bricolage Grotesque + DM Sans + Space Mono

**Why Bricolage Grotesque**: Variable width axis (75-100) + weight (200-800) + optical size. This font *shapeshifts*. Compressed at small sizes, expanded and architectural at display sizes. The name literally means "DIY construction" — perfect for a task app. It is NOT generic.

**Why DM Sans**: Pairs with Bricolage's geometry without competing. Full weight range (100-900). Legible at 11px. Has warmth.

**Why Space Mono**: Designed by Colophon Foundry for expressive, not utilitarian purposes. Retro-futuristic. Used for timestamps, metadata, counts — things that should feel like data readouts, not afterthoughts.

### Scale (base: 16px / 1rem)

| Role | Font | Size | Weight | Width | Usage |
|------|------|------|--------|-------|-------|
| Domain title (focused) | Bricolage Grotesque | 56-72px | 800 | 75 (condensed) | Focused domain card |
| Domain title (compressed) | Bricolage Grotesque | 24-28px | 600 | 85 | Unfocused domain cards |
| Task title (focused) | Bricolage Grotesque | 28-32px | 700 | 90 | Focused list item |
| Task title (default) | Bricolage Grotesque | 18-20px | 500 | 95 | Default list items |
| Body / descriptions | DM Sans | 15-16px | 400 | — | Subtasks, descriptions |
| Metadata | Space Mono | 11-12px | 400 | — | Timestamps, due dates, counts |
| Domain pill label | DM Sans | 11px | 600 | — | Category tags in flat view |
| CTA label | DM Sans | 14px | 500 | — | Push-to-talk idle label |

**Key rule**: 3-5x size jumps between hierarchy levels, not 1.5x. The focused domain title at 72px next to metadata at 11px creates *violent* hierarchy. This is intentional.

---

## Color System

### Philosophy

No purple-to-blue gradients. No cyan-on-dark neon. No generic "productivity app" palette.

Each domain owns a color world — a primary, a darker shade, a tinted surface, and a text color. These are not pastels. They are *saturated, opinionated, almost aggressive* — but they work together because they share the same OKLCH lightness/chroma relationships.

### The 5 Domain Palettes

All colors defined in OKLCH for perceptual uniformity. Hex approximations shown.

#### Light Mode

| Domain | Primary | Dark shade | Surface (10% tint on `#F5F0EB`) | Text on primary |
|--------|---------|------------|----------------------------------|-----------------|
| **Work** | `oklch(65% 0.22 30)` → `#D94A1A` (burnt vermillion) | `oklch(45% 0.18 30)` → `#8B2E0E` | `oklch(95% 0.03 30)` → `#FBF0EB` | `#FFF8F5` |
| **Personal** | `oklch(55% 0.24 300)` → `#8B2FC4` (electric purple) | `oklch(38% 0.20 300)` → `#5A1A82` | `oklch(95% 0.03 300)` → `#F5EEFA` | `#FBF5FF` |
| **Domain 3** | `oklch(72% 0.18 165)` → `#1AAD7A` (jade) | `oklch(48% 0.15 165)` → `#0D7050` | `oklch(95% 0.03 165)` → `#ECF9F3` | `#F0FFF8` |
| **Domain 4** | `oklch(68% 0.20 60)` → `#C88A1A` (deep amber) | `oklch(45% 0.17 60)` → `#825A0D` | `oklch(95% 0.03 60)` → `#FBF5E8` | `#FFFBF0` |
| **Domain 5** | `oklch(62% 0.22 350)` → `#CC3068` (crimson rose) | `oklch(42% 0.19 350)` → `#8A1A45` | `oklch(95% 0.03 350)` → `#FBECF1` | `#FFF5F8` |

**Light mode background**: `#F5F0EB` (warm parchment, NOT pure white)
**Light mode text**: `#1A1614` (warm near-black)

#### Dark Mode

| Domain | Primary (brighter for dark bg) | Glow color (20% opacity) | Surface (5% tint on `#0D0B09`) | Text on primary |
|--------|-------------------------------|--------------------------|--------------------------------|-----------------|
| **Work** | `oklch(72% 0.22 30)` → `#F06030` | `#F0603020` | `oklch(15% 0.04 30)` → `#1F1410` | `#0D0B09` |
| **Personal** | `oklch(68% 0.24 300)` → `#B050E8` | `#B050E820` | `oklch(15% 0.04 300)` → `#18101F` | `#0D0B09` |
| **Domain 3** | `oklch(78% 0.18 165)` → `#30D89A` | `#30D89A20` | `oklch(15% 0.04 165)` → `#0D1A15` | `#0D0B09` |
| **Domain 4** | `oklch(75% 0.20 60)` → `#E8A830` | `#E8A83020` | `oklch(15% 0.04 60)` → `#1A1508` | `#0D0B09` |
| **Domain 5** | `oklch(70% 0.22 350)` → `#E84878` | `#E8487820` | `oklch(15% 0.04 350)` → `#1F0D14` | `#0D0B09` |

**Dark mode background**: `#0D0B09` (warm near-black, NOT pure `#000`)
**Dark mode text**: `#F0EBE5` (warm off-white)

### Color Rules

1. **No gradients on the domains themselves** — solid, confident color. Gradients only for the voice waveform and view transitions.
2. **Tinted neutrals everywhere** — gray text gets a hint of the nearest domain's hue. Gray on colored backgrounds is forbidden.
3. **Glow, not neon** — in dark mode, colors radiate softly (box-shadow / blur at 20% opacity), they don't sit on top as harsh neon.
4. **The background itself is warm** — `#F5F0EB` light, `#0D0B09` dark. This subtle warmth prevents the "corporate SaaS" feel.

---

## Home Screen: Parent Node View (Default)

### The Concept: Liquid Focus

The screen is a vertical stack of domain cards. The card in focus is *massive*. Everything else is compressed. As you scroll, focus shifts fluidly — cards inflate and deflate like breathing.

### Layout Math

**Viewport**: Full screen minus top bar (48px) minus bottom CTA zone (100px). Call this `Hv`.

| # Domains | Focused card | Each unfocused card |
|-----------|-------------|-------------------|
| 2 | `0.72 * Hv` | `0.28 * Hv` |
| 3 | `0.60 * Hv` | `0.20 * Hv` |
| 4 | `0.55 * Hv` | `0.15 * Hv` |
| 5 | `0.48 * Hv` | `0.13 * Hv` |

### Focus Transition Curve

As a card's center approaches the viewport center, its height interpolates using:

```
focusFactor = 1.0 - (distanceFromCenter / (Hv * 0.5)).clamp(0.0, 1.0)
cardHeight = minHeight + (maxHeight - minHeight) * Curves.easeOutQuint(focusFactor)
```

`easeOutQuint` — not linear, not bounce. Smooth exponential deceleration. Things *settle* into focus.

### Focused Card Anatomy

```
┌──────────────────────────────────────────────────────┐
│                                                      │
│                                                      │
│  WORK                          ← Bricolage 800, 72px│
│                                   condensed width 75 │
│                                                      │
│  12 tasks · 3 due today        ← Space Mono 11px    │
│                                                      │
│  ┌─ Ship landing page                                │
│  ├─ Client call prep           ← DM Sans 16px       │
│  ├─ Review PRs                    top 4 tasks shown  │
│  └─ Budget review                 with subtle indent │
│                                                      │
│                                                      │
└──────────────────────────────────────────────────────┘
```

- **Background**: Domain's primary color, full saturation
- **Text**: Light text on the color (`text on primary` from palette)
- **Task preview**: 3-4 most recent/urgent tasks, single line each, slightly translucent (80% opacity)
- **No border radius on focused card** — it bleeds edge-to-edge horizontally with only 2px margin. This is a *statement*, not a card in a container.
- **Subtle grain texture overlay** (light mode only) — 2% opacity noise. Adds physicality.

### Compressed Card Anatomy

```
┌──────────────────────────────────────────────────────┐
│  Personal                    8 tasks    ← one line   │
└──────────────────────────────────────────────────────┘
```

- **Background**: Domain's surface color (tinted, low opacity)
- **Text**: Domain's primary color
- **Height**: Just enough for one line + padding
- **Left accent**: 4px solid bar in domain's primary color
- **Corner radius**: 0px top/bottom, 0px left (bleeds), 16px right — asymmetric. Not a generic rounded rect.

### Scroll Behavior

- Scroll is continuous, not snapped (snap feels like pagination, we want fluidity)
- Haptic feedback: light tap (`HapticFeedback.lightImpact()`) when a new card enters the focus threshold (>60% focus factor)
- The top bar shows the currently-focused domain name in small text, updating as focus shifts — like a section indicator
- Overscroll at top/bottom: rubber-band with domain color tinting the overscroll glow

---

## Home Screen: Flat All-Tasks View

### The Concept: A River of Tasks

All tasks from all domains, flattened and sorted. But this is NOT a boring list. It's a **focus river** — items flow upward as you scroll, expanding as they enter the spotlight and compressing as they pass.

### Sort Order (Default)

`Priority (if set) → Due date (if set, ascending) → Created date (descending)`

User can change sort via a small control in the empty header zone.

### Spatial Rules

```
┌──────────────────────────────────────────┐  ← Top of screen
│                                          │
│          47 tasks across 3 domains       │  ← 20% empty zone
│          sorted by priority              │     Muted text, centered
│                                          │     Sparse, breathing room
├──────────────────────────────────────────┤
│                                          │
│  ████████████████████████████████████    │  ← First item: 10% Hv
│  ██  Ship landing page              ██   │     Slightly elevated
│  ██  Work · Due Feb 3 · P1          ██   │     Full detail shown
│  ████████████████████████████████████    │
│                                          │
│  ┌─ Client call prep ─── Work ──────┐   │  ← Next items: 7% Hv
│  └──────────────────────────────────┘   │
│  ┌─ Grocery run ──── Personal ──────┐   │  ← Progressively smaller
│  └──────────────────────────────────┘   │
│  ┌─ Review PRs ──── Work ──────────┐   │  ← 6% Hv toward edges
│  └──────────────────────────────────┘   │
│                                          │
└──────────────────────────────────────────┘
```

### Focus Scaling Formula

```
distanceFromFocusPoint = (itemCenter - viewportCenter).abs()
normalizedDistance = (distanceFromFocusPoint / (Hv * 0.4)).clamp(0.0, 1.0)
scaleFactor = 1.0 - (0.35 * Curves.easeInQuad(normalizedDistance))

// Item height
focusedHeight = 0.10 * Hv   // ~10% of viewport
minHeight = 0.055 * Hv       // ~5.5% of viewport
itemHeight = minHeight + (focusedHeight - minHeight) * (1.0 - normalizedDistance)
```

Items also get:
- **Opacity**: 1.0 at focus → 0.65 at edges
- **Horizontal inset**: 16px at focus → 32px at edges (items physically narrow as they recede)
- **Typography scale**: Task title interpolates between 28px (focus) and 16px (edge)

### List Item Design

```
┌────────────────────────────────────────────────────┐
│ ▊                                                   │ ← 6px left bar
│ ▊  Ship landing page                                │    (domain color)
│ ▊                                                   │
│ ▊  ┌────────┐                                       │
│ ▊  │  Work  │  Added Jan 28  ·  Due Feb 3  ·  P1   │ ← metadata row
│ ▊  └────────┘                                       │    Space Mono 11px
│ ▊    (pill)                                         │
└────────────────────────────────────────────────────┘
```

- **Left bar**: 6px wide, domain's primary color, full height of card, sharp corners
- **Background**: domain's surface tint at 40% opacity (enough to color-code at a glance)
- **Domain pill**: Rounded pill, domain primary color background, white/dark text. Small (11px DM Sans 600).
- **Metadata**: Space Mono 11px. "Added" always shown. "Due" and priority only if set. Separated by centered dots (`·`).
- **Priority indicators**: Not colored dots. Instead: `P1` `P2` `P3` `P4` in Space Mono, where P1 gets the domain's dark shade color and others are muted. Text-only, no icons.
- **No icons anywhere in list items.** Text and color do all the work.
- **Card corners**: 0px left (bleeds into the color bar), 12px right — asymmetric, matching the compressed domain cards above.

---

## Push-to-Talk CTA

### The Concept: The Instrument

This is the primary interaction point. It should feel like pressing a key on an instrument — satisfying, physical, and alive.

### Idle State

```
        ┌─────────────────────────┐
        │    ◉  Hold to speak     │      ← Oval pill
        └─────────────────────────┘
              bottom center
```

- **Shape**: Rounded pill, `56px` tall, `180px` wide
- **Background**:
  - Light mode: `#1A1614` (warm near-black on warm parchment bg)
  - Dark mode: `#F0EBE5` (warm off-white on dark bg)
- **Icon**: Small mic dot (8px circle), not a full mic icon. Minimal.
- **Label**: "Hold to speak" in DM Sans 14px 500
- **Shadow**: Large, soft — `0 8px 32px rgba(0,0,0,0.15)` in light, `0 8px 32px rgba(240,235,229,0.08)` in dark
- **Position**: Centered horizontally, `32px` above safe area bottom
- **Z-index**: Above everything. Always visible.

### Active / Recording State

When the user presses and holds:

1. **Pill expands**: Animates from `180×56` to `280×72` over 200ms (`easeOutQuint`)
2. **Color shift**: Background transitions to the *most recently focused domain's primary color* — so if you were looking at Work (burnt vermillion), the button becomes vermillion. This contextual color is a designer's detail.
3. **Label disappears**, replaced by **live audio waveform**
4. **Haptic**: Medium impact on press, light impact on release

### Waveform Design

NOT generic sine waves. NOT a basic equalizer bar chart.

**Style**: Organic, fluid waveform — think a single continuous line that undulates based on audio amplitude. Rendered with `CustomPainter`.

```
Recording state:

        ┌─────────────────────────────────┐
        │                                 │
        │    ∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿     │  ← Single continuous
        │                                 │     undulating line
        └─────────────────────────────────┘
```

**Implementation**:
- Sample audio amplitude at 30fps
- Maintain a buffer of ~40 amplitude values
- Draw with `Path` using `cubicTo` for smooth Bezier curves between sample points
- Line thickness: 3px, round caps
- Line color: contrasting text color on the domain primary
- Slight vertical offset animation (the whole waveform gently floats ±2px) for "alive" feel
- When amplitude is very low (silence), the line flattens but still gently undulates — never fully still

### Release / Processing State

On release:
1. Waveform freezes momentarily (100ms)
2. Pill contracts back to idle size (300ms, `easeOutQuint`)
3. Waveform morphs into a small processing indicator (3 dots pulsing in sequence)
4. Once AI processes the command, a brief confirmation flash — the button border flashes the relevant domain color and a small text appears above: "Added to Work" or "Moved to Personal" (fades after 2s)

---

## View Toggle & Transition

### Toggle Design

Top right of the screen. Two-state segmented control.

```
┌──────────┬──────────┐
│  Nodes   │  All     │     ← Active state: filled bg, bold text
└──────────┴──────────┘        Inactive: ghost, muted text
```

- Size: compact. `~140×36px`.
- Active segment: warm near-black bg (light mode) / warm off-white bg (dark mode). Text inverts.
- Inactive segment: transparent bg, muted text.
- Corner radius: `18px` (full pill).
- Transition: sliding background indicator (not instant switch).

### The Scene Change (View Transition)

This is theatrical. When the user taps the toggle:

**Nodes → Flat view**:
1. Domain cards simultaneously **fracture** — each card splits into its constituent tasks
2. Tasks fly outward briefly (subtle, 50-80ms, `easeOutQuint`) then **reassemble** into the sorted flat list
3. The left color bars on flat list items emerge from the domain card's color — visual continuity
4. Duration: 400ms total
5. The empty 20% header zone fades in from top as cards disperse

**Flat → Nodes view**:
1. List items **cluster by color** — items with the same domain color drift toward each other
2. They merge and expand into their respective domain cards
3. Duration: 400ms total
4. Focus snaps to whichever domain had the most recently visible task

**Flutter implementation**: Use `Hero` widgets with `flightShuttleBuilder` for the color continuity, combined with `AnimatedList` item transitions. The fracture/merge can be achieved with `Staggered` animations where each item has a slight delay based on its index (10-20ms per item, capped at 200ms total stagger).

---

## Top Bar

Minimal. Not a standard `AppBar`.

```
┌──────────────────────────────────────────────────┐
│  VOKL              Work              ☰  ⬡  ⬡    │
│  (app name)     (context)         (toggle)(more) │
└──────────────────────────────────────────────────┘
```

- **Left**: App name in Bricolage Grotesque 600, 18px. Always visible.
- **Center**: Current context — in node view, shows the focused domain name. In flat view, shows "All tasks". Animates on change (crossfade). Space Mono 12px, muted.
- **Right**: View toggle (described above) + overflow menu (3 dots or hamburger — settings, sort, etc.)
- **Height**: `48px`. No elevation/shadow. Just a thin 1px bottom border in the nearest domain color (changes as focus changes).
- **Background**: Same as page background (transparent feel).

---

## Micro-interactions & Motion

### Principles
- Easing: `Curves.easeOutQuint` for all spatial movements. `Curves.easeOutCubic` for opacity/color changes.
- Duration: 200-400ms for most transitions. Never exceed 500ms.
- NO bounce. NO elastic. NO spring physics. Things *decelerate and stop*. This is cinematic, not playful-cartoon.

### Specific Moments

| Interaction | Animation |
|-------------|-----------|
| Card focus change (scroll) | Height interpolation, 60fps, driven by scroll offset. No delay. |
| Card tap (drill in) | Card expands to full screen, other cards slide off-screen. Shared element: domain color + title. 350ms. |
| Task completion (swipe) | Item compresses to 0 height + slides right. Domain color briefly flashes across the row. 300ms. |
| New task added (via voice) | Item fades in at top of relevant position with a downward push effect on items below. 250ms. |
| Push-to-talk press | Pill expands + color shift. 200ms. Haptic. |
| Push-to-talk release | Pill contracts. Waveform → dots. 300ms. |
| View toggle | Scene change transition as described. 400ms. |
| App launch | Staggered reveal: bg color → top bar slides down (100ms) → domain cards cascade in from bottom with 50ms stagger each → CTA fades up last. Total: ~600ms. |

---

## Dark Mode Specifics

Dark mode is not "invert the colors." It's a different *mood*.

- **Backgrounds**: `#0D0B09` base. Domain surfaces are `5%` tinted — barely visible, but enough to create zones.
- **Domain cards in focus**: Primary color at `85%` opacity on `#0D0B09`. The color *glows* — achieved with a `BoxShadow` using the domain's glow color (`20%` opacity, `blur: 40px, spread: -10px`).
- **Text**: `#F0EBE5` primary. Never pure white.
- **The waveform in dark mode**: Domain primary color line on the domain primary bg — use the `text on primary` color for the line. The waveform should feel like it's *emitting light*.
- **Compressed cards**: Very subtle — almost invisible borders, text in domain primary at `70%` opacity. They emerge from the darkness as you scroll toward them.
- **Flat list items**: Left color bar glows softly (subtle `BoxShadow` with domain color, `15%` opacity, `blur: 8px`).

---

## Accessibility

Maximalist does not mean inaccessible.

- All text meets **WCAG AA** contrast ratios (4.5:1 for body, 3:1 for large text)
- Focus scaling respects `MediaQuery.textScaleFactorOf` — if system text is scaled up, minimum item sizes increase proportionally
- The push-to-talk button has a text alternative and works with VoiceOver/TalkBack
- `Semantics` widgets on all interactive elements
- `reduceMotion`: If the user has reduce motion enabled, all transitions become instant crossfades (no spatial animation)
- Color is never the only indicator — domain names always accompany colors

---

## What This Brief Does NOT Cover

- Node drill-down navigation (tapping into a domain)
- Task detail/edit bottom sheet
- Settings screen / domain management
- Onboarding / first-run experience
- AI response display & confirmation flow
- Search / filter UI
- Gesture vocabulary (swipe actions, long press menus)
- Notifications & reminders
- State management architecture
- Backend / data persistence

These are subsequent briefs.

---

## Implementation Order (Recommended First Ticket)

1. Data model (`Domain`, `Task`, tree structure)
2. Color system as a `DomainTheme` provider
3. Parent Node View with focus scaling
4. Push-to-talk CTA (visual only, mock waveform)
5. Flat All-Tasks View with focus scaling
6. View toggle with transition animation
7. Wire up audio recording + AI processing
