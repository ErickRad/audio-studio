import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:youtube_explode_dart/youtube_explode_dart.dart'
    hide SearchResult;

import 'app_log.dart';
import 'dependency_manager.dart';

class ResolvedStream {
  final String videoId;
  final String extension;
  final String mime;
  final int totalBytes;
  final Stream<List<int>> Function() open;
  final DateTime resolvedAt;

  ResolvedStream({
    required this.videoId,
    required this.extension,
    required this.mime,
    required this.totalBytes,
    required this.open,
  }) : resolvedAt = DateTime.now();

  bool get fresh =>
      DateTime.now().difference(resolvedAt) < const Duration(minutes: 20);
}

class AudioSession {
  final String videoId;
  final String extension;
  final String mime;
  final int totalBytes;
  final Stream<List<int>> Function() open;
  final Directory cacheDir;
  final ValueNotifier<double> progress = ValueNotifier<double>(0);

  Uint8List _buffer;
  int filled = 0;
  bool completed = false;
  Object? error;
  File? file;
  bool _started = false;
  Completer<void> _signal = Completer<void>();
  final Completer<File> _result = Completer<File>();
  final Completer<void> _first = Completer<void>();

  AudioSession({
    required this.videoId,
    required this.extension,
    required this.mime,
    required this.totalBytes,
    required this.open,
    required this.cacheDir,
  }) : _buffer = Uint8List(totalBytes > 0 ? totalBytes + 4096 : 1 << 20);

  Future<File> get result => _result.future;

  Future<void> get firstByte => _first.future;

  void start() {
    if (_started) return;
    _started = true;
    _first.future.ignore();
    _result.future.ignore();
    unawaited(_pump());
  }

  void _notify() {
    final current = _signal;
    _signal = Completer<void>();
    current.complete();
  }

  void _append(List<int> chunk) {
    final needed = filled + chunk.length;
    if (needed > _buffer.length) {
      final grown = Uint8List(max(_buffer.length * 2, needed));
      grown.setRange(0, filled, _buffer);
      _buffer = grown;
    }
    _buffer.setRange(filled, needed, chunk);
    filled = needed;
    if (!_first.isCompleted) _first.complete();
    if (totalBytes > 0) {
      progress.value = (filled / totalBytes).clamp(0.0, 0.99).toDouble();
    }
    _notify();
  }

  Future<void> _pump() async {
    try {
      await for (final chunk in open()) {
        _append(chunk);
      }
      if (filled == 0) throw Exception('O download do áudio veio vazio.');
      final target = File(p.join(cacheDir.path, 'yt_$videoId.$extension'));
      final part = File('${target.path}.part');
      await part.writeAsBytes(Uint8List.sublistView(_buffer, 0, filled),
          flush: true);
      await part.rename(target.path);
      file = target;
      completed = true;
      progress.value = 1;
      _notify();
      _result.complete(target);
    } catch (e) {
      error = e;
      if (!_first.isCompleted) _first.completeError(e);
      _notify();
      if (!_result.isCompleted) _result.completeError(e);
    }
  }

  Stream<List<int>> read(int start, int? endExclusive) async* {
    var pos = start;
    while (true) {
      final limit = endExclusive ?? (completed ? filled : (1 << 62));
      final available = filled;
      if (pos < available && pos < limit) {
        final to = min(min(available, limit), pos + 65536);
        yield Uint8List.sublistView(_buffer, pos, to);
        pos = to;
        continue;
      }
      if (endExclusive != null && pos >= endExclusive) return;
      if (completed) return;
      final failure = error;
      if (failure != null) throw failure;
      await _signal.future;
    }
  }
}

class AudioStreamService {
  final YoutubeExplode yt;
  final Future<Directory> Function() cacheDir;
  final Future<List<String>> Function() jsArgs;

  final Map<String, Future<ResolvedStream>> _resolving = {};
  final Map<String, AudioSession> _sessions = {};
  final Set<String> failed = {};
  HttpServer? _server;

  AudioStreamService({
    required this.yt,
    required this.cacheDir,
    required this.jsArgs,
  });

  String mimeFor(String extension) {
    switch (extension) {
      case 'm4a':
      case 'mp4':
        return 'audio/mp4';
      case 'webm':
        return 'audio/webm';
      case 'mp3':
        return 'audio/mpeg';
      default:
        return 'application/octet-stream';
    }
  }

