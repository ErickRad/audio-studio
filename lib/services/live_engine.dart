import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/clip.dart';
import '../models/timeline_track.dart';
import 'app_log.dart';
import 'ffmpeg_runner.dart';

class _Voice {
  final String clipId;
  AudioClip? clip;
  double trackGain = 1;
  Player? player;
  String? openedKey;
  String? sourcePath;
  Future<bool>? readying;
  String? readyingKey;
  bool playing = false;
  bool prepared = false;
  bool busy = false;
  bool needsAlign = false;
  int lastAlignMs = 0;
  double appliedVolume = -1;
  double appliedRate = -1;
  String appliedFilter = '\u0000';

  _Voice(this.clipId);

  String get wantedKey {
    final c = clip!;
    return c.reversed ? 'rev:${c.path}:${c.inMs}:${c.outMs}' : c.path;
  }

  int sourceMsAt(int playheadMs) {
    final c = clip!;
    final offset = c.reversed ? 0 : c.inMs;
    return offset + ((playheadMs - c.startMs) * c.speed).round();
  }
}

class LiveEngine {
  static const int maxVoices = 8;
  static const int leadMs = 45;

  final ValueNotifier<int> playhead;
  final List<TimelineTrack> tracks;
  final VoidCallback onStateChanged;

  final Map<String, _Voice> voices = {};
  final Map<String, Future<String?>> reversedFiles = {};
  final Map<String, double> normalizeGains = {};
  final Set<String> measuring = {};
  final Stopwatch clock = Stopwatch();
  Timer? ticker;
  int baseMs = 0;
  int lastBalanceMs = -100000;
  bool playing = false;
  bool disposed = false;

  LiveEngine({
    required this.playhead,
    required this.tracks,
    required this.onStateChanged,
  });

  int get nowMs => baseMs + (clock.elapsedMicroseconds ~/ 1000);

  int get projectEnd {
    var end = 0;
    for (final t in tracks) {
      for (final c in t.clips) {
        if (c.endMs > end) end = c.endMs;
      }
    }
    return end;
  }

  Future<bool> _open(_Voice v) {
    final running = v.readying;
    if (running != null && v.readyingKey == v.wantedKey) return running;
    final task = _openFresh(v);
    v.readying = task;
    v.readyingKey = v.wantedKey;
    return task;
  }

  Future<bool> _openFresh(_Voice v) async {
    try {
      final clip = v.clip;
      if (clip == null) return false;
      final key = v.wantedKey;
      String? path = clip.path;
      if (clip.reversed) {
        path = await _reversedFor(clip);
        if (path == null) return false;
      }
      var player = v.player;
      if (player == null) {
        player = Player();
        v.player = player;
        final native = player.platform;
        if (native is NativePlayer) {
          await native.setProperty('vid', 'no');
          await native.setProperty('volume-max', '400');
          await native.setProperty('keep-open', 'yes');
          await native.setProperty('audio-display', 'no');
        }
      }
      if (disposed || v.clip == null) return false;
      if (v.sourcePath != path) {
        v.playing = false;
        v.prepared = false;
        await player.open(Media(path), play: false);
        v.sourcePath = path;
        if (player.state.duration <= Duration.zero) {
          try {
            await player.stream.duration
                .firstWhere((d) => d > Duration.zero)
                .timeout(const Duration(seconds: 4));
          } catch (_) {}
        }
      }
      v.openedKey = key;
      v.appliedFilter = '\u0000';
      v.appliedRate = -1;
      v.appliedVolume = -1;
      _applyParams(v, nowMs);
      return true;
    } catch (e, stack) {
      AppLog.error('editor', e, stack);
      return false;
    }
  }

  Future<String?> _reversedFor(AudioClip clip) {
    final key = '${clip.path.hashCode}_${clip.inMs}_${clip.outMs}';
    return reversedFiles.putIfAbsent(key, () async {
      final dir = await getTemporaryDirectory();
      final out = p.join(dir.path, 'reverse_$key.wav');
      if (await File(out).exists() && await File(out).length() > 0) return out;
      final start = (clip.inMs / 1000).toStringAsFixed(3);
      final end = (clip.outMs / 1000).toStringAsFixed(3);
      final ok = await FfmpegRunner.run([
        '-y',
        '-i',
        clip.path,
        '-vn',
        '-af',
        'atrim=start=$start:end=$end,asetpts=PTS-STARTPTS,areverse',
        '-c:a',
        'pcm_s16le',
        '-ar',
        '44100',
        '-ac',
        '2',
        out,
      ]);
      return ok ? out : null;
    });
  }

