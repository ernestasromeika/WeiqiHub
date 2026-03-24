# Pandanet Seek & Time Control Refactor — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Pandanet's match-loop with the seek protocol and refactor the time control system into a polymorphic hierarchy supporting Japanese and Canadian byo-yomi.

**Architecture:** Abstract `TimeControl` and `TimeState` base classes with concrete subclasses (`JapaneseByoyomi*`, `CanadianByoyomi*`). `GameTimer` becomes universal (all servers use it), `TimeDisplay` becomes a pure renderer. Pandanet uses the `seek` protocol for matchmaking with server-provided time configs.

**Tech Stack:** Flutter/Dart, TCP sockets (Pandanet), WebSockets (OGS)

**Spec:** `docs/specs/2026-03-24-pandanet-seek-and-time-control-design.md`

---

## File Structure

### New Files
| File | Responsibility |
|------|---------------|
| `lib/game_client/time_control/time_control.dart` | Abstract `TimeControl` base class + `DisplaySegment` |
| `lib/game_client/time_control/time_state.dart` | Abstract `TimeState` base class |
| `lib/game_client/time_control/japanese_byoyomi.dart` | `JapaneseByoyomiTimeControl` + `JapaneseByoyomiTimeState` |
| `lib/game_client/time_control/canadian_byoyomi.dart` | `CanadianByoyomiTimeControl` + `CanadianByoyomiTimeState` |
| `lib/game_client/pandanet/seek_config.dart` | `SeekConfig` data class |
| `test/time_control/japanese_byoyomi_test.dart` | Tests for Japanese TimeControl.tick() and TimeState.displaySegments |
| `test/time_control/canadian_byoyomi_test.dart` | Tests for Canadian TimeControl.tick() and TimeState.displaySegments |

### Modified Files
| File | What Changes |
|------|-------------|
| `lib/game_client/game_timer.dart` | Accept `TimeControl`, delegate `tick()` to it |
| `lib/game_client/game.dart` | Use abstract types, call `timeControl.initialState()` |
| `lib/game_client/automatch_preset.dart` | Import from new path |
| `lib/game_client/server_features.dart` | Remove `localTimeControl` field |
| `lib/time_display.dart` | Pure renderer: remove internal ticker, render from `displaySegments` |
| `lib/play/game_page.dart` | Remove `tickerEnabled`/`enabled`, simplify TimeDisplay creation |
| `lib/play/automatch_preset_list_tile.dart` | Use `timeControl.description()` |
| `lib/game_client/ogs/ogs_game.dart` | Use `JapaneseByoyomiTimeState`, pass `TimeControl` to `GameTimer` |
| `lib/game_client/ogs/ogs_game_client.dart` | Use `JapaneseByoyomiTimeControl`, remove `localTimeControl` |
| `lib/game_client/pandanet/pandanet_game.dart` | Add `GameTimer`, parse TIME messages into `CanadianByoyomiTimeState` |
| `lib/game_client/pandanet/pandanet_game_client.dart` | Seek protocol, dynamic presets from `seek config_list` |
| `lib/game_client/pandanet/pandanet_tcp_manager.dart` | Seek commands, config_list parsing, toggles on login |
| `lib/game_client/test_game_client.dart` | Use `JapaneseByoyomiTimeControl`, remove `localTimeControl` |
| `lib/train/time_frenzy_page.dart` | Use `GameTimer` + `JapaneseByoyomiTimeControl` with 0 periods |
| `lib/train/exam_page.dart` | Use `GameTimer` + `JapaneseByoyomiTimeControl` with 0 periods |
| `lib/train/collection_page.dart` | Use count-up `GameTimer` (or manual `Timer.periodic` with `TimeState`) |
| `test/game_timer_test.dart` | Adapt to new `GameTimer(timeControl:..., initialState:...)` signature |

### Deleted Files
| File | Reason |
|------|--------|
| `lib/game_client/time_control.dart` | Replaced by `time_control/` directory |
| `lib/game_client/time_state.dart` | Replaced by `time_control/time_state.dart` |

---

## Task 1: Abstract TimeControl and TimeState Base Classes

**Files:**
- Create: `lib/game_client/time_control/time_control.dart`
- Create: `lib/game_client/time_control/time_state.dart`

- [ ] **Step 1: Create the abstract TimeControl base class**

Create `lib/game_client/time_control/time_control.dart`:
```dart
import 'package:flutter/widgets.dart';
import 'package:wqhub/game_client/time_control/time_state.dart';

@immutable
class DisplaySegment {
  final String value;
  final bool isTime;

  const DisplaySegment({required this.value, this.isTime = true});
}

@immutable
abstract class TimeControl {
  const TimeControl();

  /// Human-readable description for preset lists.
  /// e.g. "5:00 + (5x30)", "1:00 + (10:00/25)"
  String description();

  /// Create the initial TimeState for a new game.
  TimeState initialState();

  /// Compute the next TimeState after [elapsed] time has passed since [base].
  TimeState tick(TimeState base, Duration elapsed);
}
```

- [ ] **Step 2: Create the abstract TimeState base class**

