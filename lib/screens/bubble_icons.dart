import 'dart:typed_data';

import 'package:flutter/material.dart';

/// The app's speech-bubble icons, drawn like the logo's food bubbles: a
/// thick ink outline, a coloured bubble and a white glyph. Painted rather
/// than loaded, so they stay sharp at any size.
enum BubbleGlyph {
  /// A "yum" face: votes yes.
  yes(Color(0xFF65B292)),

  /// A "meh" face: votes no.
  no(Color(0xFFF59E84)),

  /// A crossed-out empty plate: Never what I want.
  never(Color(0xFFA7ACA8)),

  /// A heart with a sparkle: I know what I want.
  favorite(Color(0xFFFBD3E2)),

  /// An exclamation mark: something needs attention.
  notice(Color(0xFFF7C948));

  const BubbleGlyph(this.color);
  final Color color;
}

const _ink = Color(0xFF1D2B2C);
const _coral = Color(0xFFF59E84);
const _heart = Color(0xFFE0558A);

class BubbleIcon extends StatelessWidget {
  const BubbleIcon(
    this.glyph, {
    super.key,
    this.size = 56,
    this.tailRight = false,
  });

  final BubbleGlyph glyph;
  final double size;

  /// Puts the bubble's tail at the bottom right instead of the bottom left.
  final bool tailRight;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: _BubblePainter(glyph, tailRight)),
  );
}

class _BubblePainter extends CustomPainter {
  _BubblePainter(this.glyph, this.tailRight);

  final BubbleGlyph glyph;
  final bool tailRight;

  Paint _stroke(double width, [Color color = _ink]) =>
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color;

  Paint _fill(Color color) => Paint()..color = color;

  @override
  void paint(Canvas canvas, Size size) {
    // Drawn on a 160-unit square, like the site's bubble artwork.
    canvas.scale(size.width / 160);
    final body =
        Path()..addRRect(
          RRect.fromLTRBR(14, 10, 146, 126, const Radius.circular(46)),
        );
    final tail =
        Path()
          ..moveTo(76, 118)
          ..lineTo(44, 152)
          ..lineTo(52, 110)
          ..close();
    var bubble = Path.combine(PathOperation.union, body, tail);
    if (tailRight) {
      // Mirrored across the middle of the 160-unit square.
      bubble = bubble.transform(
        Float64List.fromList([
          -1,
          0,
          0,
          0,
          0,
          1,
          0,
          0,
          0,
          0,
          1,
          0,
          160,
          0,
          0,
          1,
        ]),
      );
    }
    canvas
      ..drawPath(bubble, _fill(glyph.color))
      ..drawPath(bubble, _stroke(9));
    switch (glyph) {
      case BubbleGlyph.yes:
        _yum(canvas);
      case BubbleGlyph.no:
        _meh(canvas);
      case BubbleGlyph.never:
        _plate(canvas);
      case BubbleGlyph.favorite:
        _heartGlyph(canvas);
      case BubbleGlyph.notice:
        _exclamation(canvas);
    }
  }

  void _face(Canvas canvas) =>
      canvas
        ..drawCircle(const Offset(80, 70), 34, _fill(Colors.white))
        ..drawCircle(const Offset(80, 70), 34, _stroke(8));

  void _yum(Canvas canvas) {
    _face(canvas);
    final eyes =
        Path()
          ..moveTo(62, 62)
          ..quadraticBezierTo(68, 54, 74, 62)
          ..moveTo(86, 62)
          ..quadraticBezierTo(92, 54, 98, 62);
    final mouth =
        Path()
          ..moveTo(62, 76)
          ..quadraticBezierTo(80, 96, 98, 76)
          ..close();
    final tongue =
        Path()
          ..moveTo(73, 84)
          ..quadraticBezierTo(80, 92, 87, 84)
          ..close();
    canvas
      ..drawPath(eyes, _stroke(6))
      ..drawPath(mouth, _fill(_ink))
      ..drawPath(mouth, _stroke(5))
      ..drawPath(tongue, _fill(_coral));
  }

  void _meh(Canvas canvas) {
    _face(canvas);
    final mouth =
        Path()
          ..moveTo(62, 84)
          ..quadraticBezierTo(68, 78, 74, 84)
          ..quadraticBezierTo(80, 90, 86, 84)
          ..quadraticBezierTo(92, 78, 98, 84);
    canvas
      ..drawLine(const Offset(62, 62), const Offset(74, 62), _stroke(6))
      ..drawLine(const Offset(86, 62), const Offset(98, 62), _stroke(6))
      ..drawPath(mouth, _stroke(6));
  }

  void _plate(Canvas canvas) =>
      canvas
        ..drawCircle(const Offset(80, 68), 31, _fill(Colors.white))
        ..drawCircle(const Offset(80, 68), 31, _stroke(8))
        ..drawCircle(
          const Offset(80, 68),
          17,
          _stroke(5, const Color(0xFFE3E1DA)),
        )
        ..drawLine(const Offset(58, 46), const Offset(102, 90), _stroke(13))
        ..drawLine(
          const Offset(58, 46),
          const Offset(102, 90),
          _stroke(5, _coral),
        );

  void _heartGlyph(Canvas canvas) {
    final heart =
        Path()
          ..moveTo(80, 104)
          ..cubicTo(44, 82, 40, 52, 60, 44)
          ..cubicTo(70, 40, 78, 46, 80, 54)
          ..cubicTo(82, 46, 90, 40, 100, 44)
          ..cubicTo(120, 52, 116, 82, 80, 104)
          ..close();
    final shine =
        Path()
          ..moveTo(60, 58)
          ..cubicTo(62, 53, 67, 51, 71, 53);
    canvas
      ..drawPath(heart, _fill(_heart))
      ..drawPath(heart, _stroke(8))
      ..drawPath(shine, _stroke(5, Colors.white))
      ..drawLine(const Offset(112, 34), const Offset(112, 44), _stroke(4))
      ..drawLine(const Offset(107, 39), const Offset(117, 39), _stroke(4));
  }

  void _exclamation(Canvas canvas) =>
      canvas
        ..drawLine(const Offset(80, 36), const Offset(80, 78), _stroke(22))
        ..drawLine(
          const Offset(80, 36),
          const Offset(80, 78),
          _stroke(10, Colors.white),
        )
        ..drawCircle(const Offset(80, 100), 11, _fill(Colors.white))
        ..drawCircle(const Offset(80, 100), 11, _stroke(6));

  @override
  bool shouldRepaint(_BubblePainter old) =>
      old.glyph != glyph || old.tailRight != tailRight;
}
