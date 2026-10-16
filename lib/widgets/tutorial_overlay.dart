import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import 'ui_kit.dart';

class TutorialKeys {
  static final GlobalKey tabs = GlobalKey(debugLabel: 'tutorialTabs');
  static final GlobalKey searchToolbar =
      GlobalKey(debugLabel: 'tutorialSearchToolbar');
  static final GlobalKey searchBody =
      GlobalKey(debugLabel: 'tutorialSearchBody');
  static final GlobalKey librarySidebar =
      GlobalKey(debugLabel: 'tutorialLibrarySidebar');
  static final GlobalKey libraryMain =
      GlobalKey(debugLabel: 'tutorialLibraryMain');
  static final GlobalKey editorTransport =
      GlobalKey(debugLabel: 'tutorialEditorTransport');
  static final GlobalKey editorTimeline =
      GlobalKey(debugLabel: 'tutorialEditorTimeline');
  static final GlobalKey editorInspector =
      GlobalKey(debugLabel: 'tutorialEditorInspector');
  static final GlobalKey converterQueue =
      GlobalKey(debugLabel: 'tutorialConverterQueue');
  static final GlobalKey converterOptions =
      GlobalKey(debugLabel: 'tutorialConverterOptions');
}

class TutorialState {
  static final ValueNotifier<bool> showing = ValueNotifier<bool>(false);
}

class TutorialStep {
  final String title;
  final String body;
  final IconData icon;
  final int? tab;
  final GlobalKey? target;

  const TutorialStep({
    required this.title,
    required this.body,
    required this.icon,
    this.tab,
    this.target,
  });
}

List<TutorialStep> buildTutorialSteps() {
  return [
    const TutorialStep(
      title: 'Bem-vindo ao Audio Studio',
      body:
          'Pesquise músicas, baixe em MP3 com capa, organize sua biblioteca, edite o áudio em uma timeline e converta entre formatos. Este tour rápido mostra onde fica cada coisa.',
      icon: Icons.graphic_eq,
    ),
    TutorialStep(
      title: 'Navegação',
      body:
          'As quatro abas ficam aqui em cima: Buscar, Biblioteca, Editor e Conversor. Tudo o que você baixa ou importa passa pela Biblioteca.',
      icon: Icons.tab_outlined,
      target: TutorialKeys.tabs,
    ),
    TutorialStep(
      title: 'Buscar músicas',
      body:
          'Escolha YouTube ou Jamendo, digite o nome da música ou cole um link do YouTube e pressione Enter. O botão de chave inglesa confere se as dependências estão em ordem.',
      icon: Icons.search,
      tab: 0,
      target: TutorialKeys.searchToolbar,
    ),
    TutorialStep(
      title: 'Ouvir e baixar',
      body:
          'Use o botão de play para ouvir uma prévia sem esperar o download. O botão de seta baixa a música como MP3, já com título, artista e capa gravados no arquivo. Duplo clique também baixa.',
      icon: Icons.download_outlined,
      tab: 0,
      target: TutorialKeys.searchBody,
    ),
    TutorialStep(
      title: 'Pastas',
      body:
          'Crie pastas para organizar as músicas, por exemplo uma para cada pessoa que usa este computador. Novos downloads entram na pasta que estiver aberta.',
      icon: Icons.folder_outlined,
      tab: 1,
      target: TutorialKeys.librarySidebar,
    ),
    TutorialStep(
      title: 'Sua biblioteca',
      body:
          'Clique para selecionar, Ctrl+clique para várias e Shift+clique para um intervalo. Ctrl+A seleciona tudo e Delete remove. O ícone de pasta move as músicas e o duplo clique envia para o editor.',
      icon: Icons.library_music_outlined,
      tab: 1,
      target: TutorialKeys.libraryMain,
    ),
    TutorialStep(
      title: 'Controles do editor',
      body:
          'Reproduza com Espaço, divida o trecho no cursor com S, desfaça com Ctrl+Z e duplique com Ctrl+D. O botão Exportar gera o arquivo final no formato que você escolher.',
      icon: Icons.play_circle_outline,
      tab: 2,
      target: TutorialKeys.editorTransport,
    ),
    TutorialStep(
      title: 'Timeline',
      body:
          'Cada faixa recebe vários trechos. Arraste para mover, puxe as bordas para aparar e clique na régua para posicionar o cursor. Músicas da biblioteca entram aqui com duplo clique.',
      icon: Icons.view_timeline_outlined,
      tab: 2,
      target: TutorialKeys.editorTimeline,
    ),
    TutorialStep(
      title: 'Ajustes ao vivo',
      body:
          'Selecione um trecho e mude volume, velocidade, tom, graves, agudos e fades. As alterações valem na hora, sem parar a reprodução.',
      icon: Icons.tune,
      tab: 2,
      target: TutorialKeys.editorInspector,
    ),
    TutorialStep(
      title: 'Fila de conversão',
      body:
          'Adicione arquivos de áudio ou vídeo do computador, ou músicas da biblioteca. A capa é mantida quando o destino é MP3.',
      icon: Icons.swap_horiz,
      tab: 3,
      target: TutorialKeys.converterQueue,
    ),
    TutorialStep(
      title: 'Formato de saída',
      body:
          'Escolha formato, qualidade e a pasta de destino, e converta tudo de uma vez. Os resultados podem voltar para a biblioteca automaticamente.',
      icon: Icons.settings_outlined,
      tab: 3,
      target: TutorialKeys.converterOptions,
    ),
    const TutorialStep(
      title: 'Tudo pronto',
      body:
          'Você pode rever este tour a qualquer momento pelo botão de ajuda no canto superior direito. Boa edição!',
      icon: Icons.check_circle_outline,
      tab: 0,
    ),
  ];
}

