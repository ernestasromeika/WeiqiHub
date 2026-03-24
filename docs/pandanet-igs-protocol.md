# Pandanet IGS Protocol Reference

Server: `igs.joyjoy.net:6969` (TCP, text-based, telnet-style protocol from the 1990s)

## Connection & Authentication

### Login Flow
1. Connect to TCP socket
2. Server sends ASCII art banner ending with `Login:`
3. Send username + `\r\n`
4. Server responds with `??\n1 1` (password prompt in client mode)
5. Send password + `\r\n`
6. Server sends MOTD/welcome message, ending with `1 5`

### Required Toggles (after login)
These must be set before using seek or nmatch features:
```
toggle client true    → 9 Set client to be True.
toggle nmatch true    → 9 Set nmatch to be True.
toggle seek true      → 9 Set seek to be True.
```

## Response Code Prefixes
Server messages are prefixed with numeric codes:
- `1 5` — Command completed successfully (prompt, ready for next command)
- `1 6` — Command completed, but in-game state (game is active)
- `5` — Error / not available (e.g. guest account restrictions)
- `8` — Help file content
- `9` — Info/status messages (stats, match creation, system messages)
- `15` — Game data (moves, time, game properties)
- `21` — Broadcast messages (player connect/disconnect, match announcements, game results)
- `24` — System errors (e.g. `24 SYSTEM: SEEK ERROR Your client does not support seek.`)
- `27` — Who list data
- `39` — IGS entry timestamp
- `51` — Say (in-game chat)
- `63` — Seek-related responses

## Seek Protocol (Automatch)

The "seek" command is an undocumented feature inherited from glGo 1.3. It provides
server-side matchmaking — you enter a queue and the server automatically pairs you
with a compatible opponent. This is the IGS equivalent of Fox/Tygem automatch.

### Prerequisites
Must toggle these flags after login:
```
toggle client true
toggle nmatch true
toggle seek true
```

### Get Available Time Configurations
```
→ seek config_list
← 63 CONFIG_LIST_START <count>
← 63 CONFIG_LIST <id> <main_time_sec> <byo_total_sec> <byo_periods> <unknown1> <unknown2>
← ...
← 63 CONFIG_LIST_END
```

**Observed configs (as of 2026-03-24):**
| ID | Main Time | Byo-yomi Total | Periods | Per Period | Label (estimated) |
|----|-----------|---------------|---------|------------|-------------------|
| 0  | 60s (1m)  | 600s (10m)    | 25      | 24s        | Slow              |
| 1  | 60s (1m)  | 420s (7m)     | 25      | ~17s       | Fast              |
| 2  | 60s (1m)  | 300s (5m)     | 25      | 12s        | Blitz             |
| 3  | 60s (1m)  | 900s (15m)    | 25      | 36s        | Very Slow         |

**Note:** The byo-yomi here is **Canadian-style**: you must play all 25 stones within
the total byo time (e.g. 25 stones in 600 seconds for config 0). This is NOT
per-move byo-yomi like Japanese-style.

### Enter Seek Queue
```
→ seek entry <config_id> <board_size> [<max_handicap>]
← 63 ENTRY <main_time> <byo_total> <periods> <unk1> <unk2> <board_size> <unk3> <unk4> <unk5>
```

**Parameters:**
- `config_id` — Time config from CONFIG_LIST (0-3)
- `board_size` — Board size: 9, 13, or 19
- `max_handicap` — (optional) Maximum handicap stones. Default 0 (even games only).
  Higher values allow handicap games with players of different rank.

**Examples:**
```
seek entry 0 19      → 63 ENTRY 60 600 25 0 0 19 0 0 0   (even game, 19x19, slow)
seek entry 0 9       → 63 ENTRY 60 600 25 0 0 9 0 0 0    (even game, 9x9, slow)
seek entry 1 19      → 63 ENTRY 60 420 25 0 0 19 0 0 0   (even game, 19x19, fast)
seek entry 2 13      → 63 ENTRY 60 300 25 0 0 13 0 0 0   (even game, 13x13, blitz)
seek entry 3 19      → 63 ENTRY 60 900 25 0 0 19 0 0 0   (even game, 19x19, very slow)
seek entry 0 19 1    → (may match with 1 stone handicap difference)
seek entry 0 19 5    → (may match with up to 5 stones handicap difference)
```

### Cancel Seek
```
→ seek entry_cancel
← 63 ENTRY_CANCEL
```

### Opponent Found (Game Start)
When a matching opponent is found, the server sends a sequence:
```
← 63 OPPONENT_FOUND <opponent_username>
← 63 ENTRY_CANCEL
← 15 Game <game_id> I: <white> (0 60 -1) vs <black> (0 60 -1)
← 15 TIME:<game_id>:<white>(W): 0 <main>/<main> 0/<byo_total> <periods>/<periods> 0/0 0/0 0/0
← 15 TIME:<game_id>:<black>(B): 0 <main>/<main> 0/<byo_total> <periods>/<periods> 0/0 0/0 0/0
← 15 GAMERPROPS:<game_id>: <board_size> <handicap> <komi>
← 9 Handicap and komi are disable.
← 9 Creating match [<game_id>] with <opponent>.
← 9 Please use say to talk to your opponent -- help say.
← 1 6
```

