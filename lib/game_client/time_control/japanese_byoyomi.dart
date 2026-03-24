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
