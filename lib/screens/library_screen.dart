import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import '../models/library_folder.dart';
import '../models/library_item.dart';
import '../services/preview_service.dart';
import '../services/system_service.dart';
import '../state/project_controller.dart';
import '../theme/app_theme.dart';
import '../utils.dart';
import '../widgets/move_to_folder_dialog.dart';
import '../widgets/tutorial_overlay.dart';
import '../widgets/ui_kit.dart';

class LibraryScreen extends StatefulWidget {
  final VoidCallback onOpenEditor;
  final bool active;

  const LibraryScreen({
    super.key,
    required this.onOpenEditor,
    this.active = true,
  });

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  static const String allId = '*';
  static const String noneId = '-';

  String selection = allId;
  final Set<String> selected = {};
  String? anchorId;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(handleKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(handleKey);
    super.dispose();
  }

  bool focusIsTextInput() {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext == null) return false;
    return focusContext.widget is EditableText ||
        focusContext.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  bool handleKey(KeyEvent event) {
    if (!mounted || !widget.active || event is KeyUpEvent) return false;
    if (ModalRoute.of(context)?.isCurrent == false) return false;
    if (focusIsTextInput()) return false;
    if (TutorialState.showing.value) return false;
    final keys = HardwareKeyboard.instance;
    final command = keys.isControlPressed || keys.isMetaPressed;
    final key = event.logicalKey;
    if (command && key == LogicalKeyboardKey.keyA) {
      selectAll();
      return true;
    }
    if (key == LogicalKeyboardKey.delete && selected.isNotEmpty) {
      if (event is KeyRepeatEvent) return true;
      removeSelected();
      return true;
    }
    if (key == LogicalKeyboardKey.escape && selected.isNotEmpty) {
      setState(selected.clear);
      return true;
    }
    return false;
  }

  void selectAll() {
    final items = filtered(context.read<ProjectController>());
    setState(() {
      selected
        ..clear()
        ..addAll(items.map((i) => i.id));
      anchorId = items.isEmpty ? null : items.first.id;
    });
  }

  void handleTap(LibraryItem item, List<LibraryItem> items) {
    final keys = HardwareKeyboard.instance;
    final command = keys.isControlPressed || keys.isMetaPressed;
    final shift = keys.isShiftPressed;
    setState(() {
      if (shift && anchorId != null) {
        final from = items.indexWhere((i) => i.id == anchorId);
        final to = items.indexWhere((i) => i.id == item.id);
        if (from >= 0 && to >= 0) {
          final low = from < to ? from : to;
          final high = from < to ? to : from;
          if (!command) selected.clear();
          for (var i = low; i <= high; i++) {
            selected.add(items[i].id);
          }
          return;
        }
      }
      if (command) {
        if (!selected.remove(item.id)) selected.add(item.id);
      } else {
        selected
          ..clear()
          ..add(item.id);
      }
      anchorId = item.id;
    });
  }

  List<LibraryItem> targetsFor(ProjectController c, LibraryItem item) {
    if (selected.contains(item.id) && selected.length > 1) {
      return c.library.where((i) => selected.contains(i.id)).toList();
    }
    return [item];
  }

  Future<void> moveItems(List<LibraryItem> targets) async {
    if (targets.isEmpty) return;
    final project = context.read<ProjectController>();
    final destination = await showMoveToFolderDialog(
      context,
      folders: project.folders,
      items: targets,
    );
    if (destination == null) return;
    await project.moveItems(targets.map((i) => i.id), destination);
  }

  Future<void> removeSelected() async {
    final project = context.read<ProjectController>();
    final targets =
        project.library.where((i) => selected.contains(i.id)).toList();
    if (targets.isEmpty) return;
    final ok = await confirmDialog(
      context,
      title: 'Remover da biblioteca',
      message: targets.length == 1
          ? '"${targets.first.title}" será apagado do disco e removido da timeline.'
          : '${targets.length} músicas serão apagadas do disco e removidas da timeline.',
      confirmLabel: 'Remover',
    );
    if (!ok) return;
    for (final item in targets) {
      await project.removeFromLibrary(item);
    }
    if (mounted) setState(selected.clear);
  }

  Future<void> importFiles() async {
    final project = context.read<ProjectController>();
    final messenger = ScaffoldMessenger.of(context);
    final n = await project.importFiles();
    if (n > 0) {
      messenger
          .showSnackBar(SnackBar(content: Text('$n arquivo(s) importado(s)')));
    }
  }

