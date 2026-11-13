import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// The app's speech-bubble icons: soft pastel bubbles with a deeper edge
/// underneath and no outline, the "tail" a less rounded corner pointing
/// toward the middle. Painted rather than loaded, so they stay sharp at any
/// size.
enum BubbleGlyph {
  /// Says "Yes": votes yes.
  yes(Color(0xFFC2EDDD), Color(0xFF5DCAA5), Color(0xFF085041)),

  /// Says "No": votes no.
  no(Color(0xFFFAD6C8), Color(0xFFF0997B), Color(0xFF712B13)),

  /// A crossed-out plate: Never what I want.
  never(Color(0xFFE4E3DE), Color(0xFFB4B2A9), Color(0xFF444441)),

  /// A heart: I know what I want.
  favorite(Color(0xFFFBDCE8), Color(0xFFED93B1), Color(0xFF993556)),

  /// An exclamation mark: something needs attention.
  notice(Color(0xFFFFF1C9), Color(0xFFF7C948), Color(0xFF6B4E00));

  const BubbleGlyph(this.color, this.edge, this.ink);

  /// The bubble's fill.
  final Color color;

  /// The deeper edge drawn just under the bubble.
  final Color edge;

  /// The word or symbol on it.
  final Color ink;
}

const _heart = Color(0xFFD4537E);

class BubbleIcon extends StatelessWidget {
  const BubbleIcon(
    this.glyph, {
    super.key,
    this.size = 56,
    this.tailRight = false,
  });

  final BubbleGlyph glyph;
  final double size;

  /// Puts the bubble's tail corner at the bottom right instead of the bottom
  /// left.
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

  Paint _stroke(double width, Color color) =>
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color;

  Paint _fill(Color color) => Paint()..color = color;

  @override
  void paint(Canvas canvas, Size size) {
    // Drawn on a 160-unit square. The bubble is a little wider than tall,
    // centred, with room under it for the edge.
    canvas.scale(size.width / 160);
    const round = Radius.circular(48);
    const tail = Radius.circular(16);
    RRect bubbleAt(double dy) => RRect.fromLTRBAndCorners(
      6,
      20 + dy,
      154,
      134 + dy,
      topLeft: round,
      topRight: round,
      bottomLeft: tailRight ? round : tail,
      bottomRight: tailRight ? tail : round,
    );
    canvas
      ..drawRRect(bubbleAt(9), _fill(glyph.edge))
      ..drawRRect(bubbleAt(0), _fill(glyph.color));
    switch (glyph) {
      case BubbleGlyph.yes:
        _word(canvas, 'Yes');
      case BubbleGlyph.no:
        _word(canvas, 'No');
      case BubbleGlyph.never:
        _plate(canvas);
      case BubbleGlyph.favorite:
        _heartGlyph(canvas);
      case BubbleGlyph.notice:
        _exclamation(canvas);
    }
  }

  // The word itself, so the vote reads at a glance, centred in the bubble.
  void _word(Canvas canvas, String word) {
    final painter = TextPainter(
      text: TextSpan(
        text: word,
        style: GoogleFonts.baloo2(
          color: glyph.ink,
          fontSize: word.length > 2 ? 54 : 60,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      Offset(80 - painter.width / 2, 78 - painter.height / 2),
    );
  }

  void _plate(Canvas canvas) =>
      canvas
        ..drawCircle(const Offset(80, 77), 30, _stroke(9, glyph.ink))
        ..drawLine(
          const Offset(59, 56),
          const Offset(101, 98),
          _stroke(9, glyph.ink),
        );

  void _heartGlyph(Canvas canvas) {
    final heart =
        Path()
          ..moveTo(80, 110)
          ..cubicTo(46, 90, 42, 62, 61, 54)
          ..cubicTo(70, 50, 78, 56, 80, 63)
          ..cubicTo(82, 56, 90, 50, 99, 54)
          ..cubicTo(118, 62, 114, 90, 80, 110)
          ..close();
    final shine =
        Path()
          ..moveTo(61, 67)
          ..cubicTo(63, 62, 67, 60, 71, 62);
    canvas
      ..drawPath(heart, _fill(_heart))
      ..drawPath(shine, _stroke(5, Colors.white));
  }

  void _exclamation(Canvas canvas) =>
      canvas
        ..drawLine(
          const Offset(80, 46),
          const Offset(80, 84),
          _stroke(14, glyph.ink),
        )
        ..drawCircle(const Offset(80, 106), 8, _fill(glyph.ink));

  @override
  bool shouldRepaint(_BubblePainter old) =>
      old.glyph != glyph || old.tailRight != tailRight;
}
