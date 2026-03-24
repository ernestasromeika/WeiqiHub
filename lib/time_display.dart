import 'package:flutter/material.dart';
import 'package:wqhub/audio/audio_controller.dart';
import 'package:wqhub/game_client/time_control/time_state.dart';

class TimeDisplay extends StatefulWidget {
  final int tickId;
  final TimeState timeState;
  final Duration warningDuration;
  final bool voiceCountdown;

  const TimeDisplay({
    super.key,
    this.tickId = 0,
    required this.timeState,
    required this.warningDuration,
    required this.voiceCountdown,
  });

  @override
  State<TimeDisplay> createState() => _TimeDisplayState();
}

class _TimeDisplayState extends State<TimeDisplay> {
  int _lastCountdownSecond = -1;

  @override
  void didUpdateWidget(TimeDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.timeState != oldWidget.timeState ||
        widget.tickId != oldWidget.tickId) {
      _voiceCountdown();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final containerColor = widget.timeState.isLowTime(widget.warningDuration)
        ? colorScheme.errorContainer
        : colorScheme.primaryContainer;
    final textStyle = TextTheme.of(context).headlineLarge?.copyWith(
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    );

    final segments = widget.timeState.displaySegments;
    final children = <Widget>[];
    for (int i = 0; i < segments.length; i++) {
      final seg = segments[i];
      // Add ':' separator between consecutive segments, except not before
      // the very first one.
      if (i > 0) {
        children.add(Text(':', style: textStyle));
      }
      children.add(_UnitContainer(value: seg.value, color: containerColor));
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: children,
    );
  }

  void _voiceCountdown() {
    if (!widget.voiceCountdown) return;
    if (!widget.timeState.shouldVoiceCountdown) {
      _lastCountdownSecond = -1;
      return;
    }
    final seconds = widget.timeState.timeLeft.inSeconds;
    if (seconds > 0 && seconds <= 9 && seconds != _lastCountdownSecond) {
      _lastCountdownSecond = seconds;
      AudioController().count(seconds);
    }
  }
}

class _UnitContainer extends StatelessWidget {
  final String value;
  final Color color;

  const _UnitContainer({required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    final textStyle = TextTheme.of(context).headlineLarge?.copyWith(
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    );
    return Container(
      padding: EdgeInsets.only(left: 4, right: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      alignment: Alignment.center,
      child: Text(value, style: textStyle),
    );
  }
}
