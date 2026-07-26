import 'package:flutter_test/flutter_test.dart';
import 'package:my_nas/app/router/routes.dart';

/// 守护 StatefulShellRoute 的 14 个 branch 顺序在多处保持同步。
///
/// 背景：曾因 14 branch 重排后 `goBranch(4)` 仍按旧布局假设「设置」而实际落到
/// photo（main_scaffold onGotoSettings 的回归 bug）。branch 顺序的单一事实来源是
/// routes.dart 的 [AppBranch] / [branchRoutes]——`app_router.dart` 的
/// `branchNavigatorKeys` 与 `branches`、`desktop_scaffold` 的导航映射都引用它。
///
/// 仅依赖 routes.dart（无第三方/全树依赖），保证该不变量可在任何环境下被校验。
void main() {
  group('branch index ↔ route mapping', () {
    test('all derived lists share AppBranch.count length', () {
      expect(branchRoutes.length, AppBranch.count);
    });

    test('每个 AppBranch 常量索引到预期路由', () {
      expect(branchRoutes[AppBranch.home], Routes.home);
      expect(branchRoutes[AppBranch.video], Routes.video);
      expect(branchRoutes[AppBranch.live], Routes.live);
      expect(branchRoutes[AppBranch.music], Routes.music);
      expect(branchRoutes[AppBranch.photo], Routes.photo);
      expect(branchRoutes[AppBranch.reading], Routes.reading);
      expect(branchRoutes[AppBranch.mine], Routes.mine);
      expect(branchRoutes[AppBranch.ops], Routes.ops);
      expect(branchRoutes[AppBranch.download], Routes.download);
      expect(branchRoutes[AppBranch.transfer], Routes.transfer);
      expect(branchRoutes[AppBranch.sources], Routes.sources);
      expect(branchRoutes[AppBranch.pt], Routes.pt);
      expect(branchRoutes[AppBranch.nastool], Routes.nastool);
      expect(branchRoutes[AppBranch.files], Routes.files);
    });

    test('设置/我的是 branch 6（回归：曾误写成 goBranch(4)=photo）', () {
      expect(AppBranch.mine, 6);
      expect(branchRoutes[AppBranch.mine], Routes.mine);
      // 4 号 branch 是 photo，不是 mine——锁死这个易混点。
      expect(branchRoutes[4], Routes.photo);
    });

    test('branchRoutes 无重复路由', () {
      expect(branchRoutes.toSet().length, branchRoutes.length);
    });

    test('移动端原生 Tab 索引从全局 branch 映射为 0..4', () {
      expect(mobileMainTabIndexForBranch(AppBranch.video), 0);
      expect(mobileMainTabIndexForBranch(AppBranch.music), 1);
      expect(mobileMainTabIndexForBranch(AppBranch.photo), 2);
      expect(mobileMainTabIndexForBranch(AppBranch.reading), 3);
      expect(mobileMainTabIndexForBranch(AppBranch.mine), 4);
      expect(mobileMainTabIndexForBranch(AppBranch.sources), isNull);
    });
  });
}
