# Chess Camera — Product Requirements Document

**Working title:** Chess Camera
**Platform:** iPhone (iOS 18+)
**Horizon:** 10-day Apple Developer Academy Solo Challenge
**Framing:** Product-shaped UI, research-honest scope

---

## 1. One-sentence product

Chess Camera turns a physical chess game into a digitally reviewable game by watching the board with a normal iPhone camera, reading the starting position, detecting when a move has settled, using the rules of chess to infer what happened, and producing a live digital board, FEN, PGN, and replay.

---

## 2. Problem

Friends play chess on a physical board. When the pieces are reset, the game is gone unless someone wrote the moves down. Existing options are poor for a casual over-the-board game:

- Manual notation is slow and breaks the social flow.
- Electronic boards are expensive and require a special set.
- Phone chess apps record *digital* games, not *physical* ones.
- Existing camera chess systems are either research prototypes, desktop-only, or assume a controlled studio setup.

The job to be done:

> After a physical game, I want a PGN I can replay and take to Chess.com / Lichess / an engine — without buying an electronic board and without writing moves by hand.

---

## 3. Users

| User | Role in the 10 days |
|---|---|
| Primary | You and friends playing on **one known chess set**, indoors, with the phone mounted so the **full board is visible** |
| Secondary | Academy mentors / peers watching a live demo |
| Not in scope | Arbitrary chess sets, cafe lighting, handheld walking around the table, tournament arbiters |

The product is a **recording tool**, not a chess tutor and not a replacement for DGT / ChessUp / similar hardware.

---

## 4. Research questions

These are the questions the prototype exists to answer. They belong in the presentation.

1. **Technical:** Can a commodity iPhone camera reconstruct a full physical chess game — including captures and special moves — without an electronic board, under controlled conditions?
2. **HCI:** How should computer vision and user correction work together so a misread move is cheap to fix instead of fatal?
3. **Personal:** Given a prior computer-vision project (waste-sorting), is the interesting territory here *temporal state + geometry + chess constraints*, not “another classifier”?

The interesting story is **not** “the camera recognizes chess pieces.” It is:

> I built a system that turns a physical game into a digital game using a normal camera, then used the rules of chess to resolve visual uncertainty.

---

## 5. Success bar (10 days)

The prototype is a success if, on demo day, all of the following are true on **your chess set**, under **demo lighting**, with the **entire board visible**:

1. The app finds the board automatically, or the user can tap four corners in under 20 seconds.
2. It classifies the standard starting position and infers which side is White.
3. Two people play a complete real game (not a scripted 4-move miniature only).
4. Quiet moves, captures, castling, en passant, and promotion are recorded when they occur.
5. Check / checkmate / stalemate are detected from the rules engine and can end the game.
6. The live digital board stays in sync except during brief “board disturbed” windows (hands over the pieces).
7. A wrong move can be edited or undone without restarting the game.
8. The user can replay the game, copy/share PGN, and see the current FEN.
9. The finished game is saved locally and reopens from History.

A scripted short game that exercises castling and a capture is an acceptable **backup** demo if a full casual game is too long for the slot. It is not the definition of done.

---

## 6. User stories

### Setup

- As a player, I want to prop the phone so the whole board is in view and start recording without a special electronic board.
- As a player, I want the app to find the board for me, and fall back to dragging four corners if it cannot.
- As a player, I want the app to read the starting position and tell me which way White is facing, so I do not have to label a1.

### During the game

- As a player, I want to play normally — pick up pieces, capture, castle — without tapping “move done” after every ply.
- As a player, I want the digital board to update only after the physical board is stable, so a piece in my hand is not recorded as a move.
- As a player, I want to see the last move, the full move list, and the current FEN while we play.
- As a player, I want to tap a recorded move later and correct it (or undo) if the camera got it wrong.

### After the game

- As a player, I want to replay the game on a digital board.
- As a player, I want to copy or share a PGN I can paste into Lichess / Chess.com.
- As a player, I want past games to still be there when I reopen the app.

### Development / Academy

- As the builder, I want to import a recorded video of a game so I can iterate without two people sitting at a board every time.
- As a presenter, I want the UI to look like a real product while remaining honest about what the prototype cannot do.

---

## 7. Functional requirements

### Must have (MVP)

| ID | Requirement |
|---|---|
| FR-1 | Live camera capture on a physical iPhone. |
| FR-2 | Import a recorded video and run the same pipeline (debug + tests + backup demo). |
| FR-3 | Automatic chessboard detection when the full board is visible. |
| FR-4 | Manual 4-corner calibration fallback, persisted for the session. |
| FR-5 | Perspective warp to a square 8×8 grid; map image coordinates to `a1`–`h8`. |
| FR-6 | Core ML piece classifier trained **only on the demo chess set**. |
| FR-7 | Classify the starting position; reject or ask for correction if it is not a legal start (demo path: standard start). |
| FR-8 | Infer board orientation from the classified starting pieces (White’s back rank). |
| FR-9 | After move 0, treat ChessKit game state as source of truth; vision primarily observes occupancy (color as a sanity check). |
| FR-10 | Settle detector: ignore frames while the board is disturbed; commit only after occupancy is stable. |
| FR-11 | Infer the unique legal move that explains the settled delta (quiet moves, captures, castling, en passant, promotion). |
| FR-12 | Auto-accept inferred moves onto the live digital board and move list. |
| FR-13 | User can undo the last move and edit a recorded ply (from/to, promotion piece). |
| FR-14 | Show current FEN; export/copy/share PGN. |
| FR-15 | Post-game replay (step through moves). |
| FR-16 | Detect check, checkmate, and stalemate via the rules engine; offer End game. |
| FR-17 | SwiftData local history: date, PGN, final FEN, move list for replay. |
| FR-18 | Adaptive live layout: portrait stack and landscape split. |
| FR-19 | Camera permission primer and a clear empty/error state if the board is not fully visible. |

