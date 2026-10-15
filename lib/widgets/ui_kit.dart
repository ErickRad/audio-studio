import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

const TextStyle monoStyle = TextStyle(
  fontFamily: 'monospace',
  fontFamilyFallback: ['DejaVu Sans Mono', 'Consolas', 'Menlo'],
  fontFeatures: [FontFeature.tabularFigures()],
);

class ToolButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool active;
  final double iconSize;
  final Color? color;
  final bool busy;

  const ToolButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.active = false,
    this.iconSize = 18,
    this.color,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final tint = !enabled
        ? AppColors.textDim.withAlpha(80)
        : (color ?? (active ? AppColors.accent : AppColors.text));
    return Tooltip(
      message: tooltip,
      child: Material(
        color: active ? AppColors.accent.withAlpha(40) : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          hoverColor: AppColors.hover,
          onTap: onPressed,
          child: SizedBox(
            width: 30,
            height: 30,
            child: busy
                ? Center(
                    child: SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: tint),
                    ),
                  )
                : Icon(icon, size: iconSize, color: tint),
          ),
        ),
      ),
    );
  }
}

class AppButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool primary;
  final bool busy;
  final bool expand;

  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.primary = false,
    this.busy = false,
    this.expand = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    final background = primary
        ? (enabled ? AppColors.accent : AppColors.accent.withAlpha(70))
        : Colors.transparent;
    final foreground = primary
        ? Colors.white.withAlpha(enabled ? 255 : 150)
        : (enabled ? AppColors.text : AppColors.textDim);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(4),
      side: primary ? BorderSide.none : const BorderSide(color: AppColors.line),
    );
    return Material(
      color: background,
      shape: shape,
      child: InkWell(
        customBorder: shape,
        hoverColor: primary ? Colors.white.withAlpha(20) : AppColors.hover,
        onTap: enabled ? onPressed : null,
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (busy)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: foreground),
                )
              else if (icon != null)
                Icon(icon, size: 15, color: foreground),
              if (busy || icon != null) const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: foreground),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class VDivider extends StatelessWidget {
  const VDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 20,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: AppColors.line,
    );
  }
}

class AppTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData? prefixIcon;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final bool autofocus;

  const AppTextField({
    super.key,
    required this.controller,
    required this.hint,
    this.prefixIcon,
    this.onSubmitted,
    this.onChanged,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(4),
      borderSide: const BorderSide(color: AppColors.line),
    );
    return SizedBox(
      height: 32,
      child: TextField(
        controller: controller,
        autofocus: autofocus,
        onSubmitted: onSubmitted,
        onChanged: onChanged,
        cursorColor: AppColors.accent,
        textAlignVertical: TextAlignVertical.center,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: AppColors.background,
          hintText: hint,
          hintStyle: const TextStyle(fontSize: 13, color: AppColors.textDim),
          prefixIcon: prefixIcon == null ? null : Icon(prefixIcon, size: 16, color: AppColors.textDim),
          prefixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 30),
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          border: border,
          enabledBorder: border,
          focusedBorder: border.copyWith(borderSide: const BorderSide(color: AppColors.accent)),
        ),
      ),
    );
  }
}

class SegmentedControl<T> extends StatelessWidget {
  final List<(T, String)> items;
  final T value;
  final ValueChanged<T> onChanged;