Create `lib/game_client/time_control/time_state.dart`:
```dart
import 'package:flutter/widgets.dart';
import 'package:wqhub/game_client/time_control/time_control.dart';

@immutable
abstract class TimeState {
  const TimeState();

  /// The duration currently counting down.
  Duration get timeLeft;

  /// True when all time is exhausted.
  bool get isFlagged;

  /// Display segments for the TimeDisplay widget.
  List<DisplaySegment> get displaySegments;

  /// Is the player in a warning state?
  bool isLowTime(Duration threshold);

  /// Should voice countdown be active?
  bool get shouldVoiceCountdown;

  /// Zero/sentinel state.
  static const TimeState zero = _ZeroTimeState();
}

class _ZeroTimeState extends TimeState {
  const _ZeroTimeState();

  @override
  Duration get timeLeft => Duration.zero;

  @override
  bool get isFlagged => true;

  @override
  List<DisplaySegment> get displaySegments =>
      [const DisplaySegment(value: '00'), const DisplaySegment(value: '00')];

  @override
  bool isLowTime(Duration threshold) => true;

  @override
  bool get shouldVoiceCountdown => false;
}
```

- [ ] **Step 3: Verify files parse correctly**

Run: `dart analyze lib/game_client/time_control/`
Expected: No errors (warnings about unused imports OK for now)

- [ ] **Step 4: Commit**

```
git add lib/game_client/time_control/
git commit -m "feat: add abstract TimeControl and TimeState base classes"
```

---

## Task 2: JapaneseByoyomiTimeControl and JapaneseByoyomiTimeState

**Files:**
- Create: `lib/game_client/time_control/japanese_byoyomi.dart`
- Create: `test/time_control/japanese_byoyomi_test.dart`

- [ ] **Step 1: Write failing tests for JapaneseByoyomiTimeState**

Create `test/time_control/japanese_byoyomi_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:wqhub/game_client/time_control/japanese_byoyomi.dart';
import 'package:wqhub/game_client/time_control/time_state.dart';

void main() {
  group('JapaneseByoyomiTimeState', () {
    test('timeLeft returns mainTimeLeft during main time', () {
      final state = JapaneseByoyomiTimeState(
        mainTimeLeft: Duration(minutes: 5),
        periodTimeLeft: Duration(seconds: 30),
        periodsRemaining: 5,
      );
      expect(state.timeLeft, Duration(minutes: 5));
    });

    test('timeLeft returns periodTimeLeft during overtime', () {
      final state = JapaneseByoyomiTimeState(
        mainTimeLeft: Duration.zero,
        periodTimeLeft: Duration(seconds: 25),
        periodsRemaining: 3,
      );
      expect(state.timeLeft, Duration(seconds: 25));
    });

    test('isFlagged when all time exhausted', () {
      final state = JapaneseByoyomiTimeState(
        mainTimeLeft: Duration.zero,
        periodTimeLeft: Duration.zero,
        periodsRemaining: 0,
      );
      expect(state.isFlagged, true);
    });

    test('not flagged during main time', () {
      final state = JapaneseByoyomiTimeState(
        mainTimeLeft: Duration(seconds: 1),
        periodTimeLeft: Duration(seconds: 30),
        periodsRemaining: 5,
      );
      expect(state.isFlagged, false);
    });

    test('shouldVoiceCountdown true in overtime', () {
      final state = JapaneseByoyomiTimeState(
        mainTimeLeft: Duration.zero,
        periodTimeLeft: Duration(seconds: 5),
        periodsRemaining: 2,
      );
      expect(state.shouldVoiceCountdown, true);
    });

    test('shouldVoiceCountdown false in main time', () {
      final state = JapaneseByoyomiTimeState(
        mainTimeLeft: Duration(minutes: 1),
        periodTimeLeft: Duration(seconds: 30),
        periodsRemaining: 5,
      );
      expect(state.shouldVoiceCountdown, false);
    });

    test('displaySegments in main time shows MM:SS', () {
      final state = JapaneseByoyomiTimeState(
        mainTimeLeft: Duration(minutes: 5, seconds: 30),
        periodTimeLeft: Duration(seconds: 30),
        periodsRemaining: 5,
      );
      final segments = state.displaySegments;
      expect(segments.length, 2); // MM, SS
      expect(segments[0].value, '05');
      expect(segments[1].value, '30');
    });

    test('displaySegments in overtime shows Nx:MM:SS', () {
      final state = JapaneseByoyomiTimeState(
        mainTimeLeft: Duration.zero,
        periodTimeLeft: Duration(seconds: 25),
        periodsRemaining: 3,
      );
      final segments = state.displaySegments;
      expect(segments.first.value, '3x');
      expect(segments.first.isTime, false);
      expect(segments.last.value, '25');
    });
  });

  group('JapaneseByoyomiTimeControl', () {
    test('initialState creates correct state', () {
      final tc = JapaneseByoyomiTimeControl(
        mainTime: Duration(minutes: 5),
        periodCount: 5,
        timePerPeriod: Duration(seconds: 30),
      );
      final state = tc.initialState() as JapaneseByoyomiTimeState;
      expect(state.mainTimeLeft, Duration(minutes: 5));
      expect(state.periodTimeLeft, Duration(seconds: 30));
      expect(state.periodsRemaining, 5);
    });

    test('tick consumes main time', () {
      final tc = JapaneseByoyomiTimeControl(
        mainTime: Duration(minutes: 5),
        periodCount: 5,
        timePerPeriod: Duration(seconds: 30),
      );
      final base = tc.initialState();
      final result = tc.tick(base, Duration(seconds: 10)) as JapaneseByoyomiTimeState;
      expect(result.mainTimeLeft, Duration(minutes: 4, seconds: 50));
      expect(result.periodsRemaining, 5);
    });

    test('tick transitions from main to overtime', () {
      final tc = JapaneseByoyomiTimeControl(
        mainTime: Duration(seconds: 5),
        periodCount: 3,
        timePerPeriod: Duration(seconds: 30),
      );
      final base = tc.initialState();
      final result = tc.tick(base, Duration(seconds: 8)) as JapaneseByoyomiTimeState;
      expect(result.mainTimeLeft, Duration.zero);
      expect(result.periodTimeLeft, Duration(seconds: 27));
      expect(result.periodsRemaining, 3);
    });

    test('tick burns through periods', () {
      final tc = JapaneseByoyomiTimeControl(
        mainTime: Duration.zero,
        periodCount: 3,
        timePerPeriod: Duration(seconds: 10),
      );
      final base = tc.initialState();
      // 25 seconds elapsed: burns 2 full periods (20s), 5s into the last
      final result = tc.tick(base, Duration(seconds: 25)) as JapaneseByoyomiTimeState;
      expect(result.mainTimeLeft, Duration.zero);
      expect(result.periodsRemaining, 1);
      expect(result.periodTimeLeft, Duration(seconds: 5));
    });

    test('tick flags when all time exhausted', () {
      final tc = JapaneseByoyomiTimeControl(
        mainTime: Duration(seconds: 1),
        periodCount: 1,
        timePerPeriod: Duration(seconds: 2),
      );
      final base = tc.initialState();
      final result = tc.tick(base, Duration(seconds: 10));
      expect(result.isFlagged, true);
    });

    test('description format', () {
      final tc = JapaneseByoyomiTimeControl(
        mainTime: Duration(minutes: 5),
        periodCount: 5,
        timePerPeriod: Duration(seconds: 30),
      );
      expect(tc.description(), '5:00 + (5x30)');
    });

    test('description with seconds-only main time', () {
      final tc = JapaneseByoyomiTimeControl(
        mainTime: Duration(seconds: 30),
        periodCount: 5,
        timePerPeriod: Duration(seconds: 10),
      );
      expect(tc.description(), '0:30 + (5x10)');
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/time_control/japanese_byoyomi_test.dart`
Expected: FAIL (file not found / class not defined)

