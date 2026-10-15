enum SearchSource { youtube, jamendo }

class SearchResult {
  final SearchSource source;
  final String id;
  final String title;
  final String artist;
  final String imageUrl;
  final String streamUrl;
  final String downloadUrl;
  final String license;
  final int durationMs;

  const SearchResult({
    required this.source,
    required this.id,
    required this.title,
    required this.artist,
    required this.imageUrl,
    required this.durationMs,
    this.streamUrl = '',
    this.downloadUrl = '',
    this.license = '',
  });

  String get key => '${source.name}:$id';
}
