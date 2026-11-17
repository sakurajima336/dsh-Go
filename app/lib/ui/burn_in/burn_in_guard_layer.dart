import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../state/notify_state.dart';
import '../../state/sessions_state.dart';
import '../../state/settings_state.dart';

/// 防烧屏屏保：有会话正在输出、且用户一段时间没有触碰屏幕时，用纯黑盖住
/// 整个界面，只留一行「工作中」在屏幕上移动，避免静态画面长时间停留烧屏。
/// 任意一处触碰立即退出；任务结束也会自动退出。
class BurnInGuardLayer extends ConsumerStatefulWidget {
  const BurnInGuardLayer({super.key});

  @override
  ConsumerState<BurnInGuardLayer> createState() => _BurnInGuardLayerState();
}

class _BurnInGuardLayerState extends ConsumerState<BurnInGuardLayer> {
  /// 多久没有触碰屏幕才接管。
  static const idleAfter = Duration(seconds: 60);

  DateTime _lastTouch = DateTime.now();
  Timer? _ticker;
  bool _active = false;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _evaluate());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _noteTouch() {
    _lastTouch = DateTime.now();
    if (_active) setState(() => _active = false);
  }

  void _evaluate() {
    if (!mounted) return;
    final settings = ref.read(settingsProvider);
    final sessions = ref.read(sessionsProvider).value;
    final should =
        settings.loaded &&
        settings.burnInGuard &&
        ref.read(appForegroundProvider) &&
        (sessions?.any((s) => s.running) ?? false) &&
        DateTime.now().difference(_lastTouch) >= idleAfter;
    if (should != _active) setState(() => _active = should);
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(settingsProvider.select((s) => s.burnInGuardMode));
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _noteTouch(),
      child: _active ? BurnInGuardScreen(mode: mode) : const SizedBox.expand(),
    );
  }
}

/// 全屏纯黑 + 一行会动的「工作中」。单独成 widget，方便测试。
class BurnInGuardScreen extends StatelessWidget {
  const BurnInGuardScreen({super.key, required this.mode});

  final BurnInGuardMode mode;

  @override
  Widget build(BuildContext context) {
    final text = L10n.of(context).burnInWorking;
    return ColoredBox(
      color: Colors.black,
      child: switch (mode) {
        BurnInGuardMode.spots => _SpotsText(text: text),
        BurnInGuardMode.bounce => _BounceText(text: text),
      },
    );
  }
}

class _WorkingText extends StatelessWidget {
  const _WorkingText(this.text, {super.key, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.w500, letterSpacing: 2),
    );
  }
}

/// 随机位置模式：「工作中」在上、中、下三个位置之间随机停留、轮换，
/// 横向再带一点随机偏移，同一个位置不会连着出现两次。
class _SpotsText extends StatefulWidget {
  const _SpotsText({required this.text});

  final String text;

  @override
  State<_SpotsText> createState() => _SpotsTextState();
}

class _SpotsTextState extends State<_SpotsText> {
  static const _dwell = Duration(seconds: 4);
  static const _slots = [-0.72, 0.0, 0.72];

  final _random = Random();
  Timer? _timer;
  int _slot = 1;
  double _x = 0;

  @override
  void initState() {
    super.initState();
    _slot = _random.nextInt(_slots.length);
    _timer = Timer.periodic(_dwell, (_) => _next());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _next() {
    if (!mounted) return;
    var next = _random.nextInt(_slots.length);
    while (next == _slot) {
      next = _random.nextInt(_slots.length);
    }
    setState(() {
      _slot = next;
      _x = _random.nextDouble() * 1.2 - 0.6;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment(_x, _slots[_slot]),
      child: _WorkingText(widget.text, color: const Color(0xB3FFFFFF)),
    );
  }
}

/// 弹跳模式：「工作中」像电视屏保图标一样在屏幕上持续弹跳，
/// 每撞一次边换一种暗色，任何一处像素都不会长时间亮着。
class _BounceText extends StatefulWidget {
  const _BounceText({required this.text});

  final String text;

  @override
  State<_BounceText> createState() => _BounceTextState();
}

class _BounceTextState extends State<_BounceText> with SingleTickerProviderStateMixin {
  static const _palette = [
    Color(0xB3FFFFFF),
    Color(0xB3FFD54F),
    Color(0xB3A5D6A7),
    Color(0xB390CAF9),
    Color(0xB3CE93D8),
    Color(0xB3FFAB91),
  ];

  final _random = Random();
  final _textKey = GlobalKey();
  Ticker? _ticker;
  Duration _last = Duration.zero;
  Offset _pos = const Offset(40, 40);
  Offset _vel = const Offset(110, 84);
  int _colorIndex = 0;

  @override
  void initState() {
    super.initState();
    if (_random.nextBool()) _vel = Offset(-_vel.dx, _vel.dy);
    if (_random.nextBool()) _vel = Offset(_vel.dx, -_vel.dy);
    _ticker = createTicker(_tick)..start();
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  void _tick(Duration elapsed) {
    if (!mounted) return;
    final dt = _last == Duration.zero ? 0.0 : (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (dt <= 0) return;
    final area = MediaQuery.sizeOf(context);
    final textSize = _textKey.currentContext?.size ?? const Size(120, 30);
    final maxX = max(0.0, area.width - textSize.width);
    final maxY = max(0.0, area.height - textSize.height);
    var next = _pos + _vel * dt;
    var vx = _vel.dx;
    var vy = _vel.dy;
    var bounced = false;
    if (next.dx <= 0) {
      next = Offset(0, next.dy);
      vx = vx.abs();
      bounced = true;
    }
    if (next.dx >= maxX) {
      next = Offset(maxX, next.dy);
      vx = -vx.abs();
      bounced = true;
    }
    if (next.dy <= 0) {
      next = Offset(next.dx, 0);
      vy = vy.abs();
      bounced = true;
    }
    if (next.dy >= maxY) {
      next = Offset(next.dx, maxY);
      vy = -vy.abs();
      bounced = true;
    }
    setState(() {
      _pos = next;
      _vel = Offset(vx, vy);
      if (bounced) _colorIndex = (_colorIndex + 1) % _palette.length;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          left: _pos.dx,
          top: _pos.dy,
          child: _WorkingText(widget.text, key: _textKey, color: _palette[_colorIndex]),
        ),
      ],
    );
  }
}
