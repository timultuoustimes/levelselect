# LevelSelect Design Bible

**Purpose:** a reference for making the marketing website (`site/`, Astro) look like the real app.
**Source of truth:** the native SwiftUI app. Every value below was read out of the code, not designed here.

All file citations are relative to:

```
native/LevelSelect/LevelSelect/
```

**Scope note:** this documents what the app *is*, including where it is inconsistent. Inconsistencies are
called out in `> **Inconsistency**` blocks rather than smoothed over. Do not treat this document as a
spec to redesign against — treat it as a description to match.

**Global fact that shapes everything else:** the app is hard-locked to dark mode.

```swift
.preferredColorScheme(.dark)   // UI/RootView.swift:50
```

There is no light mode. Every semantic color below resolves to its dark-mode variant, always. The
website has no obligation to support a light theme either, and matching the app means committing to
dark.

---

## 1. Color palette

### 1.1 Brand colors (literal, defined in code)

All defined in `UI/Theme.swift` as `Color(red:green:blue:)`, which is sRGB with gamma-encoded
components — so the hex is a direct `round(component × 255)`.

| Token | Swift | RGB floats | Hex | Used for |
|---|---|---|---|---|
| `LSTheme.purple` | `Theme.swift:7` | 0.58, 0.36, 0.98 | `#945CFA` | **Brand default accent.** Fallback for `ThemePalette.accent`, default in the accent ColorPicker. |
| `LSTheme.purpleDeep` | `Theme.swift:8` | 0.30, 0.16, 0.55 | `#4C298C` | Only used as the top-leading stop of `heroGradient`. |
| background top | `Theme.swift:18` | 0.10, 0.07, 0.18 | `#1A122E` | Top of the app background gradient. |
| background bottom | `Theme.swift:19` | 0.05, 0.04, 0.09 | `#0D0A17` | Bottom of the app background gradient. |
| hero gradient end | `Theme.swift:28` | 0.12, 0.08, 0.22 | `#1F1438` | Bottom-trailing stop of the Continue Playing card. |
| `LSTheme.torch` | `Theme.swift:37` | 0.96, 0.64, 0.30 | `#F5A34C` | **Wordmark tint (default)**; the AI-generation torch/sparkle icon and its shimmer bar. |
| `LSTheme.torchShadow` | `Theme.swift:40` | 0.54, 0.29, 0.07 | `#8A4A12` | The hard zero-blur drop shadow under pixel type. Nothing else. |
| `LaunchBackground` | `Assets.xcassets/LaunchBackground.colorset` | 0.082, 0.067, 0.165 | `#15112A` | Splash screen ground, matching the static launch screen. |

> **Inconsistency:** `LaunchBackground` (`#15112A`) is *not* either stop of the app background gradient
> (`#1A122E` → `#0D0A17`). It sits between them. The splash is a flat color; the app behind it is a
> gradient. This is deliberate (it pixel-matches the OS launch image, `RootView.swift:135-137`) but it
> does mean the brand has three near-identical dark navies rather than one.

### 1.2 The app background gradient

```swift
// UI/Theme.swift:15-23
LinearGradient(
    colors: [Color(red: 0.10, green: 0.07, blue: 0.18),   // #1A122E
             Color(red: 0.05, green: 0.04, blue: 0.09)],  // #0D0A17
    startPoint: .top, endPoint: .bottom)
```

Applied full-bleed via the `.lsBackground()` view modifier (`Theme.swift:58-60`), which is used on
Home, Library, Stats, Wishlist, platform pages and the tracker page. It is a **vertical** gradient,
near-black with a purple cast at the top.

### 1.3 Hero gradient

```swift
// UI/Theme.swift:26-31
LinearGradient(
    colors: [purpleDeep.opacity(0.85),                    // #4C298C @ 85%
             Color(red: 0.12, green: 0.08, blue: 0.22)],  // #1F1438
    startPoint: .topLeading, endPoint: .bottomTrailing)
```

Used only on `ContinueHeroCard` (`UI/CoverCard.swift:161`). Note this one is **diagonal**, not vertical.

### 1.4 Status colors

Defaults are Apple's system colors, not literals (`UI/ThemePalette.swift:18-29`):

| Status | Default | Dark-mode hex (Apple) | Section title (`UI/Formatting.swift:55-66`) | SF Symbol (`Formatting.swift:37-48`) |
|---|---|---|---|---|
| `playing` | `.green` | `#30D158` | Now Playing | `play.circle.fill` |
| `paused` | `.orange` | `#FF9F0A` | Paused | `pause.circle.fill` |
| `completed` | `.blue` | `#0A84FF` | Completed | `checkmark.circle.fill` |
| `queued` | `.purple` | `#BF5AF2` | Up Next | `text.append` |
| `backlog` | `.gray` | `#8E8E93` | Backlog | `tray.full` |
| `shelved` | `.brown` | `#AC8E68` | Shelved | `archivebox` |
| `abandoned` | `.red` | `#FF453A` | Abandoned | `xmark.circle` |
| `wishlist` | `.pink` | `#FF375F` | Wishlist | `heart.fill` |

Display order for grouped sections (`Formatting.swift:51-53`):
`playing → paused → queued → backlog → wishlist → completed → shelved → abandoned`.

Hex values are Apple's documented dark-variant system colors; the app never writes them down, so treat
them as *the platform's* values rather than LevelSelect's. Each is individually overridable by the user
(`UI/AppearanceSettings.swift:29-35`).

> **Inconsistency:** `queued` defaults to `.purple` (`#BF5AF2`), which is a *different* purple from the
> brand accent (`#945CFA`). On a default install both appear on screen at once on Home. They are not
> meant to match, but they are close enough to look like a mistake.

### 1.5 Other literal colors in use

| Color | Where | Note |
|---|---|---|
| `.yellow` | `RatingControl.swift:50`, `GameRow.swift:38` | Star fill. Also the "Loved it" label color and the sparkle burst. |
| `.orange` | `TrackerSectionView.swift:80,258,499` | Missable-item warning triangle, error labels. |
| `.green` | `CoverCard.swift:156-158`, `GameDetailView.swift:389`, `TrackerPage.swift:105` | The Play button, the "active playthrough" dot, a fully-complete `n/n` count. Hard-coded — does **not** follow `status.color` for `.playing`. |
| `.pink` | `TrackerSectionView.swift:550` | Rank pip tint when the category name contains "keepsake" (a Hades affordance). |
| `.blue`, `.teal`, `.gray` | `GameDetailView.swift:669,676,679` | Chip group tints for Platforms / Game Modes / Perspective. |
| `.yellow` | `RootView.swift:103,127` | Save-failure banner icon and border. |

> **Inconsistency:** the green Play button and the green "session running" indicators are literal
> `.green`, while everything status-shaped goes through `ThemePalette.color(for:)`. A user who recolors
> the `playing` status gets a mismatch: the carousel icon changes, the Play button does not.

### 1.6 Surface and hairline colors

These are the workhorses. Nearly every surface in the app is white at a very low alpha over the dark
gradient.

| Value | Occurrences | Role |
|---|---|---|
| `.white.opacity(0.06)` | 6 | `LSTheme.cardFill` (`Theme.swift:34`); unselected numbered rank box; unselected ownership chip; progress-bar track. |
| `.white.opacity(0.07)` | 6 | `lsCard()` border (`Theme.swift:66`); Systems tile border; "Alt" chip background; generating shimmer track. |
| `.white.opacity(0.08)` | 6 | Circular icon-button backgrounds in the stage panels; the Stats vertical divider. |
| `.white.opacity(0.05)` | 2 | Systems-shelf tile background (`PlatformViews.swift:53`). |
| `.white.opacity(0.12)` – `0.55` | 1 each | One-offs inside the cover gloss recipe and the showcase. |

Accent-derived surfaces:

| Value | Where |
|---|---|
| `accent.opacity(0.08)` | Tracker merge-summary card background (`TrackerSectionView.swift:277`) |
| `accent.opacity(0.15)` | Small square icon chip behind `checklist` / `gamecontroller.fill` (`TrackerPage.swift:63,95`) |
| `accent.opacity(0.16)` | Playthrough picker capsule fill (`GameDetailView.swift:279`) |
| `accent.opacity(0.20)` | Selected ownership chip fill (`OwnershipControl.swift:31`) |
| `accent.opacity(0.25)` | Selected "Alt" chip fill; stage-panel 1px left edge (`GameDetailView.swift:439,527`) |
| `accent.opacity(0.35)` | Hero card border (`CoverCard.swift:164`) |
| `accent.opacity(0.40)` | Playthrough picker capsule border (`GameDetailView.swift:280`) |
| `accent.opacity(0.55)` | Selected ownership chip border (`OwnershipControl.swift:35`) |
| `accent.opacity(0.85)–(0.9)` | User-note text; location subheadings; filled numbered rank boxes |

> **Inconsistency:** three different "faint white surface" alphas (0.05 / 0.06 / 0.07) and three
> different "faint white border" alphas are in play, chosen ad hoc per component rather than from a
> scale. If you are building a CSS scale, collapsing to two tokens (`0.06` fill, `0.07` border) matches
> the majority and will be visually indistinguishable.

### 1.7 Text colors (SwiftUI hierarchical styles)

The app never sets literal text colors for body copy; it uses `.primary` / `.secondary` / `.tertiary` /
`.quaternary`. In dark mode these resolve to approximately:

| Style | Approx. dark value |
|---|---|
| `.primary` | `rgba(255,255,255,1.0)` |
| `.secondary` | `rgba(255,255,255,0.60)` |
| `.tertiary` | `rgba(255,255,255,0.30)` |
| `.quaternary` | `rgba(255,255,255,0.18)` |

`.quaternary` is used for unfilled rank pips (`RankControls.swift:80`) and for cover placeholders.

### 1.8 How the custom accent overrides everything

The accent is a single global, cached on the main actor (`UI/ThemePalette.swift:8-48`):

```swift
private(set) static var accent: Color = LSTheme.purple     // ThemePalette.swift:9
private(set) static var accentIsCustom = false             // ThemePalette.swift:12

static func refresh(from settings: ThemeSettings?) {       // ThemePalette.swift:35
    let custom = settings?.accentHex.flatMap { Color(hex: $0) }
    accent = custom ?? LSTheme.purple
    accentIsCustom = custom != nil
    ...
}
```

Rules:

1. **`LSTheme.accent` is the live accent** (`Theme.swift:12`) — it reads `ThemePalette.accent`. Every
   `LSTheme.accent` reference in the app (tab bar tint, progress bars, chips, checkmarks, links, the
   stage-panel edge, the LivePulse glow) follows the user's choice immediately.
2. **The wordmark is the exception.** `LSTheme.wordmark` (`Theme.swift:45-47`) returns
   `accentIsCustom ? accent : torch`. So the brand torch-orange survives until the user actually picks
   an accent — the default look is orange type on a purple-cast dark ground, and only *then* does the
   wordmark follow the accent.