  void select(String id) {
    final project = context.read<ProjectController>();
    setState(() {
      selection = id;
      selected.clear();
    });
    project.setActiveFolder(id == allId || id == noneId ? '' : id);
  }

  Future<void> createFolder() async {
    final project = context.read<ProjectController>();
    final name = await promptText(
      context,
      title: 'Nova pasta',
      initial: '',
      confirmLabel: 'Criar',
    );
    if (name == null || name.trim().isEmpty) return;
    await project.createFolder(name);
    if (mounted) {
      setState(() {
        selection = project.activeFolderId;
        selected.clear();
      });
    }
  }

  Future<void> renameFolder(LibraryFolder folder) async {
    final project = context.read<ProjectController>();
    final name = await promptText(
      context,
      title: 'Renomear pasta',
      initial: folder.name,
    );
    if (name == null || name.trim().isEmpty) return;
    await project.renameFolder(folder.id, name);
  }

  Future<void> deleteFolder(LibraryFolder folder) async {
    final project = context.read<ProjectController>();
    final ok = await confirmDialog(
      context,
      title: 'Excluir pasta',
      message:
          'A pasta "${folder.name}" será excluída. As músicas dela continuam na biblioteca, em "Sem pasta".',
      confirmLabel: 'Excluir',
    );
    if (!ok) return;
    await project.deleteFolder(folder.id);
    if (mounted && selection == folder.id) setState(() => selection = allId);
  }

  List<LibraryItem> filtered(ProjectController c) {
    if (selection == allId) return c.library;
    if (selection == noneId) {
      return c.library.where((i) => i.folderId.isEmpty).toList();
    }
    return c.library.where((i) => i.folderId == selection).toList();
  }

  String selectionTitle(ProjectController c) {
    if (selection == allId) return 'Todas as músicas';
    if (selection == noneId) return 'Sem pasta';
    for (final f in c.folders) {
      if (f.id == selection) return f.name;
    }
    return 'Todas as músicas';
  }

  Widget buildEntry({
    required String id,
    required String label,
    required IconData icon,
    required int count,
    LibraryFolder? folder,
  }) {
    final selected = selection == id;
    return InkWell(
      hoverColor: AppColors.hover,
      onTap: () => select(id),
      child: Container(
        height: 36,
        padding: const EdgeInsets.only(left: 14, right: 4),
        color: selected ? AppColors.hover : Colors.transparent,
        child: Row(
          children: [
            Icon(icon,
                size: 17,
                color: selected ? AppColors.accent : AppColors.textDim),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            Text('$count',
                style:
                    const TextStyle(fontSize: 11.5, color: AppColors.textDim)),
            if (folder != null)
              SizedBox(
                width: 28,
                height: 28,
                child: PopupMenuButton<String>(
                  tooltip: 'Opções da pasta',
                  padding: EdgeInsets.zero,
                  iconSize: 16,
                  icon: const Icon(Icons.more_vert,
                      size: 16, color: AppColors.textDim),
                  color: AppColors.raised,
                  constraints: const BoxConstraints(minWidth: 150),
                  onSelected: (action) {
                    if (action == 'rename') renameFolder(folder);
                    if (action == 'delete') deleteFolder(folder);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem<String>(
                        value: 'rename', height: 34, child: Text('Renomear')),
                    PopupMenuItem<String>(
                        value: 'delete', height: 34, child: Text('Excluir')),
                  ],
                ),
              )
            else
              const SizedBox(width: 28),
          ],
        ),
      ),
    );
  }

