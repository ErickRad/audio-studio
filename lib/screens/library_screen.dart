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
import '../widgets/smart_join_dialog.dart';
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
  static const String favId = '*f';

  String selection = allId;
  final Set<String> selected = {};
  String? anchorId;
  final TextEditingController searchController = TextEditingController();
  String query = '';
  int sortMode = 0;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(handleKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(handleKey);
    searchController.dispose();
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
    Iterable<LibraryItem> base = c.library;
    if (selection == noneId) {
      base = base.where((i) => i.folderId.isEmpty);
    } else if (selection == favId) {
      base = base.where((i) => i.favorite);
    } else if (selection != allId) {
      base = base.where((i) => i.folderId == selection);
    }
    final q = query.trim().toLowerCase();
    if (q.isNotEmpty) {
      base = base.where((i) =>
          i.title.toLowerCase().contains(q) ||
          i.artist.toLowerCase().contains(q));
    }
    final list = base.toList();
    switch (sortMode) {
      case 1:
        list.sort(
            (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      case 2:
        list.sort(
            (a, b) => a.artist.toLowerCase().compareTo(b.artist.toLowerCase()));
      case 3:
        list.sort((a, b) => b.durationMs.compareTo(a.durationMs));
      case 4:
        list.sort((a, b) => a.durationMs.compareTo(b.durationMs));
    }
    return list;
  }

  Future<void> editInfo(LibraryItem item) async {
    final project = context.read<ProjectController>();
    final titleController = TextEditingController(text: item.title);
    final artistController = TextEditingController(text: item.artist);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AppDialog(
        title: 'Editar informações',
        actions: [
          AppButton(
            label: 'Cancelar',
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          AppButton(
            label: 'Salvar',
            primary: true,
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppTextField(
              controller: titleController,
              hint: 'Título',
              autofocus: true,
              onSubmitted: (_) => Navigator.of(dialogContext).pop(true),
            ),
            const SizedBox(height: 10),
            AppTextField(
              controller: artistController,
              hint: 'Artista',
              onSubmitted: (_) => Navigator.of(dialogContext).pop(true),
            ),
          ],
        ),
      ),
    );
    final title = titleController.text;
    final artist = artistController.text;
    titleController.dispose();
    artistController.dispose();
    if (ok == true) await project.updateItemInfo(item.id, title, artist);
  }

  Future<void> playAll(List<LibraryItem> items, {required bool shuffle}) {
    return PreviewService.instance.playQueue(
      [for (final i in items) (id: i.id, path: i.path)],
      shuffle: shuffle,
    );
  }

  String selectionTitle(ProjectController c) {
    if (selection == allId) return 'Todas as músicas';
    if (selection == noneId) return 'Sem pasta';
    if (selection == favId) return 'Favoritas';
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
                      'Pastas',
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
                    id: favId,
                    label: 'Favoritas',
                    icon: Icons.star_border,
                    count: c.library.where((i) => i.favorite).length,
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
          icon: item.favorite ? Icons.star : Icons.star_border,
          tooltip: item.favorite ? 'Remover dos favoritos' : 'Favoritar',
          color: item.favorite ? AppColors.accent : null,
          onPressed: () => c.toggleFavorite(item.id),
        ),
        ToolButton(
          icon: Icons.edit_outlined,
          tooltip: 'Editar título e artista',
          onPressed: () => editInfo(item),
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
        selection != favId &&
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: const BoxDecoration(
                    color: AppColors.panel,
                    border: Border(bottom: BorderSide(color: AppColors.line)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: 38,
                        child: Row(
                          children: [
                            Text(
                              selectionTitle(c),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 12),
                            AppButton(
                              label: 'Importar arquivos',
                              icon: Icons.add,
                              onPressed: importFiles,
                            ),
                            const SizedBox(width: 12),
                            AppButton(
                              label: 'Mix suave',
                              icon: Icons.auto_awesome,
                              busy: c.smartBusy,
                              onPressed: selected.length < 2
                                  ? null
                                  : () {
                                      final picked = c.library
                                          .where((i) => selected.contains(i.id))
                                          .toList();
                                      runSmartJoin(
                                        context,
                                        title: 'Mix suave',
                                        description:
                                            'As músicas selecionadas serão analisadas e encadeadas no editor, com transições nas batidas e sem trocas bruscas de volume.',
                                        allowSort: true,
                                        action: (o) => c.smartMix(picked, o),
                                      );
                                    },
                            ),
                            Spacer(),
                            SizedBox(
                              width: 200,
                              child: AppTextField(
                                controller: searchController,
                                hint: 'Buscar na biblioteca',
                                prefixIcon: Icons.search,
                                onChanged: (v) => setState(() => query = v),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 140,
                              child: AppDropdown<int>(
                                value: sortMode,
                                items: const [
                                  (0, 'Mais recentes'),
                                  (1, 'Título A–Z'),
                                  (2, 'Artista A–Z'),
                                  (3, 'Mais longas'),
                                  (4, 'Mais curtas'),
                                ],
                                onChanged: (v) => setState(() => sortMode = v),
                              ),
                            ),
                            const SizedBox(width: 6),
                            ValueListenableBuilder<bool>(
                              valueListenable:
                                  PreviewService.instance.queueActive,
                              builder: (_, active, __) => Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ToolButton(
                                    icon: Icons.play_circle_outline,
                                    tooltip: 'Tocar tudo',
                                    onPressed: items.isEmpty
                                        ? null
                                        : () => playAll(items, shuffle: false),
                                  ),
                                  ToolButton(
                                    icon: Icons.shuffle,
                                    tooltip: 'Tocar em ordem aleatória',
                                    onPressed: items.isEmpty
                                        ? null
                                        : () => playAll(items, shuffle: true),
                                  ),
                                  if (active) ...[
                                    ToolButton(
                                      icon: Icons.skip_previous,
                                      tooltip: 'Faixa anterior',
                                      onPressed:
                                          PreviewService.instance.previous,
                                    ),
                                    ToolButton(
                                      icon: Icons.skip_next,
                                      tooltip: 'Próxima faixa',
                                      onPressed: PreviewService.instance.next,
                                    ),
                                    ToolButton(
                                      icon: Icons.stop,
                                      tooltip: 'Parar',
                                      onPressed: PreviewService.instance.stop,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (selected.isEmpty) ...[
                              const SizedBox(width: 8),
                              Text(
                                '${items.length} ${items.length == 1 ? 'item' : 'itens'}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textDim,
                                ),
                              ),
                            ],
                          ],
                        ),
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
