import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../state/project_controller.dart';
import '../widgets/export_flow.dart';
import '../widgets/inspector_panel.dart';
import '../widgets/timeline_view.dart';
import '../widgets/tutorial_overlay.dart';
import '../widgets/transport_bar.dart';

class EditorScreen extends StatefulWidget {
  final bool active;

  const EditorScreen({super.key, required this.active});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late final ProjectController project;

  @override
  void initState() {
    super.initState();
    project = context.read<ProjectController>();
  }

  bool _focusIsTextInput(BuildContext? focusContext) {
    if (focusContext == null) return false;

    return focusContext.widget is EditableText ||
        focusContext.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  bool _focusIsSlider(BuildContext? focusContext) {
    if (focusContext == null) return false;

    return focusContext.widget is Slider ||
        focusContext.findAncestorWidgetOfExactType<Slider>() != null;
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (!widget.active || event is KeyUpEvent) {
      return KeyEventResult.ignored;
    }

    if (ModalRoute.of(context)?.isCurrent == false) {
      return KeyEventResult.ignored;
    }

    final focusContext = FocusManager.instance.primaryFocus?.context;

    if (_focusIsTextInput(focusContext)) {
      return KeyEventResult.ignored;
    }

    final keys = HardwareKeyboard.instance;
    final command = keys.isControlPressed || keys.isMetaPressed;
    final shift = keys.isShiftPressed;
    final key = event.logicalKey;

    // Quando um slider está focado, preserve as setas para ajustar seu valor,
    // mas não bloqueie Delete, S, Espaço ou atalhos de edição.
    if (_focusIsSlider(focusContext) &&
        (key == LogicalKeyboardKey.arrowLeft ||
            key == LogicalKeyboardKey.arrowRight ||
            key == LogicalKeyboardKey.arrowUp ||
            key == LogicalKeyboardKey.arrowDown)) {
      return KeyEventResult.ignored;
    }

    if (key == LogicalKeyboardKey.space) {
      // Evita alternar play/pause repetidamente ao manter Espaço pressionado.
      if (event is KeyRepeatEvent) return KeyEventResult.handled;
      project.togglePlay();
      return KeyEventResult.handled;
    }

    if (command) {
      if (key == LogicalKeyboardKey.keyZ) {
        if (shift) {
          project.redo();
        } else {
          project.undo();
        }
        return KeyEventResult.handled;
      }

      if (key == LogicalKeyboardKey.keyY) {
        project.redo();
        return KeyEventResult.handled;
      }

      if (key == LogicalKeyboardKey.keyD) {
        project.duplicateSelected();
        return KeyEventResult.handled;
      }

      return KeyEventResult.ignored;
    }

    if (key == LogicalKeyboardKey.keyS) {
      project.splitAtPlayhead();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      project.deleteSelected(ripple: shift);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.home) {
      project.seek(0);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.end) {
      project.seek(project.projectEndMs);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowLeft) {
      project.seek(project.playheadMs - (shift ? 5000 : 1000));
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowRight) {
      project.seek(project.playheadMs + (shift ? 5000 : 1000));
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.equal ||
        key == LogicalKeyboardKey.numpadAdd) {
      project.zoom(1.25);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.minus ||
        key == LogicalKeyboardKey.numpadSubtract) {
      project.zoom(0.8);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Column(
        children: [
          KeyedSubtree(
            key: TutorialKeys.editorTransport,
            child: TransportBar(onExport: () => startExport(context)),
          ),
          Expanded(
            child: KeyedSubtree(
              key: TutorialKeys.editorTimeline,
              child: const TimelineView(),
            ),
          ),
          KeyedSubtree(
            key: TutorialKeys.editorInspector,
            child: const InspectorPanel(),
          ),
        ],
      ),
    );
  }
}
