import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import '../models/audio_formats.dart';
import '../models/search_result.dart';
import 'app_log.dart';
import 'audio_engine.dart';
import 'cover_service.dart';
import 'ffmpeg_runner.dart';
import 'storage_service.dart';
import 'youtube_service.dart';

class DownloadResult {
  final String path;
  final String coverPath;

  const DownloadResult(this.path, this.coverPath);
}

class DownloadService {
  final Dio dio = Dio();
  final YoutubeService youtube;

  DownloadService(this.youtube);

  Future<DownloadResult> download(
    SearchResult result, {
    required void Function(double) onProgress,
    required void Function(String) onStage,
  }) async {
    final folder = await StorageService.musicDir();
    final safe = StorageService.safeName('${result.artist} - ${result.title}');
    final outPath = p.join(folder.path, '$safe-${result.id}.mp3');
    AppLog.info(
        'download', '${result.source.name}: ${result.title} (${result.id})');
    final coverFuture =
        CoverService.fetch(result).catchError((Object _) => null);
    if (result.source == SearchSource.jamendo) {
      onStage('Baixando');
      await dio.download(
        result.downloadUrl,
        outPath,
        onReceiveProgress: (received, total) {
          if (total > 0) onProgress(received / total);
        },
      );
      final cover = await coverFuture;
      if (cover != null) {
        onStage('Gravando capa');
        await CoverService.embedCover(
          outPath,
          cover,
          title: result.title,
          artist: result.artist,
        );
      }
      return DownloadResult(outPath, cover ?? '');
    }
    onStage('Baixando áudio');
    final rawPath = await youtube.cachedAudio(result.id, onProgress);
    AppLog.info('download', 'áudio em $rawPath');
    onStage('Convertendo para MP3');
    final cover = await coverFuture;
    final ok = await AudioEngine.convert(
      rawPath,
      outPath,
      const ExportOptions(),
      coverPath: cover,
      title: result.title,
      artist: result.artist,
    );
    if (!ok) throw Exception('Falha na conversão: ${FfmpegRunner.lastLog}');
    AppLog.info('download', 'concluído: $outPath');
    return DownloadResult(outPath, cover ?? '');
  }
}
