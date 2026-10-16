import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart'
    hide SearchResult;

import '../models/search_result.dart';
import 'app_log.dart';
import 'audio_stream_service.dart';
import 'dependency_manager.dart';

class YoutubeService {
  final YoutubeExplode yt = YoutubeExplode();

  final Map<String, Future<String>> inflight = {};

  List<String>? jsArgsCache;
  bool? ytDlpOk;

  late final AudioStreamService streams = AudioStreamService(
    yt: yt,
    cacheDir: cacheDir,
    jsArgs: jsRuntimeArgs,
  );

  Future<String> previewUrl(String videoId) async {
    try {
      return await streams.localUrl(videoId);
    } catch (e) {
      AppLog.error('prévia', 'streaming falhou, baixando o arquivo: $e');
      return cachedAudio(videoId, (_) {});
    }
  }

  void prefetch(String videoId) => streams.prefetch(videoId);

  SearchResult fromVideo(Video v) => SearchResult(
        source: SearchSource.youtube,
        id: v.id.value,
        title: v.title,
        artist: v.author,
        imageUrl: v.thumbnails.mediumResUrl,
        durationMs: v.duration?.inMilliseconds ?? 0,
      );

  Future<String> _ytDlpPath() async {
    return DependencyManager.instance.resolve('yt-dlp');
  }

  Future<List<SearchResult>> search(String query) async {
    if (query.contains('youtu')) {
      final id = VideoId.parseVideoId(query);

      if (id != null) {
        final video = await yt.videos.get(id);
        return [fromVideo(video)];
      }
    }

    try {
      final list = await yt.search.search(
        query,
        filter: TypeFilters.video,
      );

      return list.map(fromVideo).toList();
    } catch (e, stack) {
      AppLog.error('busca', e, stack);

      if (!await ytDlpAvailable()) rethrow;

      AppLog.info('busca', 'tentando busca via yt-dlp');
      return searchWithYtDlp(query);
    }
  }

  Future<List<SearchResult>> searchWithYtDlp(String query) async {
    final executable = await _ytDlpPath();

    final result = await Process.run(
      executable,
      [
        'ytsearch20:$query',
        '--flat-playlist',
        '--dump-json',
        '--no-warnings',
      ],
    ).timeout(const Duration(seconds: 45));

    if (result.exitCode != 0) {
      throw Exception('yt-dlp: ${'${result.stderr}'.trim()}');
    }

    final items = <SearchResult>[];

    for (final line in const LineSplitter().convert('${result.stdout}')) {
      if (line.trim().isEmpty) continue;

      final json = jsonDecode(line) as Map<String, dynamic>;
      final id = json['id'] as String?;

      if (id == null) continue;

      final thumbs = json['thumbnails'];
      var thumb = (json['thumbnail'] as String?) ?? '';

      if (thumb.isEmpty && thumbs is List && thumbs.isNotEmpty) {
        final mid = thumbs.length > 1 ? thumbs[1] : thumbs.first;

        if (mid is Map<String, dynamic>) {
          thumb = (mid['url'] as String?) ?? '';
        }
      }

      final seconds = (json['duration'] as num?)?.toDouble() ?? 0;

      items.add(
        SearchResult(
          source: SearchSource.youtube,
          id: id,
          title: (json['title'] as String?) ?? id,
          artist: (json['channel'] as String?) ??
              (json['uploader'] as String?) ??
              '',
          imageUrl: thumb,
          durationMs: (seconds * 1000).round(),
        ),
      );
    }

    return items;
  }

  String describe(Object e) {
    final text =
        '$e'.replaceFirst('Exception: ', '').replaceAll('\n', ' ').trim();

    return text.length > 600 ? '${text.substring(0, 600)}…' : text;
  }

  Future<Directory> cacheDir() async {
    final base = await getTemporaryDirectory();

    final dir = Directory(
      p.join(base.path, 'audio_studio_cache'),
    );

    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    return dir;
  }

