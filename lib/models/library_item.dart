class LibraryItem {
  final String id;
  final String title;
  final String artist;
  final String path;
  final int durationMs;

  const LibraryItem({
    required this.id,
    required this.title,
    required this.artist,
    required this.path,
    required this.durationMs,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'path': path,
        'durationMs': durationMs,
      };

  factory LibraryItem.fromJson(Map<String, dynamic> json) => LibraryItem(
        id: json['id'] as String,
        title: json['title'] as String,
        artist: json['artist'] as String,
        path: json['path'] as String,
        durationMs: json['durationMs'] as int,
      );
}
