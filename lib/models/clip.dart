class AudioClip {
  final String id;
  final String label;
  final String path;
  final String coverPath;
  final int sourceMs;
  final int inMs;
  final int outMs;
  final int startMs;
  final double volume;
  final double speed;
  final double pitch;
  final double bass;
  final double treble;
  final int fadeInMs;
  final int fadeOutMs;
  final int fadeShape;
  final bool reversed;
  final bool normalize;
  final bool muted;

  const AudioClip({
    required this.id,
    required this.label,
    required this.path,
    this.coverPath = '',
    required this.sourceMs,
    required this.inMs,
    required this.outMs,
    required this.startMs,
    this.volume = 1,
    this.speed = 1,
    this.pitch = 0,
    this.bass = 0,
    this.treble = 0,
    this.fadeInMs = 0,
    this.fadeOutMs = 0,
    this.fadeShape = 0,
    this.reversed = false,
    this.normalize = false,
    this.muted = false,
  });

  int get lengthMs => outMs - inMs;
  int get durationMs => (lengthMs / speed).round();
  int get endMs => startMs + durationMs;

  AudioClip copyWith({
    String? id,
    int? inMs,
    int? outMs,
    int? startMs,
    double? volume,
    double? speed,
    double? pitch,
    double? bass,
    double? treble,
    int? fadeInMs,
    int? fadeOutMs,
    int? fadeShape,
    bool? reversed,
    bool? normalize,
    bool? muted,
  }) {
    return AudioClip(
      id: id ?? this.id,
      label: label,
      path: path,
      coverPath: coverPath,
      sourceMs: sourceMs,
      inMs: inMs ?? this.inMs,
      outMs: outMs ?? this.outMs,
      startMs: startMs ?? this.startMs,
      volume: volume ?? this.volume,
      speed: speed ?? this.speed,
      pitch: pitch ?? this.pitch,
      bass: bass ?? this.bass,
      treble: treble ?? this.treble,
      fadeInMs: fadeInMs ?? this.fadeInMs,
      fadeOutMs: fadeOutMs ?? this.fadeOutMs,
      fadeShape: fadeShape ?? this.fadeShape,
      reversed: reversed ?? this.reversed,
      normalize: normalize ?? this.normalize,
      muted: muted ?? this.muted,
    );
  }

  AudioClip resetEffects() => AudioClip(
        id: id,
        label: label,
        path: path,
        coverPath: coverPath,
        sourceMs: sourceMs,
        inMs: inMs,
        outMs: outMs,
        startMs: startMs,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'path': path,
        'coverPath': coverPath,
        'sourceMs': sourceMs,
        'inMs': inMs,
        'outMs': outMs,
        'startMs': startMs,
        'volume': volume,
        'speed': speed,
        'pitch': pitch,
        'bass': bass,
        'treble': treble,
        'fadeInMs': fadeInMs,
        'fadeOutMs': fadeOutMs,
        'fadeShape': fadeShape,
        'reversed': reversed,
        'normalize': normalize,
        'muted': muted,
      };

  factory AudioClip.fromJson(Map<String, dynamic> json) => AudioClip(
        id: json['id'] as String,
        label: json['label'] as String,
        path: json['path'] as String,
        coverPath: (json['coverPath'] as String?) ?? '',
        sourceMs: json['sourceMs'] as int,
        inMs: json['inMs'] as int,
        outMs: json['outMs'] as int,
        startMs: json['startMs'] as int,
        volume: (json['volume'] as num).toDouble(),
        speed: (json['speed'] as num).toDouble(),
        pitch: (json['pitch'] as num).toDouble(),
        bass: (json['bass'] as num).toDouble(),
        treble: (json['treble'] as num).toDouble(),
        fadeInMs: json['fadeInMs'] as int,
        fadeOutMs: json['fadeOutMs'] as int,
        fadeShape: (json['fadeShape'] as int?) ?? 0,
        reversed: json['reversed'] as bool,
        normalize: json['normalize'] as bool,
        muted: json['muted'] as bool,
      );
}