**Example (real capture):**
```
63 OPPONENT_FOUND wtapen
15 Game 52 I: wtapen (0 60 -1) vs sugadintas (0 60 -1)
15 TIME:52:wtapen(W): 0 60/60 0/600 25/25 0/0 0/0 0/0
15 TIME:52:sugadintas(B): 0 60/60 0/600 25/25 0/0 0/0 0/0
15 GAMERPROPS:52: 19 0 6.50
9 Handicap and komi are disable.
9 Creating match [52] with wtapen.
9 Please use say to talk to your opponent -- help say.
1 6
```

**Parsing the TIME line:**
```
15 TIME:<game_id>:<player>(<color>): <move_num> <main_used>/<main_total> <byo_used>/<byo_total> <periods_used>/<periods_total> <unk1> <unk2> <unk3>
```

**Parsing GAMERPROPS:**
```
15 GAMERPROPS:<game_id>: <board_size> <handicap> <komi>
```

### Errors
```
63 ERROR unknown command.       — Invalid seek subcommand
63 ERROR You are currently playing a game of some kind.  — Can't seek while in a game
24 SYSTEM: SEEK ERROR Your client does not support seek.  — Need to toggle client/nmatch/seek
```

## Move Protocol

### Making Moves
Send coordinate in letter+number format (e.g. `Q16`, `D4`):
```
→ Q16
← 15   0(B): Q16
```
Letters skip 'I' (A-H, J-T for 19x19).

### Receiving Moves
```
← 15 Game <game_id> I: <white> (0 59 -1) vs <black> (0 59 -1)
← 15 TIME:<game_id>:<white>(W): ...
← 15 TIME:<game_id>:<black>(B): ...
← 15 GAMERPROPS:<game_id>: <board_size> <handicap> <komi>
← 15   <move_num>(<color>): <coordinate>
```

### Pass
```
→ pass
```

### Resign
```
→ resign
← 9 <player> has resigned the game.
← 9 <player> lost the game <game_id> due to nocount-resignation. move <count> points.
← 9 Removed game file <white>-<black> from database.
```

## Match Command (Legacy)

The `match` command is the older, manual way to challenge a specific player:
```
match <opponent> [color] [board_size] [time_minutes] [byoyomi_minutes]
```

Default: `match <opponent> B 19 90 10` (black, 19x19, 90min main, 10min byo per 25 moves)

**Note:** The `match` command's byo-yomi is always Canadian-style: 25 moves per byo period.
The `automatch` command (with `defs`) is the ONLY way to change the 25-move default.

## Automatch Command (Legacy)

Uses settings from `defs`:
```
defs time <minutes>       — Main time
defs size <board_size>    — Board size
defs byotime <minutes>    — Byo-yomi time per period
defs stones <count>       — Stones per byo-yomi period (default 25)
```

Then: `automatch <opponent_name>` to challenge a specific player using those defaults.

## Player Stats
```
→ stats
← 9 Player:      <username>
← 9 Game:        go (1)
← 9 Language:    default
← 9 Rating:      <rank>    <number>
← 9 Rated Games:      <count>
← 9 Rank:  <rank>  <number>
← 9 Wins:         <count>
← 9 Losses:       <count>
← 9 Idle Time:  (On server) <duration>
← 9 Address:  <email>
← 9 Country:  <country>
← 9 Defaults (help defs):  time <t>, size <s>, byo-yomi time <bt>, byo-yomi stones <bs>
← 9 Verbose  Bell  Quiet  Shout  Automail  Open  Looking  Client  Kibitz  Chatter
← 9     <values...>
← 1 5
```

## Who List
```
→ who [rank_range]
```
Example: `who 3k-1d` — lists players within 3 kyu to 1 dan.

Response lines prefixed with `27`.

## Game Results (Broadcast)
```
21 {Game <id>: <white> vs <black> : White resigns.}
21 {Game <id>: <white> vs <black> : Black resigns.}
21 {Game <id>: <white> vs <black> : W <score> B <score>}
21 {Game <id>: <white> vs <black> : White forfeits on time.}
21 {Game <id>: <white> vs <black> : Black forfeits on time.}
21 {Game <id>: <white> vs <black> has adjourned.}
```

## Key Observations

1. **Time control is Canadian byo-yomi only** — All configs use 25 stones per byo period.
   There is no Japanese-style (per-move) byo-yomi option in the seek system.
   
2. **Seek vs Match** — `seek` is server-side matchmaking (queue-based, like Fox/Tygem automatch).
   `match` is direct challenge to a specific player. `automatch` is direct challenge using `defs`.

3. **Seek is undocumented** — `help seek` returns "File not found". The feature was added in
   glGo 1.3 (2005) and requires `toggle client true`, `toggle nmatch true`, `toggle seek true`.

4. **One seek at a time** — You cannot enter multiple seek queues simultaneously.
   You cannot seek while playing a game.

5. **Handicap in seek** — The third parameter to `seek entry` controls max handicap.
   With 0 (default), only even games. With higher values, the server may create handicap
   games if rank difference warrants it.
