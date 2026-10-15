import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/project_controller.dart';
import '../theme/app_theme.dart';
import '../utils.dart';
import 'ui_kit.dart';

class TransportBar extends StatelessWidget {
  final VoidCallback onExport;

  const TransportBar({super.key, required this.onExport});

  static double zoomToSlider(double px) =>
      (log(px / 8) / log(50)).clamp(0.0, 1.0).toDouble();

  static double sliderToZoom(double v) => 8 * pow(50, v).toDouble();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ProjectController>();
    final has = c.projectEndMs > 0;
    final busy = c.rendering || c.exporting;
    final hasSelection = c.selectedClip != null;
    final canPlay = has && !busy;
    return Material(
      color: AppColors.panel,
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.line)),
        ),
        child: Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ToolButton(
                      icon: Icons.undo,
                      tooltip: 'Desfazer (Ctrl+Z)',
                      onPressed: c.canUndo ? c.undo : null,
                    ),
                    ToolButton(
                      icon: Icons.redo,
                      tooltip: 'Refazer (Ctrl+Shift+Z)',
                      onPressed: c.canRedo ? c.redo : null,
                    ),
                    const VDivider(),
                    ToolButton(
                      icon: Icons.skip_previous,
                      tooltip: 'Ir ao início (Home)',
                      onPressed: has ? () => c.seek(0) : null,
                    ),
                    Tooltip(
                      message: c.playing ? 'Pausar (Espaço)' : 'Reproduzir (Espaço)',
                      child: Material(
                        color: canPlay ? AppColors.accent : AppColors.raised,
                        borderRadius: BorderRadius.circular(4),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(4),
                          onTap: canPlay ? c.togglePlay : null,
                          child: SizedBox(
                            width: 40,
                            height: 30,
                            child: Icon(
                              c.playing ? Icons.pause : Icons.play_arrow,
                              size: 20,
                              color: canPlay ? Colors.white : AppColors.textDim,
                            ),
                          ),
                        ),
                      ),
                    ),
                    ToolButton(
                      icon: Icons.stop,
                      tooltip: 'Parar',
                      onPressed: has ? c.stop : null,
                    ),
                    const SizedBox(width: 8),
                    ValueListenableBuilder<int>(
                      valueListenable: c.playhead,
                      builder: (context, ms, _) => Container(
                        width: 196,
                        height: 30,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: AppColors.line),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(formatMs(ms), style: monoStyle.copyWith(fontSize: 15)),
                            Text(
                              '  /  ${formatMs(c.projectEndMs)}',
                              style: monoStyle.copyWith(fontSize: 12, color: AppColors.textDim),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const VDivider(),
                    ToolButton(
                      icon: Icons.content_cut,
                      tooltip: 'Dividir no cursor (S)',
                      onPressed: has ? c.splitAtPlayhead : null,
                    ),
                    ToolButton(
                      icon: Icons.delete_outline,
                      tooltip: 'Excluir trecho (Delete)',
                      onPressed: hasSelection ? () => c.deleteSelected() : null,
                    ),
                    ToolButton(
                      icon: Icons.compress,
                      tooltip: 'Excluir e fechar o espaço (Shift+Delete)',
                      onPressed: hasSelection ? () => c.deleteSelected(ripple: true) : null,
                    ),
                    ToolButton(
                      icon: Icons.copy,
                      tooltip: 'Duplicar trecho (Ctrl+D)',
                      iconSize: 16,
                      onPressed: hasSelection ? c.duplicateSelected : null,
                    ),
                    const VDivider(),
                    ToolButton(
                      icon: Icons.add,
                      tooltip: 'Adicionar faixa',
                      onPressed: c.tracks.length < ProjectController.maxTracks ? c.addTrack : null,
                    ),
                    ToolButton(
                      icon: Icons.remove,
                      tooltip: 'Remover faixa ativa',
                      onPressed: c.tracks.length > 1 ? c.removeActiveTrack : null,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            ToolButton(
              icon: Icons.zoom_out,
              tooltip: 'Menos zoom (-)',
              onPressed: () => c.zoom(0.8),
            ),
            SizedBox(
              width: 110,
              child: Slider(
                value: zoomToSlider(c.pxPerSecond),
                onChanged: (v) => c.setZoom(sliderToZoom(v)),
              ),
            ),
            ToolButton(
              icon: Icons.zoom_in,
              tooltip: 'Mais zoom (+)',
              onPressed: () => c.zoom(1.25),
            ),
            const VDivider(),
            AppButton(
              label: 'Exportar',
              icon: Icons.file_download_outlined,
              primary: true,
              onPressed: canPlay ? onExport : null,
            ),
          ],
        ),
      ),
    );
  }
}