- [ ] **Step 3: Implement JapaneseByoyomiTimeControl and JapaneseByoyomiTimeState**

Create `lib/game_client/time_control/japanese_byoyomi.dart`:
```dart
import 'package:flutter/widgets.dart';
import 'package:wqhub/game_client/time_control/time_control.dart';
import 'package:wqhub/game_client/time_control/time_state.dart';

@immutable
class JapaneseByoyomiTimeState extends TimeState {
  final Duration mainTimeLeft;
  final Duration periodTimeLeft;
  final int periodsRemaining;

  const JapaneseByoyomiTimeState({
    required this.mainTimeLeft,
    required this.periodTimeLeft,
    required this.periodsRemaining,
  });

  bool get isOvertime => mainTimeLeft == Duration.zero && periodsRemaining > 0;

  @override
  Duration get timeLeft =>
      mainTimeLeft > Duration.zero ? mainTimeLeft : periodTimeLeft;

  @override
  bool get isFlagged =>
      mainTimeLeft == Duration.zero &&
      periodsRemaining == 0 &&
      periodTimeLeft == Duration.zero;

  @override
  bool isLowTime(Duration threshold) => timeLeft <= threshold;

  @override
  bool get shouldVoiceCountdown => isOvertime;

  @override
  List<DisplaySegment> get displaySegments {
    final time = timeLeft;
    final hh = time.inHours;
    final mm = time.inMinutes.remainder(60);
    final ss = time.inSeconds.remainder(60);

    String pad(int v) => v.toString().padLeft(2, '0');

    if (mainTimeLeft > Duration.zero || periodsRemaining == 0) {
      // Main time (or no overtime configured)
      return [
        if (hh > 0) DisplaySegment(value: pad(hh)),
        DisplaySegment(value: pad(mm)),
        DisplaySegment(value: pad(ss)),
      ];
    } else {
      // Overtime
      return [
        DisplaySegment(value: '${periodsRemaining}x', isTime: false),
        if (hh > 0) DisplaySegment(value: pad(hh)),
        if (mm > 0) DisplaySegment(value: pad(mm)),
        DisplaySegment(value: pad(ss)),
      ];
    }
  }

  @override
  int get hashCode =>
      Object.hash(mainTimeLeft, periodTimeLeft, periodsRemaining);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other.runtimeType != runtimeType) return false;
    return other is JapaneseByoyomiTimeState &&
        other.mainTimeLeft == mainTimeLeft &&
        other.periodTimeLeft == periodTimeLeft &&
        other.periodsRemaining == periodsRemaining;
  }

  @override
  String toString() =>
      'JapaneseByo($mainTimeLeft - ${periodsRemaining}x $periodTimeLeft)';
}

@immutable
class JapaneseByoyomiTimeControl extends TimeControl {
  final Duration mainTime;
  final int periodCount;
  final Duration timePerPeriod;

  const JapaneseByoyomiTimeControl({
    required this.mainTime,
    required this.periodCount,
    required this.timePerPeriod,
  });

  @override
  TimeState initialState() => JapaneseByoyomiTimeState(
        mainTimeLeft: mainTime,
        periodTimeLeft: timePerPeriod,
        periodsRemaining: periodCount,
      );

  @override
  TimeState tick(TimeState base, Duration elapsed) {
    if (base is! JapaneseByoyomiTimeState) return base;

    var remaining = elapsed;
    var mainTimeLeft = base.mainTimeLeft;
    var periodTimeLeft = base.periodTimeLeft;
    var periodsRemaining = base.periodsRemaining;

    // Consume main time
    if (mainTimeLeft > Duration.zero) {
      if (remaining <= mainTimeLeft) {
        mainTimeLeft -= remaining;
        remaining = Duration.zero;
      } else {
        remaining -= mainTimeLeft;
        mainTimeLeft = Duration.zero;
      }
    }

    // Consume byoyomi periods
    while (periodsRemaining > 0 && remaining >= periodTimeLeft) {
      remaining -= periodTimeLeft;
      periodsRemaining -= 1;
      if (periodsRemaining > 0) {
        periodTimeLeft = timePerPeriod;
      }
    }

    if (periodsRemaining > 0) {
      periodTimeLeft -= remaining;
    } else {
      periodTimeLeft = Duration.zero;
    }

    return JapaneseByoyomiTimeState(
      mainTimeLeft: mainTimeLeft,
      periodTimeLeft: periodTimeLeft,
      periodsRemaining: periodsRemaining,
    );
  }

  @override
  String description() {
    final mainMin = mainTime.inMinutes;
    final mainSec = mainTime.inSeconds.remainder(60);
    final mainStr = '$mainMin:${mainSec.toString().padLeft(2, '0')}';
    return '$mainStr + (${periodCount}x${timePerPeriod.inSeconds})';
  }

  @override
  int get hashCode => Object.hash(mainTime, periodCount, timePerPeriod);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other.runtimeType != runtimeType) return false;
    return other is JapaneseByoyomiTimeControl &&
        other.mainTime == mainTime &&
        other.periodCount == periodCount &&
        other.timePerPeriod == timePerPeriod;
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/time_control/japanese_byoyomi_test.dart`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```
git add lib/game_client/time_control/japanese_byoyomi.dart test/time_control/japanese_byoyomi_test.dart
git commit -m "feat: implement JapaneseByoyomiTimeControl and TimeState with tests"
```

