import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/search_result.dart';
import '../services/download_service.dart';
import '../services/app_log.dart';
import '../services/jamendo_service.dart';
import '../services/preview_service.dart';
import '../services/youtube_service.dart';
import '../state/project_controller.dart';
import '../theme/app_theme.dart';
import '../utils.dart';
import '../widgets/diagnostics_dialog.dart';
import '../widgets/tutorial_overlay.dart';
import '../widgets/ui_kit.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController queryController = TextEditingController();
  final YoutubeService youtube = YoutubeService();
  final JamendoService jamendo = JamendoService();
  late final DownloadService downloader = DownloadService(youtube);
  final List<SearchResult> results = [];
  final Map<String, double> progress = {};
  final Map<String, String> stage = {};
  final Set<String> done = {};
  Timer? hoverTimer;
  SearchSource source = SearchSource.youtube;
  SearchResult? selectedResult;
  bool loading = false;
  bool searched = false;
  String? error;

  @override
  void dispose() {
    hoverTimer?.cancel();
    queryController.dispose();
    youtube.dispose();
    super.dispose();
  }

  Future<void> search() async {
    final query = queryController.text.trim();
    if (query.isEmpty || loading) return;
    FocusScope.of(context).unfocus();
    setState(() {
      loading = true;
      error = null;
      results.clear();
      selectedResult = null;
    });
    try {
      final found = source == SearchSource.youtube
          ? await youtube.search(query)
          : await jamendo.search(query);
      if (!mounted) return;
      setState(() {
        results.addAll(found);
        searched = true;
      });
      if (source == SearchSource.youtube) {
        for (final r in found.take(2)) {
          youtube.prefetch(r.id);
        }
      }
    } catch (e, stack) {
      AppLog.error('busca', e, stack);
      if (!mounted) return;
      setState(() =>
          error = 'Falha na busca: ${'$e'.replaceFirst('Exception: ', '')}');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> download(SearchResult result) async {
    if (progress.containsKey(result.key)) return;
    AppLog.info('interface', 'clique em baixar: ${result.title}');
    final project = context.read<ProjectController>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      progress[result.key] = 0;
      stage[result.key] = 'Iniciando';
    });
    try {
      final downloaded = await downloader.download(
        result,
        onProgress: (v) {
          if (mounted) setState(() => progress[result.key] = v);
        },
        onStage: (s) {
          if (mounted) setState(() => stage[result.key] = s);
        },
      );
      await project.addToLibrary(
        title: result.title,
        artist: result.artist,
        path: downloaded.path,
        coverPath: downloaded.coverPath,
      );
      if (mounted) setState(() => done.add(result.key));
      messenger.showSnackBar(
          SnackBar(content: Text('Adicionada à biblioteca: ${result.title}')));
    } catch (e, stack) {
      AppLog.error('download', e, stack);
      if (mounted) {
        showErrorDialog(
          context,
          title: 'Falha no download',
          message: '$e'.replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          progress.remove(result.key);
          stage.remove(result.key);
        });
      }
    }
  }

  Widget buildToolbar() {
    return Container(
      key: TutorialKeys.searchToolbar,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(
        color: AppColors.panel,
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 180,
            child: SegmentedControl<SearchSource>(
              items: const [
                (SearchSource.youtube, 'YouTube'),
                (SearchSource.jamendo, 'Jamendo'),
              ],
              value: source,
              onChanged: (s) => setState(() {
                source = s;
                results.clear();
                selectedResult = null;
                error = null;
                searched = false;
              }),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: AppTextField(
              controller: queryController,
              hint: 'Nome da música, artista ou link do YouTube',
              prefixIcon: Icons.search,
              autofocus: true,
              onSubmitted: (_) => search(),
            ),
          ),
          const SizedBox(width: 8),
          AppButton(
              label: 'Buscar', primary: true, busy: loading, onPressed: search),
          const SizedBox(width: 4),
          ToolButton(
            icon: Icons.build_outlined,
            tooltip: 'Verificar dependências',
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => DiagnosticsDialog(youtube: youtube),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildMessage(String text, {Color color = AppColors.textDim}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: color),
        ),
      ),
    );
  }

  Widget buildBody() {
    if (error != null) return buildMessage(error!, color: AppColors.danger);
    if (results.isEmpty) {
      if (loading) return buildMessage('Buscando…');
      return buildMessage(
        searched
            ? 'Nenhum resultado encontrado.'
            : 'Digite o nome da música, do artista ou cole um link do YouTube.',
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView.builder(
            itemCount: results.length,
            itemExtent: 54,
            itemBuilder: (context, i) => buildRow(results[i]),
          ),
        ),
        if (selectedResult != null) ...[
          Container(width: 1, color: AppColors.line),
          Expanded(child: buildDetailsPanel(selectedResult!)),
        ],
      ],
    );
  }

  Future<void> preview(SearchResult r) async {
    AppLog.info('interface', 'clique em prévia: ${r.title}');
    final error = r.source == SearchSource.youtube
        ? await PreviewService.instance.toggle(
            r.key,
            urlResolver: () => youtube.previewUrl(r.id),
          )
        : await PreviewService.instance.toggle(r.key, url: r.streamUrl);
    if (error != null && mounted) {
      showErrorDialog(context, title: 'Não foi possível tocar', message: error);
    }
  }

  Widget buildPreviewButton(SearchResult r) {
    return ValueListenableBuilder<String?>(
      valueListenable: PreviewService.instance.currentId,
      builder: (_, current, __) => ValueListenableBuilder<String?>(
        valueListenable: PreviewService.instance.loadingId,
        builder: (_, loadingId, __) => ToolButton(
          icon: current == r.key ? Icons.stop : Icons.play_arrow,
          tooltip: loadingId == r.key
              ? 'Carregando…'
              : (current == r.key ? 'Parar prévia' : 'Ouvir prévia'),
          busy: loadingId == r.key,
          onPressed: () => preview(r),
        ),
      ),
    );
  }

  Widget buildRow(SearchResult r) {
    final busy = progress.containsKey(r.key);
    final percent = ((progress[r.key] ?? 0) * 100).round();
    final subtitle = busy
        ? '${stage[r.key] ?? ''}${percent > 0 && percent < 100 ? ' · $percent%' : ''}'
        : '${r.artist} · ${shortTime(r.durationMs)}';
    return MouseRegion(
      onEnter: (_) {
        if (r.source != SearchSource.youtube) return;
        hoverTimer?.cancel();
        hoverTimer = Timer(
          const Duration(milliseconds: 180),
          () => youtube.prefetch(r.id),
        );
      },
      onExit: (_) => hoverTimer?.cancel(),
      child: buildMediaRow(r, busy, subtitle),
    );
  }

  Widget buildMediaRow(SearchResult r, bool busy, String subtitle) {
    return MediaRow(
      leading: ThumbBox(imageUrl: r.imageUrl),
      title: r.title,
      subtitle: subtitle,
      busy: busy,
      progress: (progress[r.key] ?? 0) > 0 && (progress[r.key] ?? 0) < 1
          ? progress[r.key]
          : null,
      onTap: () => setState(() => selectedResult = r),
      onDoubleTap: done.contains(r.key) || busy ? null : () => download(r),
      actions: [
        buildPreviewButton(r),
        if (done.contains(r.key))
          const SizedBox(
            width: 30,
            height: 30,
            child: Icon(Icons.check, size: 18, color: AppColors.accent),
          )
        else
          ToolButton(
            icon: Icons.file_download_outlined,
            tooltip: 'Baixar como MP3',
            onPressed: busy ? null : () => download(r),
          ),
      ],
    );
  }

  Widget detailField(String label, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: const TextStyle(
                  fontSize: 10.5,
                  letterSpacing: 0.8,
                  color: AppColors.textDim,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 5),
          SelectableText(value,
              style: const TextStyle(fontSize: 12.5, height: 1.4)),
        ],
      ),
    );
  }

  Widget buildDetailsPanel(SearchResult r) {
    final busy = progress.containsKey(r.key);
    final downloaded = done.contains(r.key);
    return Container(
      color: AppColors.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 44,
            padding: const EdgeInsets.only(left: 16, right: 8),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.line)),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text('DETALHES DA MÍDIA',
                      style: TextStyle(
                          fontSize: 11,
                          letterSpacing: 0.9,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textDim)),
                ),
                ToolButton(
                  icon: Icons.close,
                  tooltip: 'Fechar detalhes',
                  onPressed: () => setState(() => selectedResult = null),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: SizedBox(
                        width: 144,
                        height: 144,
                        child: r.imageUrl.isEmpty
                            ? Container(
                                color: AppColors.raised,
                                child: const Icon(Icons.music_note,
                                    size: 48, color: AppColors.textDim),
                              )
                            : Image.network(
                                r.imageUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  color: AppColors.raised,
                                  child: const Icon(Icons.music_note,
                                      size: 48, color: AppColors.textDim),
                                ),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(r.title,
                      textAlign: TextAlign.left,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 5),
                  Text(r.artist,
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textDim)),
                  const SizedBox(height: 22),
                  const Divider(height: 1, color: AppColors.line),
                  const SizedBox(height: 18),
                  detailField('Fonte',
                      r.source == SearchSource.youtube ? 'YouTube' : 'Jamendo'),
                  detailField('Duração', shortTime(r.durationMs)),
                  detailField('ID da mídia', r.id),
                  detailField('Chave interna', r.key),
                  detailField('URL de stream', r.streamUrl),
                  detailField('URL da imagem', r.imageUrl),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(child: buildPreviewButton(r)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: AppButton(
                          label: downloaded
                              ? 'Baixada'
                              : (busy ? 'Baixando…' : 'Baixar MP3'),
                          icon: downloaded ? Icons.check : Icons.download,
                          primary: true,
                          expand: true,
                          onPressed:
                              busy || downloaded ? null : () => download(r),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        buildToolbar(),
        Expanded(
          child: KeyedSubtree(
            key: TutorialKeys.searchBody,
            child: buildBody(),
          ),
        ),
      ],
    );
  }
}
