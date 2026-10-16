import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../models/search_result.dart';
import 'app_log.dart';
import 'ffmpeg_runner.dart';
import 'storage_service.dart';

class CoverService {
  static final Dio dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
      responseType: ResponseType.bytes,
      validateStatus: (status) => status != null && status < 500,
    ),
  );

  static const String squareFilter =
      "crop='min(iw,ih)':'min(iw,ih)',scale=500:500";
  static const String letterboxFilter =
      'crop=iw:ih*0.75:0:ih*0.125,$squareFilter';

  static Future<String?> fromImage(
    String inputPath,
    String outPath, {
    bool letterbox = false,
  }) async {
    await FfmpegRunner.capture([
      '-y',
      '-i',
      inputPath,
      '-vf',
      letterbox ? letterboxFilter : squareFilter,
      '-frames:v',
      '1',
      '-q:v',
      '2',
      outPath,
    ]);
    final file = File(outPath);
    if (await file.exists() && await file.length() > 0) return outPath;
    return null;
  }

  static List<(String, bool)> candidates(SearchResult r) {
    if (r.source == SearchSource.youtube) {
      return [
        ('https://i.ytimg.com/vi/${r.id}/maxresdefault.jpg', false),
        ('https://i.ytimg.com/vi/${r.id}/hqdefault.jpg', true),
        if (r.imageUrl.isNotEmpty) (r.imageUrl, false),
      ];
    }
    return [if (r.imageUrl.isNotEmpty) (r.imageUrl, false)];
  }

  static Future<String?> fetch(SearchResult r) async {
    final dir = await StorageService.coversDir();
    final name = StorageService.safeName('${r.source.name}_${r.id}');
    final out = p.join(dir.path, '$name.jpg');
    final existing = File(out);
    if (await existing.exists() && await existing.length() > 0) return out;
    final source = File('$out.src');
    for (final candidate in candidates(r)) {
      try {
        final response = await dio.get<List<int>>(candidate.$1);
        final data = response.data;
        if (response.statusCode != 200 || data == null || data.length < 2000) {
          continue;
        }
        await source.writeAsBytes(data, flush: true);
        final done = await fromImage(source.path, out, letterbox: candidate.$2);
        if (done != null) {
          await source.delete();
          return done;
        }
      } catch (e) {
        AppLog.error('capa', e);
      }
    }
    if (await source.exists()) await source.delete();
    return null;
  }

  static Future<String?> extractEmbedded(String audioPath) async {
    final dir = await StorageService.coversDir();
    final hash =
        sha1.convert(utf8.encode(audioPath)).toString().substring(0, 16);
    final out = p.join(dir.path, 'local_$hash.jpg');
    final existing = File(out);
    if (await existing.exists() && await existing.length() > 0) return out;
    await FfmpegRunner.capture([
      '-y',
      '-i',
      audioPath,
      '-map',
      '0:v:0',
      '-vf',
      squareFilter,
      '-frames:v',
      '1',
      '-q:v',
      '2',
      out,
    ]);
    if (await existing.exists() && await existing.length() > 0) return out;
    if (await existing.exists()) await existing.delete();
    return null;
  }

  static Future<bool> embedCover(
    String mp3Path,
    String coverPath, {
    String title = '',
    String artist = '',
  }) async {
    final temp = '$mp3Path.cover.mp3';
    final args = <String>[
      '-y',
      '-i',
      mp3Path,
      '-i',
      coverPath,
      '-map',
      '0:a:0',
      '-map',
      '1:v:0',
      '-c',
      'copy',
      '-id3v2_version',
      '3',
      '-metadata:s:v',
      'title=Album cover',
      '-metadata:s:v',
      'comment=Cover (front)',
    ];
    if (title.isNotEmpty) args.addAll(['-metadata', 'title=$title']);
    if (artist.isNotEmpty) args.addAll(['-metadata', 'artist=$artist']);
    args.add(temp);
    final ok = await FfmpegRunner.run(args);
    if (!ok) {
      final file = File(temp);
      if (await file.exists()) await file.delete();
      return false;
    }
    await File(temp).rename(mp3Path);
    return true;
  }
}
