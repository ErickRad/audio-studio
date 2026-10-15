import 'dart:io';

import 'app_log.dart';
import 'dependency_manager.dart';

class FfmpegRunner {
  static String lastLog = '';

  static Future<bool> isAvailable() async {
    try {
      final executable = await DependencyManager.instance.resolve('ffmpeg');

      final result = await Process.run(executable, ['-version']);
      return result.exitCode == 0;
    } catch (e, stack) {
      AppLog.error('ffmpeg', e, stack);
      return false;
    }
  }

  static Future<bool> run(List<String> args) async {
    final full = [
      '-hide_banner',
      '-loglevel',
      'error',
      ...args,
    ];

    try {
      final executable = await DependencyManager.instance.resolve('ffmpeg');

      final command = '$executable ${full.join(' ')}';
      AppLog.info(
        'ffmpeg',
        command.length > 500 ? '${command.substring(0, 500)}…' : command,
      );

      final result = await Process.run(executable, full);

      if (result.exitCode == 0) {
        AppLog.info('ffmpeg', 'concluído');
        lastLog = '';
        return true;
      }

      final output = '${result.stderr}'.trim();
      lastLog =
          output.length > 400 ? output.substring(output.length - 400) : output;

      AppLog.write(
        'ERRO',
        'ffmpeg',
        'código ${result.exitCode}: $output',
      );

      return false;
    } on ProcessException catch (e) {
      lastLog = 'Não foi possível executar o FFmpeg: ${e.message}';
      AppLog.error('ffmpeg', lastLog);
      return false;
    } catch (e, stack) {
      lastLog = 'Falha ao preparar ou executar o FFmpeg: $e';
      AppLog.error('ffmpeg', e, stack);
      return false;
    }
  }

  static Future<int> probeDurationMs(String path) async {
    try {
      final executable = await DependencyManager.instance.resolve('ffprobe');

      final result = await Process.run(executable, [
        '-v',
        'error',
        '-show_entries',
        'format=duration',
        '-of',
        'default=noprint_wrappers=1:nokey=1',
        path,
      ]);

      if (result.exitCode != 0) {
        AppLog.write(
          'ERRO',
          'ffprobe',
          'código ${result.exitCode}: ${result.stderr}',
        );
        return 0;
      }

      final seconds = double.tryParse('${result.stdout}'.trim());
      return seconds == null ? 0 : (seconds * 1000).round();
    } catch (e, stack) {
      AppLog.error('ffprobe', e, stack);
      return 0;
    }
  }
}
