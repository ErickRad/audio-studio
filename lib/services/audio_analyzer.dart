import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app_log.dart';
import 'ffmpeg_runner.dart';

class AudioAnalysis {
  static const int blockMs = 100;
  static const int anchorStepMs = 4000;

  final double bpm;
  final double confidence;
  final int durationMs;
  final int firstSoundMs;
  final int lastSoundMs;
  final List<int> blocks;
  final List<int> anchors;
  final List<int> beatTimes;
  final double beatConfidence;
  final double tempoStability;
  final double loudnessLufs;
  final double truePeakDb;
  final double features;

  const AudioAnalysis({
    required this.bpm,
    required this.confidence,
    required this.durationMs,
    required this.firstSoundMs,
    required this.lastSoundMs,
    required this.blocks,
    required this.anchors,
    this.beatTimes = const [],
    this.beatConfidence = 0,
    this.tempoStability = 0,
    this.loudnessLufs = -70,
    this.truePeakDb = -90,
    this.features = 0,
  });

  bool get reliable =>
      bpm >= 60 &&
      bpm <= 200 &&
      confidence >= 0.12 &&
      (beatTimes.isNotEmpty || anchors.isNotEmpty);

  double get periodMs => bpm > 0 ? 60000 / bpm : 0;

  int anchorFor(int ms) {
    if (anchors.isEmpty) return ms;
    final index = ((ms - anchorStepMs) / anchorStepMs)
        .round()
        .clamp(0, anchors.length - 1)
        .toInt();
    return anchors[index];
  }

  int nearestBeat(int ms) {
    if (beatTimes.isEmpty) return anchorFor(ms);
    var lo = 0;
    var hi = beatTimes.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (beatTimes[mid] < ms) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    if (lo == 0) return beatTimes.first;
    final before = beatTimes[lo - 1];
    final after = beatTimes[lo];
    return (ms - before).abs() <= (after - ms).abs() ? before : after;
  }

  int snapNearest(int ms) {
    if (!reliable || periodMs <= 0) return ms;
    if (beatTimes.length >= 3) return nearestBeat(ms);
    final a = anchorFor(ms);
    final k = ((ms - a) / periodMs).round();
    return max(0, (a + k * periodMs).round());
  }

  int snapBackward(int ms) {
    if (!reliable || periodMs <= 0) return ms;
    if (beatTimes.isNotEmpty) {
      var candidate = beatTimes.first;
      for (final beat in beatTimes) {
        if (beat > ms) break;
        candidate = beat;
      }
      return candidate;
    }
    final a = anchorFor(ms);
    final k = ((ms - a) / periodMs).floor();
    return max(0, (a + k * periodMs).round());
  }

  int snapForward(int ms) {
    if (!reliable || periodMs <= 0) return ms;
    if (beatTimes.isNotEmpty) {
      for (final beat in beatTimes) {
        if (beat >= ms) return beat;
      }
      return beatTimes.last;
    }
    final a = anchorFor(ms);
    final k = ((ms - a) / periodMs).ceil();
    return max(0, (a + k * periodMs).round());
  }

  double rmsDb(int fromMs, int toMs) {
    if (blocks.isEmpty || toMs <= fromMs) return -90;
    final start = max(0, fromMs ~/ blockMs);
    final end = min(blocks.length, (toMs / blockMs).ceil());
    if (end <= start) return -90;
    var power = 0.0;
    for (var i = start; i < end; i++) {
      final v = blocks[i] / 10000.0;
      power += v * v;
    }
    power /= (end - start);
    return 10 * (log(power + 1e-9) / ln10);
  }

  Map<String, dynamic> toJson() => {
        'bpm': bpm,
        'confidence': confidence,
        'durationMs': durationMs,
        'firstSoundMs': firstSoundMs,
        'lastSoundMs': lastSoundMs,
        'blocks': blocks,
        'anchors': anchors,
        'beatTimes': beatTimes,
        'beatConfidence': beatConfidence,
        'tempoStability': tempoStability,
        'loudnessLufs': loudnessLufs,
        'truePeakDb': truePeakDb,
        'features': features
      };

