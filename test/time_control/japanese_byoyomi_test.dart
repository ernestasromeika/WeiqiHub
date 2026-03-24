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
