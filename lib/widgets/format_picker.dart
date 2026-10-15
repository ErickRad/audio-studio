import 'package:flutter/material.dart';
import '../models/audio_formats.dart';
import '../theme/app_theme.dart';
import 'ui_kit.dart';

class FormatPicker extends StatelessWidget {
  final ExportOptions options;
  final ValueChanged<ExportOptions> onChanged;

  const FormatPicker({super.key, required this.options, required this.onChanged});

  Widget group<T>(String label, List<(T, String)> items, T current, ValueChanged<T> onSelect) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textDim)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final item in items)
                ToggleChip(
                  label: item.$2,
                  selected: item.$1 == current,
                  onChanged: (_) => onSelect(item.$1),
                ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        group<String>(
          'Formato',
          [for (final f in audioFormats) (f.id, f.label)],
          options.formatId,
          (v) => onChanged(options.copyWith(formatId: v)),
        ),
        if (options.format.lossy)
          group<int>(
            'Bitrate',
            [for (final b in const [96, 128, 192, 256, 320]) (b, '$b kbps')],
            options.bitrateK,
            (v) => onChanged(options.copyWith(bitrateK: v)),
          ),
        group<int>(
          'Taxa de amostragem',
          const [(0, 'Original'), (22050, '22 kHz'), (44100, '44,1 kHz'), (48000, '48 kHz')],
          options.sampleRate,
          (v) => onChanged(options.copyWith(sampleRate: v)),
        ),
        group<int>(
          'Canais',
          const [(0, 'Original'), (1, 'Mono'), (2, 'Estéreo')],
          options.channels,
          (v) => onChanged(options.copyWith(channels: v)),
        ),
      ],
    );
  }
}
