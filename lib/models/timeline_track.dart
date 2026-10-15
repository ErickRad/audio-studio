import 'clip.dart';

class TimelineTrack {
  final String id;
  String name;
  double volume;
  bool muted;
  List<AudioClip> clips;

  TimelineTrack({
    required this.id,
    required this.name,
    this.volume = 1,
    this.muted = false,
    List<AudioClip>? clips,
  }) : clips = clips ?? [];

  TimelineTrack copy() => TimelineTrack(
        id: id,
        name: name,
        volume: volume,
        muted: muted,
        clips: List<AudioClip>.of(clips),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'volume': volume,
        'muted': muted,
        'clips': clips.map((c) => c.toJson()).toList(),
      };

  factory TimelineTrack.fromJson(Map<String, dynamic> json) => TimelineTrack(
        id: json['id'] as String,
        name: json['name'] as String,
        volume: (json['volume'] as num).toDouble(),
        muted: json['muted'] as bool,
        clips: (json['clips'] as List)
            .cast<Map<String, dynamic>>()
            .map(AudioClip.fromJson)
            .toList(),
      );
}
