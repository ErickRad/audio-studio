import 'package:flutter/material.dart';

class AppColors {
  static const background = Color(0xFF141518);
  static const panel = Color(0xFF1B1C20);
  static const raised = Color(0xFF24262B);
  static const hover = Color(0xFF2C2E34);
  static const line = Color(0xFF2F3137);
  static const text = Color(0xFFE2E3E7);
  static const textDim = Color(0xFF8B8E98);
  static const accent = Color(0xFF5B8DEF);
  static const playhead = Color(0xFFE5604D);
  static const danger = Color(0xFFE5604D);
  static const laneEven = Color(0xFF17181B);
  static const laneOdd = Color(0xFF1A1B1F);
  static const trackColors = <Color>[
    Color(0xFF4F7CAC),
    Color(0xFF5E9C8F),
    Color(0xFFB07B54),
    Color(0xFF8C73A8),
    Color(0xFF9AA05B),
    Color(0xFFB5645F),
  ];
}

ThemeData buildTheme() {
  const scheme = ColorScheme.dark(
    primary: AppColors.accent,
    onPrimary: Colors.white,
    secondary: AppColors.accent,
    surface: AppColors.panel,
    onSurface: AppColors.text,
    error: AppColors.danger,
    outline: AppColors.line,
    outlineVariant: AppColors.line,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    canvasColor: AppColors.panel,
    visualDensity: VisualDensity.compact,
    fontFamilyFallback: const ['Inter', 'Noto Sans', 'Segoe UI', 'Ubuntu', 'Cantarell'],
    dividerTheme: const DividerThemeData(color: AppColors.line, space: 1, thickness: 1),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 600),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.raised,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.line),
      ),
      textStyle: const TextStyle(fontSize: 11.5, color: AppColors.text),
    ),
    scrollbarTheme: const ScrollbarThemeData(
      thickness: WidgetStatePropertyAll(7.0),
      radius: Radius.circular(4),
      thumbColor: WidgetStatePropertyAll(Color(0xFF3A3D45)),
    ),
    sliderTheme: const SliderThemeData(
      trackHeight: 3,
      activeTrackColor: AppColors.accent,
      inactiveTrackColor: AppColors.line,
      thumbColor: AppColors.text,
      overlayShape: RoundSliderOverlayShape(overlayRadius: 0),
      thumbShape: RoundSliderThumbShape(enabledThumbRadius: 5, elevation: 0, pressedElevation: 0),
      trackShape: RectangularSliderTrackShape(),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: AppColors.raised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: const BorderSide(color: AppColors.line),
      ),
      textStyle: const TextStyle(fontSize: 12.5, color: AppColors.text),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.raised,
      contentTextStyle: const TextStyle(fontSize: 12.5, color: AppColors.text),
      behavior: SnackBarBehavior.floating,
      width: 460,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: const BorderSide(color: AppColors.line),
      ),
    ),
  );
}
