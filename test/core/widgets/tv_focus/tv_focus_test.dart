import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_nas/core/widgets/tv_focus/tv_focus_scroll.dart';
import 'package:my_nas/core/widgets/tv_focus/tv_focusable.dart';
import 'package:my_nas/core/widgets/tv_focus/tv_shelf.dart';

/// TV 焦点基础设施的行为契约（A3）：
/// - [TvFocusable] 能被 D-pad 遍历，SELECT / ENTER 触发 onPressed
/// - [TvShelf] 内左右键在 shelf 内走
/// - [TvFocusScroll] 在焦点移到视口外的卡片时把它滚进来
///
/// 这些是遥控器唯一的操作通路，没有触摸兜底：一旦焦点走不通或 SELECT 不响应，
/// 电视上表现为「整个页面点不动」，因此值得用 widget 测试锁住。
void main() {
  /// 按键需要走真实的 KeyEvent 通路（shortcuts 绑定在 FocusableActionDetector 上）。
  Future<void> pressKey(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pump();
  }

  group('TvFocusable', () {
    testWidgets('autofocus 后 SELECT 触发 onPressed', (tester) async {
      var pressed = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: TvFocusable(
            autofocus: true,
            onPressed: () => pressed++,
            child: const SizedBox(width: 100, height: 100),
          ),
        ),
      );
      await tester.pump();

      await pressKey(tester, LogicalKeyboardKey.select);
      expect(pressed, 1, reason: 'D-pad 中键必须激活卡片');
    });

    testWidgets('ENTER 等价于 SELECT（键盘 / 部分遥控器上报 enter）', (tester) async {
      var pressed = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: TvFocusable(
            autofocus: true,
            onPressed: () => pressed++,
            child: const SizedBox(width: 100, height: 100),
          ),
        ),
      );
      await tester.pump();

      await pressKey(tester, LogicalKeyboardKey.enter);
      expect(pressed, 1);
    });

    testWidgets('未获得焦点时按键不触发', (tester) async {
      var pressed = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: TvFocusable(
            onPressed: () => pressed++,
            child: const SizedBox(width: 100, height: 100),
          ),
        ),
      );
      await tester.pump();

      await pressKey(tester, LogicalKeyboardKey.select);
      expect(pressed, 0);
    });

    testWidgets('外部传入的 focusNode 不被内部 dispose', (tester) async {
      // 回归点：内部无条件 dispose 会让调用方持有已释放的 node 而崩溃。
      final node = FocusNode();
      addTearDown(node.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: TvFocusable(
            focusNode: node,
            onPressed: () {},
            child: const SizedBox(width: 100, height: 100),
          ),
        ),
      );
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));

      // node 仍可用（未被 widget dispose 掉）才能安全 addListener。
      expect(() => node.addListener(() {}), returnsNormally);
    });
  });

  group('TvShelf', () {
    testWidgets('右键在 shelf 内把焦点移到下一张卡片', (tester) async {
      final focused = <int>[];
      final nodes = [for (var i = 0; i < 4; i++) FocusNode(debugLabel: 'card$i')];
      addTearDown(() {
        for (final n in nodes) {
          n.dispose();
        }
      });
      for (var i = 0; i < nodes.length; i++) {
        final index = i;
        nodes[i].addListener(() {
          if (nodes[index].hasFocus) focused.add(index);
        });
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TvShelf(
              itemCount: nodes.length,
              itemBuilder: (context, i) => TvFocusable(
                focusNode: nodes[i],
                autofocus: i == 0,
                onPressed: () {},
                child: const SizedBox(width: 160, height: 180),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(focused, [0], reason: '首张卡片 autofocus');

      await pressKey(tester, LogicalKeyboardKey.arrowRight);
      expect(nodes[1].hasFocus, isTrue, reason: '右键应走到第二张卡片');

      await pressKey(tester, LogicalKeyboardKey.arrowLeft);
      expect(nodes[0].hasFocus, isTrue, reason: '左键应回到第一张');
    });

    testWidgets('每个 shelf 自成一个 OrderedTraversalPolicy 组', (tester) async {
      // 两个 shelf 各自成组，才能做到左右键组内走、上下键跨组。
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                TvShelf(
                  itemCount: 2,
                  itemBuilder: (context, i) => TvFocusable(
                    onPressed: () {},
                    child: const SizedBox(width: 160, height: 180),
                  ),
                ),
                TvShelf(
                  itemCount: 2,
                  itemBuilder: (context, i) => TvFocusable(
                    onPressed: () {},
                    child: const SizedBox(width: 160, height: 180),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      // MaterialApp / Scaffold 自己也会插 FocusTraversalGroup（默认
      // ReadingOrderTraversalPolicy），所以只数 shelf 用的那种策略。
      final shelfGroups = tester
          .widgetList<FocusTraversalGroup>(find.byType(FocusTraversalGroup))
          .where((g) => g.policy is OrderedTraversalPolicy);
      expect(shelfGroups, hasLength(2));
    });
  });

  group('TvFocusScroll', () {
    testWidgets('焦点移到视口外的卡片时滚动使其可见', (tester) async {
      // 视口收窄到 400px、卡片 160px：只放得下 2.5 张，第 3 张起在视口外。
      // 不能用默认 800px 宽 + 远处索引——ListView.builder 不会构建视口和
      // cacheExtent 之外的 item，那样 requestFocus 落在未挂载的 node 上，
      // 测的就不是滚动逻辑了。
      const cardCount = 20;
      const targetIndex = 3;
      final nodes = [
        for (var i = 0; i < cardCount; i++) FocusNode(debugLabel: 'card$i'),
      ];
      final controller = ScrollController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: TvFocusScroll(
                child: SizedBox(
                  height: 200,
                  width: 400,
                  child: ListView.builder(
                    controller: controller,
                    scrollDirection: Axis.horizontal,
                    itemCount: cardCount,
                    itemBuilder: (context, i) => TvFocusable(
                      focusNode: nodes[i],
                      autofocus: i == 0,
                      onPressed: () {},
                      child: const SizedBox(width: 160, height: 180),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(controller.offset, 0, reason: '初始未滚动');
      expect(
        nodes[targetIndex].context,
        isNotNull,
        reason: '目标卡片必须已挂载，否则本例测不到滚动',
      );

      // 直接请求焦点，模拟 D-pad 连按到视口边缘外的卡片。
      nodes[targetIndex].requestFocus();
      await tester.pump();
      // ensureVisible 在 postFrameCallback 里发起，动画 300ms。
      await tester.pumpAndSettle();

      expect(
        controller.offset,
        greaterThan(0),
        reason: '获得焦点的卡片在视口外时必须被滚进来，否则遥控器会「焦点丢失」',
      );

      // node 必须在 widget 树拆掉之后再 dispose：TvFocusScroll 的 dispose
      // 会读焦点树，提前释放会掩盖真实的生命周期问题。
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      for (final n in nodes) {
        n.dispose();
      }
    });

    testWidgets('焦点仍在视口内时不产生多余滚动', (tester) async {
      final nodes = [for (var i = 0; i < 3; i++) FocusNode()];
      final controller = ScrollController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TvFocusScroll(
              child: SizedBox(
                height: 200,
                child: ListView.builder(
                  controller: controller,
                  scrollDirection: Axis.horizontal,
                  itemCount: 3,
                  itemBuilder: (context, i) => TvFocusable(
                    focusNode: nodes[i],
                    autofocus: i == 0,
                    onPressed: () {},
                    child: const SizedBox(width: 160, height: 180),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      nodes[1].requestFocus();
      await tester.pumpAndSettle();

      // 3 张卡片总宽 480 < 800 视口，无可滚动区间。
      expect(controller.offset, 0);

      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      for (final n in nodes) {
        n.dispose();
      }
    });

    testWidgets('widget 树拆除时摘掉焦点监听（不读已 deactivate 的 context）',
        (tester) async {
      // 回归点：dispose 里 FocusScope.of(context) 会抛「Looking up a
      // deactivated widget's ancestor is unsafe」，监听器随之泄漏。
      final node = FocusNode();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TvFocusScroll(
              child: SingleChildScrollView(
                child: TvFocusable(
                  focusNode: node,
                  autofocus: true,
                  onPressed: () {},
                  child: const SizedBox(width: 100, height: 100),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);

      node.dispose();
    });
  });
}
