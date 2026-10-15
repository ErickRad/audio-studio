import 'dart:math';
import 'package:flutter/material.dart';
import '../services/audio_engine.dart';

class WaveformPainter extends CustomPainter {
  final List<double> peaks;
  final int inMs;
  final int outMs;
  final bool reversed;
  final Color color;

  WaveformPainter({
    required this.peaks,
    required this.inMs,
    required this.outMs,
    required this.reversed,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.height / 2;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5;
    if (peaks.isEmpty || size.width <= 0) {
      canvas.drawLine(Offset(0, mid), Offset(size.width, mid), paint);
      return;
    }
    final lengthMs = outMs - inMs;
    for (double x = 0; x < size.width; x += 2) {
      final px = reversed ? max(0.0, size.width - x - 2) : x;
      final startMs = inMs + px / size.width * lengthMs;
      final endMs = inMs + (px + 2) / size.width * lengthMs;
      final s = (startMs / AudioEngine.peakMs).floor().clamp(0, peaks.length - 1).toInt();
      final e = (endMs / AudioEngine.peakMs).ceil().clamp(s + 1, peaks.length).toInt();
      var m = 0.0;
      for (var i = s; i < e; i++) {
        if (peaks[i] > m) m = peaks[i];
      }
      final h = max(1.0, m * (size.height - 8));
      canvas.drawLine(Offset(x, mid - h / 2), Offset(x, mid + h / 2), paint);
    }
  }

  @override
  bool shouldRepaint(WaveformPainter old) =>
      old.peaks != peaks ||
      old.inMs != inMs ||
      old.outMs != outMs ||
      old.reversed != reversed ||
      old.color != color;
}
