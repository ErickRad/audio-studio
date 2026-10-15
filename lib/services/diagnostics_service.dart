import 'dart:async';
import 'dart:io';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'youtube_service.dart';

class DiagnosticResult {
  final String name;
  final bool ok;
  final String detail;

  const DiagnosticResult(this.name, this.ok, this.detail);
}

class DiagnosticsService {
  static const String testVideoId = 'jNQXAC9IVRw';

  static Future<String?> versionOf(String executable, List<String> args) async {
    try {
      final result = await Process.run(executable, args);
      if (result.exitCode != 0) return null;
      final out = '${result.stdout}'.trim();
      final text = out.isEmpty ? '${result.stderr}'.trim() : out;
      return text.isEmpty ? 'ok' : text.split('\n').first;
    } catch (_) {
      return null;
    }
  }

  static Future<List<DiagnosticResult>> run(YoutubeService youtube) async {
    final results = <DiagnosticResult>[];
    final ffmpeg = await versionOf('ffmpeg', ['-version']);
    results.add(DiagnosticResult('FFmpeg', ffmpeg != null, ffmpeg ?? 'não encontrado no PATH'));
    final ffprobe = await versionOf('ffprobe', ['-version']);
    results.add(DiagnosticResult('FFprobe', ffprobe != null, ffprobe ?? 'não encontrado no PATH'));
    final ytDlp = await versionOf('yt-dlp', ['--version']);
    results.add(
      DiagnosticResult(
        'yt-dlp',
        ytDlp != null,
        ytDlp ?? 'não encontrado (recomendado: pipx install yt-dlp)',
      ),
    );
    final deno = await versionOf('deno', ['--version']);
    final node = deno == null ? await versionOf('node', ['--version']) : null;
    results.add(
      DiagnosticResult(
        'Runtime JavaScript (usado pelo yt-dlp)',
        deno != null || node != null,
        deno ?? (node != null ? 'node $node' : 'deno ou nodejs não encontrado'),
      ),
    );
    if (Platform.isLinux) {
      var count = 0;
      try {
        final result = await Process.run('sh', ['-c', 'ldconfig -p 2>/dev/null | grep -c libmpv']);
        count = int.tryParse('${result.stdout}'.trim()) ?? 0;
      } catch (_) {}
      results.add(
        DiagnosticResult(
          'libmpv (reprodução de áudio)',
          count > 0,
          count > 0 ? 'encontrada' : 'não encontrada (sudo apt install libmpv-dev mpv)',
        ),
      );
    }
    results.add(await testExplode(youtube));
    if (ytDlp != null) results.add(await testYtDlp(youtube));
    return results;
  }

  static Future<DiagnosticResult> testExplode(YoutubeService youtube) async {
    const name = 'Download via youtube_explode';
    try {
      final manifest = await youtube.yt.videos.streamsClient
          .getManifest(testVideoId)
          .timeout(const Duration(seconds: 25));
      if (manifest.audioOnly.isEmpty) {
        return const DiagnosticResult(name, false, 'o manifesto não trouxe streams de áudio');
      }
      final info = manifest.audioOnly.withHighestBitrate();
      final chunk = await youtube.yt.videos.streamsClient
          .get(info)
          .first
          .timeout(const Duration(seconds: 25));
      return DiagnosticResult(name, true, 'ok (${chunk.length} bytes recebidos)');
    } catch (e) {
      return DiagnosticResult(name, false, youtube.describe(e));
    }
  }

  static Future<DiagnosticResult> testYtDlp(YoutubeService youtube) async {
    const name = 'Download via yt-dlp';
    try {
      final result = await Process.run('yt-dlp', [
        '--no-playlist',
        '-f',
        'bestaudio/best',
        '--simulate',
        'https://www.youtube.com/watch?v=$testVideoId',
      ]).timeout(const Duration(seconds: 60));
      if (result.exitCode == 0) return const DiagnosticResult(name, true, 'ok');
      final lines = '${result.stderr}'
          .trim()
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .toList();
      final tail = lines.length > 4 ? lines.sublist(lines.length - 4) : lines;
      return DiagnosticResult(
        name,
        false,
        tail.isEmpty ? 'código de saída ${result.exitCode}' : tail.join('\n'),
      );
    } catch (e) {
      return DiagnosticResult(name, false, youtube.describe(e));
    }
  }
}
