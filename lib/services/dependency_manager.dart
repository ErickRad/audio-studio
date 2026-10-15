
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app_log.dart';

typedef DependencyProgress = void Function(
  String message,
  double progress,
);

class DependencyManager {
  DependencyManager._();

  static final DependencyManager instance = DependencyManager._();

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(minutes: 10),
      sendTimeout: const Duration(minutes: 2),
      followRedirects: true,
    ),
  );

  Directory? _binDirectory;
  bool _initialized = false;
  bool _initializing = false;

  String status = 'Dependências não verificadas';
  double progress = 0;

  final Map<String, String> _resolved = {};

  bool get isWindows => Platform.isWindows;
  bool get isLinux => Platform.isLinux;

  String get executableExtension => isWindows ? '.exe' : '';

  Future<Directory> get binDirectory async {
    if (_binDirectory != null) return _binDirectory!;

    final support = await getApplicationSupportDirectory();
    final dir = Directory(
      p.join(support.path, 'dependencies', 'bin'),
    );

    await dir.create(recursive: true);
    _binDirectory = dir;
    return dir;
  }

  String getExecutablePath(String name) {
    final resolved = _resolved[name];
    if (resolved != null) return resolved;

    final dir = _binDirectory;
    if (dir != null) {
      return p.join(dir.path, '$name$executableExtension');
    }

    return '$name$executableExtension';
  }

  Future<String?> _findSystemExecutable(String name) async {
    final executable = '$name$executableExtension';

    try {
      final result = await Process.run(
        isWindows ? 'where.exe' : 'which',
        [executable],
      );

      if (result.exitCode != 0) return null;

      final lines = '${result.stdout}'
          .split(RegExp(r'\r?\n'))
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty);

      for (final line in lines) {
        final file = File(line);
        if (await file.exists() && await _works(line, name)) {
          return line;
        }
      }
    } catch (_) {}

    return null;
  }

  Future<bool> _works(String path, String name) async {
    try {
      final result = await Process.run(
        path,
        name == 'ffmpeg' || name == 'ffprobe'
            ? ['-version']
            : ['--version'],
      );

      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  Future<void> initialize({
    DependencyProgress? onProgress,
  }) async {
    if (_initialized) return;
    if (_initializing) {
      while (_initializing) {
        await Future<void>.delayed(
          const Duration(milliseconds: 100),
        );
      }
      return;
    }

    _initializing = true;

    try {
      if (!Platform.isLinux && !Platform.isWindows) {
        throw UnsupportedError(
          'Audio Studio ainda não oferece instalação automática '
          'de dependências para ${Platform.operatingSystem}.',
        );
      }

      if (Abi.current() != Abi.windowsX64 && Abi.current() != Abi.linuxX64) {
        throw UnsupportedError(
          'A instalação automática está configurada para x86-64. '
          'Arquitetura atual: ${Abi.current()}.',
        );
      }

      final bin = await binDirectory;

      final required = <String>['ffmpeg', 'ffprobe', 'yt-dlp'];

      for (var i = 0; i < required.length; i++) {
        final name = required[i];
        final target = File(
          p.join(bin.path, '$name$executableExtension'),
        );

        if (await target.exists() && await _works(target.path, name)) {
          _resolved[name] = target.path;
          continue;
        }

        final systemPath = await _findSystemExecutable(name);
        if (systemPath != null) {
          _resolved[name] = systemPath;
          continue;
        }

        status = 'Preparando $name';
        progress = i / required.length;
        onProgress?.call(status, progress);

        if (name == 'yt-dlp') {
          await _installYtDlp(target, onProgress);
        } else {
          await _installFfmpeg(bin, name, onProgress);
        }

        if (!await target.exists() || !await _works(target.path, name)) {
          throw Exception(
            'O executável $name foi instalado, mas não passou na verificação.',
          );
        }

        _resolved[name] = target.path;
      }

      _initialized = true;
      status = 'Dependências prontas';
      progress = 1;
      onProgress?.call(status, progress);

      AppLog.info(
        'dependencies',
        'FFmpeg: ${_resolved['ffmpeg']}',
      );
      AppLog.info(
        'dependencies',
        'FFprobe: ${_resolved['ffprobe']}',
      );
      AppLog.info(
        'dependencies',
        'yt-dlp: ${_resolved['yt-dlp']}',
      );
    } catch (e, stack) {
      status = 'Falha ao preparar dependências';
      AppLog.error('dependencies', e, stack);
      rethrow;
    } finally {
      _initializing = false;
    }
  }

  Future<String> _download(
    String url,
    String destination, {
    DependencyProgress? onProgress,
    String label = 'Baixando',
  }) async {
    final file = File(destination);
    await file.parent.create(recursive: true);

    final partial = File('$destination.part');
    if (await partial.exists()) {
      await partial.delete();
    }

    try {
      await _dio.download(
        url,
        partial.path,
        deleteOnError: true,
        onReceiveProgress: (received, total) {
          final fraction = total > 0 ? received / total : 0.0;
          status = '$label: ${(fraction * 100).toStringAsFixed(0)}%';
          progress = fraction.clamp(0.0, 1.0);
          onProgress?.call(status, progress);
        },
      );

      if (!await partial.exists() ||
          await partial.length() == 0) {
        throw Exception('O download retornou um arquivo vazio.');
      }

      if (await file.exists()) {
        await file.delete();
      }

      await partial.rename(file.path);
      return file.path;
    } catch (_) {
      if (await partial.exists()) {
        await partial.delete();
      }
      rethrow;
    }
  }

  Future<String> _downloadText(String url) async {
    final response = await _dio.get<String>(
      url,
      options: Options(responseType: ResponseType.plain),
    );

    final body = response.data;
    if (response.statusCode != 200 || body == null) {
      throw Exception('Não foi possível obter o arquivo de checksums.');
    }

    return body;
  }

  Future<void> _verifySha256(
    File file,
    String checksumUrl,
    String expectedFilename,
  ) async {
    final checksums = await _downloadText(checksumUrl);

    String? expected;

    for (final line in const LineSplitter().convert(checksums)) {
      final match = RegExp(
        r'^([a-fA-F0-9]{64})\s+\*?(.+?)\s*$',
      ).firstMatch(line);

      if (match == null) continue;

      final filename = p.basename(match.group(2)!.trim());

      if (filename == expectedFilename) {
        expected = match.group(1)!.toLowerCase();
        break;
      }
    }

    if (expected == null) {
      throw Exception(
        'O checksum oficial não contém $expectedFilename.',
      );
    }

    final actual = (await sha256.bind(file.openRead()).first).toString();

    if (actual.toLowerCase() != expected) {
      throw Exception(
        'Checksum inválido para $expectedFilename. '
        'O arquivo foi rejeitado.',
      );
    }
  }

  Future<void> _installYtDlp(
    File target,
    DependencyProgress? onProgress,
  ) async {
    final filename = isWindows ? 'yt-dlp.exe' : 'yt-dlp_linux';

    final base =
        'https://github.com/yt-dlp/yt-dlp/releases/latest/download/';

    final download = await _download(
      '$base$filename',
      '${target.path}.download',
      onProgress: onProgress,
      label: 'Baixando yt-dlp',
    );

    final downloaded = File(download);

    try {
      await _verifySha256(
        downloaded,
        '${base}SHA2-256SUMS',
        filename,
      );

      if (await target.exists()) await target.delete();
      await downloaded.rename(target.path);

      if (isLinux) {
        final chmod = await Process.run(
          'chmod',
          ['755', target.path],
        );

        if (chmod.exitCode != 0) {
          throw Exception('Não foi possível tornar yt-dlp executável.');
        }
      }
    } catch (_) {
      if (await downloaded.exists()) await downloaded.delete();
      rethrow;
    }
  }

  Future<void> _installFfmpeg(
    Directory bin,
    String requestedExecutable,
    DependencyProgress? onProgress,
  ) async {
    final filename = isWindows
        ? 'ffmpeg-master-latest-win64-gpl.zip'
        : 'ffmpeg-master-latest-linux64-gpl.tar.xz';

    final checksumName = 'checksums.sha256';

    const base =
        'https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/';

    final archiveFile = File(
      p.join(bin.path, 'ffmpeg_bundle${isWindows ? '.zip' : '.tar.xz'}'),
    );

    await _download(
      '$base$filename',
      archiveFile.path,
      onProgress: onProgress,
      label: 'Baixando FFmpeg',
    );

    final staging = Directory(
      p.join(bin.path, 'ffmpeg_staging'),
    );

    if (await staging.exists()) {
      await staging.delete(recursive: true);
    }
    await staging.create(recursive: true);

    try {
      await _verifySha256(
        archiveFile,
        '$base$checksumName',
        filename,
      );

      if (isWindows) {
        final escapedArchive = archiveFile.path.replaceAll("'", "''");
        final escapedStaging = staging.path.replaceAll("'", "''");

        final result = await Process.run('powershell.exe', [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          'Expand-Archive -LiteralPath \'$escapedArchive\' '
              '-DestinationPath \'$escapedStaging\' -Force',
        ]);

        if (result.exitCode != 0) {
          throw Exception(
            'Falha ao extrair FFmpeg: ${result.stderr}',
          );
        }
      } else {
        final result = await Process.run(
          'tar',
          ['-xJf', archiveFile.path, '-C', staging.path],
        );

        if (result.exitCode != 0) {
          throw Exception(
            'Falha ao extrair FFmpeg. '
            'Verifique se tar e xz estão disponíveis: ${result.stderr}',
          );
        }
      }

      final wantedNames = isWindows
          ? ['ffmpeg.exe', 'ffprobe.exe']
          : ['ffmpeg', 'ffprobe'];

      final found = <String, File>{};

      await for (final entity
          in staging.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;

        final name = p.basename(entity.path);
        if (wantedNames.contains(name)) {
          found[name] = entity;
        }
      }

      for (final name in wantedNames) {
        if (!found.containsKey(name)) {
          throw Exception('O pacote do FFmpeg não contém $name.');
        }
      }

      for (final name in wantedNames) {
        final destination = File(p.join(bin.path, name));
        if (await destination.exists()) await destination.delete();
        await found[name]!.copy(destination.path);

        if (isLinux) {
          final chmod = await Process.run(
            'chmod',
            ['755', destination.path],
          );

          if (chmod.exitCode != 0) {
            throw Exception('Não foi possível tornar $name executável.');
          }
        }
      }

      final installed = File(
        p.join(bin.path, '$requestedExecutable$executableExtension'),
      );

      if (!await installed.exists()) {
        throw Exception('Não foi possível instalar $requestedExecutable.');
      }
    } finally {
      if (await archiveFile.exists()) {
        await archiveFile.delete();
      }
      if (await staging.exists()) {
        await staging.delete(recursive: true);
      }
    }
  }

  Future<String> resolve(String name) async {
    await initialize();

    final path = _resolved[name];
    if (path == null) {
      throw StateError('Dependência não resolvida: $name');
    }

    return path;
  }

  Future<Map<String, String>> diagnostics() async {
    final result = <String, String>{};

    for (final name in ['ffmpeg', 'ffprobe', 'yt-dlp']) {
      try {
        final path = await resolve(name);
        final version = await Process.run(
          path,
          name == 'ffmpeg' || name == 'ffprobe'
              ? ['-version']
              : ['--version'],
        );

        result[name] = version.exitCode == 0
            ? '${'${version.stdout}'.split('\n').first} ($path)'
            : 'Falha ao executar: $path';
      } catch (e) {
        result[name] = 'Indisponível: $e';
      }
    }

    return result;
  }

  void dispose() {
    _dio.close(force: true);
  }
}