  factory AudioAnalysis.fromJson(Map<String, dynamic> json) => AudioAnalysis(
        bpm: (json['bpm'] as num?)?.toDouble() ?? 0,
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
        durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
        firstSoundMs: (json['firstSoundMs'] as num?)?.toInt() ?? 0,
        lastSoundMs: (json['lastSoundMs'] as num?)?.toInt() ?? 0,
        blocks: (json['blocks'] as List? ?? const []).map((e) => (e as num).toInt()).toList(),
        anchors: (json['anchors'] as List? ?? const []).map((e) => (e as num).toInt()).toList(),
        beatTimes: (json['beatTimes'] as List? ?? const []).map((e) => (e as num).toInt()).toList(),
        beatConfidence: (json['beatConfidence'] as num?)?.toDouble() ?? 0,
        tempoStability: (json['tempoStability'] as num?)?.toDouble() ?? 0,
        loudnessLufs: (json['loudnessLufs'] as num?)?.toDouble() ?? -70,
        truePeakDb: (json['truePeakDb'] as num?)?.toDouble() ?? -90,
        features: (json['features'] as num?)?.toDouble() ?? 0,
      );
}

double _median(List<double> values) {
  if (values.isEmpty) return 0;
  final sorted = [...values]..sort();
  final mid = sorted.length ~/ 2;
  return sorted.length.isOdd ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
}

List<double> _linearRegression(List<double> xs, List<double> ys) {
  if (xs.length != ys.length || xs.length < 2) return [0, 0, 0];
  final mx = xs.reduce((a, b) => a + b) / xs.length;
  final my = ys.reduce((a, b) => a + b) / ys.length;
  var xx = 0.0, xy = 0.0, yy = 0.0;
  for (var i = 0; i < xs.length; i++) {
    final dx = xs[i] - mx;
    xx += dx * dx;
    xy += dx * (ys[i] - my);
    yy += (ys[i] - my) * (ys[i] - my);
  }
  if (xx <= 1e-12) return [0, my, 0];
  final slope = xy / xx;
  final intercept = my - slope * mx;
  var residual = 0.0;
  for (var i = 0; i < xs.length; i++) {
    final error = ys[i] - (slope * xs[i] + intercept);
    residual += error * error;
  }
  final r2 = yy <= 1e-12 ? 0.0 : (1 - residual / yy).clamp(0.0, 1.0).toDouble();
  return [slope, intercept, r2];
}

