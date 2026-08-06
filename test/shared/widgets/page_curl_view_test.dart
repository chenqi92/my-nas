import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_nas/shared/widgets/page_curl_view.dart';

/// PageCurlView 的核心契约：
///   1. shader 未就绪 / 加载失败时必须降级渲染，不能白屏
///   2. 静止态（progress<=0）不做额外开销，直接显示当前页
///   3. 降级路径要同时保留两页，翻页方向决定变换基准点
///
/// shader 本身的视觉效果只能真机看，这里锁的是「不会崩、不白屏、
/// 降级可用」这几条。测试环境没有 GPU shader 编译能力，
/// FragmentProgram.fromAsset 会失败并走降级分支，正好覆盖该路径。
void main() {
  group('PageCurlView', () {
    testWidgets('静止态显示当前页内容', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: PageCurlView(
            currentPage: Text('current', textDirection: TextDirection.ltr),
            nextPage: Text('next', textDirection: TextDirection.ltr),
            progress: 0,
            direction: 1,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('current'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shader 不可用时降级仍渲染两页，不白屏', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: PageCurlView(
            currentPage: Text('current', textDirection: TextDirection.ltr),
            nextPage: Text('next', textDirection: TextDirection.ltr),
            progress: 0.5,
            direction: 1,
          ),
        ),
      );
      await tester.pump();

      // 降级路径把两页都挂上：底层 next、上层 current 做透视
      expect(find.text('current'), findsOneWidget);
      expect(find.text('next'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('反向翻页不抛异常', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: PageCurlView(
            currentPage: Text('current', textDirection: TextDirection.ltr),
            nextPage: Text('prev', textDirection: TextDirection.ltr),
            progress: 0.5,
            direction: -1,
            dragStartY: 0.2,
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('progress 连续变化不抛异常且可回到静止态', (tester) async {
      Widget build(double progress) => MaterialApp(
            home: PageCurlView(
              currentPage: const Text('current', textDirection: TextDirection.ltr),
              nextPage: const Text('next', textDirection: TextDirection.ltr),
              progress: progress,
              direction: 1,
            ),
          );

      for (final p in [0.0, 0.25, 0.5, 0.75, 1.0, 0.0]) {
        await tester.pumpWidget(build(p));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'progress=$p 时抛异常');
      }

      // 回到静止态后应恢复成只显示当前页的轻量路径
      expect(find.text('current'), findsOneWidget);
    });

    testWidgets('dragStartY 极值不越界', (tester) async {
      for (final y in [0.0, 1.0, -0.5, 1.5]) {
        await tester.pumpWidget(
          MaterialApp(
            home: PageCurlView(
              currentPage: const Text('c', textDirection: TextDirection.ltr),
              nextPage: const Text('n', textDirection: TextDirection.ltr),
              progress: 0.5,
              direction: 1,
              dragStartY: y,
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'dragStartY=$y 时抛异常');
      }
    });
  });
}
