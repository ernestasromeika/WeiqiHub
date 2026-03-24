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
