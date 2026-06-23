import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/core/utils/debug_log.dart';

/// 底部导航栏可见性 Provider
///
/// 用于控制经典风格下 Flutter 底部导航栏的显示/隐藏
/// 玻璃风格下由 NativeTabBarService 直接控制原生 Tab Bar
final bottomNavVisibleProvider = StateNotifierProvider<BottomNavVisibilityNotifier, bool>(
  (ref) => BottomNavVisibilityNotifier._(),
);

/// 底部导航栏可见性 Notifier
///
/// 使用引用计数来管理导航栏可见性：
/// - 每个需要隐藏导航栏的页面调用 hide() 时增加计数
/// - 页面关闭调用 show() 时减少计数
/// - 只有计数为 0 时导航栏才可见
///
/// 这解决了嵌套页面和竞态条件的问题
class BottomNavVisibilityNotifier extends StateNotifier<bool> {
  BottomNavVisibilityNotifier._() : super(true) {
    _instance = this;
  }

  /// 全局单例
  /// 由 Provider 创建时自动设置
  static BottomNavVisibilityNotifier? _instance;

  /// 获取全局实例（用于 dispose 等场景）
  static BottomNavVisibilityNotifier? get instance => _instance;

  /// 隐藏请求计数
  /// 大于 0 表示有页面请求隐藏导航栏
  int _hideRequestCount = 0;

  /// 是否已经安排了延迟更新
  bool _pendingUpdate = false;

  /// 隐藏底部导航栏
  ///
  /// 增加隐藏请求计数
  void hide() {
    _hideRequestCount++;
    _scheduleUpdate();
    debugLog('BottomNavVisibility: hide() called, count=$_hideRequestCount');
  }

  /// 显示底部导航栏
  ///
  /// 减少隐藏请求计数，只有计数归零时才显示
  void show() {
    if (_hideRequestCount > 0) {
      _hideRequestCount--;
    }
    debugLog('BottomNavVisibility: show() called, count=$_hideRequestCount');
    _scheduleUpdate();
  }

  /// 安排更新可见性状态
  ///
  /// 使用 addPostFrameCallback 延迟状态更新，确保不在构建阶段修改状态
  /// 这避免了 "Tried to modify a provider while the widget tree was building" 错误
  void _scheduleUpdate() {
    if (_pendingUpdate) return;
    _pendingUpdate = true;

    // 使用 addPostFrameCallback 确保状态更新在构建完成后执行
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _pendingUpdate = false;
      _updateVisibility();
    });
  }

  /// 更新可见性状态
  void _updateVisibility() {
    // 检查是否已被 dispose
    if (!mounted) return;

    final shouldBeVisible = _hideRequestCount <= 0;
    if (state != shouldBeVisible) {
      state = shouldBeVisible;
      debugLog('BottomNavVisibility: state changed to $state');
    }
  }

  /// 重置状态（用于热重载或异常恢复）
  void reset() {
    _hideRequestCount = 0;
    _pendingUpdate = false;
    // 直接设置状态，因为 reset 通常在安全的时机调用
    if (mounted) {
      state = true;
    }
    debugLog('BottomNavVisibility: reset');
  }

  /// 设置可见性（直接设置，强制更新）
  /// 
  /// 与 hide()/show() 不同，此方法会强制设置可见性状态
  /// 用于页面 dispose 时确保导航栏恢复可见
  /// 
  /// 注意：仍使用 _scheduleUpdate() 延迟更新，避免在 widget tree 构建时修改 provider 状态
  void setVisible(bool visible) {
    if (visible) {
      _hideRequestCount = 0;
    } else {
      _hideRequestCount = 1;
    }
    debugLog('BottomNavVisibility: setVisible($visible) called, count=$_hideRequestCount');
    // 清除待处理标志，确保 _scheduleUpdate() 能够执行
    // 这样即使之前有待处理的更新，也能正确安排新的更新
    _pendingUpdate = false;
    // 使用延迟更新避免在 widget tree 构建时修改 provider 状态
    _scheduleUpdate();
  }
}
