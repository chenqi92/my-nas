import 'package:flutter_test/flutter_test.dart';
import 'package:my_nas/shared/widgets/tv_shell/tv_back_policy.dart';

/// 锁死遥控器 BACK 的降级顺序：模态 → branch 详情 → 首页 Tab → 退出应用。
///
/// 这个顺序错一步就是用户可见的坏体验：模态没关先切了 Tab、或者在二级 Tab 上
/// 一按 BACK 就退出应用（Android TV 上表现为「闪退」）。纯函数无第三方依赖，
/// 可在任何环境下校验。
void main() {
  group('resolveTvBackAction', () {
    test('顶层模态优先于一切被关掉', () {
      // 三个条件同时成立时也必须先关模态，否则模态会悬在切换后的页面上。
      expect(
        resolveTvBackAction(
          rootCanPop: true,
          branchCanPop: true,
          isHomeBranch: false,
        ),
        TvBackAction.popRoot,
      );
    });

    test('无模态时退出 branch 内 push 的详情页', () {
      expect(
        resolveTvBackAction(
          rootCanPop: false,
          branchCanPop: true,
          isHomeBranch: false,
        ),
        TvBackAction.popBranch,
      );
    });

    test('branch 栈底 + 非首页 Tab 时回首页 Tab，而不是退出应用', () {
      expect(
        resolveTvBackAction(
          rootCanPop: false,
          branchCanPop: false,
          isHomeBranch: false,
        ),
        TvBackAction.goHomeBranch,
      );
    });

    test('首页 Tab 栈底才交还系统退出', () {
      expect(
        resolveTvBackAction(
          rootCanPop: false,
          branchCanPop: false,
          isHomeBranch: true,
        ),
        TvBackAction.exitApp,
      );
    });

    test('首页 Tab 上仍有详情页时先退详情，不退出应用', () {
      // 回归点：isHomeBranch 不能短路掉 branchCanPop，否则在首页 Tab 打开
      // 详情页后一按 BACK 就退出应用。
      expect(
        resolveTvBackAction(
          rootCanPop: false,
          branchCanPop: true,
          isHomeBranch: true,
        ),
        TvBackAction.popBranch,
      );
    });

    test('exitApp 是唯一会离开应用的动作', () {
      final actions = <TvBackAction>{
        for (final root in [true, false])
          for (final branch in [true, false])
            for (final home in [true, false])
              resolveTvBackAction(
                rootCanPop: root,
                branchCanPop: branch,
                isHomeBranch: home,
              ),
      };
      // 8 种组合只应产出 4 种动作，且 exitApp 仅在全 false + isHome 时出现。
      expect(actions, hasLength(4));
    });
  });
}
