import 'package:flutter/material.dart';
import '../utils.dart';

class RulerPainter extends CustomPainter {
  final double pxPerSecond;
  final double sidePad;
  final Color color;

  RulerPainter({required this.pxPerSecond, required this.sidePad, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final major = Paint()
      ..color = color
      ..strokeWidth = 1;
    final minor = Paint()
      ..color = color.withAlpha(90)
      ..strokeWidth = 1;
    const steps = [1, 2, 5, 10, 15, 30, 60, 120, 300, 600];
    final step = steps.firstWhere((s) => s * pxPerSecond >= 72, orElse: () => 1200);
    final subdivisions = step >= 10 ? 5 : (step >= 2 ? step : 4);
    canvas.drawLine(Offset(0, size.height - 0.5), Offset(size.width, size.height - 0.5), minor);
    for (var s = 0; sidePad + s * pxPerSecond < size.width; s += step) {
      final x = sidePad + s * pxPerSecond;
      canvas.drawLine(Offset(x, size.height - 11), Offset(x, size.height), major);
      for (var k = 1; k < subdivisions; k++) {
        final mx = x + step * pxPerSecond * k / subdivisions;
        canvas.drawLine(Offset(mx, size.height - 5), Offset(mx, size.height), minor);
      }
      final painter = TextPainter(
        text: TextSpan(text: formatSeconds(s), style: TextStyle(color: color, fontSize: 10.5)),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(canvas, Offset(x + 4, 4));
    }
  }

  @override
  bool shouldRepaint(RulerPainter old) =>
      old.pxPerSecond != pxPerSecond || old.color != color || old.sidePad != sidePad;
}