class TutorialOverlay extends StatefulWidget {
  final List<TutorialStep> steps;
  final ValueChanged<int> onTab;
  final VoidCallback onClose;

  const TutorialOverlay({
    super.key,
    required this.steps,
    required this.onTab,
    required this.onClose,
  });

  @override
  State<TutorialOverlay> createState() => _TutorialOverlayState();
}

class _TutorialOverlayState extends State<TutorialOverlay>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const double cardWidth = 380;
  static const double margin = 18;

  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );
  final FocusNode focusNode = FocusNode();
  final GlobalKey overlayKey = GlobalKey();
  int step = 0;
  Rect? from;
  Rect? to;
  bool ready = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    TutorialState.showing.value = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) focusNode.requestFocus();
      goTo(0);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    TutorialState.showing.value = false;
    controller.dispose();
    focusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    remeasure();
  }

  Rect? measure(GlobalKey? key) {
    if (key == null) return null;
    final context = key.currentContext;
    final overlay = overlayKey.currentContext?.findRenderObject();
    if (context == null || overlay is! RenderBox) return null;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    final topLeft = overlay.globalToLocal(box.localToGlobal(Offset.zero));
    return topLeft & box.size;
  }

  Rect? get current {
    final target = to;
    if (target == null) return null;
    final origin = from;
    if (origin == null) return target;
    return Rect.lerp(
        origin, target, Curves.easeInOutCubic.transform(controller.value));
  }

  void remeasure() {
    if (!mounted) return;
    final measured = measure(widget.steps[step].target);
    setState(() {
      from = measured;
      to = measured;
      controller.value = 1;
    });
  }

  Future<void> goTo(int index) async {
    final target = widget.steps[index];
    if (target.tab != null) widget.onTab(target.tab!);
    setState(() {
      step = index;
      ready = false;
    });
    await Future<void>.delayed(const Duration(milliseconds: 90));
    if (!mounted) return;
    final measured = measure(target.target);
    setState(() {
      from = current ?? measured;
      to = measured;
      ready = true;
    });
    controller
      ..value = 0
      ..forward();
  }

  void next() {
    if (step >= widget.steps.length - 1) {
      widget.onClose();
    } else {
      goTo(step + 1);
    }
  }

  void previous() {
    if (step > 0) goTo(step - 1);
  }

  KeyEventResult handleKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      next();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      previous();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    return KeyEventResult.handled;
  }

  Offset cardPosition(Size screen, Rect? hole, double cardHeight) {
    final center = Offset(
      (screen.width - cardWidth) / 2,
      (screen.height - cardHeight) / 2,
    );
    if (hole == null) return center;
    final h = hole.inflate(8);
    double left;
    double top;
    if (h.bottom + margin + cardHeight <= screen.height - margin) {
      top = h.bottom + margin;
      left = h.center.dx - cardWidth / 2;
    } else if (h.top - margin - cardHeight >= margin) {
      top = h.top - margin - cardHeight;
      left = h.center.dx - cardWidth / 2;
    } else if (h.right + margin + cardWidth <= screen.width - margin) {
      left = h.right + margin;
      top = h.center.dy - cardHeight / 2;
    } else if (h.left - margin - cardWidth >= margin) {
      left = h.left - margin - cardWidth;
      top = h.center.dy - cardHeight / 2;
    } else {
      left = screen.width - cardWidth - margin;
      top = screen.height - cardHeight - margin;
    }
    left = left.clamp(margin, screen.width - cardWidth - margin).toDouble();
    top = top.clamp(margin, screen.height - cardHeight - margin).toDouble();
    return Offset(left, top);
  }

  Widget buildDots() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < widget.steps.length; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.only(right: 4),
            width: i == step ? 14 : 5,
            height: 5,
            decoration: BoxDecoration(
              color: i == step ? AppColors.accent : AppColors.line,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      ],
    );
  }

  Widget buildCard(TutorialStep data, bool last) {
    return Material(
      color: AppColors.panel,
      elevation: 12,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: cardWidth,
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: AppColors.accent.withAlpha(36),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(data.icon, size: 17, color: AppColors.accent),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    data.title,
                    style: const TextStyle(
                        fontSize: 14.5, fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  '${step + 1} / ${widget.steps.length}',
                  style:
                      const TextStyle(fontSize: 11.5, color: AppColors.textDim),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              data.body,
              style: const TextStyle(
                  fontSize: 12.5, height: 1.5, color: AppColors.text),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                buildDots(),
                const Spacer(),
                if (!last)
                  InkWell(
                    onTap: widget.onClose,
                    borderRadius: BorderRadius.circular(4),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      child: Text('Pular',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.textDim)),
                    ),
                  ),
                const SizedBox(width: 4),
                AppButton(
                  label: 'Anterior',
                  onPressed: step == 0 ? null : previous,
                ),
                const SizedBox(width: 6),
                AppButton(
                  label: last ? 'Concluir' : 'Próximo',
                  primary: true,
                  onPressed: next,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.steps[step];
    final last = step == widget.steps.length - 1;
    return Focus(
      focusNode: focusNode,
      autofocus: true,
      onKeyEvent: handleKey,
      child: LayoutBuilder(
        key: overlayKey,
        builder: (context, constraints) {
          final screen = constraints.biggest;
          final estimated = 150.0 + (data.body.length / 52).ceil() * 19.0;
          return AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              final hole = ready ? current : null;
              final position = cardPosition(screen, hole, estimated);
              return Stack(
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {},
                      child: CustomPaint(painter: _HolePainter(hole)),
                    ),
                  ),
                  Positioned(
                    left: position.dx,
                    top: position.dy,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: ready ? 1 : 0,
                      child: buildCard(data, last),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _HolePainter extends CustomPainter {
  final Rect? hole;

  _HolePainter(this.hole);

  @override
  void paint(Canvas canvas, Size size) {
    final full = Path()..addRect(Offset.zero & size);
    final dim = Paint()..color = const Color(0xC0080809);
    final target = hole;
    if (target == null) {
      canvas.drawPath(full, dim);
      return;
    }
    final rect = RRect.fromRectAndRadius(
      target.inflate(6),
      const Radius.circular(8),
    );
    final path = Path.combine(
      PathOperation.difference,
      full,
      Path()..addRRect(rect),
    );
    canvas.drawPath(path, dim);
    canvas.drawRRect(
      rect.inflate(3),
      Paint()
        ..color = AppColors.accent.withAlpha(60)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6,
    );
    canvas.drawRRect(
      rect,
      Paint()
        ..color = AppColors.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _HolePainter oldDelegate) => true;
}
