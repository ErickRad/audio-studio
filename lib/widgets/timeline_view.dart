import 'dart:math';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/clip.dart';
import '../models/timeline_track.dart';
import '../state/project_controller.dart';
import '../theme/app_theme.dart';
import 'ruler_painter.dart';
import 'ui_kit.dart';
import 'waveform_painter.dart';

enum ClipDragMode { move, trimLeft, trimRight }

class TimelineView extends StatefulWidget {
  const TimelineView({super.key});

  @override
  State<TimelineView> createState() => _TimelineViewState();
}

class _TimelineViewState extends State<TimelineView> {
  static const double headerWidth = 168;
  static const double rulerHeight = 28;
  static const double trackHeight = 70;
  static const double sidePad = 12;
  static const double edgeWidth = 8;
  static const double scrollbarGap = 10;

  final ScrollController hScroll = ScrollController();
  final ScrollController vScroll = ScrollController();
  ProjectController? attached;
  ClipDragMode dragMode = ClipDragMode.move;
  Offset dragStart = Offset.zero;
  int dragOriginMs = 0;
  int dragOriginTrack = 0;
  double trimCarry = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final c = context.read<ProjectController>();
    if (!identical(attached, c)) {
      attached?.playhead.removeListener(followPlayhead);
      attached = c;
      c.playhead.addListener(followPlayhead);
    }
  }

  @override
  void dispose() {
    attached?.playhead.removeListener(followPlayhead);
    hScroll.dispose();
    vScroll.dispose();
    super.dispose();
  }

  void followPlayhead() {
    final c = attached;
    if (c == null || !c.playing || !hScroll.hasClients) return;
    final x = sidePad + c.playhead.value * c.pxPerSecond / 1000;
    final pos = hScroll.position;
    if (x > pos.pixels + pos.viewportDimension - 48 || x < pos.pixels) {
      hScroll.jumpTo((x - 48).clamp(0.0, pos.maxScrollExtent).toDouble());
    }
  }

  void onPointerSignal(PointerSignalEvent event, ProjectController c) {
    if (event is! PointerScrollEvent || !hScroll.hasClients) return;
    final keys = HardwareKeyboard.instance;
    if (keys.isControlPressed || keys.isMetaPressed) {
      final cursorX = event.localPosition.dx;
      final anchorMs = (hScroll.offset + cursorX - sidePad) / (c.pxPerSecond / 1000);
      c.zoom(event.scrollDelta.dy < 0 ? 1.15 : 1 / 1.15);
      final target = anchorMs * (c.pxPerSecond / 1000) + sidePad - cursorX;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!hScroll.hasClients) return;
        hScroll.jumpTo(target.clamp(0.0, hScroll.position.maxScrollExtent).toDouble());
      });
      return;
    }
    final dx = event.scrollDelta.dx;
    final dy = event.scrollDelta.dy;
    final verticalOverflow = vScroll.hasClients && vScroll.position.maxScrollExtent > 0;
    if (keys.isShiftPressed || dx != 0 || !verticalOverflow) {
      final delta = dx != 0 ? dx : dy;
      hScroll.jumpTo((hScroll.offset + delta).clamp(0.0, hScroll.position.maxScrollExtent).toDouble());
    } else {
      vScroll.jumpTo((vScroll.offset + dy).clamp(0.0, vScroll.position.maxScrollExtent).toDouble());
    }
  }

  void startDrag(
    ProjectController c,
    AudioClip clip,
    int trackIndex,
    double localX,
    double width,
    double edge,
    Offset global,
  ) {
    c.select(clip.id);
    c.setActiveTrack(trackIndex);
    c.beginEdit();
    dragStart = global;
    dragOriginMs = clip.startMs;
    dragOriginTrack = trackIndex;
    trimCarry = 0;
    if (localX <= edge) {
      dragMode = ClipDragMode.trimLeft;
    } else if (localX >= width - edge) {
      dragMode = ClipDragMode.trimRight;
    } else {
      dragMode = ClipDragMode.move;
    }
  }

  void updateDrag(ProjectController c, String id, DragUpdateDetails d, double pxPerMs) {
    if (dragMode == ClipDragMode.move) {
      final total = d.globalPosition - dragStart;
      c.moveClip(
        id,
        dragOriginMs + (total.dx / pxPerMs).round(),
        dragOriginTrack + (total.dy / trackHeight).round(),
        (8 / pxPerMs).round(),
      );
      return;
    }
    trimCarry += d.delta.dx;
    final ms = (trimCarry / pxPerMs).round();
    if (ms == 0) return;
    trimCarry -= ms * pxPerMs;
    if (dragMode == ClipDragMode.trimLeft) {
      c.trimLeft(id, ms);
    } else {
      c.trimRight(id, ms);
    }
  }

  Future<void> showClipMenu(
    ProjectController c,
    AudioClip clip,
    int trackIndex,
    Offset global,
    double localMs,
  ) async {
    c.select(clip.id);
    c.setActiveTrack(trackIndex);
    c.seek(clip.startMs + localMs.round());
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(global.dx, global.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: [
        const PopupMenuItem(value: 'split', height: 30, child: Text('Dividir aqui')),
        const PopupMenuItem(value: 'duplicate', height: 30, child: Text('Duplicar')),
        PopupMenuItem(
          value: 'mute',
          height: 30,
          child: Text(clip.muted ? 'Reativar o som' : 'Silenciar'),
        ),
        const PopupMenuDivider(height: 8),
        const PopupMenuItem(value: 'delete', height: 30, child: Text('Excluir')),
        const PopupMenuItem(value: 'ripple', height: 30, child: Text('Excluir e fechar o espaço')),
      ],
    );
    switch (choice) {
      case 'split':
        c.splitAtPlayhead();
      case 'duplicate':
        c.duplicateSelected();
      case 'mute':
        c.beginEdit();
        c.updateClip(clip.id, (x) => x.copyWith(muted: !x.muted));
      case 'delete':
        c.deleteSelected();
      case 'ripple':
        c.deleteSelected(ripple: true);
    }
  }

  Future<void> renameTrack(ProjectController c, int index, TimelineTrack track) async {
    final name = await promptText(context, title: 'Nome da faixa', initial: track.name);
    if (name != null && name.isNotEmpty) c.renameTrack(index, name);
  }

  Widget buildHeader(ProjectController c, int index) {
    final track = c.tracks[index];
    final active = index == c.activeTrack;
    final color = AppColors.trackColors[index % AppColors.trackColors.length];
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => c.setActiveTrack(index),
      onDoubleTap: () => renameTrack(c, index, track),
      child: Container(
        height: trackHeight,
        padding: const EdgeInsets.fromLTRB(10, 8, 8, 6),
        decoration: BoxDecoration(
          color: active ? AppColors.raised : AppColors.panel,
          border: Border(
            left: BorderSide(color: active ? color : color.withAlpha(110), width: 3),
            bottom: const BorderSide(color: AppColors.line),
            right: const BorderSide(color: AppColors.line),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    track.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
                Tooltip(
                  message: track.muted ? 'Reativar faixa' : 'Silenciar faixa',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(3),
                    onTap: () => c.toggleTrackMute(index),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(
                        track.muted ? Icons.volume_off : Icons.volume_up,
                        size: 15,
                        color: track.muted ? AppColors.danger : AppColors.textDim,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(
              height: 20,
              child: Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: track.volume.clamp(0.0, 1.5).toDouble(),
                      min: 0,
                      max: 1.5,
                      onChangeStart: (_) => c.beginEdit(),
                      onChanged: (v) => c.setTrackVolume(index, v),
                    ),
                  ),
                  SizedBox(
                    width: 34,
                    child: Text(
                      '${(track.volume * 100).round()}%',
                      textAlign: TextAlign.end,
                      style: monoStyle.copyWith(fontSize: 10.5, color: AppColors.textDim),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildLane(ProjectController c, int index, double width, double pxPerMs) {
    return Positioned(
      top: rulerHeight + index * trackHeight,
      left: 0,
      width: width,
      height: trackHeight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) {
          c.setActiveTrack(index);
          c.clearSelection();
          c.seek(((d.localPosition.dx - sidePad) / pxPerMs).round());
        },
        child: Container(
          decoration: BoxDecoration(
            color: index.isEven ? AppColors.laneEven : AppColors.laneOdd,
            border: const Border(bottom: BorderSide(color: AppColors.line)),
          ),
        ),
      ),
    );
  }

  Widget buildClip(ProjectController c, AudioClip clip, int ti, double pxPerMs) {
    final selected = clip.id == c.selectedId;
    final width = max(6.0, clip.durationMs * pxPerMs);
    final color = AppColors.trackColors[ti % AppColors.trackColors.length];
    final peaks = c.peaks[clip.path] ?? const <double>[];
    final edge = min(edgeWidth, width / 3);
    final tags = <String>[];
    if ((clip.speed - 1).abs() > 0.001) tags.add('${clip.speed.toStringAsFixed(2)}x');
    if (clip.pitch.abs() > 0.001) {
      tags.add('${clip.pitch > 0 ? '+' : ''}${clip.pitch.toStringAsFixed(0)} st');
    }
    if (clip.reversed) tags.add('rev');
    final title = tags.isEmpty ? clip.label : '${clip.label}  ·  ${tags.join('  ')}';
    Widget edgeZone() => MouseRegion(
          cursor: SystemMouseCursors.resizeLeftRight,
          child: ColoredBox(color: selected ? Colors.white.withAlpha(55) : Colors.transparent),
        );
    return Positioned(
      key: ValueKey(clip.id),
      left: sidePad + clip.startMs * pxPerMs,
      top: rulerHeight + ti * trackHeight + 4,
      width: width,
      height: trackHeight - 8,
      child: Opacity(
        opacity: clip.muted ? 0.4 : 1,
        child: MouseRegion(
          cursor: SystemMouseCursors.grab,
          child: GestureDetector(
            dragStartBehavior: DragStartBehavior.down,
            onTapUp: (d) {
              c.select(clip.id);
              c.setActiveTrack(ti);
              c.seek(clip.startMs + (d.localPosition.dx / pxPerMs).round());
            },
            onSecondaryTapDown: (d) =>
                showClipMenu(c, clip, ti, d.globalPosition, d.localPosition.dx / pxPerMs),
            onPanStart: (d) =>
                startDrag(c, clip, ti, d.localPosition.dx, width, edge, d.globalPosition),
            onPanUpdate: (d) => updateDrag(c, clip.id, d, pxPerMs),
            child: Container(
              decoration: BoxDecoration(
                color: color.withAlpha(selected ? 95 : 66),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(
                  color: selected ? AppColors.text : color,
                  width: selected ? 1.5 : 1,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: CustomPaint(
                          painter: WaveformPainter(
                            peaks: peaks,
                            inMs: clip.inMs,
                            outMs: clip.outMs,
                            reversed: clip.reversed,
                            color: Color.lerp(color, Colors.white, 0.5)!,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 6,
                      right: 6,
                      top: 2,
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withAlpha(235),
                        ),
                      ),
                    ),
                    Positioned(left: 0, top: 0, bottom: 0, width: edge, child: edgeZone()),
                    Positioned(right: 0, top: 0, bottom: 0, width: edge, child: edgeZone()),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget buildLanes(ProjectController c, double pxPerMs, double contentHeight) {
    return Listener(
      onPointerSignal: (e) => onPointerSignal(e, c),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final contentWidth = max(
            constraints.maxWidth,
            (c.projectEndMs + 15000) * pxPerMs + sidePad * 2,
          );
          final children = <Widget>[
            for (var i = 0; i < c.tracks.length; i++) buildLane(c, i, contentWidth, pxPerMs),
            Positioned(
              top: 0,
              left: 0,
              width: contentWidth,
              height: rulerHeight,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => c.seek(((d.localPosition.dx - sidePad) / pxPerMs).round()),
                onHorizontalDragUpdate: (d) =>
                    c.seek(((d.localPosition.dx - sidePad) / pxPerMs).round()),
                child: Container(
                  decoration: const BoxDecoration(
                    color: AppColors.panel,
                    border: Border(bottom: BorderSide(color: AppColors.line)),
                  ),
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: RulerPainter(
                      pxPerSecond: c.pxPerSecond,
                      sidePad: sidePad,
                      color: AppColors.textDim,
                    ),
                  ),
                ),
              ),
            ),
            for (var ti = 0; ti < c.tracks.length; ti++)
              for (final clip in c.tracks[ti].clips) buildClip(c, clip, ti, pxPerMs),
            if (c.projectEndMs == 0)
              Positioned(
                top: rulerHeight,
                left: 0,
                right: 0,
                height: c.tracks.length * trackHeight,
                child: const IgnorePointer(
                  child: Center(
                    child: Text(
                      'Adicione músicas pela aba Biblioteca para começar a editar.',
                      style: TextStyle(fontSize: 13, color: AppColors.textDim),
                    ),
                  ),
                ),
              ),
            ValueListenableBuilder<int>(
              valueListenable: c.playhead,
              builder: (context, ms, _) => Positioned(
                left: sidePad + ms * pxPerMs - 0.5,
                top: 0,
                height: contentHeight,
                width: 1,
                child: const IgnorePointer(child: ColoredBox(color: AppColors.playhead)),
              ),
            ),
          ];
          return Scrollbar(
            controller: hScroll,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: hScroll,
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              child: SizedBox(
                width: contentWidth,
                height: contentHeight + scrollbarGap,
                child: Stack(children: children),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ProjectController>();
    final pxPerMs = c.pxPerSecond / 1000;
    final contentHeight = rulerHeight + c.tracks.length * trackHeight;
    return ColoredBox(
      color: AppColors.background,
      child: SingleChildScrollView(
        controller: vScroll,
        physics: const NeverScrollableScrollPhysics(),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: headerWidth,
              child: Column(
                children: [
                  Container(
                    height: rulerHeight,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.only(left: 13),
                    decoration: const BoxDecoration(
                      color: AppColors.panel,
                      border: Border(
                        bottom: BorderSide(color: AppColors.line),
                        right: BorderSide(color: AppColors.line),
                      ),
                    ),
                    child: const Text(
                      'Faixas',
                      style: TextStyle(fontSize: 11.5, color: AppColors.textDim),
                    ),
                  ),
                  for (var i = 0; i < c.tracks.length; i++) buildHeader(c, i),
                  const SizedBox(height: scrollbarGap),
                ],
              ),
            ),
            Expanded(
              child: SizedBox(
                height: contentHeight + scrollbarGap,
                child: buildLanes(c, pxPerMs, contentHeight),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
