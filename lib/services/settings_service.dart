import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class SettingsService {
  static Future<File> file() async {
    final base = await getApplicationDocumentsDirectory();
    return File(p.join(base.path, 'settings.json'));
  }

  static Future<Map<String, dynamic>> read() async {
    try {
      final f = await file();
      if (!await f.exists()) return {};
      return jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  static Future<void> write(String key, Object? value) async {
    final data = await read();
    data[key] = value;
    final f = await file();
    await f.writeAsString(jsonEncode(data));
  }

  static Future<bool> tutorialSeen() async {
    final data = await read();
    return data['tutorialSeen'] == true;
  }

  static Future<void> markTutorialSeen() => write('tutorialSeen', true);
}
