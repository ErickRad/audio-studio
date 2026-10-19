import 'dart:async';
import 'package:audio_studio/widgets/smart_join_dialog.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/clip.dart';
import '../services/audio_analyzer.dart';
import '../state/project_controller.dart';
import '../theme/app_theme.dart';
import '../utils.dart';
import 'ui_kit.dart';

class InspectorPanel extends StatelessWidget {
  const InspectorPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ProjectController>();
    final clip = c.selectedClip;
    return Material(
      color: AppColors.panel,
      child: Container(
        height: 176,
        width: double.infinity,
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.line)),
        ),
        child: clip == null ? buildEmpty() : buildBody(context, c, clip),
      ),
    );
  }

  Widget buildEmpty() {
    return const Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Nenhum trecho selecionado',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          SizedBox(height: 6),
          Text(
            'Clique em um trecho da timeline para ajustar volume, fades, velocidade, tom e equalização. Arraste o trecho para movê-lo e as bordas para aparar.',
            style: TextStyle(
                fontSize: 12.5, color: AppColors.textDim, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget info(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        children: [
          SizedBox(
            width: 58,
            child: Text(label,
                style: const TextStyle(fontSize: 12, color: AppColors.textDim)),
          ),
          Expanded(
              child: Text(value, style: monoStyle.copyWith(fontSize: 11.5))),
        ],
      ),
    );
  }

  Widget buildBody(BuildContext context, ProjectController c, AudioClip clip) {
    final fadeMax =
        (clip.durationMs.toDouble() / 2).clamp(500.0, 10000.0).toDouble();
    Widget slider({
      required String label,
      required double value,
      required double min,
      required double max,
      required double defaultValue,
      required String display,
      required AudioClip Function(AudioClip, double) apply,
      int? divisions,
    }) {
      return SizedBox(
        width: 290,
        child: LabeledSlider(
          label: label,
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          display: display,
          defaultValue: defaultValue,
          onStart: c.beginEdit,
          onChanged: (v) => c.updateClip(clip.id, (x) => apply(x, v)),
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 220,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ThumbBox(filePath: clip.coverPath, size: 44),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        clip.label,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                info('Duração', shortTime(clip.durationMs)),
                info('Início', formatMs(clip.startMs)),
                info('Origem',
                    '${shortTime(clip.inMs)}–${shortTime(clip.outMs)}'),
                BpmBadge(path: clip.path, speed: clip.speed),
              ],
            ),
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(spacing: 12, runSpacing: 6, children: [
                  AppButton(
                    label: 'Aparar silêncio',
                    icon: Icons.content_cut,
                    onPressed: () async {
                      final ok = await c.trimClipSilence(clip.id);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(ok
                            ? 'Silêncio aparado.'
                            : 'Nada para aparar neste trecho.'),
                      ));
                    },
                  ),
                  AppButton(
                    label: 'Unir com o próximo',
                    icon: Icons.auto_awesome,
                    busy: c.smartBusy,
                    onPressed: () => runSmartJoin(
                      context,
                      title: 'Unir com o próximo trecho',
                      description:
                          'O trecho seguinte da mesma faixa será alinhado nas batidas e misturado com este, sem cortes bruscos.',
                      action: (o) => c.smartJoinPair(clip.id, o),
                    ),
                  ),
                  AppButton(
                    label: 'Restaurar efeitos',
                    onPressed: () {
                      c.beginEdit();
                      c.updateClip(clip.id, (x) => x.resetEffects());
                    },
                  ),
                ]),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 30,
                  children: [
                    slider(
                      label: 'Volume',
                      value: clip.volume,
                      min: 0,
                      max: 2,
                      divisions: 40,
                      defaultValue: 1,
                      display: '${(clip.volume * 100).round()}%',
                      apply: (x, v) => x.copyWith(volume: v),
                    ),
                    slider(
                      label: 'Fade in',
                      value: clip.fadeInMs.toDouble(),
                      min: 0,
                      max: fadeMax,
                      defaultValue: 0,
                      display: '${(clip.fadeInMs / 1000).toStringAsFixed(1)} s',
                      apply: (x, v) => x.copyWith(fadeInMs: v.round()),
                    ),
                    slider(
                      label: 'Fade out',
                      value: clip.fadeOutMs.toDouble(),
                      min: 0,
                      max: fadeMax,
                      defaultValue: 0,
                      display:
                          '${(clip.fadeOutMs / 1000).toStringAsFixed(1)} s',
                      apply: (x, v) => x.copyWith(fadeOutMs: v.round()),
                    ),
                    slider(
                      label: 'Velocidade',
                      value: clip.speed,
                      min: 0.25,
                      max: 3,
                      divisions: 55,
                      defaultValue: 1,
                      display: '${clip.speed.toStringAsFixed(2)}x',
                      apply: (x, v) =>
                          x.copyWith(speed: double.parse(v.toStringAsFixed(2))),
                    ),
                    slider(
                      label: 'Tom',
                      value: clip.pitch,
                      min: -12,
                      max: 12,
                      divisions: 24,
                      defaultValue: 0,
                      display: '${clip.pitch.toStringAsFixed(0)} st',
                      apply: (x, v) => x.copyWith(pitch: v),
                    ),
                    slider(
                      label: 'Graves',
                      value: clip.bass,
                      min: -15,
                      max: 15,
                      divisions: 30,
                      defaultValue: 0,
                      display: '${clip.bass.toStringAsFixed(0)} dB',
                      apply: (x, v) => x.copyWith(bass: v),
                    ),
                    slider(
                      label: 'Agudos',
                      value: clip.treble,
                      min: -15,
                      max: 15,
                      divisions: 30,
                      defaultValue: 0,
                      display: '${clip.treble.toStringAsFixed(0)} dB',
                      apply: (x, v) => x.copyWith(treble: v),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(spacing: 12, runSpacing: 6, children: [
                  ToggleChip(
                    label: 'Reverter',
                    selected: clip.reversed,
                    onChanged: (v) {
                      c.beginEdit();
                      c.updateClip(clip.id, (x) => x.copyWith(reversed: v));
                    },
                  ),
                  ToggleChip(
                    label: 'Normalizar',
                    selected: clip.normalize,
                    onChanged: (v) {
                      c.beginEdit();
                      c.updateClip(clip.id, (x) => x.copyWith(normalize: v));
                    },
                  ),
                  ToggleChip(
                    label: 'Silenciar',
                    selected: clip.muted,
                    onChanged: (v) {
                      c.beginEdit();
                      c.updateClip(clip.id, (x) => x.copyWith(muted: v));
                    },
                  ),
                  ToggleChip(
                    label: 'Fade suave',
                    selected: clip.fadeShape == 1,
                    onChanged: (v) {
                      c.beginEdit();
                      c.updateClip(
                          clip.id, (x) => x.copyWith(fadeShape: v ? 1 : 0));
                    },
                  ),
                ]),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class BpmBadge extends StatefulWidget {
  final String path;
  final double speed;

  const BpmBadge({super.key, required this.path, required this.speed});

  @override
  State<BpmBadge> createState() => _BpmBadgeState();
}

class _BpmBadgeState extends State<BpmBadge> {
  Timer? timer;
  AudioAnalysis? analysis;
  bool done = false;
  String loadedPath = '';

  @override
  void initState() {
    super.initState();
    schedule();
  }

  @override
  void didUpdateWidget(BpmBadge old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) schedule();
  }

  void schedule() {
    timer?.cancel();
    final path = widget.path;
    setStateSafe(() {
      analysis = null;
      done = false;
    });
    timer = Timer(const Duration(milliseconds: 900), () async {
      AudioAnalysis? result;
      try {
        result = await AudioAnalyzer.analyze(path);
      } catch (_) {
        result = null;
      }
      if (!mounted || widget.path != path) return;
      setState(() {
        analysis = result;
        done = true;
      });
    });
  }

  void setStateSafe(VoidCallback fn) {
    if (!mounted || !context.mounted) {
      fn();
      return;
    }
    fn();
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = analysis;
    final bpm = !done
        ? 'Analisando…'
        : (a != null && a.reliable
            ? '${(a.bpm * widget.speed).toStringAsFixed(0)}'
            : 'indefinido');

    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        children: [
          SizedBox(
            width: 58,
            child: Text('BPM',
                style: const TextStyle(fontSize: 12, color: AppColors.textDim)),
          ),
          Expanded(child: Text(bpm, style: monoStyle.copyWith(fontSize: 11.5))),
        ],
      ),
    );
  }
}
