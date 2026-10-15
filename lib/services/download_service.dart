import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import '../models/audio_formats.dart';
import '../models/search_result.dart';
import 'app_log.dart';
import 'audio_engine.dart';
import 'ffmpeg_runner.dart';
import 'storage_service.dart';
import 'youtube_service.dart';

class DownloadService {
  final Dio dio = Dio();
  final YoutubeService youtube;

  DownloadService(this.youtube);

  Future<String> download(
    SearchResult result, {
    required void Function(double) onProgress,
    required void Function(String) onStage,
  }) async {
    final folder = await StorageService.musicDir();
    final safe = StorageService.safeName('${result.artist} - ${result.title}');
    final outPath = p.join(folder.path, '$safe-${result.id}.mp3');
    AppLog.info(
        'download', '${result.source.name}: ${result.title} (${result.id})');
    if (result.source == SearchSource.jamendo) {
      onStage('Baixando');
      await dio.download(
        result.downloadUrl,
        outPath,
        onReceiveProgress: (received, total) {
          if (total > 0) onProgress(received / total);
        },
      );
      return outPath;
    }
    onStage('Baixando áudio');
    final rawPath = await youtube.cachedAudio(result.id, onProgress);
    AppLog.info('download', 'áudio em $rawPath');
    onStage('Convertendo para MP3');
    final ok =
        await AudioEngine.convert(rawPath, outPath, const ExportOptions());
    if (!ok) throw Exception('Falha na conversão: ${FfmpegRunner.lastLog}');
    AppLog.info('download', 'concluído: $outPath');
    return outPath;
  }
}
