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
