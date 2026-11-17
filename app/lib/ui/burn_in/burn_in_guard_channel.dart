import 'package:flutter/services.dart';

/// 防烧屏屏保的系统悬浮窗通道（原生侧只有 Android：`dsh/burn_in_guard`）。
/// 其他平台或原生不可用时一律返回不可用，图层回退到应用内黑屏。
abstract final class BurnInGuardChannel {
  static const _channel = MethodChannel('dsh/burn_in_guard');
  static bool _handlerSet = false;

  /// 悬浮窗被触碰时原生先自隐，再经这里回告，图层据此重置无操作计时。
  static void ensureTouchHandler(void Function() onDismissedByTouch) {
    if (_handlerSet) return;
    _handlerSet = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'dismissedByTouch') onDismissedByTouch();
    });
  }

  static Future<bool> canDraw() async {
    try {
      return await _channel.invokeMethod<bool>('canDraw') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// True 表示悬浮窗真的升起来了（厂商系统可能有权限也拒绝）。
  static Future<bool> show({
    required String mode,
    required String text,
    required bool move,
    required double speed,
  }) async {
    try {
      return await _channel.invokeMethod<bool>('show', {'mode': mode, 'text': text, 'move': move, 'speed': speed}) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Future<void> hide() async {
    try {
      await _channel.invokeMethod<void>('hide');
    } on MissingPluginException {
      // 没有原生侧就没有悬浮窗可关。
    } on PlatformException {
      // 同上。
    }
  }

  static Future<void> openPermissionSettings() async {
    try {
      await _channel.invokeMethod<void>('openPermissionSettings');
    } on MissingPluginException {
      // 没有原生侧就没有权限页可开。
    } on PlatformException {
      // 同上。
    }
  }
}
