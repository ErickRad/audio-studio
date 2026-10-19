class LibraryItem {
  final String id;
  final String title;
  final String artist;
  final String path;
  final int durationMs;
  final String coverPath;
  final String folderId;
  final bool favorite;

  const LibraryItem({
    required this.id,
    required this.title,
    required this.artist,
    required this.path,
    required this.durationMs,
    this.coverPath = '',
    this.folderId = '',
    this.favorite = false,
  });

  LibraryItem copyWith({
    String? title,
    String? artist,
    String? coverPath,
    String? folderId,
    bool? favorite,
  }) {
    return LibraryItem(
      id: id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      path: path,
      durationMs: durationMs,
      coverPath: coverPath ?? this.coverPath,
      folderId: folderId ?? this.folderId,
      favorite: favorite ?? this.favorite,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'path': path,
        'durationMs': durationMs,
        'coverPath': coverPath,
        'folderId': folderId,
        'favorite': favorite,
      };

  factory LibraryItem.fromJson(Map<String, dynamic> json) => LibraryItem(
        id: json['id'] as String,
        title: json['title'] as String,
        artist: json['artist'] as String,
        path: json['path'] as String,
        durationMs: json['durationMs'] as int,
        coverPath: (json['coverPath'] as String?) ?? '',
        folderId: (json['folderId'] as String?) ?? '',
        favorite: (json['favorite'] as bool?) ?? false,
      );
}
