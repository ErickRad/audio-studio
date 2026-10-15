import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/audio_formats.dart';
import '../models/clip.dart';
import '../models/timeline_track.dart';
import 'ffmpeg_runner.dart';

class AudioEngine {
  static const int peakMs = 20;
  static const String conform = 'aresample=44100,aformat=sample_fmts=fltp:channel_layouts=stereo';

  static String sec(num ms) => (ms / 1000).toStringAsFixed(3);

  static Future<List<double>> computePeaks(String path) async {
    final dir = await getTemporaryDirectory();
    final out = p.join(dir.path, 'peaks_${path.hashCode}.pcm');
    final ok = await FfmpegRunner.run([
      '-y',
      '-i',
      path,
      '-vn',
      '-ac',
      '1',
      '-ar',
      '8000',
      '-f',
      's16le',
      out,
    ]);
    if (!ok) return [];
    final file = File(out);
    final bytes = await file.readAsBytes();
    await file.delete();
    final view = ByteData.sublistView(bytes);
    final total = bytes.lengthInBytes ~/ 2;
    const bucket = 8 * peakMs;
    final result = <double>[];
    for (var i = 0; i < total; i += bucket) {
      var maxAbs = 0;
      final end = min(i + bucket, total);
      for (var j = i; j < end; j++) {
        final v = view.getInt16(j * 2, Endian.little).abs();
        if (v > maxAbs) maxAbs = v;
      }
      result.add(maxAbs / 32768.0);
    }
    return result;
  }

  static List<String> codecArgs(ExportOptions o) {
    final args = <String>[];
    final bitrate = '${o.bitrateK}k';
    switch (o.formatId) {
      case 'mp3':
        args.addAll(['-c:a', 'libmp3lame', '-b:a', bitrate]);
        break;
      case 'aac':
        args.addAll(['-c:a', 'aac', '-b:a', bitrate]);
        break;
      case 'ogg':
        args.addAll(['-c:a', 'libvorbis', '-b:a', bitrate]);
        break;
      case 'opus':
        args.addAll(['-c:a', 'libopus', '-b:a', bitrate]);
        break;
      case 'flac':
        args.addAll(['-c:a', 'flac']);
        break;
      default:
        args.addAll(['-c:a', 'pcm_s16le']);
    }
    if (o.sampleRate > 0) {
      args.addAll(['-ar', '${o.sampleRate}']);
    } else if (o.formatId == 'opus') {
      args.addAll(['-ar', '48000']);
    }
    if (o.channels > 0) args.addAll(['-ac', '${o.channels}']);
    return args;
  }

  static Future<bool> convert(String inPath, String outPath, ExportOptions o) {
    return FfmpegRunner.run(['-y', '-i', inPath, '-vn', ...codecArgs(o), outPath]);
  }

  static void addTempo(List<String> filters, double tempo) {
    var t = tempo;
    while (t > 2.0) {
      filters.add('atempo=2.0');
      t /= 2.0;
    }
    while (t < 0.5) {
      filters.add('atempo=0.5');
      t /= 0.5;
    }
    if ((t - 1.0).abs() > 0.0005) filters.add('atempo=${t.toStringAsFixed(5)}');
  }

  static String clipChain(AudioClip c) {
    final f = <String>[
      'atrim=start=${sec(c.inMs)}:end=${sec(c.outMs)}',
      'asetpts=PTS-STARTPTS',
      conform,
    ];
    if (c.reversed) f.add('areverse');
    final ratio = pow(2, c.pitch / 12).toDouble();
    final pitched = c.pitch.abs() > 0.001;
    if (pitched) {
      f.add('asetrate=${(44100 * ratio).round()}');
      f.add('aresample=44100');
    }
    addTempo(f, pitched ? c.speed / ratio : c.speed);
    if (c.bass.abs() > 0.01) f.add('bass=g=${c.bass.toStringAsFixed(1)}');
    if (c.treble.abs() > 0.01) f.add('treble=g=${c.treble.toStringAsFixed(1)}');
    if (c.normalize) f.add('loudnorm=I=-16:TP=-1.5:LRA=11');
    if ((c.volume - 1).abs() > 0.001) f.add('volume=${c.volume.toStringAsFixed(3)}');
    final dur = c.durationMs;
    if (c.fadeInMs > 0) {
      f.add('afade=t=in:st=0:d=${sec(min(c.fadeInMs, dur))}');
    }
    if (c.fadeOutMs > 0) {
      final fo = min(c.fadeOutMs, dur);
      f.add('afade=t=out:st=${sec(dur - fo)}:d=${sec(fo)}');
    }
    f.add(conform);
    return f.join(',');
  }

  static List<String>? buildMixArgs(
    List<TimelineTrack> tracks,
    int totalMs,
    String outPath,
    ExportOptions? options,
  ) {
    final args = <String>['-y'];
    final filters = <String>[];
    final trackLabels = <String>[];
    final totalSec = sec(totalMs);
    var inputIndex = 0;
    for (var ti = 0; ti < tracks.length; ti++) {
      final track = tracks[ti];
      if (track.muted) continue;
      final clips = track.clips.where((c) => !c.muted).toList()
        ..sort((a, b) => a.startMs.compareTo(b.startMs));
      if (clips.isEmpty) continue;
      final segments = <String>[];
      var cursor = 0;
      for (var ci = 0; ci < clips.length; ci++) {
        final clip = clips[ci];
        final gap = clip.startMs - cursor;
        if (gap > 1) {
          final gapLabel = 'g${ti}_$ci';
          filters.add('anullsrc=r=44100:cl=stereo:d=${sec(gap)}[$gapLabel]');
          segments.add('[$gapLabel]');
        }
        final label = 'c${ti}_$ci';
        args.add('-i');
        args.add(clip.path);
        filters.add('[$inputIndex:a]${clipChain(clip)}[$label]');
        inputIndex++;
        segments.add('[$label]');
        cursor = clip.endMs;
      }
      final trackLabel = 't$ti';
      filters.add(
        '${segments.join()}concat=n=${segments.length}:v=0:a=1,apad=whole_dur=$totalSec,volume=${track.volume.toStringAsFixed(3)}[$trackLabel]',
      );
      trackLabels.add('[$trackLabel]');
    }
    if (trackLabels.isEmpty) return null;
    final n = trackLabels.length;
    if (n == 1) {
      filters.add('${trackLabels.first}alimiter=limit=0.95[out]');
    } else {
      filters.add(
        '${trackLabels.join()}amix=inputs=$n:duration=longest:dropout_transition=0,volume=$n,alimiter=limit=0.95[out]',
      );
    }
    args.addAll(['-filter_complex', filters.join(';'), '-map', '[out]', '-t', totalSec]);
    if (options == null) {
      args.addAll(['-c:a', 'pcm_s16le', '-ar', '44100', '-ac', '2']);
    } else {
      args.addAll(codecArgs(options));
    }
    args.add(outPath);
    return args;
  }
}
