# Chess Camera — UI / UX

**Companion to:** [PRD.md](PRD.md), [APP_FLOW.md](APP_FLOW.md)
**Platform:** iPhone, SwiftUI, iOS 18+
**Style:** Dark camera tool — scanner energy, not a wooden chess-app skin

This is a **recording instrument**. The physical board is the hero. The digital board is a live transcript. UI stays out of the way during play and becomes precise when something is wrong.

Product-type references used: scanner / document digitizer (viewfinder, edge detect, export) + board-game transcript (move list, replay). Not a 3D felt-table game, not a social network, not an engine studio.

---

## 1. Art direction

**Keywords:** dark, precise, quiet, camera-first, high contrast, technical, honest

**Do**

- Full-screen camera during setup and live recording
- Thin vector overlays (quad, last-move arrows), not heavy chrome
- One primary action per screen
- SF Symbols for all icons (no emoji)

**Don’t**

- Skeuomorphic wood, felt green table, ornate piece renderings as the brand
- Neon gamer HUD
- Per-move confirmation modals (auto-accept is the product)
- Color-only status (always pair with text or an icon)

---

## 2. Color system

Semantic tokens only. No raw hex in views.

| Token | Hex | Use |
|---|---|---|
| `background` | `#0F172A` | App chrome, history, replay |
| `surface` | `#1E293B` | Cards, bars, sheets |
| `surfaceMuted` | `#272F42` | Secondary wells |
| `border` | `#475569` | Hairlines, inactive quad |
| `textPrimary` | `#F8FAFC` | Titles, moves |
| `textSecondary` | `#94A3B8` | Captions, FEN label |
| `accent` | `#22C55E` | Live recording, committed move, primary CTA |
| `onAccent` | `#052E16` | Text on accent buttons |
| `caution` | `#F59E0B` | Disturbed / waiting for board |
| `danger` | `#EF4444` | Illegal delta, delete game |
| `boardLight` | `#E2E8F0` | Digital light squares |
| `boardDark` | `#475569` | Digital dark squares |
| `lastMove` | `#22C55E` @ 35% | Last-move highlight on digital board |
| `overlayScrim` | `#000000` @ 55% | Bottom HUD over camera |

**Contrast:** `textPrimary` on `background` and `textPrimary` on `surface` must stay ≥ 4.5:1. Accent green is for controls and highlights, not body text on dark navy.

**Light mode:** not in MVP. Camera-first UI is dark-only. Do not invert.

**Board overlay quad:** white 80% stroke when detecting; accent stroke when locked; caution stroke when tracking is poor.

---

## 3. Typography

System fonts only (Dynamic Type).

| Role | SwiftUI style | Notes |
|---|---|---|
| Large title | `.largeTitle.weight(.bold)` | History, game over |
| Screen title | `.title2.weight(.semibold)` | Confirm start |
| Body | `.body` | Instructions, empty states |
| Callout | `.callout` | Secondary hints |
| Caption | `.caption` | FEN label “FEN” |
| Moves / FEN / PGN | `.body.monospaced()` | Tabular, SF Mono; never truncate mid-SAN without ellipsis |
| Live SAN flash | `.title3.weight(.semibold).monospaced()` | Last committed move |

Minimum readable size: do not use `.caption2` for primary move text. Support Dynamic Type; the digital board scales by available space, not by shrinking SAN below body.

---

## 4. Layout and spacing

- 8 pt grid. Default padding 16. Section gap 24.
- Touch targets ≥ 44×44 pt, ≥ 8 pt apart.
- Safe area: never put “End game” or “Adjust corners” in the home-indicator zone; use `.safeAreaInset`.
- Adaptive live layout (locked decision):

### Portrait (propped phone, default)

```
┌─────────────────────────┐
│  [camera · board quad]  │  ~55%
│                         │
├─────────────────────────┤
│  digital board (square) │  ~28%
├─────────────────────────┤
│  12. Nf3 …  waiting     │  HUD
│  [End]  [Undo]  [···]   │
└─────────────────────────┘
```

### Landscape (tripod / table)

```
┌──────────────────┬─────────────────┐
│                  │  digital board  │
│     camera       ├─────────────────┤
│     + quad       │  move list      │
│                  │  FEN            │
│                  │  [End] [Undo]   │
└──────────────────┴─────────────────┘
```

Use `ViewThatFits` / size class: `verticalSizeClass == .compact` → landscape split. Both orientations are first-class, not an afterthought.

