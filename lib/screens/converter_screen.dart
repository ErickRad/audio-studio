import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import '../models/audio_formats.dart';
import '../models/library_item.dart';
import '../services/audio_engine.dart';
import '../services/cover_service.dart';
import '../services/ffmpeg_runner.dart';
import '../services/storage_service.dart';
import '../services/system_service.dart';
import '../state/project_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/format_picker.dart';
import '../widgets/tutorial_overlay.dart';
import '../widgets/ui_kit.dart';

enum JobState { waiting, running, done, failed }

class ConvertJob {
  final String path;
  final String name;
  JobState state = JobState.waiting;
  String? output;
  String message = '';
  String coverPath = '';

  ConvertJob(this.path) : name = p.basenameWithoutExtension(path);
}

class ConverterScreen extends StatefulWidget {
  const ConverterScreen({super.key});

  @override
  State<ConverterScreen> createState() => _ConverterScreenState();
}

class _ConverterScreenState extends State<ConverterScreen> {
  final List<ConvertJob> jobs = [];
  ExportOptions options = const ExportOptions();
  String? outputDir;
  bool running = false;
  bool addToLibrary = true;

  @override
  void initState() {
    super.initState();
    StorageService.exportDir().then((d) {
      if (mounted) setState(() => outputDir = d.path);
    });
  }

  void addPaths(Iterable<String> paths, {String coverPath = ''}) {
    final added = <ConvertJob>[];
    setState(() {
      for (final path in paths) {
        if (jobs.any((j) => j.path == path)) continue;
        final job = ConvertJob(path)..coverPath = coverPath;
        jobs.add(job);
        added.add(job);
      }
    });
    for (final job in added) {
      if (job.coverPath.isNotEmpty) continue;
      CoverService.extractEmbedded(job.path).then((cover) {
        if (cover != null && mounted) setState(() => job.coverPath = cover);
      });
    }
  }

