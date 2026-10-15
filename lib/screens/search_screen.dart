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
  SearchSource source = SearchSource.youtube;
  bool loading = false;
  bool searched = false;
  String? error;

  @override
  void dispose() {
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
    } catch (e, stack) {
      AppLog.error('busca', e, stack);
      if (!mounted) return;
      setState(() => error = 'Falha na busca: ${'$e'.replaceFirst('Exception: ', '')}');
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
      final path = await downloader.download(
        result,
        onProgress: (v) {
          if (mounted) setState(() => progress[result.key] = v);
        },
        onStage: (s) {
          if (mounted) setState(() => stage[result.key] = s);
        },
      );
      await project.addToLibrary(title: result.title, artist: result.artist, path: path);
      if (mounted) setState(() => done.add(result.key));
      messenger.showSnackBar(SnackBar(content: Text('Adicionada à biblioteca: ${result.title}')));
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
          AppButton(label: 'Buscar', primary: true, busy: loading, onPressed: search),
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
    return ListView.builder(
      itemCount: results.length,
      itemExtent: 54,
      itemBuilder: (context, i) => buildRow(results[i]),
    );
  }

  Future<void> preview(SearchResult r) async {
    AppLog.info('interface', 'clique em prévia: ${r.title}');
    final error = r.source == SearchSource.youtube
        ? await PreviewService.instance.toggle(
            r.key,
            fileResolver: () => youtube.cachedAudio(r.id, (_) {}),
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
    return MediaRow(
      leading: ThumbBox(imageUrl: r.imageUrl),
      title: r.title,
      subtitle: subtitle,
      busy: busy,
      progress: (progress[r.key] ?? 0) > 0 && (progress[r.key] ?? 0) < 1 ? progress[r.key] : null,
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

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        buildToolbar(),
        Expanded(child: buildBody()),
      ],
    );
  }
}
