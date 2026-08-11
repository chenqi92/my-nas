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

  group('TV Rail index ↔ branch mapping', () {
    test('Rail 索引不是恒等映射（回归：Rail 4 应是 mine 而非 photo）', () {
      // TV Rail 只有 5 项，其局部索引 0..4 若被当成 branch 直接传 goBranch，
      // Rail 4（我的）会落到 branch 4（photo）。锁死这个易混点。
      expect(tvRailBranchForIndex(4), AppBranch.mine);
      expect(tvRailBranchForIndex(4), isNot(AppBranch.photo));
    });

    test('每个 Rail 索引映射到预期 branch', () {
      expect(tvRailBranchForIndex(0), AppBranch.video);
      expect(tvRailBranchForIndex(1), AppBranch.music);
      expect(tvRailBranchForIndex(2), AppBranch.photo);
      expect(tvRailBranchForIndex(3), AppBranch.reading);
      expect(tvRailBranchForIndex(4), AppBranch.mine);
    });

    test('branch → Rail 索引是上面的逆映射', () {
      for (var i = 0; i < tvRailBranches.length; i++) {
        expect(tvRailIndexForBranch(tvRailBranchForIndex(i)), i);
      }
    });

    test('非 Rail branch 返回 null（保留原选中项）', () {
      expect(tvRailIndexForBranch(AppBranch.sources), isNull);
      expect(tvRailIndexForBranch(AppBranch.live), isNull);
      expect(tvRailIndexForBranch(AppBranch.ops), isNull);
    });

    test('越界 Rail 索引回落到首个 Tab', () {
      expect(tvRailBranchForIndex(-1), tvRailBranches.first);
      expect(tvRailBranchForIndex(99), tvRailBranches.first);
    });

    test('Rail 与移动端底栏共用同一组 Tab', () {
      // 两处若分别维护顺序，改一处漏一处会导致同一 Tab 在手机/TV 上不同页。
      expect(tvRailBranches, mobileMainTabBranches);
    });

    test('TV 首个 Tab 是影视（BACK 回首页的落点）', () {
      // tv_back_policy 的 goHomeBranch 用 tvRailBranches.first 作为落点。
      expect(tvRailBranches.first, AppBranch.video);
    });
  });
}
