import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/app_log.dart';
import '../services/diagnostics_service.dart';
import '../services/youtube_service.dart';
import '../theme/app_theme.dart';
import 'ui_kit.dart';

class DiagnosticsDialog extends StatefulWidget {
  final YoutubeService youtube;

  const DiagnosticsDialog({super.key, required this.youtube});

  @override
  State<DiagnosticsDialog> createState() => _DiagnosticsDialogState();
}

class _DiagnosticsDialogState extends State<DiagnosticsDialog> {
  List<DiagnosticResult>? results;

  @override
  void initState() {
    super.initState();
    DiagnosticsService.run(widget.youtube).then((r) {
      AppLog.info('diagnóstico', '\n${report(r)}');
      if (mounted) setState(() => results = r);
    });
  }

  String report(List<DiagnosticResult> items) {
    return items.map((r) => '${r.ok ? 'OK' : 'FALHA'} - ${r.name}: ${r.detail}').join('\n');
  }

  Widget buildRow(DiagnosticResult r) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              r.ok ? Icons.check_circle_outline : Icons.error_outline,
              size: 16,
              color: r.ok ? AppColors.accent : AppColors.danger,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.name, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                SelectableText(
                  r.detail,
                  style: const TextStyle(fontSize: 11.5, color: AppColors.textDim, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = results;
    return AppDialog(
      title: 'Verificar dependências',
      width: 580,
      actions: [
        AppButton(
          label: 'Copiar',
          onPressed: items == null
              ? null
              : () => Clipboard.setData(ClipboardData(text: report(items))),
        ),
        AppButton(label: 'Fechar', primary: true, onPressed: () => Navigator.pop(context)),
      ],
      child: items == null
          ? const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(minHeight: 2),
                SizedBox(height: 10),
                Text(
                  'Verificando ferramentas e testando um download real…',
                  style: TextStyle(fontSize: 12.5, color: AppColors.textDim),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [for (final r in items) buildRow(r)],
            ),
    );
  }
}
