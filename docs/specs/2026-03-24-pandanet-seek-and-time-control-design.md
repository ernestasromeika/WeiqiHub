# Pandanet Seek Integration & Time Control Refactor

## Problem

1. Pandanet's automatch uses the **seek** protocol (undocumented, server-side matchmaking).
   The current implementation loops `match` commands at individual players, which is fragile
   and unreliable.

2. Pandanet uses **Canadian byo-yomi** (25 stones per period). The app's time control system
   is hardcoded for Japanese byo-yomi. There is no way to represent or display Canadian time.

3. The time control data model mixes concerns: `TimeControl` and `TimeState` contain fields
   that only make sense for Japanese byo-yomi. Adding Canadian support by bolting on more
   fields creates a muddled abstraction that will only get worse when Fischer or Simple time
   are needed for other servers.

## Goals

- Replace the `match`-loop automatch with proper `seek` protocol.
- Refactor time control into a polymorphic class hierarchy that cleanly supports
  Japanese byo-yomi, Canadian byo-yomi, and is extensible to Fischer and Simple time.
- Keep all existing OGS behavior unchanged.
- Single `TimeDisplay` widget renders all time systems, driven by data.

## Non-Goals

- Implementing Fischer or Simple time (just ensuring the design supports them).
- Changing the Pandanet login, game play, or game history flows.

---

## Part 1: Time Control Refactor

### 1.1 TimeControl (Abstract)

Replace the current concrete `TimeControl` class with an abstract base class.
Every time system must provide:

```dart
@immutable
abstract class TimeControl {
  /// Human-readable description for preset lists.
  /// e.g. "5:00 + (5x30)", "1:00 + (10:00/25)", "10:00 + (7)", "10:00"
  String description();

  /// Create the initial TimeState for a new game.
  TimeState initialState();

  /// Compute the next TimeState after [elapsed] time has passed since [base].
  /// This is the countdown logic. Each subclass owns its own math.
  TimeState tick(TimeState base, Duration elapsed);
}
```

The key insight: **countdown logic belongs to the TimeControl, not the timer engine.**

### 1.2 TimeControl Subclasses

**JapaneseByoyomiTimeControl:**
```dart
@immutable
class JapaneseByoyomiTimeControl extends TimeControl {
  final Duration mainTime;
  final int periodCount;
  final Duration timePerPeriod;
}
```
- `description()` → `"5:00 + (5x30)"` (5 min main + 5 periods of 30s)
- `tick()` → consumes main time first, then burns through periods one at a time
  (same logic as current `GameTimer._calculateTimeState`)

**CanadianByoyomiTimeControl:**
```dart
@immutable
class CanadianByoyomiTimeControl extends TimeControl {
  final Duration mainTime;
  final Duration periodTime;
  final int stonesPerPeriod;
}
```
- `description()` → `"1:00 + (10:00/25)"` (1 min main + 10 min for 25 stones)
- `tick()` → consumes main time first, then counts down period time. Period time
  does NOT auto-reset (stone tracking is external — see TimeState below).

**Future — not implemented now:**

```dart
class FischerTimeControl extends TimeControl {
  final Duration mainTime;
  final Duration increment;
}
// description() → "10:00 + (7)"

class SimpleTimeControl extends TimeControl {
  final Duration mainTime;
}
// description() → "10:00"
```

### 1.3 TimeState (Abstract)

Replace the current concrete `TimeState` with an abstract base class.
Every time state must provide:

```dart
@immutable
abstract class TimeState {
  /// The duration currently counting down (for the timer engine and display).
  Duration get timeLeft;

  /// True when all time is exhausted.
  bool get isFlagged;

  /// Display segments for the TimeDisplay widget.
  /// Each segment is rendered as a block in the clock UI.
  List<DisplaySegment> get displaySegments;

  /// Is the player in a warning state? (low time)
  bool isLowTime(Duration threshold);

  /// Should voice countdown be active?
  bool get shouldVoiceCountdown;

  static const TimeState zero = _ZeroTimeState();
}

@immutable
class DisplaySegment {
  final String value;     // e.g. "05", "3x", "15/25"
  final bool isTime;      // true for HH:MM:SS segments, false for labels like "3x"
  final bool isCritical;  // true when this segment is in warning state
}
```

