import 'package:flutter/material.dart';

/// Facebook-style Reels glyph: rounded square, slashed clapper band, play triangle.
class ReelsNavIcon extends StatelessWidget {
  const ReelsNavIcon({super.key, required this.color, this.size = 24});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _ReelsIconPainter(color)),
    );
  }
}

Widget reelsNavIconBuilder(Color color, double size) =>
    ReelsNavIcon(color: color, size: size);

class _ReelsIconPainter extends CustomPainter {
  _ReelsIconPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final stroke = s * 0.085;
    final inset = stroke / 2 + s * 0.06;
    final box = Rect.fromLTWH(inset, inset, s - inset * 2, s - inset * 2);
    final radius = Radius.circular(s * 0.24);

    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawRRect(RRect.fromRectAndRadius(box, radius), line);

    final bandY = box.top + box.height * 0.30;
    canvas.drawLine(Offset(box.left, bandY), Offset(box.right, bandY), line);

    final w = box.width;
    for (final x in [0.30, 0.62]) {
      canvas.drawLine(
        Offset(box.left + w * x, box.top),
        Offset(box.left + w * (x + 0.14), bandY),
        line,
      );
    }

    final cx = box.center.dx + w * 0.03;
    final cy = bandY + (box.bottom - bandY) / 2;
    final h = (box.bottom - bandY) * 0.46;
    final play = Path()
      ..moveTo(cx - h * 0.45, cy - h / 2)
      ..lineTo(cx + h * 0.55, cy)
      ..lineTo(cx - h * 0.45, cy + h / 2)
      ..close();
    canvas.drawPath(
      play,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      play,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke * 0.5
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_ReelsIconPainter old) => old.color != color;
}