  Future<void> _measureNormalize(AudioClip clip) async {
    final key = clip.path;
    if (normalizeGains.containsKey(key) || !measuring.add(key)) return;
    try {
      final text = await FfmpegRunner.capture([
        '-i',
        key,
        '-vn',
        '-af',
        'loudnorm=I=-16:TP=-1.5:LRA=11:print_format=json',
        '-f',
        'null',
        '-',
      ]);
      final start = text.lastIndexOf('{');
      final end = text.lastIndexOf('}');
      if (start >= 0 && end > start) {
        final json =
            jsonDecode(text.substring(start, end + 1)) as Map<String, dynamic>;
        final input = double.tryParse('${json['input_i']}');
        if (input != null && input.isFinite) {
          normalizeGains[key] = (-16 - input).clamp(-24.0, 24.0).toDouble();
        }
      }
      normalizeGains.putIfAbsent(key, () => 0);
    } finally {
      measuring.remove(key);
      if (!disposed) {
        for (final v in voices.values) {
          if (v.clip?.path == key) _applyParams(v, nowMs);
        }
      }
    }
  }

  String _filterFor(AudioClip c) {
    final f = <String>[];
    if (c.pitch.abs() > 0.001) {
      final ratio = pow(2, c.pitch / 12).toDouble();
      f.add('aresample=44100');
      f.add('asetrate=${(44100 * ratio).round()}');
      f.add('aresample=44100');
      f.add('atempo=${(1 / ratio).toStringAsFixed(5)}');
    }
    if (c.bass.abs() > 0.01) f.add('bass=g=${c.bass.toStringAsFixed(1)}');
    if (c.treble.abs() > 0.01) f.add('treble=g=${c.treble.toStringAsFixed(1)}');
    return f.isEmpty ? '' : 'lavfi=[${f.join(',')}]';
  }

  double _gainAt(_Voice v, int ph) {
    final c = v.clip!;
    var gain = c.volume * v.trackGain;
    if (c.normalize) {
      _measureNormalize(c);
      final db = normalizeGains[c.path] ?? 0;
      gain *= pow(10, db / 20).toDouble();
    }
    final local = ph - c.startMs;
    if (c.fadeInMs > 0 && local < c.fadeInMs) {
      gain *= (local / c.fadeInMs).clamp(0.0, 1.0);
    }
    final remaining = c.endMs - ph;
    if (c.fadeOutMs > 0 && remaining < c.fadeOutMs) {
      gain *= (remaining / c.fadeOutMs).clamp(0.0, 1.0);
    }
    return gain.clamp(0.0, 4.0).toDouble();
  }

  void _applyParams(_Voice v, int ph) {
    final player = v.player;
    final clip = v.clip;
    if (player == null || clip == null || v.openedKey == null) return;
    final volume = _gainAt(v, ph) * 100;
    if ((volume - v.appliedVolume).abs() > 0.4) {
      v.appliedVolume = volume;
      unawaited(player.setVolume(volume).catchError((Object _) {}));
    }
    if ((clip.speed - v.appliedRate).abs() > 0.0005) {
      v.appliedRate = clip.speed;
      unawaited(player.setRate(clip.speed).catchError((Object _) {}));
    }
    final filter = _filterFor(clip);
    if (filter != v.appliedFilter) {
      v.appliedFilter = filter;
      final native = player.platform;
      if (native is NativePlayer) {
        unawaited(native.setProperty('af', filter).catchError((Object _) {}));
      }
    }
  }

  bool _audible(_Voice v) {
    final c = v.clip;
    return c != null && !c.muted && v.trackGain > 0;
  }

  void sync() {
    if (disposed) return;
    final alive = <String>{};
    for (final track in tracks) {
      for (final clip in track.clips) {
        alive.add(clip.id);
        final voice = voices[clip.id];
        if (voice == null) continue;
        final previous = voice.clip;
        voice.clip = clip;
        voice.trackGain = track.muted ? 0 : track.volume;
        if (previous != null) {
          final geometry = previous.startMs != clip.startMs ||
              previous.inMs != clip.inMs ||
              previous.outMs != clip.outMs ||
              previous.speed != clip.speed;
          if (geometry) voice.needsAlign = true;
          if (voice.openedKey != null && voice.openedKey != voice.wantedKey) {
            voice.playing = false;
            voice.prepared = false;
            unawaited(voice.player?.pause());
            voice.readying = null;
            unawaited(_open(voice));
          }
        }
        _applyParams(voice, playhead.value);
      }
    }
    final stale = voices.keys.where((id) => !alive.contains(id)).toList();
    for (final id in stale) {
      final voice = voices.remove(id);
      if (voice != null) unawaited(_dispose(voice));
    }
    _balance(playing ? nowMs : playhead.value);
  }

  void _balance(int ph) {
    final entries = <(AudioClip, TimelineTrack, int)>[];
    for (final track in tracks) {
      for (final clip in track.clips) {
        int distance;
        if (ph >= clip.startMs && ph < clip.endMs) {
          distance = 0;
        } else if (clip.startMs > ph) {
          distance = clip.startMs - ph;
        } else {
          distance = ph - clip.endMs;
        }
        entries.add((clip, track, distance));
      }
    }
    entries.sort((a, b) => a.$3.compareTo(b.$3));
    final keep = entries.take(maxVoices).map((e) => e.$1.id).toSet();
    for (final entry in entries.take(maxVoices)) {
      final clip = entry.$1;
      var voice = voices[clip.id];
      if (voice == null) {
        voice = _Voice(clip.id)
          ..clip = clip
          ..trackGain = entry.$2.muted ? 0 : entry.$2.volume;
        voices[clip.id] = voice;
        unawaited(_open(voice));
      }
    }
    final drop = voices.keys.where((id) => !keep.contains(id)).toList();
    for (final id in drop) {
      final voice = voices.remove(id);
      if (voice != null) unawaited(_dispose(voice));
    }
  }

