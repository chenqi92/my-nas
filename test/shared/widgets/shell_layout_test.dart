import 'package:flutter_test/flutter_test.dart';
import 'package:my_nas/shared/widgets/shell_layout.dart';

/// 锁死四种外壳的选择优先级（A2 / A7）。
///
/// 最关键的一条：TV 必须先于桌面判定。电视的逻辑宽度常与桌面重合，一旦顺序反了，
/// 电视上会走成桌面 sidebar 外壳——鼠标悬停交互、无 overscan、底栏/侧栏都不可
/// 聚焦，遥控器完全操作不了。纯函数无第三方依赖，可在任何环境下校验。
void main() {
  group('resolveShellLayout', () {
    test('TV 优先于桌面（回归：电视屏宽与桌面重合）', () {
      expect(
        resolveShellLayout(
          isTvLayout: true,
          isDesktopLayout: true,
          useNativeTabBar: false,
        ),
        ShellLayout.tv,
      );
    });

    test('TV 优先于原生 TabBar', () {
      // 桌面强制 TV 模式验证时，iOS 玻璃风格不应抢走外壳。
      expect(
        resolveShellLayout(
          isTvLayout: true,
          isDesktopLayout: false,
          useNativeTabBar: true,
        ),
        ShellLayout.tv,
      );
    });

    test('非 TV 时桌面优先于原生 TabBar', () {
      expect(
        resolveShellLayout(
          isTvLayout: false,
          isDesktopLayout: true,
          useNativeTabBar: true,
        ),
        ShellLayout.desktop,
      );
    });

    test('仅原生 TabBar 时走 nativeTabBar', () {
      expect(
        resolveShellLayout(
          isTvLayout: false,
          isDesktopLayout: false,
          useNativeTabBar: true,
        ),
        ShellLayout.nativeTabBar,
      );
    });

    test('全 false 兜底到 Flutter 底栏', () {
      expect(
        resolveShellLayout(
          isTvLayout: false,
          isDesktopLayout: false,
          useNativeTabBar: false,
        ),
        ShellLayout.bottomNav,
      );
    });

    test('isTvLayout 为真时其余组合一律是 tv', () {
      for (final desktop in [true, false]) {
        for (final native in [true, false]) {
          expect(
            resolveShellLayout(
              isTvLayout: true,
              isDesktopLayout: desktop,
              useNativeTabBar: native,
            ),
            ShellLayout.tv,
            reason: 'desktop=$desktop native=$native 时也必须是 TV 外壳',
          );
        }
      }
    });
  });

  group('shellShowsBottomNav', () {
    test('只有 bottomNav 外壳自绘底栏', () {
      expect(shellShowsBottomNav(ShellLayout.bottomNav), isTrue);
      expect(shellShowsBottomNav(ShellLayout.tv), isFalse);
      expect(shellShowsBottomNav(ShellLayout.desktop), isFalse);
      expect(shellShowsBottomNav(ShellLayout.nativeTabBar), isFalse);
    });

    test('TV 外壳不画底栏（A7：底栏不可聚焦且会被电视边缘裁切）', () {
      expect(shellShowsBottomNav(ShellLayout.tv), isFalse);
    });
  });
}