Digital board always **square**. Move list scrolls independently (Lazy stack). Camera view uses `.aspectRatio` / `Color.clear` so it never stretches the board overlay incorrectly — map Vision coordinates through the displayed video gravity (`.resizeAspect`).

---

## 5. Navigation

iOS pattern: `TabView` is **wrong** here (only two destinations, and live recording needs the whole screen).

```
NavigationStack
  History (root)
    → New Game (fullScreenCover) → Detect → Confirm → Live
    → Replay (push) → Share
```

- History is home. One primary CTA: **New Game**.
- Live recording is a `fullScreenCover` so swipe-back cannot kill a game by accident. Exit via **End game** (confirm if moves exist) or checkmate sheet.
- Replay is a push from History or from Game Over.
- Sheets: Edit move, Adjust corners, Share.

Back is always explicit. Confirm before discarding an in-progress game with ≥1 move.

---

## 6. Screens

### 6.1 History (root)

**Empty:** illustration (SF Symbol `checkerboard.rectangle`) + “Games you record will appear here.” + **New Game**.

**Populated:** list by date, title, result if known (`1-0` / `0-1` / `½-½` / `*`), first 6 plies as a caption. Swipe to delete with confirmation. Tap → Replay.

Toolbar: leading app name “Chess Camera”, trailing `plus` = New Game (also a large bottom-or-inline CTA when empty).

### 6.2 Camera permission

System dialog first. If denied: explanation + **Open Settings**. Do not show a live view with a black frame and no copy.

### 6.3 Board detection

Full-screen camera. Centered caption: “Fit the whole board in view.”

- Searching: pulsing white quad candidates (if any) + caption “Looking for the board…”
- Locked: accent quad + **Looks good** (primary) and **Adjust corners** (secondary)
- Timeout (~2 s with no lock): same secondary becomes the suggested path: **Adjust corners**

Do not auto-advance until the user confirms, unless tracking has been stable for ~1 s **and** we are in video-import debug (then auto is OK). For live, prefer an explicit **Looks good** so a table edge is not accepted.

### 6.4 Four-corner calibration

Camera with four draggable handles (44 pt hit areas, larger than the dot). Order: a8-side is **not** assumed — labels are “1 / 2 / 3 / 4” in clockwise order from top-left of the **image**. Hint: “Drag the corners of the board.” Primary: **Use these corners**. Escape: Cancel back to detect.

Handles must stay on-screen; clamp to the video rect.

### 6.5 Confirm starting position

Split: warped top-down thumbnail + digital board built from classified FEN.

- Caption: “White on this side” with a **Flip** control (not color-only: icon `arrow.up.arrow.down` + label).
- If FEN is standard start: checkmark + “Standard starting position.”
- If not: caution banner “This doesn’t look like the start.” Actions: **Recapture**, tap a square to cycle piece (debug-grade but necessary), **Continue anyway** (tertiary, for stretch mid-game).
- Primary: **Start recording** (disabled until FEN is legal).

### 6.6 Live recording

HUD states (one at a time, caption + color + icon):

| State | Icon | Color | Copy |
|---|---|---|---|
| Recording / stable | `record.circle` | accent | Last SAN, e.g. `12. Nf3` |
| Disturbed | `hand.raised` | caution | “Waiting for the board…” |
| Awaiting edit | `exclamationmark.triangle` | danger | “Couldn’t read that move” + **Fix** |
| Check | `checkmark.circle` | accent | “Check” + last SAN |

Controls (all labeled, not icon-only unless 44 pt + `accessibilityLabel`):

- **Undo** — last ply; disabled at start
- **End** — ends game, confirm if not mate
- Overflow: Adjust corners, Recapture position (stretch), Import is not here

Last move: highlight from/to on the **digital** board. Optional faint arrow on camera overlay if the quad is locked (skip if noisy).

FEN is a single-line monospaced field, selectable, with **Copy**.

Haptic: light impact on successful commit. None on disturbed. Warning on illegal/ambiguous. Honor Reduce Motion (no pulse on the quad if set).

### 6.7 Edit move

Sheet, not a new navigation page.

- Show the digital board at the **previous** position.
- User taps from, then to (same pattern as a tiny chess UI). For promotion, a 4-piece picker (Q/R/B/N).
- Or pick from the short list of legal moves if we had `.ambiguous`.
- Primary **Apply**. Secondary **Undo last** (if the bad ply was already committed). Cancel dismisses without change.

If the phase was `awaitingEdit` and nothing was committed, Apply writes the first new ply.

### 6.8 Game over

Full-screen on `surface`. Result (Checkmate — White wins / Draw / Game ended). Mini board. **Replay**, **Share PGN**, **Done** (to History).

