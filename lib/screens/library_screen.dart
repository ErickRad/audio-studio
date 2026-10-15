import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import '../models/library_item.dart';
import '../services/preview_service.dart';
import '../services/system_service.dart';
import '../state/project_controller.dart';
import '../theme/app_theme.dart';
import '../utils.dart';
import '../widgets/ui_kit.dart';

class LibraryScreen extends StatelessWidget {
  final VoidCallback onOpenEditor;

  const LibraryScreen({super.key, required this.onOpenEditor});

  Future<void> importFiles(BuildContext context) async {
    final project = context.read<ProjectController>();
    final messenger = ScaffoldMessenger.of(context);
    final n = await project.importFiles();
    if (n > 0) {
      messenger.showSnackBar(SnackBar(content: Text('$n arquivo(s) importado(s)')));
    }
  }

  Future<void> remove(BuildContext context, LibraryItem item) async {
    final project = context.read<ProjectController>();
    final ok = await confirmDialog(
      context,
      title: 'Remover da biblioteca',
      message: '"${item.title}" será apagado do disco e removido da timeline.',
      confirmLabel: 'Remover',
    );
    if (ok) await project.removeFromLibrary(item);
  }

  Widget buildRow(BuildContext context, LibraryItem item) {
    final project = context.read<ProjectController>();
    final format = p.extension(item.path).replaceFirst('.', '').toUpperCase();
    void addToTimeline() {
      project.addClip(item);
      onOpenEditor();
    }

    return MediaRow(
      leading: const ThumbBox(imageUrl: ''),
      title: item.title,
      subtitle: '${item.artist} · ${shortTime(item.durationMs)} · $format',
      onDoubleTap: addToTimeline,
      actions: [
        ValueListenableBuilder<String?>(
          valueListenable: PreviewService.instance.currentId,
          builder: (_, current, __) => ToolButton(
            icon: current == item.id ? Icons.stop : Icons.play_arrow,
            tooltip: current == item.id ? 'Parar' : 'Ouvir',
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final error = await PreviewService.instance.toggle(item.id, filePath: item.path);
              if (error != null) {
                messenger.showSnackBar(SnackBar(content: Text('Não foi possível tocar: $error')));
              }
            },
          ),
        ),
        ToolButton(
          icon: Icons.playlist_add,
          tooltip: 'Adicionar à timeline (duplo clique)',
          onPressed: addToTimeline,
        ),
        ToolButton(
          icon: Icons.folder_open,
          tooltip: 'Mostrar na pasta',
          onPressed: () => SystemService.revealInFolder(item.path),
        ),
        ToolButton(
          icon: Icons.delete_outline,
          tooltip: 'Remover',
          onPressed: () => remove(context, item),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<ProjectController>().library;
    return Column(
      children: [
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: const BoxDecoration(
            color: AppColors.panel,
            border: Border(bottom: BorderSide(color: AppColors.line)),
          ),
          child: Row(
            children: [
              AppButton(
                label: 'Importar arquivos',
                icon: Icons.add,
                onPressed: () => importFiles(context),
              ),
              const Spacer(),
              Text(
                '${library.length} ${library.length == 1 ? 'item' : 'itens'}',
                style: const TextStyle(fontSize: 12, color: AppColors.textDim),
              ),
            ],
          ),
        ),
        Expanded(
          child: library.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'A biblioteca está vazia. Baixe músicas pela aba Buscar ou importe arquivos do computador.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: AppColors.textDim),
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: library.length,
                  itemExtent: 54,
                  itemBuilder: (context, i) => buildRow(context, library[i]),
                ),
        ),
      ],
    );
  }
}