  File? findFile(Directory dir, String stem) {
    for (final entity in dir.listSync()) {
      if (entity is! File) continue;

      final name = p.basename(entity.path);

      if (!name.startsWith('$stem.')) continue;
      if (name.endsWith('.part') || name.endsWith('.ytdl')) continue;

      if (entity.lengthSync() == 0) {
        try {
          entity.deleteSync();
        } catch (_) {}
        continue;
      }

      return entity;
    }

    return null;
  }

  Future<String> cachedAudio(
    String videoId,
    void Function(double) onProgress,
  ) async {
    final dir = await cacheDir();
    final existing = findFile(dir, 'yt_$videoId');

    if (existing != null) {
      AppLog.info('youtube', 'usando cache: ${existing.path}');
      onProgress(1);
      return existing.path;
    }

    try {
      final session = await streams.session(videoId);
      void listener() => onProgress(session.progress.value);
      session.progress.addListener(listener);
      try {
        final file = await session.result;
        onProgress(1);
        return file.path;
      } finally {
        session.progress.removeListener(listener);
      }
    } catch (e) {
      AppLog.error('youtube', 'streaming falhou, usando método completo: $e');
    }

    final running = inflight[videoId];

    if (running != null) {
      return running;
    }

    AppLog.info('youtube', 'obtendo áudio de $videoId');

    final task = fetchAudio(
      videoId,
      dir,
      onProgress,
    ).whenComplete(() {
      inflight.remove(videoId);
    });

    inflight[videoId] = task;

    return task;
  }

  Future<String> fetchAudio(
    String videoId,
    Directory dir,
    void Function(double) onProgress,
  ) async {
    final stem = 'yt_$videoId';
    final errors = <String>[];

    final hasYtDlp = await ytDlpAvailable();

    if (hasYtDlp) {
      try {
        return await downloadWithYtDlp(
          videoId,
          dir,
          stem,
          onProgress,
        );
      } catch (e) {
        AppLog.error('yt-dlp', e);
        errors.add('yt-dlp: ${describe(e)}');
      }
    }

    try {
      return await downloadWithExplode(
        videoId,
        p.join(dir.path, stem),
        onProgress,
      );
    } catch (e) {
      AppLog.error('youtube_explode', e);
      errors.add('youtube_explode: ${describe(e)}');
    }

    if (!hasYtDlp) {
      errors.add('yt-dlp não está disponível.');
    }

    errors.add(
      'Se o YouTube exigir um runtime JavaScript, instale Deno '
      'ou Node.js. A ferramenta de diagnóstico pode mostrar '
      'quais dependências estão disponíveis.',
    );

    throw Exception(errors.join('\n'));
  }

  Future<String?> toolVersion(
    String executable,
    List<String> args,
  ) async {
    try {
      final path = executable == 'yt-dlp' ? await _ytDlpPath() : executable;

      final result = await Process.run(path, args);

      if (result.exitCode != 0) return null;

      final output = '${result.stdout}'.trim();

      return output.isEmpty ? 'ok' : output.split('\n').first.trim();
    } catch (_) {
      return null;
    }
  }

  Future<List<String>> jsRuntimeArgs() async {
    final cached = jsArgsCache;

    if (cached != null) return cached;

    var args = <String>[];

    final deno = await toolVersion('deno', ['--version']);

    if (deno == null) {
      final node = await toolVersion('node', ['--version']);
      final version = await toolVersion('yt-dlp', ['--version']);

      if (node != null &&
          version != null &&
          _isVersionAtLeast(version, '2025.11')) {
        args = ['--js-runtimes', 'node'];
      }
    }

    jsArgsCache = args;
    return args;
  }

  bool _isVersionAtLeast(String current, String minimum) {
    final currentParts = RegExp(r'\d+')
        .allMatches(current)
        .map((m) => int.parse(m.group(0)!))
        .toList();

    final minimumParts = RegExp(r'\d+')
        .allMatches(minimum)
        .map((m) => int.parse(m.group(0)!))
        .toList();

    for (var i = 0; i < minimumParts.length; i++) {
      final a = i < currentParts.length ? currentParts[i] : 0;
      final b = minimumParts[i];

      if (a > b) return true;
      if (a < b) return false;
    }

    return true;
  }

