import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/core/utils/tv_capabilities.dart';

/// TV 模式（10-foot UI + D-pad 焦点导航）的可监听入口。
///
/// [TvCapabilities] 是静态的、供非 widget 代码同步读取；本 provider 只是它的
/// 可监听镜像，让「设置里切换 TV 模式」能立刻重建 Shell，而不必重启应用。
///
/// 初始值直接取 [TvCapabilities.override]（启动时已从 settings box 载入）。
final tvModeOverrideProvider =
    StateNotifierProvider<TvModeNotifier, TvModeOverride>(
  (ref) => TvModeNotifier(),
);

/// 当前是否按电视处理（override 合并硬件探测结果后的最终值）。
///
/// Shell 层（MainScaffold）watch 本项来决定走 TvScaffold 还是桌面 / 移动分支。
final isTvModeProvider = Provider<bool>(
  (ref) => TvCapabilities.resolveTvMode(
    ref.watch(tvModeOverrideProvider),
    isTvDevice: TvCapabilities.isTvDevice,
  ),
);

class TvModeNotifier extends StateNotifier<TvModeOverride> {
  TvModeNotifier() : super(TvCapabilities.override);

  /// 切换档位。
  ///
  /// [TvCapabilities.setOverride] 在第一个 await 之前就同步写好静态字段，因此
  /// 先取回它的 future、再更新 state：这样监听者被通知时，同步读取静态字段的
  /// `context.isTvLayout` 已经和 provider 一致。落盘异常由该方法内部的
  /// AppError.guard 兜住，此处 await 不会抛。
  Future<void> setOverride(TvModeOverride value) async {
    if (value == state) return;
    final persisted = TvCapabilities.setOverride(value);
    state = value;
    await persisted;
  }
}