Map<String, dynamic> analyzeSamples(Uint8List bytes) {
  const sr = 11025;
  const hop = 128;
  const fps = sr / hop;
  final data = ByteData.sublistView(bytes);
  final n = bytes.lengthInBytes ~/ 2;
  final durationMs = (n * 1000 / sr).round();
  const blockSize = sr ~/ 10;

  final blocks = <int>[];
  var totalSquares = 0.0;
  var peak = 0.0;
  for (var i = 0; i < n; i += blockSize) {
    final end = min(i + blockSize, n);
    var sum = 0.0;
    for (var j = i; j < end; j++) {
      final v = data.getInt16(j * 2, Endian.little) / 32768.0;
      sum += v * v;
      totalSquares += v * v;
      peak = max(peak, v.abs());
    }
    blocks.add((sqrt(sum / max(1, end - i)) * 10000).round());
  }

  const silence = 56;
  var first = 0;
  while (first < blocks.length && blocks[first] < silence) {
    first++;
  }
  var last = blocks.length - 1;
  while (last > first && blocks[last] < silence) {
    last--;
  }
  final allSilent = first >= blocks.length;
  final firstSoundMs = allSilent ? 0 : max(0, first * 100 - 80);
  final lastSoundMs = allSilent ? durationMs : min(durationMs, (last + 1) * 100 + 80);
  final rms = n == 0 ? 0.0 : sqrt(totalSquares / n);
  // This is an RMS-based loudness proxy, not standards-compliant EBU R128 LUFS.
  final loudnessLufs = rms > 1e-8 ? 20 * log(rms) / ln10 - 0.691 : -70.0;
  final truePeakDb = peak > 1e-8 ? 20 * log(peak) / ln10 : -90.0;

  final frames = n ~/ hop;
  var bpm = 0.0;
  var confidence = 0.0;
  var beatConfidence = 0.0;
  var tempoStability = 0.0;
  final anchors = <int>[];
  final beatTimes = <int>[];

  const minBpm = 60.0;
  const maxBpm = 200.0;
  final minLag = (60 * fps / maxBpm).floor();
  final maxLag = (60 * fps / minBpm).ceil();

  if (frames > maxLag * 6) {
    final energy = List<double>.filled(frames, 0);
    final flux = List<double>.filled(frames, 0);
    for (var f = 0; f < frames; f++) {
      var sum = 0.0;
      for (var j = f * hop; j < min(n, f * hop + hop); j++) {
        final v = data.getInt16(j * 2, Endian.little) / 32768.0;
        sum += v * v;
      }
      energy[f] = log(1 + 50 * sqrt(sum / hop));
      if (f > 0) flux[f] = max(0.0, energy[f] - energy[f - 1]);
    }

    // Local-mean subtraction emphasizes attacks over sustained loudness.
    const window = 32;
    final prefix = List<double>.filled(frames + 1, 0);
    for (var f = 0; f < frames; f++) {
      prefix[f + 1] = prefix[f] + flux[f];
    }
    final env = List<double>.filled(frames, 0);
    for (var f = 0; f < frames; f++) {
      final lo = max(0, f - window);
      final hi = min(frames, f + window + 1);
      final mean = (prefix[hi] - prefix[lo]) / (hi - lo);
      env[f] = max(0.0, flux[f] - mean);
    }

    // Normalize the onset envelope so quiet passages still contribute.
    final envMean = env.reduce((a, b) => a + b) / max(1, env.length);
    var envPower = 0.0;
    for (final v in env) {
      envPower += v * v;
    }
    final acf0 = envPower / max(1, frames);

    if (acf0 > 1e-12) {
      final acf = List<double>.filled(maxLag + 2, 0);
      for (var lag = max(1, minLag - 1); lag <= maxLag + 1; lag++) {
        var sum = 0.0;
        final count = frames - lag;
        for (var i = 0; i < count; i++) {
          sum += env[i] * env[i + lag];
        }
        acf[lag] = count > 0 ? sum / count : 0;
      }

      // Score candidate tempos with local autocorrelation plus harmonic support.
      final candidates = <MapEntry<int, double>>[];
      for (var lag = minLag; lag <= maxLag; lag++) {
        if (acf[lag] < acf[lag - 1] || acf[lag] < acf[lag + 1]) continue;
        var score = acf[lag] / acf0;
        final halfLag = (lag / 2).round();
        final doubleLag = lag * 2;
        if (halfLag >= minLag && halfLag <= maxLag) score += 0.18 * acf[halfLag] / acf0;
        if (doubleLag <= maxLag) score += 0.12 * acf[doubleLag] / acf0;
        candidates.add(MapEntry(lag, score));
      }
      candidates.sort((a, b) => b.value.compareTo(a.value));

      if (candidates.isNotEmpty) {
        final bestLag = candidates.first.key;
        final y0 = acf[bestLag - 1];
        final y1 = acf[bestLag];
        final y2 = acf[bestLag + 1];
        final denom = y0 - 2 * y1 + y2;
        final delta = denom.abs() < 1e-12 ? 0.0 : (0.5 * (y0 - y2) / denom).clamp(-1.0, 1.0);
        final lagF = max(1.0, bestLag + delta);
        bpm = 60 * fps / lagF;
        confidence = (y1 / acf0).clamp(0.0, 1.0).toDouble();
        if (candidates.length > 1) {
          final second = candidates[1].value;
          confidence = (confidence * 0.75 + ((candidates.first.value - second) /
              max(1e-9, candidates.first.value)).clamp(0.0, 1.0) * 0.25);
        }

        // Detect onset peaks and use a phase search to build a beat grid.
        final periodFrames = 60 * fps / bpm;
        final minDistance = max(1, (periodFrames * 0.55).round());
        final peaks = <int>[];
        for (var i = 1; i < frames - 1; i++) {
          if (env[i] >= env[i - 1] && env[i] > env[i + 1] && env[i] > envMean * 1.4) {
            if (peaks.isEmpty || i - peaks.last >= minDistance) {
              peaks.add(i);
            } else if (env[i] > env[peaks.last]) {
              peaks[peaks.length - 1] = i;
            }
          }
        }

        // Search phase against onset peaks; no artificial 120 BPM preference.
        var bestPhase = 0.0;
        var bestPhaseScore = -1.0;
        final phaseSteps = max(8, periodFrames.round());
        for (var ph = 0; ph < phaseSteps; ph++) {
          var sum = 0.0;
          for (var t = ph.toDouble(); t < frames; t += periodFrames) {
            final center = t.round().clamp(0, frames - 1).toInt();
            var local = 0.0;
            for (var d = -2; d <= 2; d++) {
              final idx = center + d;
              if (idx >= 0 && idx < frames) local = max(local, env[idx]);
            }
            sum += local;
          }
          if (sum > bestPhaseScore) {
            bestPhaseScore = sum;
            bestPhase = ph.toDouble();
          }
        }

        // Keep beat times only where the source actually contains audio.
        for (var t = bestPhase; t < frames; t += periodFrames) {
          final ms = (t / fps * 1000).round();
          if (ms >= firstSoundMs && ms <= lastSoundMs) beatTimes.add(ms);
        }
        if (beatTimes.length >= 2) {
          final errors = <double>[];
          for (final peakFrame in peaks) {
            final peakMs = (peakFrame / fps * 1000);
            if (peakMs < firstSoundMs || peakMs > lastSoundMs) continue;
            final nearest = beatTimes.reduce((a, b) =>
                (a - peakMs).abs() < (b - peakMs).abs() ? a : b);
            errors.add((nearest - peakMs).abs());
          }
          final alignment = errors.isEmpty ? 0.0 : exp(-_median(errors) / max(1, periodFrames / fps * 1000 * 0.22));
          beatConfidence = (alignment * 0.65 + confidence * 0.35).clamp(0.0, 1.0);
        }

        const segmentFrames = 8 * fps;
        const stepFrames = 4 * fps;
        final segmentCount = max(1, ((frames - segmentFrames) / stepFrames).ceil() + 1);
        final localBpms = <double>[];
        final localTimes = <double>[];
        for (var s = 0; s < segmentCount; s++) {
          final start = (s * stepFrames).round();
          final end = min(frames, start + segmentFrames.round());
          if (end <= start) continue;
          var phase = bestPhase;
          var bestSum = -1.0;
          final phaseSpan = max(1, periodFrames.round());
          for (var ph = 0; ph < phaseSpan; ph++) {
            var sum = 0.0;
            for (var t = start + ph.toDouble(); t < end; t += periodFrames) {
              sum += env[t.round().clamp(start, end - 1).toInt()];
            }
            if (sum > bestSum) {
              bestSum = sum;
              phase = ph.toDouble();
            }
          }
          anchors.add(((start + phase) / fps * 1000).round());
          if (s > 0) {
            final xs = <double>[];
            final ys = <double>[];
            for (final bt in beatTimes) {
              if (bt >= start / fps * 1000 && bt <= end / fps * 1000) {
                xs.add(bt.toDouble());
                ys.add(bt.toDouble());
              }
            }
            if (xs.length >= 3) {
              // Regression over beat index vs time robustly estimates local period.
              final beatIndices = List<double>.generate(xs.length, (i) => i.toDouble());
              final reg = _linearRegression(beatIndices, ys);
              if (reg[0] > 0) {
                localBpms.add(60000 / reg[0]);
                localTimes.add((start + end) / 2 / fps * 1000);
              }
            }
          }
        }

        if (localBpms.length >= 2) {
          final med = _median(localBpms);
          final deviations = localBpms.map((v) => (v - med).abs()).toList();
          final mad = _median(deviations);
          tempoStability = (1 - mad / max(1, med * 0.08)).clamp(0.0, 1.0);
          // A significant linear trend means tempo changes systematically.
          final regression = _linearRegression(localTimes, localBpms);
          if (regression[2] > 0.55) {
            tempoStability = min(tempoStability, 0.75);
          }
        } else {
          tempoStability = confidence;
        }
      }
    }
  }

  return {
    'bpm': bpm,
    'confidence': confidence,
    'durationMs': durationMs,
    'firstSoundMs': firstSoundMs,
    'lastSoundMs': lastSoundMs,
    'blocks': blocks,
    'anchors': anchors,
    'beatTimes': beatTimes,
    'beatConfidence': beatConfidence,
    'tempoStability': tempoStability,
    'loudnessLufs': loudnessLufs,
    'truePeakDb': truePeakDb,
  };
}

