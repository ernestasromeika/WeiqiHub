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

    test('isOvertime false when flagged', () {
      final state = CanadianByoyomiTimeState(
        mainTimeLeft: Duration.zero,
        periodTimeLeft: Duration.zero,
        stonesRemaining: 10,
        stonesPerPeriod: 25,
      );
      expect(state.isOvertime, false);
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

    test('displaySegments in main time shows only time', () {
      final state = CanadianByoyomiTimeState(
        mainTimeLeft: Duration(minutes: 1),
        periodTimeLeft: Duration(seconds: 600),
        stonesRemaining: 25,
        stonesPerPeriod: 25,
      );
      final segments = state.displaySegments;
      expect(segments.every((s) => s.isTime), true);
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

    test('shouldVoiceCountdown false in main time', () {
      final state = CanadianByoyomiTimeState(
        mainTimeLeft: Duration(seconds: 30),
        periodTimeLeft: Duration(seconds: 600),
        stonesRemaining: 25,
        stonesPerPeriod: 25,
      );
      expect(state.shouldVoiceCountdown, false);
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

    test('tick preserves stonesRemaining', () {
      final tc = CanadianByoyomiTimeControl(
        mainTime: Duration.zero,
        periodTime: Duration(seconds: 600),
        stonesPerPeriod: 25,
      );
      // Simulate a state where 10 stones have been played
      final base = CanadianByoyomiTimeState(
        mainTimeLeft: Duration.zero,
        periodTimeLeft: Duration(seconds: 400),
        stonesRemaining: 15,
        stonesPerPeriod: 25,
      );
      final result = tc.tick(base, Duration(seconds: 10)) as CanadianByoyomiTimeState;
      expect(result.periodTimeLeft, Duration(seconds: 390));
      expect(result.stonesRemaining, 15); // unchanged by tick
    });

    test('description format', () {
      final tc = CanadianByoyomiTimeControl(
        mainTime: Duration(seconds: 60),
        periodTime: Duration(seconds: 600),
        stonesPerPeriod: 25,
      );
      expect(tc.description(), '1:00 + (10:00/25)');
    });

    test('description with short period', () {
      final tc = CanadianByoyomiTimeControl(
        mainTime: Duration(seconds: 60),
        periodTime: Duration(seconds: 300),
        stonesPerPeriod: 25,
      );
      expect(tc.description(), '1:00 + (5:00/25)');
    });
  });
}
