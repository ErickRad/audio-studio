import 'package:flutter/material.dart';
import '../services/ffmpeg_runner.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import '../widgets/tutorial_overlay.dart';
import '../widgets/ui_kit.dart';
import 'converter_screen.dart';
import 'editor_screen.dart';
import 'library_screen.dart';
import 'search_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const tabs = <(IconData, String)>[
    (Icons.search, 'Buscar'),
    (Icons.library_music_outlined, 'Biblioteca'),
    (Icons.graphic_eq, 'Editor'),
    (Icons.swap_horiz, 'Conversor'),
  ];

  int index = 0;
  bool? ffmpegOk;
  bool showTutorial = false;

  @override
  void initState() {
    super.initState();
    checkFfmpeg();
    SettingsService.tutorialSeen().then((seen) {
      if (seen) return;
      Future<void>.delayed(const Duration(milliseconds: 500), () {
        if (mounted) setState(() => showTutorial = true);
      });
    });
  }

  void openTutorial() => setState(() => showTutorial = true);

  void closeTutorial() {
    SettingsService.markTutorialSeen();
    setState(() {
      showTutorial = false;
      index = 0;
    });
  }

  Future<void> checkFfmpeg() async {
    final ok = await FfmpegRunner.isAvailable();
    if (mounted) setState(() => ffmpegOk = ok);
  }

  Widget buildBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: AppColors.raised,
        border: Border(
          bottom: BorderSide(color: AppColors.line),
          left: BorderSide(color: Color(0xFFD9A441), width: 3),
        ),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'FFmpeg não foi encontrado no sistema. Instale-o (Linux: sudo apt install ffmpeg) para baixar, converter e editar áudio.',
              style: TextStyle(fontSize: 12.5),
            ),
          ),
          const SizedBox(width: 12),
          AppButton(label: 'Verificar novamente', onPressed: checkFfmpeg),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: buildShell()),
        if (showTutorial)
          Positioned.fill(
            child: TutorialOverlay(
              steps: buildTutorialSteps(),
              onTab: (i) => setState(() => index = i),
              onClose: closeTutorial,
            ),
          ),
      ],
    );
  }

  Widget buildShell() {
    return Scaffold(
      body: Column(
        children: [
          Material(
            color: AppColors.panel,
            child: Container(
              height: 40,
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.line)),
              ),
              child: Row(
                children: [
                  Image.asset(
                    "assets/icons/audio_studio.png",
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 22),
                    child: const Text(
                      'Audio Studio',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                  KeyedSubtree(
                    key: TutorialKeys.tabs,
                    child: SidebarTabs(
                      items: tabs,
                      index: index,
                      onChanged: (i) => setState(() => index = i),
                    ),
                  ),
                  const Spacer(),
                  ToolButton(
                    icon: Icons.help_outline,
                    tooltip: 'Ver o tutorial novamente',
                    onPressed: openTutorial,
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ),
          if (ffmpegOk == false) buildBanner(),
          Expanded(
            child: IndexedStack(
              index: index,
              children: [
                const SearchScreen(),
                LibraryScreen(
                  active: index == 1,
                  onOpenEditor: () => setState(() => index = 2),
                ),
                EditorScreen(active: index == 2),
                const ConverterScreen(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