---

## Task 3: CanadianByoyomiTimeControl and CanadianByoyomiTimeState

**Files:**
- Create: `lib/game_client/time_control/canadian_byoyomi.dart`
- Create: `test/time_control/canadian_byoyomi_test.dart`

- [ ] **Step 1: Write failing tests for CanadianByoyomiTimeState**

Create `test/time_control/canadian_byoyomi_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:wqhub/game_client/time_control/canadian_byoyomi.dart';
import 'package:wqhub/game_client/time_control/time_state.dart';

void main() {
  group('CanadianByoyomiTimeState', () {
    test('timeLeft returns mainTimeLeft during main time', () {
      final state = CanadianByoyomiTimeState(
        mainTimeLeft: Duration(seconds: 60),
        periodTimeLeft: Duration(seconds: 600),
        stonesRemaining: 25,
        stonesPerPeriod: 25,
      );
      expect(state.timeLeft, Duration(seconds: 60));
    });

    test('timeLeft returns periodTimeLeft during overtime', () {
      final state = CanadianByoyomiTimeState(
        mainTimeLeft: Duration.zero,
        periodTimeLeft: Duration(seconds: 400),
        stonesRemaining: 15,
        stonesPerPeriod: 25,
      );
      expect(state.timeLeft, Duration(seconds: 400));
    });

    test('isFlagged when all time exhausted', () {
      final state = CanadianByoyomiTimeState(
        mainTimeLeft: Duration.zero,
        periodTimeLeft: Duration.zero,
        stonesRemaining: 10,
        stonesPerPeriod: 25,
      );
      expect(state.isFlagged, true);
    });

    test('not flagged during overtime with time left', () {
      final state = CanadianByoyomiTimeState(
        mainTimeLeft: Duration.zero,
        periodTimeLeft: Duration(seconds: 100),
        stonesRemaining: 10,
        stonesPerPeriod: 25,
      );
      expect(state.isFlagged, false);
    });

    test('displaySegments in overtime shows time + stones', () {
      final state = CanadianByoyomiTimeState(
        mainTimeLeft: Duration.zero,
        periodTimeLeft: Duration(minutes: 5, seconds: 30),
        stonesRemaining: 15,
        stonesPerPeriod: 25,
      );
      final segments = state.displaySegments;
      // Should show time segments + stones label
      expect(segments.last.isTime, false);
      expect(segments.last.value, '10/25'); // 25 - 15 = 10 stones played
    });

    test('shouldVoiceCountdown true in overtime', () {
      final state = CanadianByoyomiTimeState(
        mainTimeLeft: Duration.zero,
        periodTimeLeft: Duration(seconds: 5),
        stonesRemaining: 3,
        stonesPerPeriod: 25,
      );
      expect(state.shouldVoiceCountdown, true);
    });
  });

  group('CanadianByoyomiTimeControl', () {
    test('initialState creates correct state', () {
      final tc = CanadianByoyomiTimeControl(
        mainTime: Duration(seconds: 60),
        periodTime: Duration(seconds: 600),
        stonesPerPeriod: 25,
      );
      final state = tc.initialState() as CanadianByoyomiTimeState;
      expect(state.mainTimeLeft, Duration(seconds: 60));
      expect(state.periodTimeLeft, Duration(seconds: 600));
      expect(state.stonesRemaining, 25);
      expect(state.stonesPerPeriod, 25);
    });

    test('tick consumes main time', () {
      final tc = CanadianByoyomiTimeControl(
        mainTime: Duration(seconds: 60),
        periodTime: Duration(seconds: 600),
        stonesPerPeriod: 25,
      );
      final base = tc.initialState();
      final result = tc.tick(base, Duration(seconds: 10)) as CanadianByoyomiTimeState;
      expect(result.mainTimeLeft, Duration(seconds: 50));
      expect(result.stonesRemaining, 25);
    });

    test('tick transitions to overtime', () {
      final tc = CanadianByoyomiTimeControl(
        mainTime: Duration(seconds: 5),
        periodTime: Duration(seconds: 600),
        stonesPerPeriod: 25,
      );
      final base = tc.initialState();
      final result = tc.tick(base, Duration(seconds: 8)) as CanadianByoyomiTimeState;
      expect(result.mainTimeLeft, Duration.zero);
      expect(result.periodTimeLeft, Duration(seconds: 597));
      expect(result.stonesRemaining, 25);
    });

    test('tick flags when period time runs out', () {
      final tc = CanadianByoyomiTimeControl(
        mainTime: Duration.zero,
        periodTime: Duration(seconds: 10),
        stonesPerPeriod: 25,
      );
      final base = tc.initialState();
      final result = tc.tick(base, Duration(seconds: 15));
      expect(result.isFlagged, true);
    });

    test('description format', () {
      final tc = CanadianByoyomiTimeControl(
        mainTime: Duration(seconds: 60),
        periodTime: Duration(seconds: 600),
        stonesPerPeriod: 25,
      );
      expect(tc.description(), '1:00 + (10:00/25)');
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/time_control/canadian_byoyomi_test.dart`
Expected: FAIL