Map<String, dynamic> decodeAnalysisCache(String text) =>
    jsonDecode(text) as Map<String, dynamic>;

String encodeAnalysisCache(Map<String, dynamic> data) => jsonEncode(data);

class AnalysisGate {
  static const int limit = 1;
  static int active = 0;
  static final List<Completer<void>> waiting = [];

  static Future<void> acquire() async {
    if (active < limit) {
      active++;
      return;
    }
    final c = Completer<void>();
    waiting.add(c);
    await c.future;
  }

  static void release() {
    if (waiting.isNotEmpty) {
      waiting.removeAt(0).complete();
    } else {
      active = max(0, active - 1);
    }
  }
}

class AudioAnalyzer {
  static const int maxEntries = 120;
  static final Map<String, AudioAnalysis> memory = {};
  static final Map<String, Future<AudioAnalysis?>> running = {};
  static Map<String, AudioAnalysis>? disk;
  static Timer? saveTimer;

  static Future<File> cacheFile() async {
    final base = await getApplicationDocumentsDirectory();
    return File(p.join(base.path, 'analysis_cache.json'));
  }

  static Future<void> loadDisk() async {
    if (disk != null) return;
    final loaded = <String, AudioAnalysis>{};
    try {
      final file = await cacheFile();
      if (await file.exists()) {
        final data = await compute(decodeAnalysisCache, await file.readAsString());
        data.forEach((key, value) {
          loaded[key] = AudioAnalysis.fromJson(value as Map<String, dynamic>);
        });
      }
    } catch (e) {
      AppLog.error('análise', e);
    }
    disk = loaded;
  }

