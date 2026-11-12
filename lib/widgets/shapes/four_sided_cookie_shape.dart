import 'package:material_ui/material_ui.dart';

class FourSidedCookieShape extends StatelessWidget {
  const FourSidedCookieShape({
    required this.size,
    required this.color,
    required this.child,
    super.key,
  });

  final double size;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _FourSidedCookiePainter(color),
        child: Center(child: child),
      ),
    );
  }
}

class _FourSidedCookiePainter extends CustomPainter {
  const _FourSidedCookiePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(_buildFourSidedCookiePath(size), Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _FourSidedCookiePainter oldDelegate) =>
      oldDelegate.color != color;
}

Path _buildFourSidedCookiePath(Size size) {
  final path = Path()
    ..moveTo(size.width * 0.02, size.height * 0.34)
    ..cubicTo(
      -0.07,
      size.height * 0.14,
      size.width * 0.14,
      -0.07,
      size.width * 0.34,
      size.height * 0.02,
    )
    ..cubicTo(
      size.width * 0.4,
      size.height * 0.05,
      size.width * 0.47,
      size.height * 0.08,
      size.width * 0.54,
      size.height * 0.08,
    )
    ..cubicTo(
      size.width * 0.6,
      size.height * 0.05,
      size.width * 0.66,
      size.height * 0.02,
      size.width * 0.66,
      size.height * 0.02,
    )
    ..cubicTo(
      size.width * 0.86,
      -0.07,
      size.width * 1.07,
      size.height * 0.14,
      size.width * 0.98,
      size.height * 0.34,
    )
    ..cubicTo(
      size.width * 0.95,
      size.height * 0.4,
      size.width * 0.92,
      size.height * 0.47,
      size.width * 0.92,
      size.height * 0.54,
    )
    ..cubicTo(
      size.width * 0.95,
      size.height * 0.6,
      size.width * 0.98,
      size.height * 0.66,
      size.width * 0.98,
      size.height * 0.66,
    )
    ..cubicTo(
      size.width * 1.07,
      size.height * 0.86,
      size.width * 0.86,
      size.height * 1.07,
      size.width * 0.66,
      size.height * 0.98,
    )
    ..cubicTo(
      size.width * 0.6,
      size.height * 0.95,
      size.width * 0.54,
      size.height * 0.92,
      size.width * 0.47,
      size.height * 0.92,
    )
    ..cubicTo(
      size.width * 0.4,
      size.height * 0.95,
      size.width * 0.34,
      size.height * 0.98,
      size.width * 0.34,
      size.height * 0.98,
    )
    ..cubicTo(
      size.width * 0.14,
      size.height * 1.07,
      -0.07,
      size.height * 0.86,
      size.width * 0.02,
      size.height * 0.66,
    )
    ..cubicTo(
      size.width * 0.05,
      size.height * 0.6,
      size.width * 0.08,
      size.height * 0.54,
      size.width * 0.08,
      size.height * 0.47,
    )
    ..cubicTo(
      size.width * 0.05,
      size.height * 0.4,
      size.width * 0.02,
      size.height * 0.34,
      size.width * 0.02,
      size.height * 0.34,
    )
    ..close();
  return path;
}