  Future<void> pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ProjectController.importExtensions,
      allowMultiple: true,
    );
    if (result == null) return;
    addPaths(result.files.map((f) => f.path).whereType<String>());
  }

  Future<void> pickOutputDir() async {
    final dir = await FilePicker.platform
        .getDirectoryPath(dialogTitle: 'Pasta de saída');
    if (dir != null && mounted) setState(() => outputDir = dir);
  }

  String uniquePath(String dir, String name, String ext) {
    var candidate = p.join(dir, '$name.$ext');
    var n = 2;
    while (File(candidate).existsSync()) {
      candidate = p.join(dir, '$name ($n).$ext');
      n++;
    }
    return candidate;
  }

  Future<void> convertAll() async {
    final dir = outputDir;
    if (running || dir == null) return;
    final project = context.read<ProjectController>();
    setState(() => running = true);
    for (final job in jobs) {
      if (job.state == JobState.done) continue;
      if (!mounted) return;
      setState(() {
        job.state = JobState.running;
        job.message = '';
      });
      final out = uniquePath(
          dir, StorageService.safeName(job.name), options.format.ext);
      final ok = await AudioEngine.convert(
        job.path,
        out,
        options,
        coverPath: job.coverPath,
        title: job.name,
      );
      if (!mounted) return;
      setState(() {
        job.state = ok ? JobState.done : JobState.failed;
        job.output = ok ? out : null;
        job.message = ok ? '' : FfmpegRunner.lastLog.split('\n').last;
      });
      if (ok && addToLibrary) {
        await project.addToLibrary(
          title: p.basenameWithoutExtension(out),
          artist: 'Convertido',
          path: out,
          coverPath: job.coverPath,
        );
      }
    }
    if (mounted) setState(() => running = false);
  }

  String subtitleFor(ConvertJob job) {
    switch (job.state) {
      case JobState.waiting:
        return 'Aguardando · ${p.extension(job.path).replaceFirst('.', '').toUpperCase()} para ${options.format.label}';
      case JobState.running:
        return 'Convertendo…';
      case JobState.done:
        final size = File(job.output!).lengthSync() / 1048576;
        return '${p.basename(job.output!)} · ${size.toStringAsFixed(2)} MB';
      case JobState.failed:
        return job.message.isEmpty
            ? 'Falha na conversão'
            : 'Falha: ${job.message}';
    }
  }

  Widget buildQueueToolbar(List<LibraryItem> library) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: AppColors.panel,
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        children: [
          AppButton(
              label: 'Adicionar arquivos',
              icon: Icons.add,
              onPressed: running ? null : pickFiles),
          const SizedBox(width: 8),
          PopupMenuButton<LibraryItem>(
            enabled: !running,
            tooltip: 'Adicionar da biblioteca',
            color: AppColors.raised,
            constraints: const BoxConstraints(
                minWidth: 280, maxWidth: 460, maxHeight: 420),
            onSelected: (item) =>
                addPaths([item.path], coverPath: item.coverPath),
            itemBuilder: (_) => library.isEmpty
                ? const [
                    PopupMenuItem<LibraryItem>(
                      enabled: false,
                      height: 32,
                      child: Text('Biblioteca vazia'),
                    ),
                  ]
                : [
                    for (final item in library)
                      PopupMenuItem<LibraryItem>(
                        value: item,
                        height: 32,
                        child: Row(
                          children: [
                            ThumbBox(filePath: item.coverPath, size: 24),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(item.title,
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                            ),
                          ],
                        ),
                      ),
                  ],
            child: Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppColors.line),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.library_music_outlined, size: 15),
                  SizedBox(width: 6),
                  Text('Da biblioteca',
                      style: TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          ),
          const Spacer(),
          AppButton(
            label: 'Limpar concluídos',
            onPressed: running || !jobs.any((j) => j.state == JobState.done)
                ? null
                : () => setState(
                    () => jobs.removeWhere((j) => j.state == JobState.done)),
          ),
        ],
      ),
    );
  }

  Widget buildJobRow(ConvertJob job) {
    return MediaRow(
      leading: SizedBox(
        width: 40,
        height: 40,
        child: Stack(
          children: [
            job.coverPath.isNotEmpty
                ? ThumbBox(filePath: job.coverPath)
                : Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.raised,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: const Icon(Icons.audio_file_outlined,
                        size: 18, color: AppColors.textDim),
                  ),
            if (job.state == JobState.done || job.state == JobState.failed)
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    color: Color(0xCC000000),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    job.state == JobState.done
                        ? Icons.check
                        : Icons.error_outline,
                    size: 12,
                    color: job.state == JobState.done
                        ? AppColors.accent
                        : AppColors.danger,
                  ),
                ),
              ),
          ],
        ),
      ),
      title: job.name,
      subtitle: subtitleFor(job),
      busy: job.state == JobState.running,
      actions: [
        if (job.state == JobState.done)
          ToolButton(
            icon: Icons.folder_open,
            tooltip: 'Mostrar na pasta',
            onPressed: () => SystemService.revealInFolder(job.output!),
          ),
        ToolButton(
          icon: Icons.close,
          tooltip: 'Remover da fila',
          onPressed: job.state == JobState.running
              ? null
              : () => setState(() => jobs.remove(job)),
        ),
      ],
    );
  }

  Widget buildOptionsPanel() {
    final pending = jobs.where((j) => j.state != JobState.done).length;
    return Container(
      key: TutorialKeys.converterOptions,
      width: 320,
      decoration: const BoxDecoration(
        color: AppColors.panel,
        border: Border(left: BorderSide(color: AppColors.line)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Saída',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          FormatPicker(
              options: options, onChanged: (o) => setState(() => options = o)),
          const SizedBox(height: 10),
          const Text('Pasta de destino',
              style: TextStyle(fontSize: 12, color: AppColors.textDim)),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  outputDir ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              const SizedBox(width: 8),
              AppButton(
                  label: 'Alterar', onPressed: running ? null : pickOutputDir),
            ],
          ),
          const SizedBox(height: 10),
          CheckRow(
            label: 'Adicionar resultados à biblioteca',
            value: addToLibrary,
            onChanged: (v) => setState(() => addToLibrary = v),
          ),
          const Spacer(),
          AppButton(
            label: pending == 0
                ? 'Converter'
                : 'Converter $pending ${pending == 1 ? 'arquivo' : 'arquivos'}',
            icon: Icons.swap_horiz,
            primary: true,
            expand: true,
            busy: running,
            onPressed: pending == 0 || outputDir == null ? null : convertAll,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<ProjectController>().library;
    return Row(
      children: [
        Expanded(
          child: KeyedSubtree(
            key: TutorialKeys.converterQueue,
            child: Column(
              children: [
                buildQueueToolbar(library),
                Expanded(
                  child: jobs.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'Adicione arquivos de áudio ou vídeo, ou itens da biblioteca, e escolha o formato de saída.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 13, color: AppColors.textDim),
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: jobs.length,
                          itemExtent: 54,
                          itemBuilder: (context, i) => buildJobRow(jobs[i]),
                        ),
                ),
              ],
            ),
          ),
        ),
        buildOptionsPanel(),
      ],
    );
  }
}
