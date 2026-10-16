import 'package:flutter/material.dart';

import '../services/room_backend.dart';
import 'account_screen.dart';
import 'home_screen.dart';

/// The app's two main places, Home and Account, behind a bar that floats
/// over the bottom of the screen. Rooms open on top of it, so the bar steps
/// aside while a room is running.
class MainShell extends StatefulWidget {
  const MainShell({super.key, required this.currentUid});

  final String currentUid;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  var _tab = 0;

  @override
  Widget build(BuildContext context) {
    final accounts = RoomBackendScope.of(context).accounts;
    final home = HomeScreen(currentUid: widget.currentUid);
    // Builds without accounts have nothing to show on an Account tab.
    if (accounts == null) return home;
    return FloatingBarInset(
      height: _barHeight + _barGap,
      child: Scaffold(
        body: Stack(
          children: [
            IndexedStack(
              index: _tab,
              children: [home, AccountScreen(accounts: accounts)],
            ),
            // The bar floats inside the bottom of the screen's card, as wide
            // as the card less a margin, so it reads as part of the screen.
            Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                top: false,
                minimum: const EdgeInsets.only(bottom: _barGap),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420 - 32),
                    child: _FloatingBar(
                      selected: _tab,
                      onSelected: (tab) => setState(() => _tab = tab),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const _barHeight = 56.0;
const _barGap = 16.0;

/// How much room a screen leaves at its bottom for the floating bar; zero
/// where there is no bar.
class FloatingBarInset extends InheritedWidget {
  const FloatingBarInset({
    super.key,
    required this.height,
    required super.child,
  });

  final double height;

  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FloatingBarInset>()?.height ??
      0;

  @override
  bool updateShouldNotify(FloatingBarInset oldWidget) =>
      height != oldWidget.height;
}

class _FloatingBar extends StatelessWidget {
  const _FloatingBar({required this.selected, required this.onSelected});

  final int selected;
  final ValueChanged<int> onSelected;

  static const _items = [
    (Icons.home_outlined, Icons.home_rounded, 'Home'),
    (Icons.account_circle_outlined, Icons.account_circle, 'Account'),
  ];

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    // Soft mint sets the bar apart from the white card; a deeper, green-tinted
    // shadow lifts it so it reads as floating over the screen.
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: primary.withValues(alpha: 0.30),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Material(
        color: barMint,
        borderRadius: BorderRadius.circular(28),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          height: _barHeight,
          child: Row(
            children: [
              for (final (index, (icon, active, label)) in _items.indexed)
                Expanded(
                  child: Semantics(
                    selected: index == selected,
                    button: true,
                    label: label,
                    excludeSemantics: true,
                    child: Tooltip(
                      message: label,
                      child: InkResponse(
                        onTap: () => onSelected(index),
                        radius: 28,
                        // The unselected green-grey keeps 3:1 contrast on mint.
                        child: Icon(
                          index == selected ? active : icon,
                          size: 30,
                          color:
                              index == selected
                                  ? primary
                                  : const Color(0xFF5E7A6C),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The site's soft mint.
const barMint = Color(0xFFE3F2EA);