- [ ] **Step 3: Implement CanadianByoyomiTimeControl and CanadianByoyomiTimeState**

Create `lib/game_client/time_control/canadian_byoyomi.dart`:
```dart
import 'package:flutter/widgets.dart';
import 'package:wqhub/game_client/time_control/time_control.dart';
import 'package:wqhub/game_client/time_control/time_state.dart';

@immutable
class CanadianByoyomiTimeState extends TimeState {
  final Duration mainTimeLeft;
  final Duration periodTimeLeft;
  final int stonesRemaining;
  final int stonesPerPeriod;

  const CanadianByoyomiTimeState({
    required this.mainTimeLeft,
    required this.periodTimeLeft,
    required this.stonesRemaining,
    required this.stonesPerPeriod,
  });

  bool get isOvertime =>
      mainTimeLeft == Duration.zero && periodTimeLeft > Duration.zero;

  @override
  Duration get timeLeft =>
      mainTimeLeft > Duration.zero ? mainTimeLeft : periodTimeLeft;

  @override
  bool get isFlagged =>
      mainTimeLeft == Duration.zero && periodTimeLeft == Duration.zero;

  @override
  bool isLowTime(Duration threshold) => timeLeft <= threshold;

  @override
  bool get shouldVoiceCountdown => isOvertime;

  @override
  List<DisplaySegment> get displaySegments {
    final time = timeLeft;
    final hh = time.inHours;
    final mm = time.inMinutes.remainder(60);
    final ss = time.inSeconds.remainder(60);

    String pad(int v) => v.toString().padLeft(2, '0');

    final timeSegments = [
      if (hh > 0) DisplaySegment(value: pad(hh)),
      DisplaySegment(value: pad(mm)),
      DisplaySegment(value: pad(ss)),
    ];

    if (mainTimeLeft > Duration.zero || stonesPerPeriod == 0) {
      return timeSegments;
    } else {
      // Overtime: show time + stones played/total
      final stonesPlayed = stonesPerPeriod - stonesRemaining;
      return [
        ...timeSegments,
        DisplaySegment(value: '$stonesPlayed/$stonesPerPeriod', isTime: false),
      ];
    }
  }

  @override
  int get hashCode =>
      Object.hash(mainTimeLeft, periodTimeLeft, stonesRemaining, stonesPerPeriod);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other.runtimeType != runtimeType) return false;
    return other is CanadianByoyomiTimeState &&
        other.mainTimeLeft == mainTimeLeft &&
        other.periodTimeLeft == periodTimeLeft &&
        other.stonesRemaining == stonesRemaining &&
        other.stonesPerPeriod == stonesPerPeriod;
  }

  @override
  String toString() =>
      'CanadianByo($mainTimeLeft - $periodTimeLeft stones:$stonesRemaining/$stonesPerPeriod)';
}

@immutable
class CanadianByoyomiTimeControl extends TimeControl {
  final Duration mainTime;
  final Duration periodTime;
  final int stonesPerPeriod;

  const CanadianByoyomiTimeControl({
    required this.mainTime,
    required this.periodTime,
    required this.stonesPerPeriod,
  });

  @override
  TimeState initialState() => CanadianByoyomiTimeState(
        mainTimeLeft: mainTime,
        periodTimeLeft: periodTime,
        stonesRemaining: stonesPerPeriod,
        stonesPerPeriod: stonesPerPeriod,
      );

  @override
  TimeState tick(TimeState base, Duration elapsed) {
    if (base is! CanadianByoyomiTimeState) return base;

    var remaining = elapsed;
    var mainTimeLeft = base.mainTimeLeft;
    var periodTimeLeft = base.periodTimeLeft;

    // Consume main time
    if (mainTimeLeft > Duration.zero) {
      if (remaining <= mainTimeLeft) {
        mainTimeLeft -= remaining;
        remaining = Duration.zero;
      } else {
        remaining -= mainTimeLeft;
        mainTimeLeft = Duration.zero;
      }
    }

    // Consume period time (Canadian has one period that resets on stone completion)
    if (remaining > Duration.zero) {
      if (remaining <= periodTimeLeft) {
        periodTimeLeft -= remaining;
      } else {
        periodTimeLeft = Duration.zero;
      }
    }

    return CanadianByoyomiTimeState(
      mainTimeLeft: mainTimeLeft,
      periodTimeLeft: periodTimeLeft,
      stonesRemaining: base.stonesRemaining,
      stonesPerPeriod: base.stonesPerPeriod,
    );
  }

  @override
  String description() {
    final mainMin = mainTime.inMinutes;
    final mainSec = mainTime.inSeconds.remainder(60);
    final mainStr = '$mainMin:${mainSec.toString().padLeft(2, '0')}';
    final periodMin = periodTime.inMinutes;
    final periodSec = periodTime.inSeconds.remainder(60);
    final periodStr = '$periodMin:${periodSec.toString().padLeft(2, '0')}';
    return '$mainStr + ($periodStr/$stonesPerPeriod)';
  }

  @override
  int get hashCode => Object.hash(mainTime, periodTime, stonesPerPeriod);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other.runtimeType != runtimeType) return false;
    return other is CanadianByoyomiTimeControl &&
        other.mainTime == mainTime &&
        other.periodTime == periodTime &&
        other.stonesPerPeriod == stonesPerPeriod;
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/time_control/canadian_byoyomi_test.dart`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```
git add lib/game_client/time_control/canadian_byoyomi.dart test/time_control/canadian_byoyomi_test.dart
git commit -m "feat: implement CanadianByoyomiTimeControl and TimeState with tests"
```