### 6.9 Replay

Digital board + slider or step buttons (`chevron.left` / `chevron.right`) + move list (tap a ply to jump). Toolbar: Share. FEN for the shown position, copyable.

Autoplay is optional stretch; if present, respect Reduce Motion (no autoplay by default).

### 6.10 Share

System share sheet. Activity item: `game.pgn` file. Also **Copy PGN** on the replay toolbar for speed.

---

## 7. Adaptive and device

- iPhone 13-class width and Pro Max both required.
- Landscape must keep 44 pt controls; if the move list collides, the list scrolls, controls stay pinned.
- iPad: not designed; default SwiftUI scaling is acceptable.
- Camera preview: `AVCaptureVideoPreviewLayer` videoGravity `.resizeAspect`. Overlay geometry must use the same aspect math (letterboxing). **This is a common bug — specify tests or a debug “dot on a1” overlay.**

---

## 8. Motion

| Event | Motion |
|---|---|
| Screen push | System default |
| Cover present | System full-screen cover |
| Quad lock | Stroke color 200 ms ease-out |
| Move commit | Digital piece 200 ms ease-out to new square; skip if Reduce Motion (snap) |
| Disturbed banner | Opacity 150 ms |
| Sheet | System sheet |

No decorative particle effects. No looping animations except a restrained detecting pulse (disabled under Reduce Motion).

---

## 9. Accessibility

- Every icon button: `accessibilityLabel` (“Undo last move”, “End game”, “Flip board”).
- Move list: each row is a button “Move 12, knight f3” not “Nf3” only.
- Digital board: accessibility container; selected square announced as `e2, white pawn`.
- Live status: `accessibilityAddTraits(.updatesFrequently)` on the HUD caption so VoiceOver can hear “Waiting for the board” / committed SAN (`UIAccessibility.post(notification: .announcement)` on commit — do not spam during disturbed).
- Dynamic Type: HUD can grow; camera region shrinks first.
- Reduce Motion / Reduce Transparency: no blur-only HUD; use solid `surface` at 95% if Reduce Transparency is on.
- Contrast: white overlay on camera is not enough for small text — HUD text sits on scrim, not on the video.

---

## 10. Empty, loading, error

| Situation | UI |
|---|---|
| No games | Empty History (§6.1) |
| Camera denied | Permission screen |
| Detecting > 2 s | Offer corners |
| Classifier running | Disable **Start recording**, `ProgressView` + “Reading pieces…” |
| Illegal/ambiguous | Banner + Fix; game stays on last good FEN |
| Video import fail | Alert with Retry / Cancel |
| Save fail | Alert; keep PGN on screen so the user can copy |

Errors say **what happened** and **what to do** (“Couldn’t read that move. Fix it or undo.”), never “Error 3.”

---

## 11. Copy (product voice)

Short, literal, no jokes, no “magic AI.”

- “Fit the whole board in view.”
- “Looking for the board…”
- “Waiting for the board…”
- “Couldn’t read that move.”
- “Standard starting position.”
- “This doesn’t look like the start.”
- “Start recording”
- “End game”

Avoid: “Neural engine”, “AI sees all”, “Perfect chess vision.”

---

## 12. Components (reuse)

| Component | Used in |
|---|---|
| `DigitalBoardView` | Confirm, Live, Replay, Edit |
| `MoveListView` | Live (landscape), Replay |
| `FenBar` | Live, Replay, Game over |
| `CameraPreview` | Detect, Corners, Live |
| `BoardQuadOverlay` | Detect, Live |
| `StatusBanner` | Live HUD |
| `PrimaryButton` | accent fill, 50 pt height, 12 pt corner radius |
| `SecondaryButton` | border + text |

Corner radius 12 for buttons and cards. 2 pt for digital board squares (flush grid, no gaps).

---

## 13. SwiftUI implementation notes

- Views are structs; logic in `@Observable` `RecordingSessionViewModel`.
- `#Preview` for History empty/filled, Confirm (standard FEN), Live (recording / disturbed / awaitingEdit), Replay.
- Prefer `NavigationStack` + `navigationDestination`.
- `.task` for starting the camera; stop on disappear.
- `@MainActor` ViewModel; pipeline is an actor.
- SF Symbols, not custom icon fonts.

---

## 14. Visual success for the Academy

The live screen should read in one glance: **camera of the real board**, **digital twin**, **last move**. If a reviewer cannot tell that the app is *recording a physical game*, the layout failed — even if the inference is correct.