3. **The wordmark's shadow follows suit.** `Wordmark.swift:45-49`: a custom accent gets
   `tint.mix(with: .black, by: 0.55)`; the default gets the fixed `LSTheme.torchShadow`.
4. **Status colors override independently** of the accent, per status, via a hex map
   (`ThemePalette.swift:41-47`).
5. Accent is stored as a `#RRGGBB` hex string and synced through CloudKit
   (`AppearanceSettings.swift:53-62`, `ThemePalette.swift:64-87`).
6. Changing it bumps `themeVersion`, which is applied as `.id(themeVersion)` on the `TabView`
   (`RootView.swift:28,55-58`) — a brute-force full rebuild of the view tree.

**For the website:** the site has no accent picker, so it should use the *default* state — brand purple
`#945CFA` as accent, torch orange `#F5A34C` for the wordmark. Do not make the website's wordmark purple;
that is the custom-accent state, not the brand state.

---

## 2. Typography

### 2.1 The two faces

**Press Start 2P** — bundled TTF, registered at runtime into the process font list rather than declared
in Info.plist (`Services/FontRegistrar.swift:8-15`, asset at `Resources/PressStart2P-Regular.ttf`,
OFL license at `Resources/PressStart2P-OFL.txt`).

```swift
// UI/Theme.swift:51-53
static func pixel(_ size: CGFloat) -> Font {
    .custom("Press Start 2P", size: size)
}
```

**Everything else** — the system font (SF Pro on iOS/macOS), always via semantic text styles
(`.caption2`, `.caption`, `.footnote`, `.subheadline`, `.callout`, `.body`, `.headline`, `.title3`,
`.title2`, `.largeTitle`), never a raw point size, with a handful of exceptions listed below.

### 2.2 THE RULE for pixel font vs system font

The rule is stated in the code and — unusually — actually held to:

> "Display face: Press Start 2P (bundled, registered at launch). **Use for wordmarks and small display
> moments only — never body text.**" — `Theme.swift:49-50`

An exhaustive grep for `LSTheme.pixel` returns **exactly one call site**:

```
UI/Wordmark.swift:33:    .font(LSTheme.pixel(size))
```

**Press Start 2P is used for the word "LevelSelect" and nothing else, anywhere in the app.** Not for
headings, not for numbers, not for stats, not for buttons, not for the timer. This is the single most
important typographic fact in this document.

The wordmark appears in exactly two places (plus previews):

| Location | Call | Size |
|---|---|---|
| Home nav bar (`principal` toolbar item, iOS only) | `Wordmark(size: 13)` | `RootView.swift:192` |
| Settings header | `Wordmark(size: 22, showsIcon: true)` | `SettingsView.swift:36` |

Everything else that looks "branded" — the splash — is a baked raster asset (`LaunchLogo`,
`RootView.swift:140`), not live type.

### 2.3 Type scale actually in use

Mapping SwiftUI text styles to their default iOS point sizes/weights:

| Style | pt / weight | Where it's used |
|---|---|---|
| `.largeTitle` + `.rounded` + `monospacedDigit` | 34 / Regular | The live session timer only (`SessionControlsView.swift:84`). The **only** use of the rounded design in the app. |
| `.title2.bold()` | 22 / Bold | Game title on the detail page (`GameDetailView.swift:595`) |
| `.title3.bold()` | 20 / Bold | Carousel section titles ("Now Playing"), "Systems" (`CoverCard.swift:58`, `PlatformViews.swift:37`) |
| `.title3.bold().monospacedDigit()` | 20 / Bold | Stats big numbers (`StatsView.swift:134`) |
| `.headline` | 17 / Semibold | Collapsible section titles, Stats card titles, game row titles, hero card title |
| `.callout` | 16 / Regular | Generating-tracker elapsed counter |
| `.subheadline` | 15 / Regular | Body copy default: tracker item names, summaries, info cells, session rows |
| `.subheadline.weight(.semibold)` | 15 / Semibold | Category headers, playthrough names, "Open" affordance |
| `.footnote` | 13 / Regular | Cover card titles, save-failure banner, "Drag to spin · tap to close" |
| `.caption` | 12 / Regular | Field labels, locations, descriptions, counts, metadata |
| `.caption2` | 11 / Regular | Chevrons, pins, tiny badges |

Raw point sizes appear only for tiny glyphs, always via `.font(.system(size:))`:
`8` (chip remove ✕, `Collapsible.swift:139`; grid-cell pin, `LibraryView.swift:563`; row stars,
`GameRow.swift:38`), `7` (sparkle, `RatingControl.swift:93`), `10` (grid-cell status label,
`LibraryView.swift:551`), `11`/`13` (rank pips/hearts, `RankControls.swift:52-53`), `22`
(generating torch, `GeneratingTrackerView.swift:94`).

### 2.4 Other typographic details

- **`monospacedDigit()`** is applied consistently to anything that ticks or counts: the timer, durations,
  `n/m` progress counts, stats numbers, year counts. This is a real signature of the app — numbers never
  jitter.
- **`.kerning(1)`** is used exactly once: the `"CONTINUE PLAYING"` eyebrow label on Home
  (`RootView.swift:249`), which is `.caption.weight(.semibold)`, uppercase, secondary.
- **`.contentTransition(.numericText())`** on the timer (`SessionControlsView.swift:85`,
  `GameDetailView.swift:458`) — digits roll rather than swap.
- **Strikethrough** on completed tracker items, colored `.secondary` (`TrackerSectionView.swift:494`).

---

## 3. The wordmark shadow recipe

`UI/Wordmark.swift`. The doc comment (lines 5-12) explains the reasoning; the recipe is lines 32-36.

```swift
Text("LevelSelect")
    .font(LSTheme.pixel(size))                                    // Wordmark.swift:33
    .foregroundStyle(tint)                                        // Wordmark.swift:34
    .shadow(color: shadowTint, radius: 0, y: max(1, size * 0.16)) // Wordmark.swift:35
    .shadow(color: tint.opacity(0.3), radius: size * 0.65)        // Wordmark.swift:36
```

**Two shadows, two jobs:**

| # | Color | Radius | Offset | Job |
|---|---|---|---|---|
| 1 | `shadowTint` (opaque) | **`0`** | x: 0, y: `max(1, size × 0.16)` | Legibility. Zero blur is load-bearing — Press Start 2P strokes are ~2px at display sizes, and a blurred shadow eats the corners and turns glyphs to mush. A hard offset adds a second contrast edge instead. This is the pixel-art convention. |
| 2 | `tint` @ 30% | `size × 0.65` | none (0, 0) | Atmosphere. The torch-lit glow. The only place blur belongs. |

Order matters: SwiftUI applies modifiers outward, so the hard shadow is laid first and the soft glow
wraps the result.

**`shadowTint`** (`Wordmark.swift:45-49`):
- default (no custom accent) → `LSTheme.torchShadow` = `#8A4A12`
- custom accent → `tint.mix(with: .black, by: 0.55)` — i.e. the accent darkened 55% toward black, so a
  custom accent gets a shadow that belongs to it rather than a fixed brown.

**Resolved at the two real sizes:**

| Size | Hard shadow y-offset | Glow radius |
|---|---|---|
| 13 (nav bar) | `max(1, 2.08)` = **2.08pt** | **8.45pt** |
| 22 (settings) | `max(1, 3.52)` = **3.52pt** | **14.3pt** |

**Optional door icon** (`showsIcon: true`, `Wordmark.swift:25-31`):
- `Image("DoorMark")`, `scaledToFit`, height = `size × 2.1`
- its own shadow: `.black.opacity(0.5)`, radius `size × 0.35`, y `size × 0.12`
- `HStack(spacing: size * 0.55)` between icon and type

Everything scales off the single `size` parameter, so the lockup is resolution-independent.

---

## 4. Motion

### 4.1 The signature

Two things define LevelSelect's motion, and they are stated in the code as intent, not inferred:

> "Springy pressed state for tappable cards (**"fluid buttons" — everything moves, nothing snaps**)."
> — `Theme.swift:164-165`

Almost every state change in the app is a **spring**, not an ease. Springs cluster at
`response 0.28–0.34`, `dampingFraction 0.55–0.8` — fast, small, slightly bouncy. Long eases are reserved
for ambience (the pulse, the shine).

The second signature is **breathing**: two independent slow sine loops (the LivePulse, the generating
torch) that are deliberately *off* the 1-second clock tick so the mismatch reads as ambient rather than
as a stuttering clock.

### 4.2 Complete animation inventory

| # | Animation | Parameters | Trigger | File:line |
|---|---|---|---|---|
| 1 | Pressable card | `spring(response: 0.3, damping: 0.7)` on `scale 0.96` + `opacity 0.9` | button press | `Theme.swift:165-171` |
| 2 | BouncyTap press-in | `spring(response: 0.16, damping: 0.5)` → `scale 0.92` | tap down | `Theme.swift:184` |
| 3 | BouncyTap release | `spring(response: 0.32, damping: 0.55)` → `scale 1` | 110 ms after press-in, then action fires | `Theme.swift:185-189` |
| 4 | Collapsible section | `spring(response: 0.32, damping: 0.8)` | header tap; chevron rotates 0° → −90° | `Collapsible.swift:25,36` |
| 5 | Carousel collapse | `spring(response: 0.32, damping: 0.8)`; chevron 0° → 90° | header chevron tap | `CoverCard.swift:47,52` |
| 6 | Rating pick | `spring(response: 0.34, damping: 0.55)` | star tap (+ haptic: heavy at 5, light otherwise) | `RatingControl.swift:60-66` |
| 7 | Rating label | `spring(response: 0.3, damping: 0.7)`, transition `.push(from: .bottom) + .opacity` in / `.opacity` out | rating changes | `RatingControl.swift:24,36-38` |
| 8 | Sparkle burst | `easeOut(duration: 0.55)`; 6 sparkles on a hexagon, travel `18pt × t`, opacity `1−t`, scale `0.4+t` | rating hits 5 | `RatingControl.swift:86-103` |
| 9 | Ownership chip | `spring(response: 0.28, damping: 0.6)`; unselected sits at `scale 0.98` | chip tap (+ selection haptic) | `OwnershipControl.swift:38,41,45` |
| 10 | Rank pips / boxes | `snappy(duration: 0.18)` (= bounce 0.15 → ζ 0.85) | rank set | `RankControls.swift:88,110` |
| 11 | Alt chip reveal | `snappy(duration: 0.2)`, transition `.opacity + .move(edge: .top)` | "Alt" tap | `RankControls.swift:154,173` |
| 12 | Stage slide | `spring(response: 0.5, damping: 0.85)` | stage 1↔2↔3 on wide screens | `GameDetailView.swift:382` |
| 13 | Game-info edit toggle | `spring(response: 0.3, damping: 0.8)` | Edit/Done | `GameDetailView.swift:640` |
| 14 | Save-failure banner | `spring(duration: 0.35)` (bounce 0 → critically damped), transition `.move(edge: .bottom) + .opacity` | save fails / retried | `RootView.swift:45,49` |
| 15 | Splash dismiss | `easeOut(duration: 0.5)` after a `1.0 s` hold, `.transition(.opacity)` | app launch | `RootView.swift:32,71-74` |
| 16 | Generation stage caption | `easeInOut(duration: 0.35)`, `.contentTransition(.opacity)` | caption text changes | `GeneratingTrackerView.swift:47-48` |
| 17 | **Cover shine** | `easeInOut(duration: 0.85).delay(delay)` | on appear | `Theme.swift:135` |
| 18 | **LivePulse** | `easeInOut(duration: 3.3).repeatForever(autoreverses: true)` | session running | `Theme.swift:158` |
| 19 | Generating torch | driven by `sin(elapsed × 2.2)` and `sin(elapsed × 1.3 + 0.8)` — continuous, not `withAnimation` | generation in flight | `GeneratingTrackerView.swift:91-99` |
| 20 | Generating shimmer bar | `elapsed mod 1.6 / 1.6` sweep, band = 40% of width | generation in flight | `GeneratingTrackerView.swift:104-126` |
| 21 | Showcase appear | `spring(response: 0.5, damping: 0.72)`; scale 0.35→1, opacity 0→1, scrim 0→0.72 | cover tapped | `CoverShowcase.swift:52` |
| 22 | Showcase close | `spring(response: 0.4, damping: 0.85)`, then dismissed 260 ms later | scrim tap | `CoverShowcase.swift:93-97` |
| 23 | **Showcase spin release** | `spring(response: 0.75, damping: 0.32)` — reduce-motion: `0.9` | drag ends | `CoverShowcase.swift:35-38` |
| 24 | Carousel scroll transition | `scaleEffect` 1→0.86, `opacity` 1→0.6, `rotation3DEffect` `phase.value × −12°` about Y | horizontal scroll | `CoverCard.swift:84-89` |
| 25 | Systems scroll transition | `scaleEffect` 1→0.9, `opacity` 1→0.65 | horizontal scroll | `PlatformViews.swift:65-69` |
| 26 | Star bounce | `.symbolEffect(.bounce, value: filled)` | star fills | `RatingControl.swift:51` |
| 27 | Pip symbol swap | `.contentTransition(.symbolEffect(.replace))` | rank changes | `RankControls.swift:81` |
| 28 | Timer digits | `.contentTransition(.numericText())` | every second | `SessionControlsView.swift:85` |