### 1.4 TimeState Subclasses

**JapaneseByoyomiTimeState:**
```dart
@immutable
class JapaneseByoyomiTimeState extends TimeState {
  final Duration mainTimeLeft;
  final Duration periodTimeLeft;
  final int periodsRemaining;

  bool get isOvertime => mainTimeLeft == Duration.zero && periodsRemaining > 0;
}
```
- During main time → `displaySegments` returns `[MM:SS]` or `[HH:MM:SS]`
- During overtime → `displaySegments` returns `[{periodsRemaining}x, :, MM:SS]`
- `timeLeft` → returns `mainTimeLeft` during main, `periodTimeLeft` during overtime
- `isLowTime` → checks `timeLeft <= threshold`
- `shouldVoiceCountdown` → true when in overtime
- `isFlagged` → `mainTimeLeft == 0 && periodsRemaining == 0 && periodTimeLeft == 0`

**CanadianByoyomiTimeState:**
```dart
@immutable
class CanadianByoyomiTimeState extends TimeState {
  final Duration mainTimeLeft;
  final Duration periodTimeLeft;
  final int stonesRemaining;    // stones left to play in this period
  final int stonesPerPeriod;    // total stones per period (for display)

  bool get isOvertime => mainTimeLeft == Duration.zero && periodTimeLeft > Duration.zero;
}
```
- During main time → `displaySegments` returns `[MM:SS]` or `[HH:MM:SS]`
- During overtime → `displaySegments` returns `[MM:SS, (stonesPlayed/stonesPerPeriod)]`
  where stonesPlayed = stonesPerPeriod - stonesRemaining
- `timeLeft` → returns `mainTimeLeft` during main, `periodTimeLeft` during overtime
- `shouldVoiceCountdown` → true when in overtime
- `isFlagged` → `mainTimeLeft == 0 && periodTimeLeft == 0`

**Flagging invariant:** When `isFlagged` is true, all time fields are zero or exhausted.
`isOvertime` is false when flagged (since `periodTimeLeft == 0`). `stonesRemaining` may
be non-zero when flagged (player ran out of time before playing all stones), but this
does not affect any branching since `isFlagged` takes precedence in all display and
logic paths.

**ZeroTimeState (sentinel):**
```dart
class _ZeroTimeState extends TimeState {
  // isFlagged = true, timeLeft = Duration.zero, displaySegments = [00:00]
}
```

### 1.5 GameTimer Refactor

`GameTimer` becomes the universal countdown engine for ALL servers. It receives a
`TimeControl` and delegates countdown math to it.

```dart
class GameTimer extends ValueNotifier<(int, TimeState)> {
  final TimeControl timeControl;

  GameTimer({required this.timeControl, required TimeState initialState})
    : _baseState = initialState, super((0, initialState));

  void start(TimeState newState) { ... }
  void stop() { ... }

  void _tick() {
    final elapsed = clock.now().difference(_startTime!);
    final newState = timeControl.tick(_baseState, elapsed);  // delegate to TimeControl
    value = (value.$1 + 1, newState);
  }
}
```

The timer just calls `timeControl.tick()` — it doesn't know or care what time system is in use.

**Unified timer architecture:** Every server uses `GameTimer`. The previous split where
OGS used `GameTimer` and Pandanet relied on `TimeDisplay`'s internal ticker is eliminated.
The `localTimeControl` flag in `ServerFeatures` and `TimeDisplay`'s internal `Timer.periodic`
are both removed. All countdown is driven by `GameTimer`, which emits `(tick, TimeState)`
updates that `TimeDisplay` renders.

For OGS: `GameTimer.start()` is called when the server sends clock updates (same as before).
For Pandanet: `GameTimer.start()` is called when a move is received (switching whose clock
ticks). Between server TIME updates, `GameTimer` ticks locally. When a TIME message arrives,
`GameTimer.start()` is called with the server-provided state, correcting any drift.

### 1.6 TimeDisplay Refactor

`TimeDisplay` becomes a pure rendering widget. It receives a `TimeState` and renders it.
It no longer has an internal timer or countdown logic.

```dart
@override
Widget build(BuildContext context) {
  final segments = timeState.displaySegments;
  final isWarning = timeState.isLowTime(warningDuration);
  // render segments as a Row of _UnitContainer widgets
  // use isWarning for container color
}
```

