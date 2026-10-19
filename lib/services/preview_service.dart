import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import 'app_log.dart';

class PreviewService {
  static final PreviewService instance = PreviewService._();

  final AudioPlayer player = AudioPlayer();
  final ValueNotifier<String?> currentId = ValueNotifier<String?>(null);
  final ValueNotifier<String?> loadingId = ValueNotifier<String?>(null);
  int ticket = 0;
  List<({String id, String path})> queue = [];
  int queueIndex = -1;
  final ValueNotifier<bool> queueActive = ValueNotifier<bool>(false);

  PreviewService._() {
    player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        currentId.value = null;
        if (queueActive.value) unawaited(next());
      }
    });
    player.playbackEventStream.listen((_) {},
        onError: (Object error, StackTrace stack) {
      AppLog.error('player', error, stack);
      currentId.value = null;
      loadingId.value = null;
    });
  }

  Future<String?> toggle(
    String id, {
    String? url,
    String? filePath,
    Future<String> Function()? urlResolver,
    bool fromQueue = false,
  }) async {
    if (!fromQueue) endQueue();
    if (currentId.value == id) {
      await stop();
      return null;
    }
    final mine = ++ticket;
    final watch = Stopwatch()..start();
    AppLog.info('prévia', 'solicitada: $id');
    currentId.value = id;
    loadingId.value = id;
    try {
      final stopping = player.stop();
      var source = url ?? filePath;
      if (urlResolver != null) {
        source = await urlResolver();
        AppLog.info(
            'prévia', 'fonte pronta em ${watch.elapsedMilliseconds} ms');
      }
      await stopping;
      if (mine != ticket) return null;
      if (source == null) throw Exception('Nenhuma fonte de áudio');
      final isUrl =
          source.startsWith('http://') || source.startsWith('https://');
      if (isUrl) {
        await player.setUrl(source).timeout(const Duration(seconds: 25));
      } else {
        await player.setFilePath(source).timeout(const Duration(seconds: 25));
      }
      if (mine != ticket) return null;
      AppLog.info('prévia', 'tocando em ${watch.elapsedMilliseconds} ms: $id');
      unawaited(player.play());
      return null;
    } catch (e, stack) {
      AppLog.error('prévia', e, stack);
      if (mine == ticket) currentId.value = null;
      final text =
          '$e'.replaceFirst('Exception: ', '').replaceAll('\n', ' ').trim();
      return text.length > 800 ? '${text.substring(0, 800)}…' : text;
    } finally {
      if (mine == ticket && loadingId.value == id) loadingId.value = null;
    }
  }

  void endQueue() {
    queue = [];
    queueIndex = -1;
    queueActive.value = false;
  }

  Future<void> playQueue(
    List<({String id, String path})> items, {
    bool shuffle = false,
  }) async {
    if (items.isEmpty) return;
    final list = [...items];
    if (shuffle) list.shuffle();
    queue = list;
    queueIndex = -1;
    queueActive.value = true;
    await next();
  }

  Future<void> next() async {
    if (!queueActive.value) return;
    var tries = 0;
    while (queueIndex + 1 < queue.length && tries < queue.length) {
      queueIndex++;
      tries++;
      final item = queue[queueIndex];
      final error = await toggle(item.id, filePath: item.path, fromQueue: true);
      if (error == null) return;
    }
    endQueue();
  }

  Future<void> previous() async {
    if (!queueActive.value || queue.isEmpty) return;
    queueIndex = (queueIndex - 2).clamp(-1, queue.length).toInt();
    await next();
  }

  Future<void> stop() async {
    endQueue();
    ticket++;
    currentId.value = null;
    loadingId.value = null;
    await player.stop();
  }
}
