import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wqhub/game_client/game_timer.dart';
import 'package:wqhub/game_client/time_control/japanese_byoyomi.dart';
import 'package:wqhub/game_client/time_control/time_state.dart';

void main() {
  group('GameTimer', () {
    test('initializes with given time state', () {
      final tc = JapaneseByoyomiTimeControl(
        mainTime: Duration(minutes: 5),
        periodCount: 5,
        timePerPeriod: Duration(seconds: 30),
      );
      final initialState = JapaneseByoyomiTimeState(
        mainTimeLeft: Duration(minutes: 5),
        periodTimeLeft: Duration(seconds: 30),
        periodsRemaining: 5,
      );

      final timer = GameTimer(timeControl: tc, initialState: initialState);

      expect(timer.currentState, equals(initialState));
      expect(timer.isRunning, isFalse);

      timer.dispose();
    });

    test('counts down main time when started', () {
      fakeAsync((async) {
        final tc = JapaneseByoyomiTimeControl(
          mainTime: Duration(seconds: 10),
          periodCount: 5,
          timePerPeriod: Duration(seconds: 30),
        );
        final initialState = JapaneseByoyomiTimeState(
          mainTimeLeft: Duration(seconds: 10),
          periodTimeLeft: Duration(seconds: 30),
          periodsRemaining: 5,
        );

        final timer = GameTimer(timeControl: tc, initialState: initialState);
        timer.start(initialState);

        expect(timer.isRunning, isTrue);
        final state0 = timer.currentState as JapaneseByoyomiTimeState;
        expect(state0.mainTimeLeft, Duration(seconds: 10));

        // Advance 3 seconds
        async.elapse(Duration(seconds: 3));
        final state1 = timer.currentState as JapaneseByoyomiTimeState;
        expect(state1.mainTimeLeft, Duration(seconds: 7));

        // Advance 5 more seconds
        async.elapse(Duration(seconds: 5));
        final state2 = timer.currentState as JapaneseByoyomiTimeState;
        expect(state2.mainTimeLeft, Duration(seconds: 2));

        timer.dispose();
      });
    });

    test('transitions from main time to overtime', () {
      fakeAsync((async) {
        final tc = JapaneseByoyomiTimeControl(
          mainTime: Duration(seconds: 2),
          periodCount: 5,
          timePerPeriod: Duration(seconds: 30),
        );
        final initialState = JapaneseByoyomiTimeState(
          mainTimeLeft: Duration(seconds: 2),
          periodTimeLeft: Duration(seconds: 30),
          periodsRemaining: 5,
        );

        final timer = GameTimer(timeControl: tc, initialState: initialState);
        timer.start(initialState);

        // Advance past main time
        async.elapse(Duration(seconds: 3));

        final state = timer.currentState as JapaneseByoyomiTimeState;
        expect(state.mainTimeLeft, Duration.zero);
        expect(state.periodTimeLeft, Duration(seconds: 29));
        expect(state.periodsRemaining, 5);

        timer.dispose();
      });
    });

    test('counts down overtime periods', () {
      fakeAsync((async) {
        final tc = JapaneseByoyomiTimeControl(
          mainTime: Duration.zero,
          periodCount: 3,
          timePerPeriod: Duration(seconds: 10),
        );
        final initialState = JapaneseByoyomiTimeState(
          mainTimeLeft: Duration.zero,
          periodTimeLeft: Duration(seconds: 10),
          periodsRemaining: 3,
        );

        final timer = GameTimer(timeControl: tc, initialState: initialState);
        timer.start(initialState);

        // Use up 5 seconds of first period
        async.elapse(Duration(seconds: 5));

        var state = timer.currentState as JapaneseByoyomiTimeState;
        expect(state.mainTimeLeft, Duration.zero);
        expect(state.periodTimeLeft, Duration(seconds: 5));
        expect(state.periodsRemaining, 3);

        // Use up remaining 5 seconds to complete first period
        async.elapse(Duration(seconds: 5));

        state = timer.currentState as JapaneseByoyomiTimeState;
        expect(state.mainTimeLeft, Duration.zero);
        // Should now be in second period with full period time
        expect(state.periodTimeLeft, Duration(seconds: 10));
        expect(state.periodsRemaining, 2);

        // Use up another 11 seconds (full period + 1 second into next)
        async.elapse(Duration(seconds: 11));

        state = timer.currentState as JapaneseByoyomiTimeState;
        expect(state.mainTimeLeft, Duration.zero);
        expect(state.periodTimeLeft, Duration(seconds: 9));
        expect(state.periodsRemaining, 1);

        timer.dispose();
      });
    });

    test('reaches zero state when time exhausted', () {
      fakeAsync((async) {
        final tc = JapaneseByoyomiTimeControl(
          mainTime: Duration(seconds: 1),
          periodCount: 1,
          timePerPeriod: Duration(seconds: 2),
        );
        final initialState = JapaneseByoyomiTimeState(
          mainTimeLeft: Duration(seconds: 1),
          periodTimeLeft: Duration(seconds: 2),
          periodsRemaining: 1,
        );

        final timer = GameTimer(timeControl: tc, initialState: initialState);
        timer.start(initialState);

        // Exhaust all time
        async.elapse(Duration(seconds: 10));

        expect(timer.currentState.isFlagged, isTrue);

        timer.dispose();
      });
    });

    test('emits updates via notifier', () {
      fakeAsync((async) {
        final tc = JapaneseByoyomiTimeControl(
          mainTime: Duration(seconds: 5),
          periodCount: 5,
          timePerPeriod: Duration(seconds: 30),
        );
        final initialState = JapaneseByoyomiTimeState(
          mainTimeLeft: Duration(seconds: 5),
          periodTimeLeft: Duration(seconds: 30),
          periodsRemaining: 5,
        );

        final timer = GameTimer(timeControl: tc, initialState: initialState);
        final updates = <(int, TimeState)>[];

        timer.addListener(() {
          updates.add(timer.value);
        });

        timer.start(initialState);

        // Initial update from start()
        expect(updates.length, 1);
        final state0 = updates[0].$2 as JapaneseByoyomiTimeState;
        expect(state0.mainTimeLeft, Duration(seconds: 5));

        // Advance 3 seconds, should get 3 tick updates
        async.elapse(Duration(seconds: 3));

        expect(updates.length, 4); // 1 from start + 3 from ticks
        final stateLast = updates.last.$2 as JapaneseByoyomiTimeState;
        expect(stateLast.mainTimeLeft, Duration(seconds: 2));

        timer.dispose();
      });
    });

    test('tick counter increments on each update', () {
      fakeAsync((async) {
        final tc = JapaneseByoyomiTimeControl(
          mainTime: Duration(seconds: 5),
          periodCount: 5,
          timePerPeriod: Duration(seconds: 30),
        );
        final initialState = JapaneseByoyomiTimeState(
          mainTimeLeft: Duration(seconds: 5),
          periodTimeLeft: Duration(seconds: 30),
          periodsRemaining: 5,
        );

        final timer = GameTimer(timeControl: tc, initialState: initialState);
        timer.start(initialState);

        final initialTick = timer.value.$1;

        async.elapse(Duration(seconds: 2));

        final newTick = timer.value.$1;
        expect(newTick, greaterThan(initialTick));

        timer.dispose();
      });
    });

    test('stop freezes the timer', () {
      fakeAsync((async) {
        final tc = JapaneseByoyomiTimeControl(
          mainTime: Duration(seconds: 10),
          periodCount: 5,
          timePerPeriod: Duration(seconds: 30),
        );
        final initialState = JapaneseByoyomiTimeState(
          mainTimeLeft: Duration(seconds: 10),
          periodTimeLeft: Duration(seconds: 30),
          periodsRemaining: 5,
        );

        final timer = GameTimer(timeControl: tc, initialState: initialState);
        timer.start(initialState);

        async.elapse(Duration(seconds: 3));
        final state1 = timer.currentState as JapaneseByoyomiTimeState;
        expect(state1.mainTimeLeft, Duration(seconds: 7));

        timer.stop();
        expect(timer.isRunning, isFalse);

        // Time should not advance after stop
        async.elapse(Duration(seconds: 5));
        final state2 = timer.currentState as JapaneseByoyomiTimeState;
        expect(state2.mainTimeLeft, Duration(seconds: 7));

        timer.dispose();
      });
    });

    test('can restart with new state after stop', () {
      fakeAsync((async) {
        final tc = JapaneseByoyomiTimeControl(
          mainTime: Duration(seconds: 10),
          periodCount: 5,
          timePerPeriod: Duration(seconds: 30),
        );
        final initialState = JapaneseByoyomiTimeState(
          mainTimeLeft: Duration(seconds: 10),
          periodTimeLeft: Duration(seconds: 30),
          periodsRemaining: 5,
        );

        final timer = GameTimer(timeControl: tc, initialState: initialState);
        timer.start(initialState);

        async.elapse(Duration(seconds: 3));
        timer.stop();

        // Start with new state
        final newState = JapaneseByoyomiTimeState(
          mainTimeLeft: Duration(seconds: 20),
          periodTimeLeft: Duration(seconds: 30),
          periodsRemaining: 5,
        );
        timer.start(newState);

        expect(timer.isRunning, isTrue);
        final state1 = timer.currentState as JapaneseByoyomiTimeState;
        expect(state1.mainTimeLeft, Duration(seconds: 20));

        async.elapse(Duration(seconds: 2));
        final state2 = timer.currentState as JapaneseByoyomiTimeState;
        expect(state2.mainTimeLeft, Duration(seconds: 18));

        timer.dispose();
      });
    });
  });
}
