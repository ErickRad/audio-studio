import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../state/project_controller.dart';
import '../widgets/export_flow.dart';
import '../widgets/inspector_panel.dart';
import '../widgets/timeline_view.dart';
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
    HardwareKeyboard.instance.addHandler(handleKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(handleKey);
    super.dispose();
  }

  bool typingInTextField() {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext == null) return false;
    return focusContext.widget is EditableText ||
        focusContext.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  bool handleKey(KeyEvent event) {
    if (!widget.active || event is KeyUpEvent) return false;
    if (ModalRoute.of(context)?.isCurrent == false) return false;
    if (typingInTextField()) return false;
    final keys = HardwareKeyboard.instance;
    final command = keys.isControlPressed || keys.isMetaPressed;
    final shift = keys.isShiftPressed;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.space) {
      if (event is KeyRepeatEvent) return true;
      project.togglePlay();
      return true;
    }
    if (command) {
      if (key == LogicalKeyboardKey.keyZ) {
        shift ? project.redo() : project.undo();
        return true;
      }
      if (key == LogicalKeyboardKey.keyY) {
        project.redo();
        return true;
      }
      if (key == LogicalKeyboardKey.keyD) {
        project.duplicateSelected();
        return true;
      }
      return false;
    }
    if (key == LogicalKeyboardKey.keyS) {
      project.splitAtPlayhead();
      return true;
    }
    if (key == LogicalKeyboardKey.delete || key == LogicalKeyboardKey.backspace) {
      project.deleteSelected(ripple: shift);
      return true;
    }
    if (key == LogicalKeyboardKey.home) {
      project.seek(0);
      return true;
    }
    if (key == LogicalKeyboardKey.end) {
      project.seek(project.projectEndMs);
      return true;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      project.seek(project.playheadMs - (shift ? 5000 : 1000));
      return true;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      project.seek(project.playheadMs + (shift ? 5000 : 1000));
      return true;
    }
    if (key == LogicalKeyboardKey.equal || key == LogicalKeyboardKey.numpadAdd) {
      project.zoom(1.25);
      return true;
    }
    if (key == LogicalKeyboardKey.minus || key == LogicalKeyboardKey.numpadSubtract) {
      project.zoom(0.8);
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TransportBar(onExport: () => startExport(context)),
        const Expanded(child: TimelineView()),
        const InspectorPanel(),
      ],
    );
  }
}
