import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_nas/shared/widgets/tab_bar_minimize_on_scroll.dart';

/// TabBarMinimizeOnScroll 在非 iOS 平台必须完全透明——不包装、不监听、
/// 不产生任何原生调用，保证 Android / 桌面行为与引入该组件前一致。
///
/// iOS 上的实际最小化效果依赖原生 UITabBarController，只能真机验证；
/// 这里能自动化验证的是「低版本/其他平台不受影响」这条契约。
void main() {
  group('TabBarMinimizeOnScroll', () {
    testWidgets('非 iOS 平台原样返回 child，不插入监听层', (tester) async {
      // 测试环境默认 TargetPlatform 非 iOS，且 Platform.isIOS 在
      // flutter test 下为宿主平台（Windows/Linux/macOS CI 均非 iOS 设备）
      const key = Key('scroll-child');

      await tester.pumpWidget(
        const MaterialApp(
          home: TabBarMinimizeOnScroll(
            child: SingleChildScrollView(
              key: key,
              child: SizedBox(height: 2000),
            ),
          ),
        ),
      );

      expect(find.byKey(key), findsOneWidget);
      // child 必须仍可正常滚动
      await tester.drag(find.byKey(key), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('滚动不抛异常且不拦截通知', (tester) async {
      var outerNotificationCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: NotificationListener<ScrollUpdateNotification>(
            onNotification: (_) {
              outerNotificationCount++;
              return false;
            },
            child: const TabBarMinimizeOnScroll(
              child: SingleChildScrollView(
                child: SizedBox(height: 2000),
              ),
            ),
          ),
        ),
      );

      await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -200));
      await tester.pumpAndSettle();

      // 关键契约：return false 让外层监听者照常收到通知
      expect(outerNotificationCount, greaterThan(0));
      expect(tester.takeException(), isNull);
    });

    testWidgets('threshold 可配置且不影响子树布局', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: TabBarMinimizeOnScroll(
            threshold: 40,
            child: SingleChildScrollView(
              child: SizedBox(height: 1200, width: 300),
            ),
          ),
        ),
      );

      // 包装层不得引入额外的高度约束。
      // 宽度不断言：SingleChildScrollView 只在滚动轴（竖直）放开约束，
      // 交叉轴仍会把子组件拉伸到视口宽度，这与本组件无关。
      final box = tester.getSize(find.byType(SizedBox).first);
      expect(box.height, 1200);
    });
  });
}