### 4.3 The LivePulse cadence (the 6.6 s breath)

```swift
// UI/Theme.swift:142-161
struct LivePulse: View {
    var body: some View {
        Circle()
            .fill(LSTheme.accent)
            .frame(width: 130, height: 130)
            .blur(radius: 42)
            .opacity(on ? 0.34 : 0.14)
            .scaleEffect(on ? 1.08 : 0.9)
            .onAppear {
                guard !reduceMotion else { on = true; return }
                withAnimation(.easeInOut(duration: 3.3).repeatForever(autoreverses: true)) { on = true }
            }
    }
}
```

- **3.3 s each way, autoreversing → a 6.6 s full cycle.**
- The comment states why: *"Slow, ~6.6s breath — clearly off the 1s tick so the mismatch reads as an
  intentional ambient glow, not a stuttering clock."* (`Theme.swift:156-157`)
- Animated properties: **opacity 0.14 ↔ 0.34** and **scale 0.9 ↔ 1.08**, together.
- Geometry: a **130 × 130 pt circle** filled with the live accent and **blurred by 42 pt**.
- Reduce Motion: holds the *bright* end (`on = true`) steady — a static glow, not nothing.
- Used in exactly one place: behind the running session timer (`SessionControlsView.swift:88-90`), and
  only while `state == .running`.

### 4.4 The cover shimmer (CoverShine)

```swift
// UI/Theme.swift:116-138
struct CoverShine: View {
    var delay: Double = 0.35
    @State private var phase: CGFloat = -1.4
    // Rectangle, LinearGradient(.clear → .white.opacity(0.35) → .clear), leading→trailing
    // .frame(width: w * 0.45)
    // .rotationEffect(.degrees(22))
    // .offset(x: phase * w)
    // .blendMode(.plusLighter)
    // onAppear: withAnimation(.easeInOut(duration: 0.85).delay(delay)) { phase = 1.4 }
}
```

- A **one-shot** diagonal sweep, not a loop. It fires once when the cover appears.
- Band width = **45% of the cover width**, rotated **22°**, peak white **0.35**, blend `plusLighter`.
- Travels from `−1.4 × width` to `+1.4 × width` over **0.85 s**, `easeInOut`.
- Default delay **0.35 s**; the detail-page hero uses **0.25 s** (`GameDetailView.swift:585`).
- Respects Reduce Motion by not running at all (`Theme.swift:134`).
- Applied to: the detail-page hero cover, and the Continue Playing hero card cover
  (`CoverCard.swift:114`). **Not** applied to library grid cells or carousel cover cards.

### 4.5 The cover spin (CoverShowcase)

`UI/CoverShowcase.swift`. Tap a cover on the game page to blow it up into a draggable 3D object.

- Enlarged size: **264 × 350 pt** (`CoverShowcase.swift:14`), corner radius **14**.
- Drag → rotation: `yaw = drag.width / 6`, `pitch = −drag.height / 6` degrees
  (`CoverShowcase.swift:15-16`), applied as two `rotation3DEffect`s with **`perspective: 0.55`**
  (`:26-27`).
- **Release spring: `response 0.75, dampingFraction 0.32`** (`:35-38`) — by far the bounciest spring in
  the app (overshoots to ~135%, settles over ~2.5 s). This is the deliberate "wobble on release".
  Reduce Motion swaps damping to `0.9`, which removes the wobble entirely.
- The drop shadow **tracks the tilt**: `radius 26`, `x: −yaw × 0.7`, `y: 24`, `.black.opacity(0.55)`
  (`:30`).
- A specular hotspot **slides with the tilt**: an `EllipticalGradient` centered at
  `(0.5 − yaw/55, 0.4 + pitch/55)`, `.white.opacity(0.4) → .clear`, `softLight` (`:74-81`).
- Scrim: `.black.opacity(0.72)`, tap to close.

### 4.6 Reduce Motion

Honored in three places, each differently and deliberately:

| Component | Behavior |
|---|---|
| `CoverShine` (`Theme.swift:134`) | Does not run at all. |
| `LivePulse` (`Theme.swift:155`) | Snaps to the bright end and holds — a steady glow. |
| `CoverShowcase` (`Theme.swift`→`CoverShowcase.swift:36`) | Keeps the spring but raises damping `0.32 → 0.9`, killing the wobble while keeping the motion. |

`PressableCardStyle` claims to honor Reduce Motion in its doc comment (`Theme.swift:166`) but does not
actually read the environment value.

> **Inconsistency:** the `PressableCardStyle` doc comment says *"Honors Reduce Motion by keeping the
> scale subtle"* — that is a rationalization, not an implementation. It never checks
> `accessibilityReduceMotion`. Neither does `BouncyTap`, which is the more aggressive of the two
> (0.92 scale + haptic).

---

## 5. Surfaces

### 5.1 Corner radii in use

Frequency across all Swift files:

| Radius | Count | Where |
|---|---|---|
| **14** | 10 | Cover showcase; generating card; save-failure banner; misc sheets |
| **16** | 4 | `lsCard()` (the standard card); `ContinueHeroCard` |
| **12** | 4 | `CoverCard` thumb; the green Play button |
| **10** | 4 | Library grid cell cover; merge-summary card; hero-card cover |
| **8** | 1 | Detail-page hero cover |
| **7** | 3 | Small square icon chips (28 × 28) |
| **6** | 3 | `CoverThumb` default (`Formatting.swift:113-114`) |
| **5** | 1 | Numbered rank box (20 × 20) |
| **18** | 2 | Systems-shelf tile (84 × 84) |

Capsules (fully rounded) are used for all chips, badges, pills and progress bars.

> **Inconsistency:** covers get **five** different corner radii depending on where they appear —
> 6 (`CoverThumb` base), 8 (detail hero), 10 (grid cell, hero card), 12 (carousel card), 14 (showcase).
> There is a loose logic (bigger cover → bigger radius) but no stated scale, and the base `CoverThumb`
> clips at 6 *before* the caller re-clips at their own radius, so the gloss overlay geometry and the
> outer clip disagree on small covers.

### 5.2 Materials and blur

| Material | Count | Where |
|---|---|---|
| `.ultraThinMaterial` | 9 | Status pill and pin badge on library grid cells; pin on carousel cards; ownership badge pill; **both stage panels** (`GameDetailView.swift:437,525`) |
| `.regularMaterial` | 1 | Save-failure banner (`RootView.swift:124`) |

Explicit blurs:

| Blur | Where |
|---|---|
| `blur(radius: 42)` | LivePulse glow (`Theme.swift:150`) |
| `blur(radius: 60, opaque: true)` | Ambient cover backdrop (`GameDetailView.swift:557`) |

### 5.3 The `lsCard()` recipe

The standard card, used across Stats and Home (`Theme.swift:63-67`):

```swift
padding(14)
    .background(LSTheme.cardFill, in: .rect(cornerRadius: 16))          // white @ 6%
    .overlay(RoundedRectangle(cornerRadius: 16)
        .strokeBorder(.white.opacity(0.07), lineWidth: 1))
```

That's it: **14pt padding, 16pt radius, white 6% fill, 1px white 7% border.** No shadow, no material.

### 5.4 The cover gloss ("diamorphic") recipe

`coverGloss(cornerRadius:)` (`Theme.swift:72-111`) — four stacked overlays. The comment calls it the
soft-3D "diamorphic" look and notes it is intentionally static (cheap enough to apply to every cover).

**Layer 1 — top-left sheen** (`:74-84`), `blendMode(.softLight)`:
```
LinearGradient(topLeading → bottomTrailing) stops:
  white 0.32 @ 0%
  white 0.06 @ 30%
  clear      @ 58%
```

**Layer 2 — convex specular hotspot** (`:86-93`), `blendMode(.softLight)`:
```
EllipticalGradient(white 0.22 → clear)
  center: (0.30, 0.18)
  startRadiusFraction: 0, endRadiusFraction: 0.6
```

**Layer 3 — grounding shadow at the bottom edge** (`:95-103`), `blendMode(.multiply)`:
```
LinearGradient(center → bottom): clear → black 0.22
```
Comment: *"a soft dark bottom edge gives the card thickness so it reads as an object sitting on the
surface, not a flat sticker."*

**Layer 4 — top hairline** (`:104-110`):
```
strokeBorder(LinearGradient(top → bottom): white 0.45 → white 0.02), lineWidth: 1
```

### 5.5 Shadow inventory

