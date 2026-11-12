// Draws the app's real screens with the demo's made-up places and saves them
// for the site's hero phone. Run with `npm run site:screenshots` whenever
// those screens change; it is not part of the regular test run.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whatdoyouwant/models/user.dart';
import 'package:whatdoyouwant/screens/main_shell.dart';
import 'package:whatdoyouwant/screens/results_screen.dart';
import 'package:whatdoyouwant/screens/room_screen.dart';
import 'package:whatdoyouwant/screens/swipe_screen.dart';
import 'package:whatdoyouwant/services/account_service.dart';
import 'package:whatdoyouwant/services/demo_room_backend.dart';
import 'package:whatdoyouwant/services/my_places.dart';
import 'package:whatdoyouwant/services/room_backend.dart';
import 'package:whatdoyouwant/themes/main_theme.dart';

import '../test/support/fakes.dart' show ShellAuth;

/// A phone's screen in logical pixels, drawn at [_pixelRatio] for the site.
const _screen = Size(375, 812);
const _pixelRatio = 1.5;
const _statusBar = 44.0;
const _out = 'site/media/demo';

/// The demo's backend with a join link, so the lobby shows its QR code. The
/// link opens the site's home page, never a room.
class _ShotBackend extends DemoRoomBackend {
  _ShotBackend() : super(pace: Duration.zero);

  @override
  Uri? joinLinkFor(String joinCode) =>
      Uri.parse('https://getwhatdoyouwant.app/');
}

Future<void> _loadFonts() async {
  const baloo = {
    'Baloo2_regular': 'Baloo2-Regular.ttf',
    'Baloo2_500': 'Baloo2-Medium.ttf',
    'Baloo2_600': 'Baloo2-SemiBold.ttf',
    'Baloo2_700': 'Baloo2-Bold.ttf',
    'Baloo2_800': 'Baloo2-ExtraBold.ttf',
  };
  for (final MapEntry(key: family, value: file) in baloo.entries) {
    final loader = FontLoader(family)
      ..addFont(rootBundle.load('assets/google_fonts/$file'));
    await loader.load();
  }
  final material =
      '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
  Future<ByteData> font(String name) async =>
      ByteData.sublistView(await File('$material/$name').readAsBytes());
  await (FontLoader('MaterialIcons')
    ..addFont(font('materialicons-regular.otf'))).load();
  await (FontLoader('Roboto')
        ..addFont(font('roboto-regular.ttf'))
        ..addFont(font('roboto-medium.ttf'))
        ..addFont(font('roboto-bold.ttf')))
      .load();
}

void main() {
  final shot = GlobalKey();
  late _ShotBackend backend;

  setUp(() async {
    // This runs under flutter test, just outside test/ so the regular run skips it.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    backend = _ShotBackend();
    Directory(_out).createSync(recursive: true);
  });

  Future<void> phone(WidgetTester tester) async {
    tester.view.physicalSize = _screen * _pixelRatio;
    tester.view.devicePixelRatio = _pixelRatio;
    tester.view.padding = const FakeViewPadding(top: _statusBar * _pixelRatio);
    tester.view.viewPadding = const FakeViewPadding(
      top: _statusBar * _pixelRatio,
    );
    addTearDown(tester.view.reset);
    await tester.runAsync(_loadFonts);
  }

  Widget app(Widget home) => RoomBackendScope(
    backend: backend,
    accounts: AccountService(ShellAuth()),
    myPlaces: MemoryMyPlaces(),
    demo: true,
    child: RepaintBoundary(
      key: shot,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: appTheme,
        home: home,
      ),
    ),
  );

  Future<void> save(WidgetTester tester, String name) async {
    await tester.runAsync(() async {
      // Asset images decode outside the fake clock.
      for (final element in find.byType(Image).evaluate()) {
        final image = (element.widget as Image).image;
        await precacheImage(image, element);
      }
    });
    await tester.pump();
    final boundary =
        shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final bytes = await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: _pixelRatio);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    });
    File('$_out/$name.png').writeAsBytesSync(bytes!);
  }

  // The site says once, on the swipe screen, that the places are made up: a
  // small note in the top card's corner, drawn only into the screenshot.
  OverlayEntry fictionalNote(WidgetTester tester) {
    final cards =
        find.byType(Card).evaluate().toList()..sort(
          (a, b) => tester
              .getRect(find.byWidget(a.widget))
              .top
              .compareTo(tester.getRect(find.byWidget(b.widget)).top),
        );
    final card = tester.getRect(find.byWidget(cards.first.widget));
    final entry = OverlayEntry(
      builder:
          (context) => Positioned(
            left: card.left + 18,
            top: card.top + 14,
            child: Text(
              '* Fictional location',
              style: Theme.of(context).textTheme.bodySmall!.copyWith(
                color: const Color(0xFF4A5A52),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
    );
    Overlay.of(cards.first).insert(entry);
    return entry;
  }

  testWidgets('home', (tester) async {
    await phone(tester);
    await tester.pumpWidget(app(const MainShell(currentUid: 'guest')));
    // The comic springs in on its own; let it land.
    await tester.pump(const Duration(seconds: 2));
    await save(tester, 'home');
  });

  testWidgets('lobby, swipe and results', (tester) async {
    await phone(tester);
    final you = AppUser(id: 'demo-you', name: 'You');
    await tester.pumpWidget(app(RoomScreen(currentUser: you)));
    await tester.pumpAndSettle();
    // Scrolled down to who's here and Start, with the QR code still in view.
    await tester.ensureVisible(find.text('Start Swiping'));
    await tester.pumpAndSettle();
    await save(tester, 'lobby');
    await tester.tap(find.text('Start Swiping'));
    for (var frame = 0; frame < 8; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(SwipeScreen), findsOneWidget);
    final note = fictionalNote(tester);
    await tester.pump();
    await save(tester, 'swipe');
    note.remove();
    await tester.pump();

    final yes = {0, 2, 3, 6};
    for (var i = 0; find.byType(ResultsScreen).evaluate().isEmpty; i++) {
      await tester.tap(
        find.byTooltip(yes.contains(i) ? 'Vote Yes' : 'Vote No'),
      );
      for (var frame = 0; frame < 8; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }
    for (var i = 0; i < 10 && find.text('Map').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    await tester.pump(const Duration(seconds: 2));
    await save(tester, 'results');
    await tester.pumpWidget(const SizedBox());
    backend.dispose();
  });
}