The widget rebuilds when `GameTimer` emits new values through the existing
`ValueListenableBuilder` in `game_page.dart`. This is the same mechanism OGS already uses.

Voice countdown uses `timeState.shouldVoiceCountdown` instead of checking `isOvertime`.

The `tickerEnabled`, `tickMode`, `enabled`, and `onTimeout` properties are removed from
`TimeDisplay`. Timeout detection (if needed) moves to `GameTimer` or the game class.

Training pages (time_frenzy, exam, collection) that used `TimeDisplay`'s internal ticker
will instead use a lightweight `GameTimer` with a `SimpleTimeControl` that just counts
down main time.

### 1.7 Canadian Byo-yomi: Stone Tracking

In Canadian byo-yomi, the period timer resets when all stones are played. The server
tells us when this happens (via TIME messages), but for local countdown between server
updates, the `PandanetGame` must track stones played per period.

When a move is made during overtime:
1. Decrement `stonesRemaining`
2. If `stonesRemaining` reaches 0, reset `periodTimeLeft` to full period time and
   reset `stonesRemaining` to `stonesPerPeriod`

This logic lives in `PandanetGame._onMessage` when processing move messages, not in
the timer or display.

### 1.8 Game Base Class Changes

The `Game` constructor currently creates `TimeState` directly from `TimeControl` fields:
```dart
final t = TimeState(
  mainTimeLeft: timeControl.mainTime,
  periodTimeLeft: timeControl.timePerPeriod,
  periodCount: timeControl.periodCount,
);
```

This changes to use the abstract factory method:
```dart
final t = timeControl.initialState();
```

The `Game` class no longer knows which time system is in use. It stores the abstract
`TimeControl` and abstract `TimeState` in `blackTime`/`whiteTime` value notifiers.

### 1.9 Migration Path (Backward Compatibility)

- All existing code that creates `TimeControl(mainTime:..., periodCount:..., timePerPeriod:...)`
  changes to `JapaneseByoyomiTimeControl(mainTime:..., periodCount:..., timePerPeriod:...)`.
- All existing code that creates `TimeState(mainTimeLeft:..., periodTimeLeft:..., periodCount:...)`
  changes to `JapaneseByoyomiTimeState(mainTimeLeft:..., periodTimeLeft:..., periodsRemaining:...)`.
- `TimeState.zero` remains as a universal sentinel.
- `TimeState.isOvertime` is removed from the base; callers that need it use the concrete type
  or the abstract `shouldVoiceCountdown`.
- Training pages (time_frenzy, exam, collection) that use `periodCount: 0` will use a
  lightweight `GameTimer` with a `SimpleTimeControl` (or `JapaneseByoyomiTimeControl` with
  0 periods) instead of `TimeDisplay`'s removed internal ticker.
- The `localTimeControl` flag is removed from `ServerFeatures`. The `tickerEnabled`,
  `tickMode`, `enabled`, and `onTimeout` properties are removed from `TimeDisplay`.

---

## Part 2: Pandanet Seek Integration

### 2.1 Connection Flow

After login, the TCP manager sends the three required toggles:
```
toggle client true
toggle nmatch true
toggle seek true
```

Then fetches the available time configs:
```
seek config_list
```

### 2.2 Seek Config Parsing

The TCP manager parses `CONFIG_LIST` responses and stores them:

```dart
class SeekConfig {
  final int id;
  final Duration mainTime;
  final Duration periodTime;
  final int stonesPerPeriod;
}
```

The observed configs map to:

| ID | Main | Period Time | Stones | Description |
|----|------|------------|--------|-------------|
| 0  | 1m   | 10m        | 25     | 1:00 + (10:00/25) |
| 1  | 1m   | 7m         | 25     | 1:00 + (7:00/25)  |
| 2  | 1m   | 5m         | 25     | 1:00 + (5:00/25)  |
| 3  | 1m   | 15m        | 25     | 1:00 + (15:00/25) |

### 2.3 Automatch Presets

`PandaNetGameClient.automatchPresets` is generated dynamically from the seek configs
crossed with board sizes (9, 13, 19):