| Shadow | Where |
|---|---|
| `black 0.40, r 5, y 2` | Library grid cell; hero card cover |
| `black 0.40, r 5, y 3` | Collections cover |
| `black 0.45, r 6, y 3` | Carousel `CoverCard` |
| `black 0.50, r 8, y 4` | Detail-page hero cover |
| `black 0.55, r 26, x −yaw×0.7, y 24` | Cover showcase (tilt-tracking) |
| `black 0.50, r size×0.35, y size×0.12` | Wordmark door icon |
| `torch @ 0.35–0.70, r 8–14` | Generating torch (pulsing) |

Pattern: **bigger cover → deeper, softer, further-offset shadow.** All are pure black at 40–55%.

### 5.6 Glow treatments

There are only three glows in the app, and they are all accent- or torch-colored:

1. **Wordmark glow** — `tint @ 30%`, radius `size × 0.65`, no offset (`Wordmark.swift:36`).
2. **LivePulse** — a 130pt accent circle blurred 42pt at 14–34% opacity (`Theme.swift:146-152`).
3. **Generating torch** — `torch @ 0.35 + 0.35·pulse`, radius `8 + 6·pulse` (`GeneratingTrackerView.swift:96-97`).

### 5.7 The ambient backdrop (game detail page)

`GameDetailView.swift:536-576`. The single most distinctive surface in the app: every game page is
tinted by its own box art.

```
ZStack(alignment: .top) {
    LSTheme.background                       // the base gradient

    if pageBackground == .status {
        LinearGradient(status.color @ 45% → clear, top → center)
            .frame(height: 420)
    } else if let cover {
        AsyncImage(cover)
            .scaledToFill()
            .frame(height: 420)
            .clipped()
            .blur(radius: 60, opaque: true)
            .saturation(1.5)
            .opacity(0.55)
            .mask(LinearGradient(stops: [
                black       @ 0,
                black 0.6   @ 0.55,
                clear       @ 1
            ], top → bottom))
    }
}
.ignoresSafeArea()
```

Key numbers: **420 pt tall**, **60 pt blur**, **1.5× saturation**, **55% opacity**, masked to fade out
by the bottom with a mid-stop at 60% at 55% down. User-switchable between `.cover` (default) and
`.status` (`ThemePalette.swift:13,39`).

---

## 6. Spacing and layout

### 6.1 The 640 pt reading width

```swift
// UI/GameDetailView.swift:355-357
.padding()
.frame(maxWidth: 640, alignment: .leading)
.frame(maxWidth: .infinity)
```

The **single** constrained reading column in the app. The double-`frame` idiom is the standard SwiftUI
centering trick: clamp to 640 and left-align content inside, then expand the wrapper to fill and center
the clamped block.

The tracker's adaptive grid is explicitly tuned against it (`TrackerSectionView.swift:352-356`):
*"one column on a narrow phone with long names, two on a normal phone, three at the 640pt reading width
used on iPad and Mac."*

> **Inconsistency:** 640 is not applied globally. Other max widths exist: **600** (About section,
> `AboutSection.swift:61`), **440** and **420** (Wishlist, `WishlistView.swift:51,224`). Home, Library
> and Stats are **unconstrained** — they fill the window at any width. Only the game detail page has a
> reading measure.

### 6.2 Spacing scale

Values actually used, by role:

| Value | Role |
|---|---|
| **26** | Home top-level section spacing (`RootView.swift:243`) |
| **20** | Game detail section spacing (`GameDetailView.swift:295`); tracker page (`TrackerPage.swift:150`) |
| **18** | Stage tracker panel section spacing (`GameDetailView.swift:421`); action button rows (`TrackerSectionView.swift:88`, `GameDetailView.swift:683`) |
| **16** | Stats card spacing (`StatsView.swift:15`); detail hero HStack (`GameDetailView.swift:582`) |
| **14** | Card padding (`lsCard`, hero card, generating card); carousel item spacing (`CoverCard.swift:75`) |
| **12** | Intra-section spacing; `CollapsibleSection` header→content (`Collapsible.swift:23`); stage panel header padding (`GameDetailView.swift:418`) |
| **10** | Carousel header→content (`CoverCard.swift:44`); merge-summary padding |
| **8** | Small stacks, chip rows |
| **6** | Chip spacing (`FlowLayout(spacing: 6)`), cover card title gap |
| **5, 4, 3, 2** | Tight label stacks; tracker item rows use **2** between rows and **3** vertical padding |

`.padding()` with no argument (= 16 pt on iOS) is the default page padding everywhere:
`GameDetailView.swift:355`, `StatsView.swift:23`, `TrackerPage.swift:152`, `PlatformViews.swift:101`.

### 6.3 Fixed sizes

| Element | Size | Citation |
|---|---|---|
| Detail hero cover | 138 × 184 | `GameDetailView.swift:584` |
| Carousel cover card | 108 × 144 (card width 108) | `CoverCard.swift:11,30` |
| Hero card cover | 76 × 101 | `CoverCard.swift:113` |
| Game row cover | 44 × 58 | `GameRow.swift:9` |
| Cover showcase | 264 × 350 | `CoverShowcase.swift:14` |
| Systems tile | 84 × 84 icon well, 90 wide cell, icon 54 | `PlatformViews.swift:51-63` |
| Play button (hero) | 56 × 56 | `CoverCard.swift:153` |
| Small icon chip | 28 × 28, radius 7 | `TrackerPage.swift:62-63` |
| Numbered rank box | 20 × 20, radius 5 | `RankControls.swift:99-101` |
| **Tracker checkbox tap target** | glyph ~22pt, **hit area 36 × 44** | `TrackerSectionView.swift:485` |
| Library grid cell | `GridItem(.adaptive(minimum: 105), spacing: 12)`, row spacing 16 | `PlatformViews.swift:92` |
| Tracker dense grid column | `GridItem(.adaptive(minimum: 180))`, spacing 2 | `TrackerSectionView.swift:361` |
| Progress bar (Stats) | height **6**, capsule | `StatsView.swift:148-157` |
| Shimmer bar | height **4**, capsule | `GeneratingTrackerView.swift:125` |
| Stats divider | 1 × 34, white 8% | `StatsView.swift:144` |
| Stage panel edge | 1px, accent @ 25% | `GameDetailView.swift:439` |

Cover aspect ratio is **3:4** where stated explicitly (`LibraryView.swift:542`); the fixed sizes above
are all approximately 3:4 (138×184 = 0.750, 108×144 = 0.750, 76×101 = 0.752, 44×58 = 0.759,
264×350 = 0.754).

### 6.4 The sliding stage geometry

Wide-screen only (`horizontalSizeClass == .regular && width > height && display == .compact`),
`GameDetailView.swift:364-384`. Three panels, positioned as fractions of the container width:

| Stage | Page width | Page offset | Tracker width | Tracker offset | Video width | Video offset |
|---|---|---|---|---|---|---|
| 1 | `w` | 0 | `0.42w` | `w` | `0.54w` | `1.02w` |
| 2 | `0.58w` | 0 | `0.42w` | `0.58w` | `0.54w` | `1.02w` |
| 3 | `0.58w` | `−0.58w` | `0.46w` | 0 | `0.54w` | `0.46w` |

Animated with `spring(response: 0.5, dampingFraction: 0.85)`, clipped to the container.

---

## 7. Component patterns

### 7.1 Card

Two distinct card recipes exist.

**(a) The standard card — `lsCard()`** (`Theme.swift:63-67`). Padding 14, radius 16, `white 6%` fill,
1px `white 7%` border, no shadow. Used by every Stats card.

**(b) The hero card** (`CoverCard.swift:160-166`). Padding 14, radius 16, but filled with
`LSTheme.heroGradient` (diagonal `#4C298C` 85% → `#1F1438`) and bordered with `accent @ 35%` instead of
white. Used only for Continue Playing.

A third, ad-hoc variant appears for the generating state (padding 14, radius **14**, `cardFill`, **no**
border — `GeneratingTrackerView.swift:82-83`) and for the merge summary (padding 10, radius 10,
`accent @ 8%`, no border — `TrackerSectionView.swift:276-277`).

> **Inconsistency:** four card recipes with different radii (16/16/14/10) and different border rules
> (white / accent / none / none). `lsCard()` exists as a shared helper but two of the four don't use it.

### 7.2 Row

The canonical row is the tracker item (`TrackerSectionView.swift:463-537`):

```
HStack(alignment: .top, spacing: 4) {
    Button { toggle } label: {
        Image(systemName: done ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(done ? accent : .secondary)
            .font(.body)
            .frame(width: 36, height: 44, alignment: .top)   // hit target > glyph
            .contentShape(.rect)
    }
    VStack(alignment: .leading, spacing: 2) {
        name (.subheadline, strikethrough when done, .secondary when done)
        [missable ⚠ .caption2 .orange]
        [location  .caption .secondary]
        [description → AltDescription]
        [note → Label(systemImage: "pencil.line") .caption accent@85%]
        [rank → RankPicker]
    }
    Spacer(minLength: 0)
}
.contentShape(.rect)
.padding(.vertical, 3)
.contextMenu { Edit Item }
```

Notable: the hit target (36 × 44) is deliberately larger than the ~22pt glyph and **top-aligned**, so it
still lines up with the first line of a multi-line row.

A second row shape — the "navigational row" — recurs in `TrackerPage.swift:89-114` and
`TrackerPage.swift:58-75`:

```
HStack(spacing: 10) {
    icon (.caption, accent) in a 28×28 well: accent @ 15%, radius 7
    VStack(spacing: 2) { title .subheadline.semibold ; subtitle .caption .secondary }
    Spacer()
    ["Open" .subheadline.semibold accent]
    chevron.right .caption2 .tertiary
}
.contentShape(.rect)
```

The library row (`GameRow.swift`) is a third shape: 44×58 cover, 12pt gap, title `.headline`, a metadata
line of `.caption` with a status glyph and platform icon, tiny 8pt stars, trailing ownership badges.

### 7.3 Section header

Two patterns, by context.

**Collapsible section header** (`Collapsible.swift:22-40`) — the game detail page:
```
Button {
    withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { expanded.toggle() }
} label: {
    HStack {
        Label(title, systemImage: icon).font(.headline)
        Spacer()
        Image(systemName: "chevron.down")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .rotationEffect(.degrees(expanded ? 0 : -90))
    }
    .contentShape(.rect)
}
```
Expansion state persists library-wide via `@AppStorage("section.\(title)")` (`Collapsible.swift:19`).
Content enters with `.transition(.opacity.combined(with: .move(edge: .top)))`.
Sections are separated by plain `Divider()`s on the game page (`GameDetailView.swift:300-353`).

**Carousel header** (`CoverCard.swift:45-70`) — Home:
```
HStack(spacing: 6) {
    chevron.right (rotates 0°→90°, .caption.semibold, .secondary)
    status glyph  (accent if .playing, else .secondary)
    Text(sectionTitle).font(.title3.bold())
    Text("(n)").font(.subheadline).foregroundStyle(.secondary)
    Spacer()
    Button("See all").font(.subheadline).foregroundStyle(accent)
}
```