  Future<void> _dispose(_Voice v) async {
    final player = v.player;
    v.player = null;
    v.clip = null;
    try {
      await player?.dispose();
    } catch (_) {}
  }

  Future<void> _prepare(_Voice v) async {
    v.busy = true;
    try {
      if (!await _open(v)) return;
      final player = v.player;
      if (player == null || v.clip == null) return;
      await player.seek(Duration(milliseconds: v.sourceMsAt(v.clip!.startMs)));
      v.prepared = true;
    } finally {
      v.busy = false;
    }
  }

  Future<void> _begin(_Voice v) async {
    v.busy = true;
    try {
      if (!await _open(v)) return;
      final player = v.player;
      final clip = v.clip;
      if (player == null || clip == null) return;
      final ph = nowMs;
      if (ph >= clip.endMs) return;
      if (!v.prepared || ph - clip.startMs > 60) {
        final target = v.sourceMsAt(ph + (v.prepared ? 0 : leadMs));
        await player.seek(Duration(milliseconds: max(0, target)));
      }
      _applyParams(v, ph);
      await player.play();
      v.playing = true;
      v.prepared = false;
      v.needsAlign = false;
      v.lastAlignMs = ph;
    } finally {
      v.busy = false;
    }
  }

  Future<void> _halt(_Voice v) async {
    v.playing = false;
    v.prepared = false;
    try {
      await v.player?.pause();
    } catch (_) {}
  }

  void _reconcile(_Voice v, int ph) {
    final clip = v.clip;
    if (clip == null || v.busy) return;
    final inside = ph >= clip.startMs && ph < clip.endMs;
    if (!inside || !_audible(v)) {
      if (v.playing) {
        unawaited(_halt(v));
      } else if (!v.prepared &&
          _audible(v) &&
          clip.startMs > ph &&
          clip.startMs - ph < 1500) {
        unawaited(_prepare(v));
      }
      return;
    }
    if (!v.playing) {
      unawaited(_begin(v));
      return;
    }
    _applyParams(v, ph);
    final due = v.needsAlign ? 80 : 500;
    if (ph - v.lastAlignMs < due) return;
    v.lastAlignMs = ph;
    v.needsAlign = false;
    final player = v.player;
    if (player == null) return;
    final expected = v.sourceMsAt(ph);
    final actual = player.state.position.inMilliseconds;
    if ((actual - expected).abs() > 180) {
      unawaited(player.seek(Duration(milliseconds: max(0, expected))));
    }
  }

  void _tick() {
    if (!playing || disposed) return;
    final ph = nowMs;
    final end = projectEnd;
    if (end <= 0 || ph >= end) {
      unawaited(_finish(end));
      return;
    }
    playhead.value = ph;
    for (final v in voices.values.toList()) {
      _reconcile(v, ph);
    }
    if (ph - lastBalanceMs > 400) {
      lastBalanceMs = ph;
      _balance(ph);
    }
  }

  Future<void> _finish(int end) async {
    if (!playing) return;
    playing = false;
    ticker?.cancel();
    clock.stop();
    baseMs = end;
    playhead.value = end;
    await Future.wait(voices.values.toList().map(_halt));
    onStateChanged();
  }

  Future<void> play(int fromMs) async {
    if (playing || disposed) return;
    final end = projectEnd;
    if (end <= 0) return;
    baseMs = fromMs >= end - 30 ? 0 : fromMs;
    clock
      ..reset()
      ..start();
    playing = true;
    playhead.value = baseMs;
    _balance(baseMs);
    lastBalanceMs = baseMs;
    ticker?.cancel();
    ticker = Timer.periodic(const Duration(milliseconds: 16), (_) => _tick());
    onStateChanged();
    _tick();
  }

  Future<void> pause() async {
    if (!playing) return;
    final ph = nowMs;
    playing = false;
    ticker?.cancel();
    clock.stop();
    baseMs = ph;
    playhead.value = min(ph, projectEnd);
    await Future.wait(voices.values.toList().map(_halt));
    onStateChanged();
  }

  Future<void> seek(int ms) async {
    baseMs = ms;
    clock.reset();
    if (playing) clock.start();
    playhead.value = ms;
    lastBalanceMs = -100000;
    for (final v in voices.values.toList()) {
      v.prepared = false;
      if (v.playing) unawaited(_halt(v));
    }
    if (!playing) _balance(ms);
  }

  Future<void> dispose() async {
    disposed = true;
    ticker?.cancel();
    final all = voices.values.toList();
    voices.clear();
    await Future.wait(all.map(_dispose));
  }
}