```dart
for (final config in seekConfigs) {
  for (final boardSize in [9, 13, 19]) {
    presets.add(AutomatchPreset(
      id: 'seek_${config.id}_${boardSize}',
      boardSize: boardSize,
      variant: Variant.standard,
      rules: Rules.japanese,
      timeControl: CanadianByoyomiTimeControl(
        mainTime: config.mainTime,
        periodTime: config.periodTime,
        stonesPerPeriod: config.stonesPerPeriod,
      ),
    ));
  }
}
```

### 2.4 Finding a Game (Seek Entry)

`PandaNetGameClient.findGame(presetId)`:
1. Parse the preset ID to extract config ID and board size
2. Send `seek entry <config_id> <board_size>`
3. Listen for `63 OPPONENT_FOUND <username>`
4. Parse the game start sequence (code 15 messages)
5. Create and return a `PandanetGame`

### 2.5 Cancelling Seek

`PandaNetGameClient.stopAutomatch()`:
1. Send `seek entry_cancel`
2. Wait for `63 ENTRY_CANCEL` confirmation

### 2.6 Game Start Parsing

When `63 OPPONENT_FOUND` arrives, the server sends:
```
15 Game <id> I: <white> (<params>) vs <black> (<params>)
15 TIME:<id>:<white>(W): 0 <main>/<main> 0/<byo> <periods>/<periods> 0/0 0/0 0/0
15 TIME:<id>:<black>(B): 0 <main>/<main> 0/<byo> <periods>/<periods> 0/0 0/0 0/0
15 GAMERPROPS:<id>: <board_size> <handicap> <komi>
```

Parse these to create the game with proper time state, player info, and board properties.

### 2.7 TIME Message Updates During Game

During gameplay, the server sends TIME messages after each move. The `PandanetGame`
parses these to update `blackTime` and `whiteTime` with fresh `CanadianByoyomiTimeState`
values, including `stonesRemaining`.

The TIME format observed:
```
15 TIME:<game_id>:<player>(<color>): <move> <main_used>/<main_total> <byo_used>/<byo_total> <stones_used>/<stones_total> 0/0 0/0 0/0
```

---

## Part 3: Files Changed

### New Files
- `lib/game_client/time_control/time_control.dart` — abstract base
- `lib/game_client/time_control/japanese_byoyomi.dart` — Japanese TimeControl + TimeState
- `lib/game_client/time_control/canadian_byoyomi.dart` — Canadian TimeControl + TimeState
- `lib/game_client/pandanet/seek_config.dart` — SeekConfig data class

### Modified Files
- `lib/game_client/time_state.dart` — refactor to abstract base
- `lib/game_client/game_timer.dart` — accept TimeControl, delegate tick logic
- `lib/game_client/game.dart` — use abstract TimeControl/TimeState, call initialState()
- `lib/game_client/automatch_preset.dart` — TimeControl field becomes abstract type
- `lib/game_client/server_features.dart` — remove `localTimeControl` flag
- `lib/time_display.dart` — pure renderer, remove internal ticker/countdown logic
- `lib/play/game_page.dart` — remove tickerEnabled/enabled props, adapt to new TimeState
- `lib/play/automatch_preset_list_tile.dart` — use `timeControl.description()`
- `lib/game_client/ogs/ogs_game.dart` — use JapaneseByoyomiTimeControl/State
- `lib/game_client/ogs/ogs_game_client.dart` — use JapaneseByoyomiTimeControl
- `lib/game_client/pandanet/pandanet_game.dart` — GameTimer, parse TIME messages, Canadian state
- `lib/game_client/pandanet/pandanet_game_client.dart` — seek protocol, dynamic presets
- `lib/game_client/pandanet/pandanet_tcp_manager.dart` — seek commands, config parsing
- `lib/game_client/test_game_client.dart` — use JapaneseByoyomiTimeControl
- `lib/train/time_frenzy_page.dart` — use GameTimer instead of TimeDisplay ticker
- `lib/train/exam_page.dart` — use GameTimer instead of TimeDisplay ticker
- `lib/train/collection_page.dart` — use GameTimer instead of TimeDisplay ticker
- `test/game_timer_test.dart` — adapt to new interface

### Deleted Files
- `lib/game_client/time_control.dart` — replaced by time_control/ directory