---

## Task 4: Refactor GameTimer to Use Abstract TimeControl

**Files:**
- Modify: `lib/game_client/game_timer.dart`
- Modify: `test/game_timer_test.dart`

- [ ] **Step 1: Update GameTimer to accept TimeControl and delegate tick()**

In `lib/game_client/game_timer.dart`, replace the entire file with:

The key changes:
- Constructor takes `TimeControl timeControl` parameter
- Remove `_calculateTimeState` method entirely
- `_tick()` calls `timeControl.tick(_baseState, elapsed)` instead
- `currentState` getter also uses `timeControl.tick()`
- Update import from old `time_state.dart` to new `time_control/time_state.dart`

- [ ] **Step 2: Update game_timer_test.dart**

All tests now need to pass a `JapaneseByoyomiTimeControl` to `GameTimer` and use `JapaneseByoyomiTimeState` instead of `TimeState`. Update imports and constructors throughout. The test logic stays the same — just the types change.

- [ ] **Step 3: Run tests**

Run: `flutter test test/game_timer_test.dart`
Expected: All tests PASS

- [ ] **Step 4: Commit**

```
git add lib/game_client/game_timer.dart test/game_timer_test.dart
git commit -m "refactor: GameTimer delegates tick logic to TimeControl"
```

---

## Task 5: Migrate Game Base Class and ServerFeatures

**Files:**
- Modify: `lib/game_client/game.dart`
- Modify: `lib/game_client/server_features.dart`
- Modify: `lib/game_client/automatch_preset.dart`
- Delete: `lib/game_client/time_control.dart`
- Delete: `lib/game_client/time_state.dart`

- [ ] **Step 1: Update Game base class**

In `lib/game_client/game.dart`:
- Change imports from `time_control.dart` / `time_state.dart` to `time_control/time_control.dart` and `time_control/time_state.dart`
- Replace constructor body:
  ```dart
  final t = timeControl.initialState();
  blackTime.value = (2, t);
  whiteTime.value = (2, t);
  ```

- [ ] **Step 2: Remove localTimeControl from ServerFeatures**

In `lib/game_client/server_features.dart`:
- Remove `final bool localTimeControl;`
- Remove `required this.localTimeControl,`
- Remove from `hashCode` and `operator ==`

- [ ] **Step 3: Update AutomatchPreset import**

In `lib/game_client/automatch_preset.dart`:
- Change import from `time_control.dart` to `time_control/time_control.dart`

- [ ] **Step 4: Delete old files**

Delete `lib/game_client/time_control.dart` and `lib/game_client/time_state.dart`.

- [ ] **Step 5: Run analyzer to find all remaining broken imports**

Run: `flutter analyze`
Expected: Errors in files still importing old paths. Note them for the next tasks.

- [ ] **Step 6: Commit**

```
git add -A
git commit -m "refactor: migrate Game, ServerFeatures, AutomatchPreset to abstract time control"
```

---

## Task 6: Refactor TimeDisplay to Pure Renderer

**Files:**
- Modify: `lib/time_display.dart`
- Modify: `lib/play/game_page.dart`

- [ ] **Step 1: Rewrite TimeDisplay as pure renderer**