### Should have (if time)

| ID | Requirement |
|---|---|
| FR-20 | Move-confidence / “couldn’t read that” banner when 0 or >1 legal moves match. |
| FR-21 | Re-classify a square on demand (recovery after a total desync). |
| FR-22 | Haptic tick when a move is committed. |
| FR-23 | Saved calibration reused when the phone does not move. |

### Must not (explicit non-goals)

See §8.

---

## 8. Non-goals

Out of scope for this challenge. Do not build them, and do not apologize for their absence in the demo — name them as constraints.

- Arbitrary chess sets, boards, or lighting.
- Handheld / walking camera; the phone may be angled but should stay still.
- Automatic detection of a1 from printed letters/numbers on the physical board.
- Per-frame 12-class classification as the source of truth for the whole game.
- Play-vs-computer, cloud analysis, opening books, or using Stockfish to decide move legality (ChessKit remains source of truth for recording).
- Clocks, time controls, increment.
- Online play, accounts, iCloud sync, Chess.com OAuth.
- Multi-game broadcast, spectator mode, two phones.
- Android, iPad-optimized layout (iPhone first; iPad may run it, not a target).
- macOS app (video import on iPhone covers the debugging need).
- Paid AI APIs, OpenCV, server backends.
- Training a universal piece model.

---

## 9. Constraints

| Constraint | Value |
|---|---|
| Duration | 10 days |
| Platform | iPhone, iOS 18+, Swift 6, SwiftUI |
| Camera | AVFoundation live + `PhotosPicker` / file import for video |
| Vision | Apple Vision + Core ML only |
| Chess rules | ChessKit (`chesskit-app/chesskit-swift`) — do not hand-roll legality |
| AI budget | No paid AI credits |
| Hardware | One physical set; tripod preferred; **full board must be visible** |
| Start | Standard starting position for the demo path |
| Correction | Auto-accept + later edit/undo (no per-move confirm dialog) |
| Persistence | On-device SwiftData; no iCloud |
| Overlap | Must not be “waste-sort, but chess pieces” |

---

## 10. Competitive honesty

Camera chess recording is **not novel**. Electronic boards, desktop CV projects, and some mobile recorders already exist.

The Academy contribution is:

- A constrained iPhone prototype with a clear pipeline (geometry → occupancy → rules).
- An HCI stance: vision is allowed to be wrong; editing is a first-class part of recording.
- A documented experiment: what worked, what failed, and how far a 10-day build got under one set / one lighting / one mount.

Do not claim the app replaces a DGT board. Claim it answers the research questions under the stated constraints.

---

## 11. Risks and product responses

| Risk | Product response |
|---|---|
| Piece classifier fails on this set | Train only on this set; after move 0, occupancy + rules carry the game; start confirmation screen lets the user fix the initial FEN |
| Hands occlude the board | Do not commit until occupancy is stable for a settle window |
| Angled camera | Homography to a square board; require full board in frame |
| Castling / en passant / promotion look like “too many squares changed” | Never infer from raw pixel diff alone; only legal ChessKit moves are candidates |
| Ambiguous or illegal visual delta | Do not guess; banner + edit UI |
| 10-day scope | One set, one start, still camera, video fixtures, no engine |
| Overlap with waste-sort | Lead with temporal + rules, not classification accuracy slides |

---

## 12. Demo ritual (product-level)

The intended use, which the UI should teach in one screen:

1. Place the board under indoor light. Standard starting position.
2. Mount the iPhone (tripod or stand) so every square is visible. Angle is OK.
3. Open Chess Camera → New Game.
4. Grant camera. Wait for auto-detect, or tap four corners.
5. Confirm the classified start (flip if orientation is wrong).
6. Play. Do not hover over the board between moves.
7. End game → replay → share PGN.

If auto-detect fails in the presentation, 4-corner fallback is a feature, not a failure.

---

## 13. Glossary

| Term | Meaning |
|---|---|
| Occupancy | 64-bit mask: square has a piece or not |
| Settle | Occupancy unchanged for N milliseconds while the board is otherwise quiet |
| Disturbed | Occupancy or large motion since the last committed position (hand, piece in air) |
| Source of truth | ChessKit `Game` after a move is committed; vision proposes, rules accept |
| PGN | Portable Game Notation — the takeaway artifact |
| FEN | Forsyth–Edwards Notation — current position snapshot |
| Homography | Perspective warp from camera quad → square top-down board |
