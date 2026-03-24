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

    // Consume period time
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
