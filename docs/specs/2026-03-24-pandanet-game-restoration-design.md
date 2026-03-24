# Pandanet Game Restoration

## Problem

When a player disconnects from a Pandanet game (network drop, app close, etc.), the game
is automatically adjourned/stored by the server. Currently, `PandaNetGameClient.ongoingGame()`
returns `null`, so the app has no way to detect or restore these games. The player must
use an external client to resume.

## Goal

Implement `ongoingGame()` for Pandanet so that stored/adjourned games are automatically
detected and restored on login, following the same pattern as OGS.

## Non-Goals

- Mid-game TCP reconnection (socket drops during a live game). This is a separate problem
  that will be addressed later once we have captured the relevant server messages.
- Observing other players' games.

---

## Protocol

### Check for stored games
```
→ stored
← 18 Found 0 stored games.        (no games)
← 9 sugadintas-opponent            (one or more stored games)
← 18 Found N stored games.
```

### Load a stored game
```
→ load sugadintas-opponent
← 15 Game <id> I: <white> (...) vs <black> (...)
← 15 TIME:<id>:<white>(W): ...
← 15 TIME:<id>:<black>(B): ...
← 15 GAMERPROPS:<id>: <board_size> <handicap> <komi>
← 9 Match [<id>] with <opponent> in <n> accepted.
← 1 6
```
If load fails (opponent offline, game doesn't exist):
```
← 5 <error message>
← 1 5
```

### Get all moves from a game
```
→ moves <game_id>
← 15 Game <id> I: <white> (...) vs <black> (...)
← 9 Handicap and komi are disable.
← 15   0(B): Q16
← 15   1(W): R4
← 15   2(B): D4
← ...
← 15  53(W): C1 C2       ← move at C1, captures stone at C2
← 1 6
```

The moves list includes the complete game history from move 0. Captures are listed
after the move coordinate (space-separated). For reconstruction, only the first
coordinate (the actual move) is needed -- the game engine handles captures.

---

## Design

### TCP Manager: New Methods

**`getStoredGames()`** → `Future<List<String>>`
- Sends `stored`
- Collects response lines matching game name format (`<player1>-<player2>`)
- Returns list of game names, or empty list if none

**`loadGame(String gameName)`** → sends `load <gameName>`
- Does not return a result directly -- game start messages flow through the
  normal message stream (same as seek)

**`getGameMoves(int gameId)`** → `Future<List<String>>`
- Sends `moves <gameId>`
- Collects all `15  <num>(<color>): <coord>` lines
- Returns the raw move lines

All three use the existing Completer pattern from `getStats()` / `getSeekConfigs()`.

### Game Client: `ongoingGame()` Implementation

```
1. Ensure TCP connected (connect if needed, using stored credentials)
2. Call getStoredGames()
3. If empty → return null
4. Take the first stored game name
5. Send loadGame(gameName)
6. Listen on messages stream for game start sequence:
   - Parse "15 Game <id> I: <white> (...) vs <black> (...)"
   - Parse TIME messages for initial time state
   - Parse GAMERPROPS for board size, handicap, komi
   - Wait for "accepted" or "1 6" to confirm game loaded
7. If load fails (timeout or error message) → return null
8. Send "moves <gameId>" and collect move list
9. Parse moves into List<wq.Move> using existing parseCoordinate()
10. Construct PandanetGame with previousMoves
11. Send "say Hi!" greeting
12. Return the game
```

The game start parsing is identical to `findGame()` -- extract into a shared
helper method to avoid duplication.

### Move Parsing

Move lines from the `moves` command:
```
15   0(B): Q16
15   1(W): R4
15  53(W): C1 C2
15   0(B): Handicap 2     ← handicap, not a coordinate move
```

Parse with: `RegExp(r'(\d+)\s*\(\s*([BW])\s*\):\s*([A-Ta-t]\d{1,2})')`
- Skip lines containing "Handicap" (handicap stones are handled separately)
- Extract: move number, color (B/W), coordinate
- Convert coordinate using existing `parseCoordinate()`
- For handicap games, `PandanetGame.handicapPoints19()` generates the initial stones

### Shared Game Start Parsing

Extract the game start message parsing from `findGame()` into a reusable method:

```dart
Future<PandanetGame?> _parseGameStart({
  required String username,
  required Duration timeout,
}) async { ... }
```

Both `findGame()` and `ongoingGame()` call this after sending their respective
commands (seek entry vs load).

---

## Files Changed

### Modified
- `lib/game_client/pandanet/pandanet_tcp_manager.dart`
  - Add `getStoredGames()`, `loadGame()`, `getGameMoves()`
- `lib/game_client/pandanet/pandanet_game_client.dart`
  - Implement `ongoingGame()`
  - Extract shared `_parseGameStart()` from `findGame()`
  - Refactor `findGame()` to use `_parseGameStart()`