  Future<bool> ytDlpAvailable() async {
    final known = ytDlpOk;
    if (known != null) return known;
    try {
      final executable = await _ytDlpPath();
      final result = await Process.run(executable, ['--version']);
      ytDlpOk = result.exitCode == 0;
      return ytDlpOk!;
    } catch (e) {
      AppLog.error('yt-dlp', e);
      return false;
    }
  }

  Future<String> downloadWithExplode(
    String videoId,
    String outputStem,
    void Function(double) onProgress,
  ) async {
    final manifest = await yt.videos.streamsClient.getManifest(videoId);

    final streams = manifest.audioOnly.toList()
      ..sort((a, b) => b.bitrate.compareTo(a.bitrate));

    if (streams.isEmpty) {
      throw Exception('Nenhum stream de áudio disponível.');
    }

    final streamInfo = streams.first;
    final extension = streamInfo.container.name;
    final outputPath = '$outputStem.$extension';
    final outputFile = File(outputPath);

    final stream = yt.videos.streamsClient.get(streamInfo);
    final sink = outputFile.openWrite();

    var received = 0;
    final total = streamInfo.size.totalBytes;

    try {
      await for (final chunk in stream) {
        sink.add(chunk);
        received += chunk.length;

        if (total > 0) {
          onProgress((received / total).clamp(0.0, 1.0));
        }
      }

      await sink.flush();
      await sink.close();

      if (!await outputFile.exists() || await outputFile.length() == 0) {
        throw Exception('O download do áudio resultou em arquivo vazio.');
      }

      onProgress(1);
      return outputFile.path;
    } catch (_) {
      await sink.close();

      if (await outputFile.exists()) {
        await outputFile.delete();
      }

      rethrow;
    }
  }

  Future<String> downloadWithYtDlp(
    String videoId,
    Directory dir,
    String stem,
    void Function(double) onProgress,
  ) async {
    final executable = await _ytDlpPath();
    final jsArgs = await jsRuntimeArgs();

    final process = await Process.start(
      executable,
      [
        '-f',
        'bestaudio/best',
        '--no-playlist',
        '--newline',
        '--force-overwrites',
        ...jsArgs,
        '-o',
        p.join(dir.path, '$stem.%(ext)s'),
        'https://www.youtube.com/watch?v=$videoId',
      ],
    );

    AppLog.info('yt-dlp', 'iniciado para $videoId');

    final messages = <String>[];

    void handle(String line) {
      final match = RegExp(
        r'\[download\]\s+(\d+(?:\.\d+)?)%',
      ).firstMatch(line);

      if (match != null) {
        onProgress(double.parse(match.group(1)!) / 100);
        return;
      }

      final text = line.trim();

      if (text.isNotEmpty) {
        AppLog.info('yt-dlp', text);
        messages.add(text);
      }
    }

    final outDone = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .forEach(handle);

    final errDone = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .forEach(handle);

    final code = await process.exitCode.timeout(
      const Duration(minutes: 4),
      onTimeout: () {
        process.kill();
        return -1;
      },
    );

    AppLog.info('yt-dlp', 'finalizou com código $code');

    await Future.wait([outDone, errDone]).timeout(
      const Duration(seconds: 5),
      onTimeout: () => <void>[],
    );

    final file = findFile(dir, stem);

    AppLog.info('yt-dlp', 'arquivo localizado: ${file?.path}');

    if (code != 0 || file == null) {
      final tail = messages.length > 3
          ? messages.sublist(messages.length - 3)
          : messages;

      final detail = tail.isEmpty ? 'código de saída $code' : tail.join(' / ');

      throw Exception(detail);
    }

    return file.path;
  }

  void dispose() {
    streams.dispose();
    yt.close();
  }
}
