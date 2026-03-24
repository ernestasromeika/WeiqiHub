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
