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
    expect(await BurnInGuardChannel.show(mode: 'spots', text: '工作中'), isFalse);
    await BurnInGuardChannel.hide();
    await BurnInGuardChannel.openPermissionSettings();
  });

  test('native side answers are passed through', () async {
    String? shownMode;
    String? shownText;
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'canDraw':
          return true;
        case 'show':
          shownMode = call.arguments['mode'] as String?;
          shownText = call.arguments['text'] as String?;
          return true;
        default:
          return null;
      }
    });

    expect(await BurnInGuardChannel.canDraw(), isTrue);
    expect(await BurnInGuardChannel.show(mode: 'bounce', text: '工作中'), isTrue);
    expect(shownMode, 'bounce');
    expect(shownText, '工作中');
  });
}
