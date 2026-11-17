import 'package:dsh_app/l10n/l10n.dart';
import 'package:dsh_app/state/settings_state.dart';
import 'package:dsh_app/ui/burn_in/burn_in_guard_layer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AppSettings> _loadedSettings(ProviderContainer container) async {
  var settings = container.read(settingsProvider);
  for (var i = 0; i < 50 && !settings.loaded; i++) {
    await Future<void>.delayed(Duration.zero);
    settings = container.read(settingsProvider);
  }
  return settings;
}

Widget _screen(BurnInGuardMode mode, {bool move = true, double speed = 1.0}) {
  return MaterialApp(
    locale: const Locale('zh', 'CN'),
    supportedLocales: AppLocale.supported,
    localizationsDelegates: const [L10n.delegate, ...GlobalMaterialLocalizations.delegates],
    home: BurnInGuardScreen(mode: mode, move: move, speed: speed),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('burn-in guard defaults on in spots mode and persists changes', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final settings = await _loadedSettings(container);
    expect(settings.loaded, isTrue);
    expect(settings.burnInGuard, isTrue);
    expect(settings.burnInGuardMode, BurnInGuardMode.spots);

    await container.read(settingsProvider.notifier).setBurnInGuard(false);
    await container.read(settingsProvider.notifier).setBurnInGuardMode(BurnInGuardMode.bounce);

    final changed = container.read(settingsProvider);
    expect(changed.burnInGuard, isFalse);
    expect(changed.burnInGuardMode, BurnInGuardMode.bounce);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('burn_in_guard'), isFalse);
    expect(prefs.getString('burn_in_guard_mode'), 'bounce');
  });

  test('move switch and bounce speed default, persist and clamp', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final settings = await _loadedSettings(container);
    expect(settings.burnInGuardMove, isTrue);
    expect(settings.burnInGuardSpeed, 1.0);

    await container.read(settingsProvider.notifier).setBurnInGuardMove(false);
    await container.read(settingsProvider.notifier).setBurnInGuardSpeed(9.0);
    final changed = container.read(settingsProvider);
    expect(changed.burnInGuardMove, isFalse);
    expect(changed.burnInGuardSpeed, 2.5);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('burn_in_guard_move'), isFalse);
    expect(prefs.getDouble('burn_in_guard_speed'), 2.5);
  });

  test('stored burn-in guard preferences are loaded back', () async {
    SharedPreferences.setMockInitialValues({'burn_in_guard': false, 'burn_in_guard_mode': 'bounce'});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final settings = await _loadedSettings(container);
    expect(settings.burnInGuard, isFalse);
    expect(settings.burnInGuardMode, BurnInGuardMode.bounce);
  });

  testWidgets('move off shows a plain black screen with no label', (tester) async {
    await tester.pumpWidget(_screen(BurnInGuardMode.bounce, move: false));
    await tester.pump();
    expect(find.text('工作中'), findsNothing);
    final box = tester.widget<ColoredBox>(
      find.descendant(of: find.byType(BurnInGuardScreen), matching: find.byType(ColoredBox)),
    );
    expect(box.color, Colors.black);
  });

  testWidgets('spots mode shows the label and moves it to another slot', (tester) async {
    await tester.pumpWidget(_screen(BurnInGuardMode.spots));
    await tester.pump();

    expect(find.text('工作中'), findsOneWidget);
    final box = tester.widget<ColoredBox>(
      find.descendant(of: find.byType(BurnInGuardScreen), matching: find.byType(ColoredBox)),
    );
    expect(box.color, Colors.black);

    Alignment alignmentOf() =>
        tester
                .widget<Align>(find.descendant(of: find.byType(BurnInGuardScreen), matching: find.byType(Align)))
                .alignment
            as Alignment;
    final first = alignmentOf();
    expect(const [-0.72, 0.0, 0.72], contains(first.y));

    await tester.pump(const Duration(seconds: 4));
    final second = alignmentOf();
    expect(second.y, isNot(first.y));
    expect(const [-0.72, 0.0, 0.72], contains(second.y));
  });

  testWidgets('bounce mode keeps the label moving', (tester) async {
    await tester.pumpWidget(_screen(BurnInGuardMode.bounce));
    await tester.pump();

    expect(find.text('工作中'), findsOneWidget);
    final first = tester.getTopLeft(find.text('工作中'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    final second = tester.getTopLeft(find.text('工作中'));
    expect(second, isNot(first));
  });
}
