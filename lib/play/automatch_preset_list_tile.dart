import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/material.dart';
import 'package:wqhub/game_client/automatch_preset.dart';
import 'package:wqhub/l10n/app_localizations.dart';

class AutomatchPresetListTile extends StatelessWidget {
  final AutomatchPreset preset;
  final ValueNotifier<IMap<String, AutomatchPresetStats>> stats;
  final Function() onTap;

  const AutomatchPresetListTile(
      {super.key,
      required this.preset,
      required this.stats,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final title = Text(preset.timeControl.description());

    return ListTile(
      leading: Text(loc.nxnBoardSize(preset.boardSize)),
      title: title,
      subtitle: Text('${loc.rules}: ${preset.rules.toLocalizedString(loc)}'),
      trailing: ValueListenableBuilder(
        valueListenable: stats,
        builder: (context, value, child) {
          final st = value.get(preset.id);
          if (st == null) {
            return SizedBox.shrink();
          } else {
            return Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 4,
              children: <Widget>[
                Icon(Icons.people),
                Text(st.playerCount.toString()),
              ],
            );
          }
        },
      ),
      onTap: onTap,
    );
  }
}