And one eyebrow label, used once (`RootView.swift:246-249`): `"CONTINUE PLAYING"`, `.caption.semibold`,
`.secondary`, `.kerning(1)`.

> **Inconsistency:** the two headers rotate their chevrons in opposite directions and use different
> glyphs (`chevron.down` rotating to −90° vs `chevron.right` rotating to +90°). They also disagree on
> title size (`.headline` vs `.title3.bold()`).

### 7.4 Pill / badge / chip

**The metadata `Chip`** (`Collapsible.swift:128-151`) is the canonical pill:
```
.font(.caption)
.padding(.horizontal, 10)
.padding(.vertical, 5)
.background(tint.opacity(0.18), in: .capsule)
.overlay(Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 1))
.foregroundStyle(.primary)
```
Optional trailing ✕ at `.system(size: 8, weight: .bold)`.

**Selectable chip** (`OwnershipControl.swift:18-42`) — same shape, different numbers:
```
.font(.caption.weight(.medium))
.padding(.horizontal, 9).padding(.vertical, 5)
background: on ? accent@20% : white@6%
border:     on ? accent@55% : clear
foreground: on ? accent      : .secondary
scale:      on ? 1           : 0.98
```

**Menu pill** (`GameDetailView.swift:277-281`): `.padding(.horizontal, 12).padding(.vertical, 7)`,
`accent@16%` fill, `accent@40%` border.

**Tiny "Alt" chip** (`RankControls.swift:156-164`): `.caption2.semibold`, h-padding 6, v-padding 1,
`accent@25%` / `white@7%` fill, border `accent@60%` / `accent@25%`.

**Material badge** (`LibraryView.swift:546-576`): a status dot + optional label on
`.ultraThinMaterial` in a capsule, h-padding 7 / v-padding 4, inset 6 from the cover edge.

> **Inconsistency:** five pill recipes with five different padding pairs (10/5, 9/5, 12/7, 6/1, 7/4) and
> five different fill alphas (18%, 20%, 16%, 25%, material). The *shape* is consistent (always a
> capsule, always tint-fill + tint-border) but no shared constant exists.

### 7.5 Progress bar

Three implementations.

**(a) Tracker header** (`TrackerSectionView.swift:317-318`) — the system control:
```swift
ProgressView(value: Double(done), total: Double(allItems.count))
    .tint(LSTheme.accent)
```
Preceded by a right-aligned `"\(done)/\(count)"` in `.subheadline.monospacedDigit()` `.secondary`, plus
an eye/eye-slash toggle for hiding completed items.

**(b) Stats bar** (`StatsView.swift:148-157`) — hand-built, and the more distinctive one:
```swift
GeometryReader { geo in
    ZStack(alignment: .leading) {
        Capsule().fill(.white.opacity(0.06))                       // track
        Capsule()
            .fill(LinearGradient(colors: [color, color.opacity(0.55)],
                                 startPoint: .leading, endPoint: .trailing))
            .frame(width: max(4, geo.size.width * fraction))        // min 4pt stub
    }
}
.frame(height: 6)
```
The **fill is a gradient that fades to 55% of itself left→right**, and there is a **4pt minimum width**
so a nonzero-but-tiny value still shows.

**(c) Indeterminate shimmer** (`GeneratingTrackerView.swift:104-126`) — height 4, capsule track at
`white 7%`, a band 40% of the width filled with `torch 0 → 0.85 → 0` sweeping left to right on a
**1.6 s** loop.

### 7.6 Rank controls

`UI/RankControls.swift`. Four displays, chosen by `RankDisplay.resolve(explicit:categoryName:maxRank:)`
(`:22-35`). The resolution order is: explicit schema hint → category name contains "keepsake" → hearts →
`maxRank ≤ 5` → pips → `maxRank ≤ 12` → numbered → stepper.

| Display | Construction | Citation |
|---|---|---|
| **pips** | `circle.fill` at `.system(size: 11)`, `HStack(spacing: 5)`; filled = tint, unfilled = `.quaternary` | `:52, :72-89` |
| **hearts** | identical but `heart.fill` at size **13**; tinted `.pink` when the category is "keepsake" | `:53`, `TrackerSectionView.swift:550` |
| **numbered** | 20 × 20 boxes, radius 5, `HStack(spacing: 4)`, `.caption2.monospacedDigit().weight(.medium)`; filled = `tint @ 90%` + white text, unfilled = `white @ 6%` + `.secondary` | `:91-111` |
| **stepper** | system `Stepper` with `"\(current)/\(maxRank)"`, `.caption.monospacedDigit()`, `.controlSize(.mini)` | `:113-120` |

All are **tap-to-set**: tapping pip *n* sets rank *n*; tapping the pip you're already on sets `n − 1`,
so a mis-tap costs one tap to undo (`:39-40, :76, :94`). Both pips and numbered animate with
`.snappy(duration: 0.18)`; pips also use `.contentTransition(.symbolEffect(.replace))`.

Optional per-rank names ("Base", "Upgraded") render beside the control in `.caption2` `.secondary`
(`:58-63`).

---

## 8. Iconography

### 8.1 SF Symbols conventions

The app is SF-Symbols-first; there are no custom vector glyphs except the door mark and the console
renders.

**Conventions observed:**

1. **Filled variants for status and state, outline for actions.** Status glyphs are `.fill`
   (`play.circle.fill`, `checkmark.circle.fill`, `heart.fill`) but `backlog`/`shelved`/`abandoned` are
   *not* (`tray.full`, `archivebox`, `xmark.circle`).
   > **Inconsistency:** the status symbol set is half-filled, half-outline with no stated rule
   > (`Formatting.swift:37-48`). Five filled, three outline.

2. **Toggle state via `symbolVariant`** rather than two symbol names, where possible:
   `.symbolVariant(on ? .fill : .none)` (`OwnershipControl.swift:25`).

3. **Icons sized by text style, not points.** Almost every glyph is `.font(.caption)`,
   `.font(.caption2)`, `.font(.subheadline)` etc., so they scale with Dynamic Type. Raw
   `.system(size:)` only for the sub-11pt decorations listed in §2.3.

4. **Chevron vocabulary:** `chevron.right` `.caption2` `.tertiary` = "this row navigates".
   `chevron.down` rotating = "this section collapses". `chevron.up.chevron.down` `.caption2` = "this is
   a menu" (`GameDetailView.swift:273-275`).

5. **`Label(_:systemImage:)` for anything with text**, never a hand-built HStack of icon + text, except
   where custom spacing is needed.

6. **Circular icon buttons** in the stage panels share one recipe: glyph at `.caption.weight(.bold)`,
   `.padding(6)`, `.background(.white.opacity(0.08), in: .circle)` (`GameDetailView.swift:411-414`,
   `:470-473`, `:507-510`).

**Tab bar** (`RootView.swift:19-24`): `house.fill`, `square.grid.2x2.fill`, `bag.fill`,
`chart.bar.fill` — all filled, tinted `LSTheme.accent`. The wishlist deliberately uses a **bag, not a
heart**: *"the wishlist is things to buy, and a heart reads as 'favorited' (which is what `pinned`
already means)"* (`RootView.swift:21-22`).

**Section icons** (`GameDetailView.swift:301-352`): `stopwatch`, `flag.checkered`, `checklist`,
`play.rectangle`, `text.alignleft`, `info.circle`, `tag`, `star.bubble`, `note.text`. All outline.

**Ownership** (`Enums.swift:29-35`): `opticaldisc` / `arrow.down.circle` / `cpu`.

### 8.2 The claymorphic console icons

Platform icons are **raster PNGs**, not symbols. Resolved by substring match on the IGDB platform string
(`LibraryView.swift:445-484`), returning an asset name like `platform-snes`; `nil` falls back to
`gamecontroller.fill` tinted with the accent (`PlatformViews.swift:17-20`).

Asset catalog: 27 `platform-*.imageset` entries in `Assets.xcassets` — these are what the app ships
and reads. The 1024 × 1024 transparent-background source renders they were derived from are kept
outside this public repo, at `~/Dev/archive/levelselect-art/console-icon-sources/` (37 PNGs, named
descriptively: `super-nintendo-entertainment-system.png`, `nintendo-switch-2.png`,
`ps5-original-disc.png`). Reach for them when a new platform needs an icon; the app's copies are
resized and renamed derivatives.

**The style, as observed in the rendered art:**

- **Three-quarter isometric view**, consistently lit and consistently angled across the set — the
  console sits rotated ~35° with its front-left corner toward the viewer, tilted slightly down so you
  see the top face.
- **Matte plastic**, not glossy. Broad soft diffuse shading with almost no specular highlight; a single
  soft key light from the upper left.
- **Heavily rounded, beveled edges** — every hard corner of the real hardware is softened. This is the
  claymorphic part: the object reads as molded from a soft solid rather than assembled from panels.
- **Authentic but slightly desaturated hardware colors** (the SNES is its real off-white grey with the
  lilac/violet buttons and slot cover — note how well that lilac happens to sit next to the brand
  purple).
- **A soft contact shadow** grounding the object, and where the hardware has a controller, it is
  included with its cable drawn as a soft curve.
- **Transparent background**, square canvas, object roughly filling 85–90% of the frame.
- Detail level is *simplified realism*: real proportions and real port/vent details, but no textures,
  no logos, no text.

**How they're presented** (`PlatformViews.swift:50-63`): a 54pt icon inside an 84 × 84 well with a
`white 5%` fill, an 18pt continuous corner radius and a `white 7%` hairline border, with the platform
short name in `.caption.weight(.medium)` beneath and a count in `.caption2` `.secondary`.

Also used inline at small sizes: 20pt in the detail hero metadata line (`GameDetailView.swift:603`),
15pt in library rows (`GameRow.swift:25`), 24pt in the platform page toolbar (`PlatformViews.swift:112`).

> **Inconsistency:** the doc comment above `PlatformShort` still says *"Placeholder icons for now —
> swappable for the soft-3D console icons later"* (`LibraryView.swift:487-488`). The soft-3D icons are
> already shipped; the comment is stale.

### 8.3 The door mark

`Assets.xcassets/DoorMark.imageset/door-mark.png` — the dungeon-door icon that `LSTheme.torch` is named
after (*"Torch orange from the dungeon-door icon/wordmark artwork"*, `Theme.swift:36`). Used only in
`Wordmark(showsIcon: true)`, i.e. only in Settings. `LaunchLogo` and `LockupWide` are separate baked
lockups.

---

## TRANSLATING TO CSS

Everything below is a translation of the values above. Where the app is inconsistent, this section
picks the majority value and says so.

### T.1 Custom properties

