import 'package:dsh_app/ui/burn_in/burn_in_guard_channel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dsh/burn_in_guard');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('no native side: overlay reports unavailable instead of throwing', () async {
    expect(await BurnInGuardChannel.canDraw(), isFalse);
    expect(await BurnInGuardChannel.show(mode: 'spots', text: '工作中', move: true, speed: 1.0), isFalse);
    await BurnInGuardChannel.hide();
    await BurnInGuardChannel.openPermissionSettings();
  });

  test('native side answers are passed through', () async {
    Object? shownMode;
    Object? shownText;
    Object? shownMove;
    Object? shownSpeed;
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'canDraw':
          return true;
        case 'show':
          shownMode = call.arguments['mode'];
          shownText = call.arguments['text'];
          shownMove = call.arguments['move'];
          shownSpeed = call.arguments['speed'];
          return true;
        default:
          return null;
      }
    });

    expect(await BurnInGuardChannel.canDraw(), isTrue);
    expect(await BurnInGuardChannel.show(mode: 'bounce', text: '工作中', move: false, speed: 2.0), isTrue);
    expect(shownMode, 'bounce');
    expect(shownText, '工作中');
    expect(shownMove, isFalse);
    expect(shownSpeed, 2.0);
  });
}
