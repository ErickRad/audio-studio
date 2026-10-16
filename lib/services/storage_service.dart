import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class StorageService {
  static Future<Directory> ensure(String name) async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, name));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<Directory> musicDir() => ensure('music');

  static Future<Directory> exportDir() => ensure('exports');

  static Future<Directory> coversDir() => ensure('covers');

  static Future<File> foldersFile() async {
    final base = await getApplicationDocumentsDirectory();
    return File(p.join(base.path, 'folders.json'));
  }

  static Future<File> libraryFile() async {
    final base = await getApplicationDocumentsDirectory();
    return File(p.join(base.path, 'library.json'));
  }

  static Future<File> projectFile() async {
    final base = await getApplicationDocumentsDirectory();
    return File(p.join(base.path, 'project.json'));
  }

  static String safeName(String value) => value
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