  static void scheduleSave() {
    saveTimer?.cancel();
    saveTimer = Timer(const Duration(seconds: 1), () async {
      final entries = disk;
      if (entries == null) return;
      while (entries.length > maxEntries) {
        entries.remove(entries.keys.first);
      }
      try {
        final file = await cacheFile();
        final text = await compute(
          encodeAnalysisCache,
          entries.map((k, v) => MapEntry(k, v.toJson())),
        );
        await file.writeAsString(text);
      } catch (e) {
        AppLog.error('análise', e);
      }
    });
  }

  static Future<AudioAnalysis?> analyze(String path) async {
    final file = File(path);
    if (!await file.exists()) return null;
    final stat = await file.stat();
    final key = '$path|${stat.size}|${stat.modified.millisecondsSinceEpoch}|analysis-v3';
    final cached = memory[key];
    if (cached != null) return cached;
    final pending = running[key];
    if (pending != null) return pending;
    final task = compute_(path, key);
    running[key] = task;
    task.then((_) {
      running.remove(key);
    }, onError: (Object _) {
      running.remove(key);
    });
    return task;
  }

  static Future<AudioAnalysis?> compute_(String path, String key) async {
    await loadDisk();
    final stored = disk![key];
    if (stored != null) {
      memory[key] = stored;
      return stored;
    }
    await AnalysisGate.acquire();
    try {
      return await decode(path, key);
    } finally {
      AnalysisGate.release();
    }
  }

  static Future<AudioAnalysis?> decode(String path, String key) async {
    final stored = disk![key];
    if (stored != null) {
      memory[key] = stored;
      return stored;
    }
    final watch = Stopwatch()..start();
    final dir = await getTemporaryDirectory();
    final out = p.join(dir.path, 'analysis_${key.hashCode.toUnsigned(32)}.pcm');
    final ok = await FfmpegRunner.run([
      '-y', '-threads', '1', '-i', path, '-vn', '-ac', '1',
      '-ar', '11025', '-f', 's16le', out,
    ]);
    if (!ok) return null;
    final pcm = File(out);
    try {
      final bytes = await pcm.readAsBytes();
      if (bytes.lengthInBytes < 4000) return null;
      final result = await compute(analyzeSamples, bytes);
      final analysis = AudioAnalysis.fromJson(result);
      memory[key] = analysis;
      disk![key] = analysis;
      scheduleSave();
      AppLog.info(
        'análise',
        '${p.basename(path)}: ${analysis.bpm.toStringAsFixed(1)} BPM '
            '(confiança ${analysis.confidence.toStringAsFixed(2)}, '
            'batidas ${analysis.beatConfidence.toStringAsFixed(2)}, '
            'estabilidade ${analysis.tempoStability.toStringAsFixed(2)}) '
            'em ${watch.elapsedMilliseconds} ms',
      );
      return analysis;
    } catch (e, stack) {
      AppLog.error('análise', e, stack);
      return null;
    } finally {
      if (await pcm.exists()) await pcm.delete();
    }
  }
}
