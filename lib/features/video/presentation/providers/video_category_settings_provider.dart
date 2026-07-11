import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/features/video/data/services/video_category_settings_service.dart';
import 'package:my_nas/features/video/domain/entities/video_category_config.dart';

/// 视频分类设置 Provider
final videoCategorySettingsProvider =
    StateNotifierProvider<VideoCategorySettingsNotifier, VideoCategorySettings>(
  (ref) => VideoCategorySettingsNotifier(),
);

/// 视频分类设置 Notifier
class VideoCategorySettingsNotifier extends StateNotifier<VideoCategorySettings> {
  VideoCategorySettingsNotifier() : super(VideoCategorySettings.defaults()) {
    _init();
  }

  final _service = VideoCategorySettingsService();
  StreamSubscription<VideoCategorySettings>? _subscription;

  Future<void> _init() async {
    await _service.init();
    state = _service.settings;

    // 监听设置变化
    _subscription = _service.settingsStream.listen((settings) {
      state = settings;
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  /// 切换分类可见性
  Future<void> toggleVisibility(String uniqueKey) async {
    await _service.toggleVisibility(uniqueKey);
  }

  /// 重新排序分类
  Future<void> reorder(int oldIndex, int newIndex) async {
    await _service.reorder(oldIndex, newIndex);
  }

  /// 添加动态分类
  Future<void> addDynamicCategory(
    VideoHomeCategory category,
    String filter,
  ) async {
    await _service.addDynamicCategory(category, filter);
  }

  /// 移除动态分类
  Future<void> removeDynamicCategory(
    VideoHomeCategory category,
    String filter,
  ) async {
    await _service.removeDynamicCategory(category, filter);
  }

  /// 批量添加动态分类
  Future<void> addDynamicCategories(
    VideoHomeCategory category,
    List<String> filters,
  ) async {
    await _service.addDynamicCategories(category, filters);
  }

  /// 批量移除某类型的所有动态分类
  Future<void> removeAllDynamicCategoriesOfType(
    VideoHomeCategory category,
  ) async {
    await _service.removeAllDynamicCategoriesOfType(category);
  }

  /// 重置为默认
  Future<void> resetToDefaults() async {
    await _service.resetToDefaults();
  }
}
