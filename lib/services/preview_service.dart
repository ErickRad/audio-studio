import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'dart:io';
import '../models/audio_formats.dart';
import 'app_log.dart';
import 'audio_engine.dart';

class PreviewService {
  static final PreviewService instance = PreviewService._();

  final AudioPlayer player = AudioPlayer();
  final ValueNotifier<String?> currentId = ValueNotifier<String?>(null);
  final ValueNotifier<String?> loadingId = ValueNotifier<String?>(null);

  PreviewService._() {
    player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        currentId.value = null;
      }
    });
    player.playbackEventStream.listen((_) {}, onError: (Object error, StackTrace stack) {
      AppLog.error('player', error, stack);
      currentId.value = null;
      loadingId.value = null;
    });
  }

  Future<String?> toggle(
    String id, {
    String? url,
    String? filePath,
    Future<String> Function()? fileResolver,
  }) async {
    if (currentId.value == id) {
      await stop();
      return null;
    }
    AppLog.info('prévia', 'solicitada: $id');
    await player.stop();
    currentId.value = id;
    try {
      var path = filePath;
      if (fileResolver != null) {
        loadingId.value = id;
        path = await fileResolver();
        AppLog.info('prévia', 'arquivo obtido: $path');
        if (currentId.value != id) return null;
        path = await playableCopy(path);
        if (currentId.value != id) return null;
      }
      if (url != null) {
        await player.setUrl(url).timeout(const Duration(seconds: 25));
      } else if (path != null) {
        AppLog.info('prévia', 'carregando no player: $path');
        await player.setFilePath(path).timeout(
              const Duration(seconds: 25),
              onTimeout: () => throw Exception(
                'o player não carregou o arquivo em 25s (verifique libmpv: sudo apt install libmpv-dev mpv)',
              ),
            );
      } else {
        throw Exception('Nenhuma fonte de áudio');
      }
      if (currentId.value != id) return null;
      AppLog.info('prévia', 'tocando: $id');
      player.play();
      return null;
    } catch (e, stack) {
      AppLog.error('prévia', e, stack);
      if (currentId.value == id) currentId.value = null;
      final text = '$e'.replaceFirst('Exception: ', '').replaceAll('\n', ' ').trim();
      return text.length > 800 ? '${text.substring(0, 800)}…' : text;
    } finally {
      if (loadingId.value == id) loadingId.value = null;
    }
  }

  Future<String> playableCopy(String path) async {
    if (path.toLowerCase().endsWith('.mp3')) return path;
    final out = '${path.substring(0, path.lastIndexOf('.'))}.preview.mp3';
    final file = File(out);
    if (await file.exists() && await file.length() > 0) return out;
    AppLog.info('prévia', 'convertendo para mp3: $out');
    await AudioEngine.convert(path, out, const ExportOptions());
    if (!await file.exists() || await file.length() == 0) {
      throw Exception('falha ao converter o áudio para prévia (ffmpeg)');
    }
    return out;
  }

  Future<void> stop() async {
    await player.stop();
    currentId.value = null;
    loadingId.value = null;
  }
}
