import 'package:flutter/material.dart';
import '../services/smart_join.dart';
import '../theme/app_theme.dart';
import 'ui_kit.dart';

Future<SmartJoinOptions?> showSmartJoinDialog(
  BuildContext context, {
  required String title,
  required String description,
  bool allowSort = false,
}) {
  return showDialog<SmartJoinOptions>(
    context: context,
    builder: (_) => SmartJoinDialog(
      title: title,
      description: description,
      allowSort: allowSort,
    ),
  );
}

Future<void> runSmartJoin(
  BuildContext context, {
  required String title,
  required String description,
  required Future<String> Function(SmartJoinOptions options) action,
  bool allowSort = false,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final options = await showSmartJoinDialog(
    context,
    title: title,
    description: description,
    allowSort: allowSort,
  );
  if (options == null) return;
  messenger.showSnackBar(
    const SnackBar(content: Text('Analisando batidas e andamento…')),
  );
  final message = await action(options);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

class SmartJoinDialog extends StatefulWidget {
  final String title;
  final String description;
  final bool allowSort;

  const SmartJoinDialog({
    super.key,
    required this.title,
    required this.description,
    required this.allowSort,
  });

  @override
  State<SmartJoinDialog> createState() => _SmartJoinDialogState();
}

class _SmartJoinDialogState extends State<SmartJoinDialog> {
  SmartJoinOptions options = const SmartJoinOptions();

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: widget.title,
      width: 440,
      actions: [
        AppButton(
          label: 'Cancelar',
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppButton(
          label: 'Unir',
          icon: Icons.auto_awesome,
          primary: true,
          onPressed: () => Navigator.of(context).pop(options),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.description,
            style: const TextStyle(fontSize: 12.5, color: AppColors.textDim),
          ),
          const SizedBox(height: 12),
          CheckRow(
            label: 'Alinhar nas batidas',
            value: options.alignBeats,
            onChanged: (v) => setState(() {
              options = options.copyWith(alignBeats: v);
            }),
          ),
          CheckRow(
            label: 'Ajustar andamento (até 10%)',
            value: options.matchTempo,
            onChanged: (v) => setState(() {
              options = options.copyWith(matchTempo: v);
            }),
          ),
          CheckRow(
            label: 'Equilibrar volume na transição',
            value: options.matchLoudness,
            onChanged: (v) => setState(() {
              options = options.copyWith(matchLoudness: v);
            }),
          ),
          CheckRow(
            label: 'Aparar silêncio no início e no fim',
            value: options.trimSilence,
            onChanged: (v) => setState(() {
              options = options.copyWith(trimSilence: v);
            }),
          ),
          if (widget.allowSort)
            CheckRow(
              label: 'Ordenar por BPM crescente',
              value: options.sortByBpm,
              onChanged: (v) => setState(() {
                options = options.copyWith(sortByBpm: v);
              }),
            ),
          const SizedBox(height: 8),
          FormRow(
            label: 'Sobreposição',
            child: SegmentedControl<int>(
              items: const [
                (0, 'Auto'),
                (2000, '2 s'),
                (4000, '4 s'),
                (6000, '6 s'),
              ],
              value: options.overlapMs,
              onChanged: (v) => setState(() {
                options = options.copyWith(overlapMs: v);
              }),
            ),
          ),
        ],
      ),
    );
  }
}
