import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import '../models/audio_formats.dart';
import '../services/system_service.dart';
import '../state/project_controller.dart';
import '../theme/app_theme.dart';
import 'format_picker.dart';
import 'ui_kit.dart';

class ExportDialog extends StatefulWidget {
  const ExportDialog({super.key});

  @override
  State<ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<ExportDialog> {
  ExportOptions options = const ExportOptions();

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'Exportar mixagem',
      actions: [
        AppButton(label: 'Cancelar', onPressed: () => Navigator.pop(context)),
        AppButton(
          label: 'Escolher destino',
          primary: true,
          onPressed: () => Navigator.pop(context, options),
        ),
      ],
      child: FormatPicker(
        options: options,
        onChanged: (o) => setState(() => options = o),
      ),
    );
  }
}

Future<void> startExport(BuildContext context) async {
  final project = context.read<ProjectController>();
  if (project.projectEndMs == 0 || project.exporting) return;
  final messenger = ScaffoldMessenger.of(context);
  final options = await showDialog<ExportOptions>(
    context: context,
    builder: (_) => const ExportDialog(),
  );
  if (options == null) return;
  final ext = options.format.ext;
  final target = await FilePicker.platform.saveFile(
    dialogTitle: 'Exportar mixagem',
    fileName: 'mixagem.$ext',
    type: FileType.custom,
    allowedExtensions: [ext],
  );
  if (target == null) return;
  final outPath = target.toLowerCase().endsWith('.$ext') ? target : '$target.$ext';
  final result = await project.exportProject(options, outPath);
  if (result == null) {
    messenger.showSnackBar(
      SnackBar(content: Text('Não foi possível exportar. ${project.lastError}')),
    );
    return;
  }
  messenger.showSnackBar(
    SnackBar(
      content: Text('Exportado: ${p.basename(result)}'),
      action: SnackBarAction(
        label: 'Mostrar na pasta',
        textColor: AppColors.accent,
        onPressed: () => SystemService.revealInFolder(result),
      ),
    ),
  );
}