```css
:root {
  /* ---- Brand ---- */
  --ls-purple:        #945CFA;   /* LSTheme.purple — default accent */
  --ls-purple-deep:   #4C298C;   /* LSTheme.purpleDeep */
  --ls-torch:         #F5A34C;   /* LSTheme.torch — WORDMARK COLOR */
  --ls-torch-shadow:  #8A4A12;   /* LSTheme.torchShadow — hard pixel shadow */

  /* The live accent. The app lets users change this; the site should not.
     Kept as its own token so accent-tinted surfaces stay derivable. */
  --ls-accent:        var(--ls-purple);
  --ls-accent-rgb:    148 92 250;   /* for color-mix / rgb() alpha syntax */

  /* ---- Ground ---- */
  --ls-bg-top:        #1A122E;
  --ls-bg-bottom:     #0D0A17;
  --ls-bg: linear-gradient(to bottom, var(--ls-bg-top), var(--ls-bg-bottom));
  --ls-hero-bg: linear-gradient(to bottom right,
                  rgb(76 41 140 / 0.85), #1F1438);
  --ls-splash-bg:     #15112A;

  /* ---- Surfaces (the workhorses) ---- */
  --ls-card-fill:     rgb(255 255 255 / 0.06);
  --ls-card-border:   rgb(255 255 255 / 0.07);
  --ls-well-fill:     rgb(255 255 255 / 0.05);
  --ls-button-fill:   rgb(255 255 255 / 0.08);

  /* ---- Text (SwiftUI hierarchical, dark mode) ---- */
  --ls-text:          rgb(255 255 255 / 1);
  --ls-text-2:        rgb(255 255 255 / 0.60);
  --ls-text-3:        rgb(255 255 255 / 0.30);
  --ls-text-4:        rgb(255 255 255 / 0.18);

  /* ---- Status ---- */
  --ls-playing:   #30D158;
  --ls-paused:    #FF9F0A;
  --ls-completed: #0A84FF;
  --ls-queued:    #BF5AF2;
  --ls-backlog:   #8E8E93;
  --ls-shelved:   #AC8E68;
  --ls-abandoned: #FF453A;
  --ls-wishlist:  #FF375F;
  --ls-star:      #FFD60A;

  /* ---- Radii ---- */
  --ls-r-cover-sm:  6px;
  --ls-r-cover:     10px;
  --ls-r-cover-lg:  14px;
  --ls-r-chip:      7px;    /* small square icon wells */
  --ls-r-card:      16px;   /* lsCard() */
  --ls-r-panel:     14px;
  --ls-r-tile:      18px;   /* Systems shelf */

  /* ---- Spacing (values the app actually uses) ---- */
  --ls-s-1:  2px;
  --ls-s-2:  4px;
  --ls-s-3:  6px;
  --ls-s-4:  8px;
  --ls-s-5:  10px;
  --ls-s-6:  12px;
  --ls-s-7:  14px;   /* card padding */
  --ls-s-8:  16px;   /* default page padding */
  --ls-s-9:  20px;   /* section spacing */
  --ls-s-10: 26px;   /* top-level Home section spacing */

  --ls-measure: 640px;   /* the reading width */
}

html { color-scheme: dark; }   /* the app is .preferredColorScheme(.dark) — no light mode */

body {
  background: var(--ls-bg);
  background-attachment: fixed;   /* SwiftUI's gradient does not scroll with content */
  color: var(--ls-text);
  font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI",
               Roboto, Helvetica, Arial, sans-serif;
}
```

Note `background-attachment: fixed`. `.lsBackground()` applies the gradient to the container behind a
`ScrollView`, so it does **not** scroll away. A plain `background: linear-gradient(...)` on `body` will
stretch over the full document height and read differently on a long page.

### T.2 Typography

**Load Press Start 2P self-hosted.** The app ships the TTF (`Resources/PressStart2P-Regular.ttf`, OFL) —
copy it into `site/public/fonts/` rather than pulling from Google Fonts, so the site and the app are
byte-identical typographically and the site has no third-party font request.

```css
@font-face {
  font-family: "Press Start 2P";
  src: url("/fonts/PressStart2P-Regular.woff2") format("woff2"),
       url("/fonts/PressStart2P-Regular.ttf")   format("truetype");
  font-weight: 400;
  font-style: normal;
  font-display: block;   /* block, not swap: a fallback-then-swap on a pixel
                            wordmark is a visible layout jolt */
}
```

**THE RULE, in CSS terms:**

```css
/* Press Start 2P applies to ONE selector on the whole site. */
.ls-wordmark { font-family: "Press Start 2P", monospace; }

/* Everything else — every heading, every button, every number — is the system font.
   Do NOT use the pixel font for h1/h2, nav links, stat numbers, or buttons.
   The app never does. */
```

Type scale, mapped from SwiftUI text styles at their iOS defaults:

```css
:root {
  --ls-t-caption2:   0.6875rem; /* 11 */
  --ls-t-caption:    0.75rem;   /* 12 */
  --ls-t-footnote:   0.8125rem; /* 13 */
  --ls-t-subhead:    0.9375rem; /* 15 — the body default */
  --ls-t-callout:    1rem;      /* 16 */
  --ls-t-headline:   1.0625rem; /* 17, weight 600 */
  --ls-t-title3:     1.25rem;   /* 20, weight 700 */
  --ls-t-title2:     1.375rem;  /* 22, weight 700 */
  --ls-t-largetitle: 2.125rem;  /* 34 */
}

/* Anything that ticks or counts */
.ls-numeric { font-variant-numeric: tabular-nums; }

/* The one eyebrow label pattern (RootView.swift:246-249) */
.ls-eyebrow {
  font-size: var(--ls-t-caption);
  font-weight: 600;
  letter-spacing: 1px;         /* .kerning(1) is absolute points, not em */
  color: var(--ls-text-2);
  text-transform: uppercase;
}

/* The session timer is the app's only rounded-design type */
.ls-timer {
  font-family: ui-rounded, "SF Pro Rounded", system-ui, sans-serif;
  font-size: var(--ls-t-largetitle);
  font-variant-numeric: tabular-nums;
  color: var(--ls-accent);
}
```

### T.3 The wordmark

`text-shadow` takes `x y blur color`, which maps directly onto the two SwiftUI shadows. The critical
detail is **the first shadow has zero blur** — that is not an approximation, it is the whole point.

```css
.ls-wordmark {
  font-family: "Press Start 2P", monospace;
  color: var(--ls-torch);              /* NOT purple — see §1.8 rule 2 */
  /* 1) hard offset for legibility (blur MUST stay 0)
     2) soft torch glow for atmosphere                  */
  text-shadow:
    0 0.16em 0        var(--ls-torch-shadow),
    0 0     0.65em    rgb(245 163 76 / 0.3);
  /* Press Start 2P has no lowercase distinction in width; it is a fixed
     8x8 pixel grid, so let it set its own tracking. */
  line-height: 1;
}
```

Both offsets are expressed in `em`, which reproduces the app's `size × 0.16` / `size × 0.65` scaling
exactly at any font-size. The app's `max(1, size * 0.16)` floor only matters below 6.25px, which no web
rendering will hit.

At the two real app sizes:

```css
.ls-wordmark--nav      { font-size: 13px; }  /* → 2.08px offset,  8.45px glow */
.ls-wordmark--settings { font-size: 22px; }  /* → 3.52px offset, 14.3px glow  */
/* A marketing hero will want something much larger; the em-based recipe scales. */
```

**Pixel-font rendering caution:** Press Start 2P is a bitmap-derived design. On the web it will be
antialiased and go soft at small sizes. If the wordmark looks mushy, restrict it to sizes that are
multiples of 8px, and consider `-webkit-font-smoothing: none` / `image-rendering: pixelated` only if
you rasterize it — do not apply those to live text, they degrade it further on most browsers.