  Widget buildSidebar(ProjectController c) {
    final unfiled = c.library.where((i) => i.folderId.isEmpty).length;
    return Material(
      key: TutorialKeys.librarySidebar,
      color: AppColors.panel,
      child: Container(
        width: 224,
        decoration: const BoxDecoration(
          border: Border(right: BorderSide(color: AppColors.line)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 48,
              padding: const EdgeInsets.only(left: 14, right: 6),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.line)),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'PASTAS',
                      style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 0.9,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textDim,
                      ),
                    ),
                  ),
                  ToolButton(
                    icon: Icons.create_new_folder_outlined,
                    tooltip: 'Nova pasta',
                    onPressed: createFolder,
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 6),
                children: [
                  buildEntry(
                    id: allId,
                    label: 'Todas as músicas',
                    icon: Icons.library_music_outlined,
                    count: c.library.length,
                  ),
                  buildEntry(
                    id: noneId,
                    label: 'Sem pasta',
                    icon: Icons.inbox_outlined,
                    count: unfiled,
                  ),
                  if (c.folders.isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(14, 12, 14, 4),
                      child: Divider(height: 1, color: AppColors.line),
                    ),
                  for (final folder in c.folders)
                    buildEntry(
                      id: folder.id,
                      label: folder.name,
                      icon: Icons.folder_outlined,
                      count: c.library
                          .where((i) => i.folderId == folder.id)
                          .length,
                      folder: folder,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildRow(
    ProjectController c,
    LibraryItem item,
    List<LibraryItem> items,
  ) {
    final format = p.extension(item.path).replaceFirst('.', '').toUpperCase();
    void addToTimeline() {
      c.addClip(item);
      widget.onOpenEditor();
    }

    return MediaRow(
      leading: ThumbBox(filePath: item.coverPath),
      title: item.title,
      subtitle: '${item.artist} · ${shortTime(item.durationMs)} · $format',
      selected: selected.contains(item.id),
      onTapDown: (_) => handleTap(item, items),
      onDoubleTap: addToTimeline,
      actions: [
        ValueListenableBuilder<String?>(
          valueListenable: PreviewService.instance.currentId,
          builder: (_, current, __) => ToolButton(
            icon: current == item.id ? Icons.stop : Icons.play_arrow,
            tooltip: current == item.id ? 'Parar' : 'Ouvir',
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final error = await PreviewService.instance
                  .toggle(item.id, filePath: item.path);
              if (error != null) {
                messenger.showSnackBar(
                    SnackBar(content: Text('Não foi possível tocar: $error')));
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
          icon: Icons.drive_file_move_outline,
          tooltip: 'Mover para pasta',
          onPressed: () => moveItems(targetsFor(c, item)),
        ),
        ToolButton(
          icon: Icons.folder_open,
          tooltip: 'Mostrar na pasta',
          onPressed: () => SystemService.revealInFolder(item.path),
        ),
        ToolButton(
          icon: Icons.delete_outline,
          tooltip: 'Remover',
          onPressed: () async {
            if (!selected.contains(item.id) || selected.length == 1) {
              setState(() {
                selected
                  ..clear()
                  ..add(item.id);
              });
            }
            await removeSelected();
          },
        ),
      ],
    );
  }

  Widget buildEmpty() {
    final text = selection == allId
        ? 'A biblioteca está vazia. Baixe músicas pela aba Buscar ou importe arquivos do computador.'
        : 'Esta pasta está vazia. Novos downloads e importações feitos com ela aberta ficam aqui, ou mova músicas pelo ícone de pasta em cada linha.';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: AppColors.textDim),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ProjectController>();
    if (selection != allId &&
        selection != noneId &&
        !c.folders.any((f) => f.id == selection)) {
      selection = allId;
    }
    final items = filtered(c);
    final visible = items.map((i) => i.id).toSet();
    selected.removeWhere((id) => !visible.contains(id));
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        buildSidebar(c),
        Expanded(
          child: KeyedSubtree(
            key: TutorialKeys.libraryMain,
            child: Column(
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
                        onPressed: importFiles,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          selectionTitle(c),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (selected.isNotEmpty) ...[
                        Text(
                          '${selected.length} ${selected.length == 1 ? 'selecionada' : 'selecionadas'}',
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.accent),
                        ),
                        const SizedBox(width: 8),
                        AppButton(
                          label: 'Mover',
                          icon: Icons.drive_file_move_outline,
                          onPressed: () => moveItems(
                            c.library
                                .where((i) => selected.contains(i.id))
                                .toList(),
                          ),
                        ),
                        const SizedBox(width: 6),
                        AppButton(label: 'Remover', onPressed: removeSelected),
                        ToolButton(
                          icon: Icons.close,
                          tooltip: 'Limpar seleção (Esc)',
                          onPressed: () => setState(selected.clear),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Text(
                        '${items.length} ${items.length == 1 ? 'item' : 'itens'}',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textDim),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: items.isEmpty
                      ? buildEmpty()
                      : ListView.builder(
                          itemCount: items.length,
                          itemExtent: 54,
                          itemBuilder: (context, i) =>
                              buildRow(c, items[i], items),
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
