import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The app's loading animation: the pizza, burger and sushi bubbles pop in
/// one by one, turn a third of a circle three times with a little bounce,
/// then pop out and start again. With reduced motion turned on they stay
/// still and gently fade instead.
///
/// The web page's loading screen (web/index.html) plays the same animation
/// in CSS, so the two look alike while the app starts. Keep its numbers in
/// step when changing the settings below.
///
/// ```dart
/// const FoodLoader()                                 // 64 px, inline
/// const FoodLoader(size: FoodLoader.largeSize)       // waiting screens
/// const FoodLoader(duration: Duration(seconds: 8))   // a slower loop
/// ```
class FoodLoader extends StatefulWidget {
  const FoodLoader({
    super.key,
    this.size = defaultSize,
    this.duration = defaultDuration,
    this.calmDuration = defaultCalmDuration,
    this.bubbles = defaultBubbles,
    this.label = 'Loading',
  });

  // ---- Settings -----------------------------------------------------------

  /// Width and height of the whole loader.
  static const defaultSize = 64.0;

  /// For waiting screens, where the loader is the main thing on screen.
  static const largeSize = 110.0;

  /// One full loop: pop in, three turns, pop out.
  static const defaultDuration = Duration(seconds: 6);

  /// One fade in and out of the reduced motion version.
  static const defaultCalmDuration = Duration(milliseconds: 1800);

  /// Exactly three: bottom left, top and bottom right, in that order. Any square images
  /// work, such as a coffee bubble in place of one of these.
  static const defaultBubbles = [
    'assets/images/bubbles/pizza.webp',
    'assets/images/bubbles/burger.webp',
    'assets/images/bubbles/sushi.webp',
  ];

  /// Each bubble's width as a share of [size].
  static const bubbleShare = 0.42;

  /// Where each bubble's centre sits, as shares of [size].
  static const slots = [
    Offset(0.275, 0.68),
    Offset(0.5, 0.29),
    Offset(0.725, 0.68),
  ];

  /// The point the bubbles turn around, as shares of [size].
  static const turnCentre = Offset(0.5, 0.55);

  /// How far into the loop each bubble pops in after the one before.
  static const popStagger = 0.05;

  /// How far into the reduced motion fade each bubble starts after the one
  /// before, as a share of [calmDuration].
  static const calmStagger = 1 / 6;

  /// When each turn starts and ends, as shares of the loop. The bubbles rest
  /// between turns and before the first one so the pop-in can be seen.
  static const turns = [(0.22, 0.32), (0.40, 0.50), (0.58, 0.68)];

  /// Overshoots a little at both ends, which gives each turn its bounce.
  static const turnCurve = Cubic(0.68, -0.2, 0.27, 1.25);

  // -------------------------------------------------------------------------

  final double size;
  final Duration duration;
  final Duration calmDuration;
  final List<String> bubbles;

  /// What screen readers announce.
  final String label;

  @override
  State<FoodLoader> createState() => _FoodLoaderState();
}

class _FoodLoaderState extends State<FoodLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _loop = AnimationController(vsync: this);
  bool? _calm;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _restartIfChanged();
  }

  @override
  void didUpdateWidget(FoodLoader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration ||
        oldWidget.calmDuration != widget.calmDuration) {
      _calm = null;
      _restartIfChanged();
    }
  }

  void _restartIfChanged() {
    final calm = MediaQuery.disableAnimationsOf(context);
    if (calm == _calm) return;
    _calm = calm;
    _loop
      ..duration = calm ? widget.calmDuration : widget.duration
      ..repeat();
  }

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final bubble = size * FoodLoader.bubbleShare;
    final calm = _calm ?? false;
    return Semantics(
      label: widget.label,
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: size,
          child: AnimatedBuilder(
            animation: _loop,
            builder: (context, _) {
              final t = _loop.value;
              final turn = calm ? 0.0 : _turnAt(t);
              final centre = FoodLoader.turnCentre * size;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  for (var i = 0; i < 3; i++)
                    _place(
                      // Turned around the centre, but each bubble stays upright.
                      _rotate(FoodLoader.slots[i] * size, centre, turn),
                      bubble,
                      calm ? _calmBubble(t, i) : _poppingBubble(t, i),
                      widget.bubbles[i],
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _place(
    Offset centre,
    double width,
    Widget Function(Widget) look,
    String image,
  ) => Positioned(
    left: centre.dx - width / 2,
    top: centre.dy - width / 2,
    width: width,
    height: width,
    child: look(
      Image.asset(
        image,
        width: width,
        height: width,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
      ),
    ),
  );

  Widget Function(Widget) _poppingBubble(double t, int i) {
    final (scale, degrees) = _popAt((t - FoodLoader.popStagger * i) % 1);
    return (child) => Transform.rotate(
      angle: degrees * math.pi / 180,
      child: Transform.scale(scale: scale, child: child),
    );
  }

  Widget Function(Widget) _calmBubble(double t, int i) {
    final phase = (t - FoodLoader.calmStagger * i) % 1;
    // Faint, full, faint again: one gentle breath per cycle.
    final wave = Curves.easeInOut.transform(
      phase < 0.5 ? phase * 2 : 2 - phase * 2,
    );
    return (child) => Opacity(opacity: 0.35 + 0.65 * wave, child: child);
  }

  static Offset _rotate(Offset point, Offset centre, double radians) {
    final d = point - centre;
    final cos = math.cos(radians), sin = math.sin(radians);
    return centre + Offset(d.dx * cos - d.dy * sin, d.dx * sin + d.dy * cos);
  }

  /// The ring's angle, in radians, a third of a turn per step.
  static double _turnAt(double t) {
    var angle = 0.0;
    for (final (start, end) in FoodLoader.turns) {
      if (t <= start) break;
      final progress = t >= end ? 1.0 : (t - start) / (end - start);
      angle += FoodLoader.turnCurve.transform(progress);
    }
    return angle * 2 * math.pi / 3;
  }

  /// Scale and tilt (degrees) through one loop: a springy pop in, a rest,
  /// a small swell and a pop out.
  static (double, double) _popAt(double t) {
    const keys = [
      (0.0, 0.0, -12.0),
      (0.05, 1.18, 4.0),
      (0.08, 0.94, -1.0),
      (0.10, 1.0, 0.0),
      (0.78, 1.0, 0.0),
      (0.81, 1.12, 0.0),
      (0.86, 0.0, 0.0),
      (1.0, 0.0, 0.0),
    ];
    for (var k = 1; k < keys.length; k++) {
      final (end, endScale, endTilt) = keys[k];
      if (t > end) continue;
      final (start, startScale, startTilt) = keys[k - 1];
      final p = Curves.ease.transform((t - start) / (end - start));
      return (
        startScale + (endScale - startScale) * p,
        startTilt + (endTilt - startTilt) * p,
      );
    }
    return (0, 0);
  }
}
