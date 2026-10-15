import 'package:flutter/material.dart';
import '../services/ffmpeg_runner.dart';
import '../theme/app_theme.dart';
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

  @override
  void initState() {
    super.initState();
    checkFfmpeg();
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
                  SidebarTabs(
                    items: tabs,
                    index: index,
                    onChanged: (i) => setState(() => index = i),
                  ),
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
                LibraryScreen(onOpenEditor: () => setState(() => index = 2)),
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
