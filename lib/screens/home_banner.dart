import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'bubble_icons.dart';

const _ink = Color(0xFF1E2A28);
// A soft drop shadow, so the bubbles and cards seem to hover over the page.
const _hover = [
  BoxShadow(color: Color(0x1F1E2A28), blurRadius: 12, offset: Offset(0, 5)),
];

/// One food card in the banner's swipe loop.
class _Pick {
  const _Pick(this.image, this.label, this.liked);
  final String image;
  final String label;
  final bool liked;
}

const _picks = [
  _Pick('assets/images/bubbles/pizza.webp', 'Pizza', true),
  _Pick('assets/images/bubbles/burger.webp', 'Burgers', false),
  _Pick('assets/images/bubbles/sushi.webp', 'Sushi', true),
];

/// The picture on Home: he asks the question in the title above, she answers
/// "It's not that simple!", and food cards get swiped between them. Only the portraits are artwork; the
/// bubbles and cards are drawn here so they stay crisp and match the app.
class HomeBanner extends StatefulWidget {
  const HomeBanner({super.key});

  static const aspectRatio = 1.83;

  @override
  State<HomeBanner> createState() => _HomeBannerState();
}

class _HomeBannerState extends State<HomeBanner>
    with SingleTickerProviderStateMixin {
  late final _swipe = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1650),
  )..addStatusListener(_next);

  int _index = 0;
  int _swipesLeft = 0;
  bool _started = false;

  // One pass through the foods, about five seconds, then it rests on the
  // first card: movement that runs on by itself should stop or be pausable.
  // A tap plays it again.
  void _play() {
    if (MediaQuery.disableAnimationsOf(context) || _swipe.isAnimating) return;
    _swipesLeft = _picks.length;
    _swipe.forward(from: 0);
  }

  void _next(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    setState(() => _index = (_index + 1) % _picks.length);
    _swipesLeft--;
    if (_swipesLeft > 0) {
      _swipe.forward(from: 0);
    } else {
      _swipe.value = 0;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _swipe
        ..stop()
        ..value = 0;
    } else if (!_started) {
      _started = true;
      _play();
    }
  }

  @override
  void dispose() {
    _swipe.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label:
          "A man looks exasperated and a woman answers, "
          "'It's not that simple!' while food cards are swiped between them.",
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: _play,
          child: AspectRatio(
            aspectRatio: HomeBanner.aspectRatio,
            child: LayoutBuilder(
              builder: (context, box) => _scene(context, box.biggest),
            ),
          ),
        ),
      ),
    );
  }

  Widget _scene(BuildContext context, Size size) {
    final w = size.width;
    final h = size.height;
    // Her line follows the banner's width but never drops below a readable
    // size on small phones; large-text settings still apply.
    final fontSize = math.max(15.0, w * 0.054);
    final cardW = w * 0.18;
    final cardH = h * 0.48;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 0,
          bottom: 0,
          height: h,
          child: Image.asset('assets/images/home/man.webp'),
        ),
        Positioned(
          right: 0,
          bottom: 0,
          height: h,
          child: Image.asset('assets/images/home/woman.webp'),
        ),
        Positioned(
          left: (w - cardW) / 2,
          top: h * 0.27,
          width: cardW,
          height: cardH,
          child: AnimatedBuilder(
            animation: _swipe,
            builder: (context, _) => _cards(cardW),
          ),
        ),
        // The title above asks the question, so only her answer is drawn:
        // low on her side, clear of the buttons underneath.
        Positioned(
          right: w * 0.08,
          bottom: h * 0.04,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: w * 0.9),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: _Line("It's not that simple!", fontSize: fontSize),
            ),
          ),
        ),
      ],
    );
  }

  Widget _cards(double cardW) {
    final t = _swipe.value;
    final current = _picks[_index];
    final upcoming = _picks[(_index + 1) % _picks.length];
    final stamp = Curves.easeOutBack.transform(
      ((t - 0.30) / 0.15).clamp(0.0, 1.0),
    );
    final fly = Curves.easeIn.transform(((t - 0.50) / 0.32).clamp(0.0, 1.0));
    final direction = current.liked ? 1.0 : -1.0;
    final rise = 0.92 + 0.08 * fly;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: Transform.translate(
            offset: Offset(0, 6 * (1 - fly)),
            child: Transform.scale(
              scale: rise,
              child: _FoodCard(upcoming, stamp: 0, cardW: cardW),
            ),
          ),
        ),
        Positioned.fill(
          child: Opacity(
            opacity: 1 - fly,
            child: Transform.translate(
              offset: Offset(direction * fly * cardW * 1.6, 0),
              child: Transform.rotate(
                angle: direction * fly * 0.32,
                child: _FoodCard(current, stamp: stamp, cardW: cardW),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FoodCard extends StatelessWidget {
  const _FoodCard(this.pick, {required this.stamp, required this.cardW});

  final _Pick pick;
  final double stamp;
  final double cardW;

  @override
  Widget build(BuildContext context) {
    final badge = cardW * 0.36;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(cardW * 0.14),
              boxShadow: _hover,
            ),
            child: Padding(
              padding: EdgeInsets.all(cardW * 0.1),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(child: Image.asset(pick.image)),
                  SizedBox(height: cardW * 0.04),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      pick.label,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: math.max(10.0, cardW * 0.16),
                        color: _ink,
                        height: 1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          top: -badge * 0.3,
          right: -badge * 0.3,
          child: Transform.scale(
            scale: stamp,
            child: BubbleIcon(
              pick.liked ? BubbleGlyph.yes : BubbleGlyph.no,
              size: badge,
            ),
          ),
        ),
      ],
    );
  }
}

/// Her answer: a floating bubble in the title's lettering, with a small tail
/// pointing up at her.
class _Line extends StatelessWidget {
  const _Line(this.text, {required this.fontSize});

  final String text;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final tail = fontSize * 0.5;
    final bubble = DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(fontSize * 0.6),
        boxShadow: _hover,
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: fontSize * 0.45,
          vertical: fontSize * 0.04,
        ),
        child: Text(
          text,
          maxLines: 1,
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: fontSize,
            color: Theme.of(context).colorScheme.primary,
            height: 1.25,
          ),
        ),
      ),
    );
    final pointer = Positioned.fill(
      top: -tail * 0.45,
      child: Align(
        alignment: const Alignment(0.5, -1),
        child: Transform.rotate(
          angle: math.pi / 4,
          child: SizedBox.square(
            dimension: tail,
            child: const ColoredBox(color: Colors.white),
          ),
        ),
      ),
    );
    return Stack(clipBehavior: Clip.none, children: [pointer, bubble]);
  }
}