If a custom accent were ever supported on the site, the shadow rule is
`color-mix(in srgb, var(--ls-accent) 45%, black)` (the app's `mix(with: .black, by: 0.55)`).

### T.4 Motion

**Springs → `linear()` easing.** Modern CSS `linear()` can encode a SwiftUI spring essentially exactly,
including overshoot. These were generated by numerically solving the second-order system for
`response`/`dampingFraction` and sampling the unit-step response at 25 points, with the duration set to
0.1% settling time. Use these verbatim.

```css
:root {
  /* --- The app's core interaction springs --- */

  /* spring(response: 0.3, dampingFraction: 0.7)  — pressable card, rating label */
  --ls-spring-press: 492ms linear(
    0, 0.0751, 0.2424, 0.4375, 0.6213, 0.7737, 0.8881, 0.9661, 1.0135, 1.0376,
    1.0457, 1.0439, 1.0369, 1.0281, 1.0194, 1.012, 1.0063, 1.0023, 0.9998,
    0.9985, 0.9979, 0.9979, 0.9982, 0.9986, 0.999);

  /* spring(response: 0.16, dampingFraction: 0.5) — BouncyTap press-in */
  --ls-spring-tapdown: 324ms linear(
    0, 0.116, 0.3727, 0.6574, 0.898, 1.0613, 1.1444, 1.1625, 1.1385, 1.0949,
    1.049, 1.0115, 0.987, 0.9754, 0.9738, 0.9784, 0.9857, 0.9931, 0.9989,
    1.0025, 1.0041, 1.0042, 1.0033, 1.0021, 1.001);

  /* spring(response: 0.32, dampingFraction: 0.55) — BouncyTap release */
  --ls-spring-tapup: 643ms linear(
    0, 0.1126, 0.358, 0.6273, 0.8549, 1.0123, 1.098, 1.1259, 1.1157, 1.0862,
    1.052, 1.0221, 1.0008, 0.9887, 0.9843, 0.985, 0.9885, 0.9928, 0.9967,
    0.9996, 1.0013, 1.002, 1.0019, 1.0015, 1.001);

  /* spring(response: 0.32, dampingFraction: 0.8) — collapse / disclosure */
  --ls-spring-collapse: 432ms linear(
    0, 0.0517, 0.1705, 0.3164, 0.4638, 0.5982, 0.7125, 0.8045, 0.8753, 0.9273,
    0.9637, 0.9878, 1.0026, 1.0108, 1.0144, 1.0151, 1.0141, 1.0122, 1.0099,
    1.0077, 1.0057, 1.0041, 1.0027, 1.0017, 1.001);

  /* spring(response: 0.28, dampingFraction: 0.6) — chip toggle */
  --ls-spring-chip: 454ms linear(
    0, 0.0755, 0.2494, 0.4583, 0.6592, 0.8273, 0.9523, 1.0341, 1.0785, 1.0942,
    1.0906, 1.0758, 1.0564, 1.0369, 1.02, 1.0071, 0.9984, 0.9933, 0.9912,
    0.9912, 0.9924, 0.9942, 0.9961, 0.9977, 0.9991);

  /* spring(response: 0.5, dampingFraction: 0.72) — modal / showcase appear */
  --ls-spring-appear: 804ms linear(
    0, 0.0721, 0.2329, 0.4211, 0.5995, 0.7493, 0.8638, 0.9441, 0.9952, 1.0237,
    1.0362, 1.0382, 1.0343, 1.0277, 1.0205, 1.0138, 1.0084, 1.0044, 1.0016,
    0.9998, 0.9989, 0.9986, 0.9986, 0.9987, 0.999);

  /* spring(response: 0.5, dampingFraction: 0.85) — stage slide (also 0.4/0.85 close) */
  --ls-spring-slide: 697ms linear(
    0, 0.0541, 0.1761, 0.3225, 0.4678, 0.5981, 0.7076, 0.7952, 0.8624, 0.9121,
    0.9474, 0.9715, 0.9873, 0.9971, 1.0026, 1.0053, 1.0062, 1.0061, 1.0055,
    1.0046, 1.0037, 1.0028, 1.0021, 1.0015, 1.001);

  /* spring(response: 0.75, dampingFraction: 0.32) — the cover-spin wobble.
     The signature "everything moves, nothing snaps" gesture. Overshoots to 135%. */
  --ls-spring-wobble: 2503ms linear(
    0, 0.3004, 0.856, 1.2526, 1.3408, 1.2042, 1.0141, 0.8977, 0.8873, 0.9432,
    1.0063, 1.0389, 1.0362, 1.0148, 0.9944, 0.9858, 0.9887, 0.9965, 1.0029,
    1.005, 1.0034, 1.0007, 0.9987, 0.9983, 0.999);

  /* snappy(duration: 0.18) — rank pips, small discrete state changes */
  --ls-snappy: 251ms linear(
    0, 0.0542, 0.1762, 0.3227, 0.4679, 0.5983, 0.7078, 0.7954, 0.8626, 0.9122,
    0.9475, 0.9716, 0.9874, 0.9971, 1.0026, 1.0053, 1.0062, 1.0061, 1.0055,
    1.0046, 1.0036, 1.0028, 1.0021, 1.0015, 1.001);
}
```

**cubic-bezier fallbacks** for older browsers (no overshoot; the bounce is lost but the timing is close):

```css
/* @supports not (transition-timing-function: linear(0, 1)) */
--ls-spring-press-fallback:    360ms cubic-bezier(0.22, 1.00, 0.36, 1.00);  /* easeOutQuint-ish */
--ls-spring-collapse-fallback: 320ms cubic-bezier(0.34, 1.16, 0.64, 1.00);
--ls-spring-tapup-fallback:    380ms cubic-bezier(0.34, 1.56, 0.64, 1.00);  /* back-out, fakes bounce */
--ls-snappy-fallback:          180ms cubic-bezier(0.33, 1.00, 0.68, 1.00);
```

**Non-spring easings, translated directly:**

```css
--ls-ease-shine:  850ms cubic-bezier(0.42, 0, 0.58, 1);   /* easeInOut(0.85) — cover shine */
--ls-ease-pulse:  3300ms cubic-bezier(0.42, 0, 0.58, 1);  /* easeInOut(3.3)  — LivePulse half-cycle */
--ls-ease-splash: 500ms cubic-bezier(0, 0, 0.58, 1);      /* easeOut(0.5)    — splash fade */
--ls-ease-stage:  350ms cubic-bezier(0.42, 0, 0.58, 1);   /* easeInOut(0.35) — caption crossfade */
--ls-ease-spark:  550ms cubic-bezier(0, 0, 0.58, 1);      /* easeOut(0.55)   — sparkle burst */
```

**Usage:**

```css
.ls-card--pressable { transition: transform var(--ls-spring-press),
                                  opacity   var(--ls-spring-press); }
.ls-card--pressable:active { transform: scale(0.96); opacity: 0.9; }

.ls-chip { transition: background-color var(--ls-spring-chip),
                       border-color     var(--ls-spring-chip),
                       transform        var(--ls-spring-chip); }
.ls-chip:not([aria-pressed="true"]) { transform: scale(0.98); }

.ls-disclosure__chevron { transition: transform var(--ls-spring-collapse); }
.ls-disclosure[open] .ls-disclosure__chevron { transform: rotate(0deg); }
.ls-disclosure       .ls-disclosure__chevron { transform: rotate(-90deg); }
```

### T.5 The LivePulse

The 6.6 s breath. Because CSS `animation-direction: alternate` runs the named keyframes forward then
backward, declare **one 3.3 s half-cycle** and alternate it — that is exactly what
`.repeatForever(autoreverses: true)` does.

```css
@keyframes ls-pulse {
  from { opacity: 0.14; transform: scale(0.90); }
  to   { opacity: 0.34; transform: scale(1.08); }
}

.ls-pulse {
  width: 130px;
  height: 130px;
  border-radius: 50%;
  background: var(--ls-accent);
  filter: blur(42px);
  pointer-events: none;

  animation: ls-pulse 3.3s cubic-bezier(0.42, 0, 0.58, 1) infinite alternate;
}

/* Reduce Motion: the app holds the BRIGHT end, it does not stop at the dim end
   and it does not remove the glow. (Theme.swift:155) */
@media (prefers-reduced-motion: reduce) {
  .ls-pulse { animation: none; opacity: 0.34; transform: scale(1.08); }
}
```

Two notes on fidelity:

- SwiftUI's `blur(radius: 42)` is a Gaussian with σ ≈ radius/2 on Apple platforms, whereas CSS
  `filter: blur(42px)` takes σ directly. If the web glow looks too diffuse, try `blur(21px)` — but
  `42px` matches the *visual* spread more closely in practice because the SwiftUI circle is also being
  scaled. Tune by eye against a screenshot.
- The pulse sits **behind** the timer, so it needs `position: absolute; z-index: -1` (or a
  `::before`) plus a positioned parent — it must not affect layout.

### T.6 The cover shine

A one-shot 0.85 s diagonal sweep, fired on appear with a 0.35 s delay.

```css
.ls-cover { position: relative; overflow: hidden; }

.ls-cover::after {
  content: "";
  position: absolute;
  top: -25%;
  bottom: -25%;
  left: 0;
  width: 45%;                                   /* w * 0.45 */
  transform: rotate(22deg) translateX(-140%);   /* phase = -1.4 */
  background: linear-gradient(to right,
              transparent, rgb(255 255 255 / 0.35), transparent);
  mix-blend-mode: plus-lighter;                 /* .blendMode(.plusLighter) */
  pointer-events: none;
  animation: ls-shine 850ms cubic-bezier(0.42, 0, 0.58, 1) 350ms 1 both;
}

@keyframes ls-shine {
  from { transform: rotate(22deg) translateX(-140%); }
  to   { transform: rotate(22deg) translateX(311%);  }
  /* SwiftUI offsets by phase * containerWidth; the band is 45% of that width,
     so -1.4w → +1.4w in band-widths is -311% → +311%. Starting at -140% of the
     band (≈ -0.63w) is close enough visually and avoids a long dead lead-in. */
}

@media (prefers-reduced-motion: reduce) {
  .ls-cover::after { animation: none; opacity: 0; }   /* the app skips it entirely */
}
```

To fire it on scroll-into-view rather than page load (the app fires it when the cover *appears*), gate
it with an `IntersectionObserver` that adds a class, or use `animation-timeline: view()` where supported.

### T.7 Surfaces

**The card:**

```css
.ls-card {
  padding: 14px;
  border-radius: 16px;
  background: var(--ls-card-fill);
  border: 1px solid var(--ls-card-border);
  /* no shadow — lsCard() has none */
}

.ls-card--hero {
  padding: 14px;
  border-radius: 16px;
  background: var(--ls-hero-bg);
  border: 1px solid rgb(var(--ls-accent-rgb) / 0.35);
}
```

**The cover gloss.** Four layers with two different blend modes. In CSS this needs two pseudo-elements
plus the border, because `mix-blend-mode` applies per element:

```css
.ls-cover {
  position: relative;
  border-radius: var(--ls-r-cover);
  overflow: hidden;
  /* Layer 4: top hairline */
  box-shadow: inset 0 0 0 1px rgb(255 255 255 / 0.45);   /* approximation, see note */
}

/* Layers 1 + 2: soft-light sheen and specular hotspot */
.ls-cover::before {
  content: "";
  position: absolute;
  inset: 0;
  pointer-events: none;
  mix-blend-mode: soft-light;
  background:
    /* Layer 2 — convex hotspot at (30%, 18%) */
    radial-gradient(ellipse 60% 60% at 30% 18%,
      rgb(255 255 255 / 0.22), transparent),
    /* Layer 1 — top-left sheen */
    linear-gradient(to bottom right,
      rgb(255 255 255 / 0.32) 0%,
      rgb(255 255 255 / 0.06) 30%,
      transparent             58%);
}

/* Layer 3: grounding shadow at the bottom edge */
.ls-cover::after {
  content: "";
  position: absolute;
  inset: 50% 0 0 0;
  pointer-events: none;
  mix-blend-mode: multiply;
  background: linear-gradient(to bottom, transparent, rgb(0 0 0 / 0.22));
}
```

> The hairline is a **gradient** stroke in the app (`white 0.45` at the top fading to `white 0.02` at
> the bottom), which `box-shadow: inset` cannot do. For fidelity use a `border-image` or a third
> pseudo-element with `padding: 1px` and a masked gradient background; for most site uses the flat
> `inset 0 0 0 1px rgb(255 255 255 / 0.18)` compromise reads correctly and is much simpler.

**Material / blur panels:**

```css
/* .ultraThinMaterial over a dark ground */
.ls-material {
  background: rgb(255 255 255 / 0.10);
  backdrop-filter: blur(20px) saturate(180%);
  -webkit-backdrop-filter: blur(20px) saturate(180%);
}
/* .regularMaterial */
.ls-material--regular {
  background: rgb(28 28 30 / 0.72);
  backdrop-filter: blur(30px) saturate(180%);
}
```

**The ambient cover backdrop** — the single most recognizable page treatment, and very cheap on the web:

```css
.ls-ambient {
  position: absolute;
  inset: 0 0 auto 0;
  height: 420px;
  z-index: -1;
  background-image: var(--cover-url);   /* set inline per game */
  background-size: cover;
  background-position: center;
  filter: blur(60px) saturate(1.5);
  opacity: 0.55;
  transform: scale(1.1);   /* blur eats the edges; SwiftUI's opaque:true avoids
                              this, CSS needs the overscale instead */
  -webkit-mask-image: linear-gradient(to bottom,
      #000 0%, rgb(0 0 0 / 0.6) 55%, transparent 100%);
          mask-image: linear-gradient(to bottom,
      #000 0%, rgb(0 0 0 / 0.6) 55%, transparent 100%);
}
```

**Shadows:**

```css
--ls-shadow-cover-sm: 0 2px 5px rgb(0 0 0 / 0.40);
--ls-shadow-cover-md: 0 3px 6px rgb(0 0 0 / 0.45);
--ls-shadow-cover-lg: 0 4px 8px rgb(0 0 0 / 0.50);
--ls-shadow-showcase: 0 24px 26px rgb(0 0 0 / 0.55);
```

SwiftUI `radius` ≈ CSS blur-radius for shadows (both are roughly 2σ), so the mapping is 1:1.

### T.8 Layout

```css
.ls-measure {
  max-width: var(--ls-measure);   /* 640px */
  margin-inline: auto;
  padding: 16px;
}
```

This reproduces the `frame(maxWidth: 640, alignment: .leading).frame(maxWidth: .infinity)` idiom:
constrain, then center the constrained block. Note the app applies `.padding()` *inside* the 640 clamp,
so the actual text measure is **608px**, not 640.

> The app applies this to the game detail page only. A marketing site will want it on prose sections
> and a wider container on hero/gallery sections — that is a reasonable divergence, since Home and
> Library in the app are unconstrained too.

```css
/* Cover aspect — always 3:4 */
.ls-cover { aspect-ratio: 3 / 4; }

/* Library grid — GridItem(.adaptive(minimum: 105), spacing: 12), row spacing 16 */
.ls-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(105px, 1fr));
  gap: 16px 12px;
}

/* Tracker dense grid — .adaptive(minimum: 180), spacing 2 */
.ls-grid--dense {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(180px, 1fr));
  gap: 2px;
}

/* Horizontal carousel — LazyHStack(spacing: 14) + scrollTargetBehavior(.viewAligned) */
.ls-carousel {
  display: flex;
  gap: 14px;
  overflow-x: auto;
  scroll-snap-type: x mandatory;
  scrollbar-width: none;                 /* .scrollIndicators(.hidden) */
  padding-inline: 16px;
}
.ls-carousel::-webkit-scrollbar { display: none; }
.ls-carousel > * { scroll-snap-align: start; flex: 0 0 auto; }
```

**Carousel scroll transition** (`CoverCard.swift:84-89`) — the covers that scale, fade and tilt as they
scroll. This maps onto scroll-driven animations where supported:

```css
@supports (animation-timeline: view(inline)) {
  .ls-carousel > * {
    animation: ls-shelf linear both;
    animation-timeline: view(inline);
    animation-range: entry 0% cover 15%, cover 85% exit 100%;
  }
  @keyframes ls-shelf {
    from { transform: scale(0.86) perspective(600px) rotateY(-12deg); opacity: 0.6; }
    50%  { transform: scale(1)    perspective(600px) rotateY(0deg);   opacity: 1; }
    to   { transform: scale(0.86) perspective(600px) rotateY(12deg);  opacity: 0.6; }
  }
}
```

### T.9 Components

**Chip / pill:**

```css
.ls-chip {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  font-size: var(--ls-t-caption);
  padding: 5px 10px;
  border-radius: 999px;
  background: rgb(var(--ls-accent-rgb) / 0.18);
  border: 1px solid rgb(var(--ls-accent-rgb) / 0.35);
  color: var(--ls-text);
}
/* Selected state (OwnershipControl) */
.ls-chip[aria-pressed="true"] {
  background: rgb(var(--ls-accent-rgb) / 0.20);
  border-color: rgb(var(--ls-accent-rgb) / 0.55);
  color: var(--ls-accent);
}
```

**Progress bar** — use the Stats recipe (`b` in §7.5), it's the distinctive one:

```css
.ls-progress {
  height: 6px;
  border-radius: 999px;
  background: rgb(255 255 255 / 0.06);
  overflow: hidden;
}
.ls-progress__fill {
  height: 100%;
  min-width: 4px;                      /* the app's max(4, ...) floor */
  border-radius: 999px;
  background: linear-gradient(to right,
              var(--ls-accent),
              color-mix(in srgb, var(--ls-accent) 55%, transparent));
  transition: width var(--ls-spring-collapse);
}
```

**Indeterminate shimmer** (generating state):

```css
.ls-shimmer {
  height: 4px;
  border-radius: 999px;
  background: rgb(255 255 255 / 0.07);
  overflow: hidden;
  position: relative;
}
.ls-shimmer::after {
  content: "";
  position: absolute;
  inset-block: 0;
  width: 40%;
  background: linear-gradient(to right,
              rgb(245 163 76 / 0), rgb(245 163 76 / 0.85), rgb(245 163 76 / 0));
  animation: ls-sweep 1.6s linear infinite;
}
@keyframes ls-sweep {
  from { transform: translateX(-100%); }
  to   { transform: translateX(250%); }
}
```

**Section header (disclosure):**

```css
.ls-section__header {
  display: flex;
  align-items: center;
  gap: 6px;
  font-size: var(--ls-t-headline);
  font-weight: 600;
  cursor: pointer;
}
.ls-section__chevron {
  margin-left: auto;
  font-size: var(--ls-t-caption);
  color: var(--ls-text-2);
  transform: rotate(-90deg);
  transition: transform var(--ls-spring-collapse);
}
[open] > .ls-section__header .ls-section__chevron { transform: rotate(0); }
```

**Systems tile:**

```css
.ls-tile {
  width: 84px;
  height: 84px;
  display: grid;
  place-items: center;
  border-radius: 18px;
  background: var(--ls-well-fill);
  border: 1px solid var(--ls-card-border);
}
.ls-tile img { width: 54px; height: 54px; object-fit: contain; }
```

### T.10 Iconography on the web

- **SF Symbols cannot be used on the web.** They are not licensed for it and are not a webfont. Use an
  outline icon set with matching metrics — Lucide and Phosphor both have close analogues for
  `play.circle.fill`, `checkmark.circle.fill`, `chevron.right`, `stopwatch`, `checklist`,
  `flag.checkered`, `sparkles`, `tag`. Match the *convention* (§8.1), not the exact glyph: filled for
  status/state, outline for actions and section headers; sized by the adjacent text style; chevrons at
  `--ls-text-3`.
- **The console icons transfer directly.** The site's copies live at `site/public/assets/sys-*.png`;
  the 1024px transparent sources are archived outside the repo (see above). Convert to WebP/AVIF and
  serve at 2× the display size. They are the single strongest visual asset the app has and the site
  should lean on them.
- **The door mark** (`Assets.xcassets/DoorMark.imageset/door-mark.png`) is the wordmark's companion; if
  the site uses a lockup, it belongs at `2.1em` height beside the type with `0.55em` of gap
  (`Wordmark.swift:24,29`) and its own `drop-shadow(0 0.12em 0.35em rgb(0 0 0 / 0.5))`.

### T.11 Reduce Motion

The app's behavior is not "disable everything" — it is three distinct decisions (§4.6). Mirror them:

```css
@media (prefers-reduced-motion: reduce) {
  /* Shine: skipped entirely */
  .ls-cover::after { animation: none; opacity: 0; }

  /* Pulse: holds the BRIGHT end, still glowing */
  .ls-pulse { animation: none; opacity: 0.34; transform: scale(1.08); }

  /* Springs: keep the motion, remove the bounce.
     Do NOT set everything to 0.01ms — the app doesn't. */
  :root {
    --ls-spring-press:    200ms ease-out;
    --ls-spring-tapdown:  120ms ease-out;
    --ls-spring-tapup:    200ms ease-out;
    --ls-spring-collapse: 200ms ease-out;
    --ls-spring-chip:     180ms ease-out;
    --ls-spring-appear:   250ms ease-out;
    --ls-spring-slide:    250ms ease-out;
    --ls-spring-wobble:   300ms ease-out;
    --ls-snappy:          150ms ease-out;
  }

  /* Scroll-driven shelf transitions: off */
  .ls-carousel > * { animation: none; }
}
```

### T.12 Fidelity checklist

If the site does only five things, do these — they carry the identity:

1. **Vertical `#1A122E → #0D0A17` gradient ground**, fixed, never a flat black.
2. **Wordmark in Press Start 2P, torch orange `#F5A34C`, with the two-shadow recipe** — zero-blur
   `0 0.16em 0 #8A4A12` plus `0 0 0.65em rgb(245 163 76 / 0.3)`. Pixel font **nowhere else**.
3. **Springs, not eases**, on every interactive state change — `--ls-spring-press` on cards,
   `--ls-spring-collapse` on disclosures. Nothing snaps.
4. **The 6.6 s accent breath** somewhere on the page. It is the app's ambient signature.
5. **Covers get the gloss + a 3:4 ratio + a black 40–50% shadow**, and the claymorphic console icons
   get room to be seen.

---

## Appendix: file map

| File | What it owns |
|---|---|
| `UI/Theme.swift` | `LSTheme` colors and gradients, `lsBackground()`, `lsCard()`, `coverGloss()`, `CoverShine`, `LivePulse`, `PressableCardStyle`, `BouncyTap` |
| `UI/ThemePalette.swift` | Live accent cache, status-color overrides, `Color(hex:)` / `hexString()` |
| `UI/Wordmark.swift` | The wordmark and its two-shadow recipe |
| `UI/Collapsible.swift` | `CollapsibleSection`, `FlowLayout`, `Chip`, `EditableChips` |
| `UI/RankControls.swift` | `RankDisplay`, `RankPicker` (pips/hearts/numbered/stepper), `AltDescription` |
| `UI/CoverShowcase.swift` | The 3D spin-and-wobble cover viewer |
| `UI/CoverCard.swift` | `CoverCard`, `StatusCarousel`, `ContinueHeroCard` (hero gradient) |
| `UI/GameDetailView.swift` | Ambient backdrop, 640pt measure, sliding stage, hero, chips, info grid |
| `UI/TrackerSectionView.swift` | Category disclosure, item rows, dense grid, progress header |
| `UI/TrackerPage.swift` | `CompactTrackerCard` (navigational rows), dedicated tracker page |
| `UI/StatsView.swift` | `lsCard()` usage, stat tiles, the gradient progress bar |
| `UI/PlatformViews.swift` | `PlatformIconView`, Systems shelf tiles |
| `UI/LibraryView.swift` | `PlatformIcon.assetName` mapping, `LibraryGridCell`, `PlatformShort` |
| `UI/Formatting.swift` | `GameStatus` labels/colors/symbols/order, `CoverThumb`, `PlatformPreference` |
| `UI/RootView.swift` | Tab bar, splash, dark-mode lock, theme refresh, Home |
| `UI/AppearanceSettings.swift` | Accent + status color pickers, page background choice |
| `UI/RatingControl.swift` | Star rating, sparkle burst |
| `UI/OwnershipControl.swift` | Selectable chips, ownership badges |
| `UI/GeneratingTrackerView.swift` | Torch pulse, shimmer bar, staged captions |
| `UI/SessionControlsView.swift` | The timer, `LivePulse` host |
| `Services/FontRegistrar.swift` | Runtime registration of Press Start 2P |
| `Assets.xcassets/` | `DoorMark`, `LaunchLogo`, `LockupWide`, `LaunchBackground`, 27 `platform-*` |
| `Resources/PressStart2P-Regular.ttf` | The pixel font (OFL, license alongside) |
| `site/public/assets/sys-*.png` | The site's console art (app-sized copies) |
| _(archived outside repo)_ | 37 source console renders, 1024px, transparent — `~/Dev/archive/levelselect-art/` |