In `lib/time_display.dart`:
- Remove `TickMode` enum, `_timer`, `_timeLeft`, `_onTick`, `onTimeout`, `tickerEnabled`, `enabled`, `tickMode`
- Keep `tickId`, `timeState`, `warningDuration`, `voiceCountdown`
- `build()` reads `timeState.displaySegments` and renders them as a `Row` of `_UnitContainer` widgets, with `:` separators between time segments
- `_voiceCountdown()` uses `timeState.shouldVoiceCountdown` and `timeState.timeLeft`
- Warning color uses `timeState.isLowTime(warningDuration)`

- [ ] **Step 2: Update game_page.dart TimeDisplay usages**

In `lib/play/game_page.dart` (lines 217-231 and 247-261):
- Remove `enabled:` parameter
- Remove `tickerEnabled:` parameter
- Keep `tickId`, `timeState`, `warningDuration`, `voiceCountdown`

- [ ] **Step 3: Update game_page.dart imports**

Change `time_state.dart` import to `time_control/time_state.dart`.

- [ ] **Step 4: Run analyzer**

Run: `flutter analyze lib/time_display.dart lib/play/game_page.dart`
Expected: No errors

- [ ] **Step 5: Commit**

```
git add lib/time_display.dart lib/play/game_page.dart
git commit -m "refactor: TimeDisplay becomes pure renderer driven by displaySegments"
```

---

## Task 7: Migrate OGS to New Time Types

**Files:**
- Modify: `lib/game_client/ogs/ogs_game.dart`
- Modify: `lib/game_client/ogs/ogs_game_client.dart`

- [ ] **Step 1: Update OGSGameClient**

In `lib/game_client/ogs/ogs_game_client.dart`:
- Change `TimeControl(` to `JapaneseByoyomiTimeControl(` everywhere (lines 112-159, 382-386)
- Update import paths
- Remove `localTimeControl: false` from `serverFeatures`

- [ ] **Step 2: Update OGSGame**

In `lib/game_client/ogs/ogs_game.dart`:
- Change `TimeState(` to `JapaneseByoyomiTimeState(` in `_parseOGSTimeData` (line 508)
  - `mainTimeLeft:` stays same
  - `periodTimeLeft:` stays same
  - `periodCount:` becomes `periodsRemaining:`
- Change `GameTimer(initialState:...)` to `GameTimer(timeControl: timeControl, initialState:...)` (lines 82-83)
- The `initialTimeState` construction (lines 77-80) changes to `timeControl.initialState()`
- Update import paths

- [ ] **Step 3: Run analyzer and tests**

Run: `flutter analyze lib/game_client/ogs/`
Run: `flutter test`
Expected: No errors, existing tests pass

- [ ] **Step 4: Commit**

```
git add lib/game_client/ogs/
git commit -m "refactor: migrate OGS to JapaneseByoyomiTimeControl/State"
```

---

## Task 8: Migrate TestGameClient and Training Pages

**Files:**
- Modify: `lib/game_client/test_game_client.dart`
- Modify: `lib/train/time_frenzy_page.dart`
- Modify: `lib/train/exam_page.dart`
- Modify: `lib/train/collection_page.dart`
- Modify: `lib/play/automatch_preset_list_tile.dart`

- [ ] **Step 1: Update TestGameClient**

In `lib/game_client/test_game_client.dart`:
- Change `TimeControl(` to `JapaneseByoyomiTimeControl(`
- Remove `localTimeControl: true` from `serverFeatures`
- Update imports

- [ ] **Step 2: Update AutomatchPresetListTile**

In `lib/play/automatch_preset_list_tile.dart`:
- Replace lines 20-22 with: `final title = Text(preset.timeControl.description());`
- Remove unused imports

- [ ] **Step 3: Update training pages**

For `time_frenzy_page.dart` and `exam_page.dart`:
- Replace `TimeDisplay` with a `ValueListenableBuilder` driven by a `GameTimer`
- Create a `JapaneseByoyomiTimeControl` with 0 periods for pure countdown
- Create a `GameTimer` in `initState`, start it, listen for `isFlagged` for timeout
- The `TimeDisplay` widget just renders the state (no `tickerEnabled`, `enabled`, `onTimeout`)

For `collection_page.dart` (count-up stopwatch):
- Use a simple `Timer.periodic` that increments a `Duration` in state and builds `TimeDisplay` with a manually constructed `JapaneseByoyomiTimeState` (all in mainTimeLeft, 0 periods)
- OR create a local `ValueNotifier<(int, TimeState)>` that a periodic timer updates

- [ ] **Step 4: Run full build**

Run: `flutter build windows`
Expected: Build succeeds

- [ ] **Step 5: Commit**

```
git add lib/game_client/test_game_client.dart lib/play/automatch_preset_list_tile.dart lib/train/
git commit -m "refactor: migrate TestGameClient, training pages, and preset display to new time types"
```

---

## Task 9: Pandanet TCP Manager — Seek Protocol

**Files:**
- Create: `lib/game_client/pandanet/seek_config.dart`
- Modify: `lib/game_client/pandanet/pandanet_tcp_manager.dart`

- [ ] **Step 1: Create SeekConfig data class**

Create `lib/game_client/pandanet/seek_config.dart`:
```dart
import 'package:flutter/widgets.dart';

@immutable
class SeekConfig {
  final int id;
  final Duration mainTime;
  final Duration periodTime;
  final int stonesPerPeriod;

  const SeekConfig({
    required this.id,
    required this.mainTime,
    required this.periodTime,
    required this.stonesPerPeriod,
  });
}
```

