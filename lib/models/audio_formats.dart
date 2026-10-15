class AudioFormat {
  final String id;
  final String label;
  final String ext;
  final bool lossy;

  const AudioFormat(this.id, this.label, this.ext, this.lossy);
}

const List<AudioFormat> audioFormats = [
  AudioFormat('mp3', 'MP3', 'mp3', true),
  AudioFormat('aac', 'AAC (M4A)', 'm4a', true),
  AudioFormat('ogg', 'OGG Vorbis', 'ogg', true),
  AudioFormat('opus', 'Opus', 'opus', true),
  AudioFormat('flac', 'FLAC', 'flac', false),
  AudioFormat('wav', 'WAV', 'wav', false),
];

class ExportOptions {
  final String formatId;
  final int bitrateK;
  final int sampleRate;
  final int channels;

  const ExportOptions({
    this.formatId = 'mp3',
    this.bitrateK = 192,
    this.sampleRate = 0,
    this.channels = 0,
  });

  AudioFormat get format => audioFormats.firstWhere((f) => f.id == formatId);

  ExportOptions copyWith(
      {String? formatId, int? bitrateK, int? sampleRate, int? channels}) {
    return ExportOptions(
      formatId: formatId ?? this.formatId,
      bitrateK: bitrateK ?? this.bitrateK,
      sampleRate: sampleRate ?? this.sampleRate,
      channels: channels ?? this.channels,
    );
  }
}
