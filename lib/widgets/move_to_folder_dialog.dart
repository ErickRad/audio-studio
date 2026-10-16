import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/library_folder.dart';
import '../models/library_item.dart';
import '../state/project_controller.dart';
import '../theme/app_theme.dart';
import 'ui_kit.dart';

Future<String?> showMoveToFolderDialog(
  BuildContext context, {
  required List<LibraryFolder> folders,
  required List<LibraryItem> items,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => MoveToFolderDialog(folders: folders, items: items),
  );
}

class MoveToFolderDialog extends StatelessWidget {
  final List<LibraryFolder> folders;
  final List<LibraryItem> items;

  const MoveToFolderDialog({
    super.key,
    required this.folders,
    required this.items,
  });

  Future<void> createAndMove(BuildContext context) async {
    final project = context.read<ProjectController>();
    final name = await promptText(
      context,
      title: 'Nova pasta',
      initial: '',
      confirmLabel: 'Criar',
    );
    if (name == null || name.trim().isEmpty) return;
    final id = await project.createFolder(name, activate: false);
    if (id == null || !context.mounted) return;
    Navigator.pop(context, id);
  }

  Widget option({
    required BuildContext context,
    required String label,
    required IconData icon,
    required VoidCallback? onTap,
    bool highlighted = false,
    String? note,
  }) {
    final enabled = onTap != null;
    return InkWell(
      hoverColor: AppColors.hover,
      onTap: onTap,
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: highlighted
                  ? AppColors.accent
                  : (enabled ? AppColors.text : AppColors.textDim),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: enabled || highlighted
                      ? (highlighted ? AppColors.accent : AppColors.text)
                      : AppColors.textDim,
                  fontWeight: highlighted ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            if (note != null)
              Text(note,
                  style: const TextStyle(
                      fontSize: 11.5, color: AppColors.textDim)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = items.map((i) => i.folderId).toSet();
    final single = current.length == 1 ? current.first : null;
    final subtitle = items.length == 1
        ? items.first.title
        : '${items.length} músicas selecionadas';
    return AppDialog(
      title: 'Mover para pasta',
      width: 380,
      actions: [
        AppButton(label: 'Cancelar', onPressed: () => Navigator.pop(context)),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5, color: AppColors.textDim),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.line),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Material(
              color: Colors.transparent,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  option(
                    context: context,
                    label: 'Nova pasta…',
                    icon: Icons.create_new_folder_outlined,
                    highlighted: true,
                    onTap: () => createAndMove(context),
                  ),
                  const Divider(height: 1, color: AppColors.line),
                  option(
                    context: context,
                    label: 'Sem pasta',
                    icon: Icons.inbox_outlined,
                    note: single == '' ? 'Atual' : null,
                    onTap:
                        single == '' ? null : () => Navigator.pop(context, ''),
                  ),
                  for (final folder in folders)
                    option(
                      context: context,
                      label: folder.name,
                      icon: Icons.folder_outlined,
                      note: single == folder.id ? 'Atual' : null,
                      onTap: single == folder.id
                          ? null
                          : () => Navigator.pop(context, folder.id),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
