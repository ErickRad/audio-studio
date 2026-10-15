import 'dart:io';

class AppLog {
  static void info(String tag, String message) => write('INFO', tag, message);

  static void error(String tag, Object error, [StackTrace? stack]) {
    write('ERRO', tag, '$error');
    if (stack != null) stderr.writeln(stack);
  }

  static void write(String level, String tag, String message) {
    final now = DateTime.now();
    final time = '${two(now.hour)}:${two(now.minute)}:${two(now.second)}';
    stderr.writeln('[$time] [$level] [$tag] $message');
  }

  static String two(int value) => value.toString().padLeft(2, '0');
}
