class LibraryFolder {
  final String id;
  final String name;

  const LibraryFolder({required this.id, required this.name});

  LibraryFolder copyWith({String? name}) =>
      LibraryFolder(id: id, name: name ?? this.name);

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  factory LibraryFolder.fromJson(Map<String, dynamic> json) => LibraryFolder(
        id: json['id'] as String,
        name: json['name'] as String,
      );
}