  const SegmentedControl({
    super.key,
    required this.items,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          for (final item in items)
            Expanded(
              child: Material(
                color: item.$1 == value ? AppColors.raised : Colors.transparent,
                child: InkWell(
                  hoverColor: AppColors.hover,
                  onTap: () => onChanged(item.$1),
                  child: Center(
                    child: Text(
                      item.$2,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: item.$1 == value ? FontWeight.w600 : FontWeight.w400,
                        color: item.$1 == value ? AppColors.text : AppColors.textDim,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class SidebarTabs extends StatelessWidget {
  final List<(IconData, String)> items;
  final int index;
  final ValueChanged<int> onChanged;

  const SidebarTabs({
    super.key,
    required this.items,
    required this.index,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < items.length; i++)
          SizedBox(
            width: 124,
            child: InkWell(
              hoverColor: AppColors.hover,
              onTap: () => onChanged(i),
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: i == index ? AppColors.accent : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      items[i].$1,
                      size: 15,
                      color: i == index ? AppColors.text : AppColors.textDim,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      items[i].$2,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: i == index ? FontWeight.w600 : FontWeight.w400,
                        color: i == index ? AppColors.text : AppColors.textDim,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class LabeledSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String display;
  final double defaultValue;
  final ValueChanged<double> onChanged;
  final VoidCallback onStart;

  const LabeledSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.display,
    required this.defaultValue,
    required this.onChanged,
    required this.onStart,
    this.divisions,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onDoubleTap: () {
        onStart();
        onChanged(defaultValue);
      },
      child: SizedBox(
        height: 26,
        child: Row(
          children: [
            SizedBox(
              width: 76,
              child: Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textDim)),
            ),
            Expanded(
              child: Slider(
                value: value.clamp(min, max).toDouble(),
                min: min,
                max: max,
                divisions: divisions,
                onChangeStart: (_) => onStart(),
                onChanged: onChanged,
              ),
            ),
            SizedBox(
              width: 56,
              child: Text(
                display,
                textAlign: TextAlign.end,
                style: monoStyle.copyWith(fontSize: 11.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ToggleChip extends StatelessWidget {
  final String label;
  final bool selected;
  final ValueChanged<bool> onChanged;

  const ToggleChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(4),
      side: BorderSide(color: selected ? AppColors.accent : AppColors.line),
    );
    return Material(
      color: selected ? AppColors.accent.withAlpha(45) : Colors.transparent,
      shape: shape,
      child: InkWell(
        customBorder: shape,
        hoverColor: AppColors.hover,
        onTap: () => onChanged(!selected),
        child: Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Center(
            widthFactor: 1,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: selected ? AppColors.text : AppColors.textDim,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CheckRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const CheckRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: Checkbox(
                value: value,
                onChanged: (v) => onChanged(v ?? false),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                activeColor: AppColors.accent,
                side: const BorderSide(color: AppColors.textDim, width: 1.3),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
              ),
            ),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontSize: 12.5)),
          ],
        ),
      ),
    );
  }
}

class AppDropdown<T> extends StatelessWidget {
  final T? value;
  final List<(T, String)> items;
  final ValueChanged<T> onChanged;
  final String? hint;

  const AppDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.line),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          isDense: true,
          iconSize: 18,
          dropdownColor: AppColors.raised,
          style: const TextStyle(fontSize: 12.5, color: AppColors.text),
          hint: hint == null
              ? null
              : Text(hint!, style: const TextStyle(fontSize: 12.5, color: AppColors.textDim)),
          items: [
            for (final item in items)
              DropdownMenuItem<T>(
                value: item.$1,
                child: Text(item.$2, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}

class FormRow extends StatelessWidget {
  final String label;
  final Widget child;

  const FormRow({super.key, required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(label, style: const TextStyle(fontSize: 12.5, color: AppColors.textDim)),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class AppDialog extends StatelessWidget {
  final String title;
  final Widget child;
  final List<Widget> actions;
  final double width;

  const AppDialog({
    super.key,
    required this.title,
    required this.child,
    required this.actions,
    this.width = 380,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.panel,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: const BorderSide(color: AppColors.line),
      ),
      child: SizedBox(
        width: width,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 14),
              Flexible(child: SingleChildScrollView(child: child)),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  for (var i = 0; i < actions.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    actions[i],
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<String?> promptText(
  BuildContext context, {
  required String title,
  required String initial,
  String confirmLabel = 'Salvar',
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AppDialog(
      title: title,
      width: 340,
      actions: [
        AppButton(label: 'Cancelar', onPressed: () => Navigator.pop(dialogContext)),
        AppButton(
          label: confirmLabel,
          primary: true,
          onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
        ),
      ],
      child: AppTextField(
        controller: controller,
        hint: title,
        autofocus: true,
        onSubmitted: (v) => Navigator.pop(dialogContext, v.trim()),
      ),
    ),
  );
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AppDialog(
      title: title,
      width: 360,
      actions: [
        AppButton(label: 'Cancelar', onPressed: () => Navigator.pop(dialogContext, false)),
        AppButton(
          label: confirmLabel,
          primary: true,
          onPressed: () => Navigator.pop(dialogContext, true),
        ),
      ],
      child: Text(message, style: const TextStyle(fontSize: 12.5, color: AppColors.textDim)),
    ),
  );
  return result == true;
}

class MediaRow extends StatelessWidget {
  final Widget leading;
  final String title;
  final String subtitle;
  final List<Widget> actions;
  final bool busy;
  final double? progress;
  final VoidCallback? onDoubleTap;

  const MediaRow({
    super.key,
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.actions,
    this.busy = false,
    this.progress,
    this.onDoubleTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      hoverColor: AppColors.hover,
      onTap: () {},
      onDoubleTap: onDoubleTap,
      child: Container(
        height: 54,
        padding: const EdgeInsets.fromLTRB(10, 0, 6, 0),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.line.withAlpha(120))),
        ),
        child: Stack(
          children: [
            Row(
              children: [
                leading,
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11.5, color: AppColors.textDim),
                      ),
                    ],
                  ),
                ),
                ...actions,
              ],
            ),
            if (busy)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: LinearProgressIndicator(
                  minHeight: 2,
                  value: progress,
                  color: AppColors.accent,
                  backgroundColor: Colors.transparent,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class ThumbBox extends StatelessWidget {
  final String imageUrl;

  const ThumbBox({super.key, required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: 40,
      height: 40,
      color: AppColors.raised,
      child: const Icon(Icons.music_note, size: 18, color: AppColors.textDim),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: SizedBox(
        width: 40,
        height: 40,
        child: imageUrl.isEmpty
            ? placeholder
            : Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => placeholder,
              ),
      ),
    );
  }
}

Future<void> showErrorDialog(
  BuildContext context, {
  required String title,
  required String message,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AppDialog(
      title: title,
      width: 540,
      actions: [
        AppButton(
          label: 'Copiar',
          onPressed: () => Clipboard.setData(ClipboardData(text: message)),
        ),
        AppButton(
          label: 'Fechar',
          primary: true,
          onPressed: () => Navigator.pop(dialogContext),
        ),
      ],
      child: SelectableText(
        message,
        style: const TextStyle(fontSize: 12, color: AppColors.textDim, height: 1.45),
      ),
    ),
  );
}
