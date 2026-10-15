import 'dart:io';
import 'package:path/path.dart' as p;

class SystemService {
  static Future<void> revealInFolder(String filePath) async {
    try {
      if (Platform.isWindows) {
        await Process.run('explorer', ['/select,', filePath]);
      } else if (Platform.isMacOS) {
        await Process.run('open', ['-R', filePath]);
      } else {
        await Process.run('xdg-open', [p.dirname(filePath)]);
      }
    } catch (_) {}
  }
}