- [ ] **Step 2: Add seek support to PandanetTcpManager**

In `lib/game_client/pandanet/pandanet_tcp_manager.dart`, add:

1. After login, send the three toggles:
   ```dart
   _socket!.writeln('toggle client true');
   _socket!.writeln('toggle nmatch true');
   _socket!.writeln('toggle seek true');
   ```

2. Add a `getSeekConfigs()` method that sends `seek config_list` and parses the response:
   - Collect lines starting with `63 CONFIG_LIST`
   - Parse each as: `63 CONFIG_LIST <id> <main_sec> <byo_sec> <stones> <unk1> <unk2>`
   - Return `List<SeekConfig>`

3. Add `sendSeekEntry(int configId, int boardSize)` method:
   - Sends `seek entry $configId $boardSize`

4. Add `sendSeekCancel()` method:
   - Sends `seek entry_cancel`

5. Parse `63 OPPONENT_FOUND <username>` and `63 ENTRY_CANCEL` in `_handleFullMessage`

- [ ] **Step 3: Run analyzer**

Run: `flutter analyze lib/game_client/pandanet/`
Expected: No errors

- [ ] **Step 4: Commit**

```
git add lib/game_client/pandanet/seek_config.dart lib/game_client/pandanet/pandanet_tcp_manager.dart
git commit -m "feat: add seek protocol support to PandanetTcpManager"
```

---

## Task 10: Pandanet GameClient — Seek-Based Automatch

**Files:**
- Modify: `lib/game_client/pandanet/pandanet_game_client.dart`

- [ ] **Step 1: Replace hardcoded presets with dynamic seek configs**

Replace `_createAutomatchPresets()` with a method that:
1. Uses the `SeekConfig` list from the TCP manager
2. For each config, creates presets for board sizes 9, 13, 19
3. Uses `CanadianByoyomiTimeControl` for each

- [ ] **Step 2: Replace findGame with seek entry**

Replace the `findGame()` method:
1. Parse preset ID to get config ID and board size
2. Call `_tcpManager.sendSeekEntry(configId, boardSize)`
3. Listen for `63 OPPONENT_FOUND` on the message stream
4. Parse the game start messages (code 15)
5. Create `PandanetGame` with `CanadianByoyomiTimeControl`

- [ ] **Step 3: Replace stopAutomatch with seek cancel**

Replace `stopAutomatch()`:
1. Call `_tcpManager.sendSeekCancel()`

- [ ] **Step 4: Remove localTimeControl from serverFeatures**

Remove `localTimeControl: true` from the `ServerFeatures` constructor.

- [ ] **Step 5: Update imports**

Change `time_control.dart` import to `time_control/canadian_byoyomi.dart` and `time_control/time_control.dart`.

- [ ] **Step 6: Run analyzer**

Run: `flutter analyze lib/game_client/pandanet/pandanet_game_client.dart`
Expected: No errors

- [ ] **Step 7: Commit**

```
git add lib/game_client/pandanet/pandanet_game_client.dart
git commit -m "feat: replace match-loop with seek protocol for Pandanet automatch"
```

---

## Task 11: Pandanet Game — GameTimer and TIME Message Parsing

**Files:**
- Modify: `lib/game_client/pandanet/pandanet_game.dart`

- [ ] **Step 1: Add GameTimer instances**

Add `_blackTimer` and `_whiteTimer` `GameTimer` instances (same pattern as OGSGame):
- Create with `CanadianByoyomiTimeControl` and initial state
- Bridge to `blackTime` / `whiteTime` via listeners

- [ ] **Step 2: Parse TIME messages**

In `_onMessage`, parse lines matching `15 TIME:<game_id>:<player>(<color>):` format:
```
15 TIME:<id>:<player>(W): <move> <main_used>/<main_total> <byo_used>/<byo_total> <stones_used>/<stones_total> 0/0 0/0 0/0
```
Extract `mainTimeLeft`, `periodTimeLeft`, `stonesRemaining` and create `CanadianByoyomiTimeState`.
Call `timer.start(newState)` for the current player, `timer.stop()` for the other.

- [ ] **Step 3: Handle stone tracking on move**

When a move is received during overtime:
- The server sends updated TIME with new stone counts, so we rely on server updates
- Between updates, the GameTimer ticks down `periodTimeLeft` locally

- [ ] **Step 4: Update imports and remove old time_control import**

- [ ] **Step 5: Run full build**

Run: `flutter build windows`
Expected: Build succeeds

- [ ] **Step 6: Commit**

```
git add lib/game_client/pandanet/pandanet_game.dart
git commit -m "feat: add GameTimer and TIME message parsing to PandanetGame"
```

---

## Task 12: Final Verification

- [ ] **Step 1: Run full test suite**

Run: `flutter test`
Expected: All tests pass

- [ ] **Step 2: Run full build**

Run: `flutter build windows`
Expected: Build succeeds with no errors

- [ ] **Step 3: Run analyzer**

Run: `flutter analyze`
Expected: No errors (warnings about unused Pandanet fields are OK)

- [ ] **Step 4: Clean up igs_explorer.py**

Delete or gitignore `igs_explorer.py` (the protocol exploration script).

- [ ] **Step 5: Final commit**

```
git add -A
git commit -m "chore: final cleanup after time control refactor and seek integration"
```