  Future<File?> cachedFile(String videoId) async {
    final dir = await cacheDir();
    final stem = 'yt_$videoId.';
    for (final entity in dir.listSync()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (!name.startsWith(stem)) continue;
      if (name.endsWith('.part') || name.endsWith('.ytdl')) continue;
      if (entity.lengthSync() == 0) continue;
      return entity;
    }
    return null;
  }

  Future<ResolvedStream> resolve(String videoId) {
    final running = _resolving[videoId];
    if (running != null) return running;
    final task = _resolveFresh(videoId);
    _resolving[videoId] = task;
    task.then((value) {
      Timer(const Duration(minutes: 20), () => _resolving.remove(videoId));
    }, onError: (Object _) {
      _resolving.remove(videoId);
    });
    return task;
  }

  void prefetch(String videoId) {
    cachedFile(videoId).then((file) {
      if (file != null) return;
      resolve(videoId).then((_) {}, onError: (Object e) {
        AppLog.error('prefetch', e);
      });
    });
  }

  Future<ResolvedStream> _resolveFresh(String videoId) async {
    final watch = Stopwatch()..start();
    try {
      final stream = await _resolveWithYtDlp(videoId);
      AppLog.info(
          'stream', 'yt-dlp resolvido em ${watch.elapsedMilliseconds} ms');
      return stream;
    } catch (e) {
      AppLog.error('stream', 'yt-dlp falhou ao resolver: $e');
    }
    final stream =
        await _resolveWithExplode(videoId).timeout(const Duration(seconds: 15));
    AppLog.info(
        'stream', 'manifesto resolvido em ${watch.elapsedMilliseconds} ms');
    return stream;
  }

  Future<ResolvedStream> _resolveWithExplode(String videoId) async {
    final manifest = await yt.videos.streamsClient.getManifest(videoId);
    final audio = manifest.audioOnly.toList();
    if (audio.isEmpty) throw Exception('Nenhum stream de áudio disponível.');
    audio.sort((a, b) => b.bitrate.compareTo(a.bitrate));
    final mp4 = audio.where((s) => s.container == StreamContainer.mp4);
    final pick = mp4.isNotEmpty ? mp4.first : audio.first;
    final extension =
        pick.container == StreamContainer.mp4 ? 'm4a' : pick.container.name;
    return ResolvedStream(
      videoId: videoId,
      extension: extension,
      mime: mimeFor(extension),
      totalBytes: pick.size.totalBytes,
      open: () => yt.videos.streamsClient.get(pick),
    );
  }

  Future<ResolvedStream> _resolveWithYtDlp(String videoId) async {
    final executable = await DependencyManager.instance.resolve('yt-dlp');
    final extra = await jsArgs();
    final result = await Process.run(executable, [
      '-f',
      'bestaudio[ext=m4a]/bestaudio',
      '-j',
      '--no-playlist',
      '--no-warnings',
      ...extra,
      'https://www.youtube.com/watch?v=$videoId',
    ]).timeout(const Duration(seconds: 45));
    if (result.exitCode != 0) {
      throw Exception('yt-dlp: ${'${result.stderr}'.trim()}');
    }
    final lines = const LineSplitter()
        .convert('${result.stdout}')
        .where((l) => l.trim().startsWith('{'))
        .toList();
    if (lines.isEmpty) throw Exception('yt-dlp não retornou dados.');
    final json = jsonDecode(lines.last) as Map<String, dynamic>;
    final url = json['url'] as String?;
    final protocol = '${json['protocol'] ?? 'https'}';
    if (url == null || !protocol.startsWith('http')) {
      throw Exception('Formato sem URL direta ($protocol).');
    }
    final extension = '${json['ext'] ?? 'm4a'}';
    final size =
        ((json['filesize'] ?? json['filesize_approx']) as num?)?.toInt() ?? 0;
    final rawHeaders = json['http_headers'];
    final headers = <String, String>{};
    if (rawHeaders is Map) {
      rawHeaders.forEach((k, v) => headers['$k'] = '$v');
    }
    final uri = Uri.parse(url);
    return ResolvedStream(
      videoId: videoId,
      extension: extension,
      mime: mimeFor(extension),
      totalBytes: size,
      open: () => _rangedGet(uri, headers, size),
    );
  }

