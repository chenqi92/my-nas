import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_nas/features/video/presentation/providers/video_player_provider.dart';
import 'package:my_nas/features/video/presentation/widgets/video_gesture_controller.dart';

/// TV 上必须关掉播放器的拖拽手势（A5/A6）。
///
/// 电视没有触摸屏，但遥控器的方向键在 Flutter 里会被某些盒子上报成指针拖动；
/// 若 pan 手势仍挂着，左右键会同时触发「seek 手势」和「焦点移动」，表现为进度
/// 乱跳。因此 TV 模式下 [VideoGestureController.enableGestures] 必须为 false，
/// 且此时 tap / doubleTap 仍要可用（用来显示 / 隐藏控制栏）。
void main() {
  const state = VideoPlayerState(duration: Duration(minutes: 10));

  Finder gestureSurface() => find
      .descendant(
        of: find.byType(VideoGestureController),
        matching: find.byType(GestureDetector),
      )
      .first;

  Widget host({
    required bool enableGestures,
    required VoidCallback onTap,
    ValueChanged<Duration>? onSeek,
  }) => MaterialApp(
    home: Scaffold(
      body: VideoGestureController(
        playerState: state,
        enableGestures: enableGestures,
        onTap: onTap,
        onDoubleTap: (_) {},
        onVolumeChange: (_) {},
        onSeek: onSeek ?? (_) {},
        child: const SizedBox.expand(),
      ),
    ),
  );

  testWidgets('enableGestures=false 时横向拖动不触发 seek', (tester) async {
    final seeks = <Duration>[];
    await tester.pumpWidget(
      host(enableGestures: false, onTap: () {}, onSeek: seeks.add),
    );

    // 从屏幕中心向右拖 200px：开启手势时这会产生 seek。
    await tester.drag(gestureSurface(), const Offset(200, 0));
    await tester.pumpAndSettle();

    expect(seeks, isEmpty, reason: 'TV 模式下拖动不应改变播放位置');
  });

  testWidgets('enableGestures=false 时纵向拖动不显示音量 / 亮度覆盖层', (tester) async {
    await tester.pumpWidget(host(enableGestures: false, onTap: () {}));

    await tester.drag(gestureSurface(), const Offset(0, -200));
    await tester.pumpAndSettle();

    // 覆盖层只在手势进行中出现；关掉手势后不应有任何进度指示。
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('enableGestures=false 时 tap 仍然可用（显示 / 隐藏控制栏）', (tester) async {
    var taps = 0;
    await tester.pumpWidget(host(enableGestures: false, onTap: () => taps++));

    await tester.tap(gestureSurface());
    // 同一个 GestureDetector 还挂着 onDoubleTapDown：双击识别器会把 arena
    // hold 到 kDoubleTapTimeout(300ms) 结束，onTap 在那之前不会回调。
    // 只 pump 一帧拿不到 tap，必须把测试时钟推过双击窗口。
    await tester.pump(const Duration(milliseconds: 400));

    expect(taps, 1, reason: '遥控器 SELECT 会走 tap，必须保留');
  });

  testWidgets('enableGestures=true 时横向拖动触发 seek（对照组）', (tester) async {
    final seeks = <Duration>[];
    await tester.pumpWidget(
      host(enableGestures: true, onTap: () {}, onSeek: seeks.add),
    );

    await tester.drag(gestureSurface(), const Offset(200, 0));
    await tester.pumpAndSettle();

    // 对照组证明上面的「不触发」来自 enableGestures，而不是测试没戳到手势。
    expect(seeks, isNotEmpty, reason: '移动端拖动应产生 seek');
  });
}