  Stream<List<int>> _rangedGet(
    Uri url,
    Map<String, String> headers,
    int total,
  ) async* {
    final client = HttpClient();
    try {
      var pos = 0;
      const chunk = 4 * 1024 * 1024;
      while (total <= 0 ? pos == 0 : pos < total) {
        final request = await client.getUrl(url);
        headers.forEach((k, v) => request.headers.set(k, v));
        if (total > 0) {
          request.headers
              .set('range', 'bytes=$pos-${min(pos + chunk, total) - 1}');
        }
        final response = await request.close();
        if (response.statusCode >= 400) {
          throw Exception('HTTP ${response.statusCode}');
        }
        var got = 0;
        await for (final data in response) {
          got += data.length;
          yield data;
        }
        if (total <= 0) break;
        if (got == 0) throw Exception('Resposta vazia do servidor.');
        pos += got;
      }
    } finally {
      client.close(force: true);
    }
  }

  Future<AudioSession> session(String videoId) async {
    if (failed.contains(videoId)) {
      throw Exception('Streaming indisponível para este vídeo.');
    }
    final existing = _sessions[videoId];
    if (existing != null) return existing;
    final stream = await resolve(videoId);
    final again = _sessions[videoId];
    if (again != null) return again;
    final dir = await cacheDir();
    final created = AudioSession(
      videoId: videoId,
      extension: stream.extension,
      mime: stream.mime,
      totalBytes: stream.totalBytes,
      open: stream.open,
      cacheDir: dir,
    );
    _sessions[videoId] = created;
    created.result.then((_) {
      _sessions.remove(videoId);
    }, onError: (Object _) {
      failed.add(videoId);
      _sessions.remove(videoId);
      _resolving.remove(videoId);
    });
    created.start();
    return created;
  }

  Future<void> _ensureServer() async {
    if (_server != null) return;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    server.listen(_handle, onError: (Object e) {
      AppLog.error('stream', e);
    });
    AppLog.info('stream', 'servidor local na porta ${server.port}');
  }

  Future<String> localUrl(String videoId) async {
    await _ensureServer();
    final cached = await cachedFile(videoId);
    if (cached == null) {
      final active = await session(videoId);
      await active.firstByte.timeout(const Duration(seconds: 20));
    }
    return 'http://127.0.0.1:${_server!.port}/yt/$videoId';
  }

  ({int start, int? end})? _parseRange(String? header, int total) {
    if (header == null || total <= 0) return null;
    final match = RegExp(r'bytes=(\d*)-(\d*)').firstMatch(header);
    if (match == null) return null;
    final a = match.group(1)!;
    final b = match.group(2)!;
    if (a.isEmpty && b.isEmpty) return null;
    if (a.isEmpty) {
      final suffix = int.parse(b);
      return (start: max(0, total - suffix), end: total);
    }
    final start = int.parse(a);
    final end = b.isEmpty ? total : min(int.parse(b) + 1, total);
    return (start: start, end: end);
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    try {
      final segments = request.uri.pathSegments;
      if (segments.length != 2 || segments[0] != 'yt') {
        response.statusCode = HttpStatus.notFound;
        return;
      }
      final id = segments[1];
      final active = _sessions[id];
      int total;
      String mime;
      Stream<List<int>> Function(int, int?) reader;
      if (active != null && active.file == null) {
        total = active.totalBytes;
        mime = active.mime;
        reader = active.read;
      } else {
        final file = active?.file ?? await cachedFile(id);
        if (file == null) {
          response.statusCode = HttpStatus.notFound;
          return;
        }
        total = await file.length();
        mime = mimeFor(p.extension(file.path).replaceFirst('.', ''));
        reader = (s, e) => file.openRead(s, e);
      }
      final range = _parseRange(request.headers.value('range'), total);
      response.headers.set('content-type', mime);
      response.headers.set('accept-ranges', total > 0 ? 'bytes' : 'none');
      var start = 0;
      int? end;
      if (range != null) {
        start = range.start;
        end = range.end;
        response.statusCode = HttpStatus.partialContent;
        response.headers
            .set('content-range', 'bytes $start-${(end ?? total) - 1}/$total');
        response.contentLength = (end ?? total) - start;
      } else if (total > 0) {
        response.contentLength = total;
      }
      await response.addStream(reader(start, end));
    } catch (e) {
      AppLog.error('stream', 'requisição interrompida: $e');
    } finally {
      try {
        await response.close();
      } catch (_) {}
    }
  }

  Future<void> dispose() async {
    await _server?.close(force: true);
    _server = null;
  }
}
