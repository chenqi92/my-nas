/// 模块快照的冲突处理方式。
enum SyncMergePolicy {
  /// 整体快照只能由较新的一端覆盖，适用于设置等单值状态。
  lastWriteWins,

  /// 模块自身的 [SyncableModule.importData] 会按记录合并，适用于收藏、
  /// 播放进度等多记录状态。同步器会始终读取双方快照后再写回并集。
  recordMerge,
}

/// 一个可同步的模块自我描述。
///
/// 每个模块（音乐播放列表、视频播放进度、阅读进度等）实现该接口后注册到
/// [CloudSyncRegistry]，[CloudSyncService] 会按 enabled 列表逐个同步。
abstract class SyncableModule {
  /// 全局唯一 key，用作 manifest.json 字段名 + WebDAV 文件名（`<key>.json`）
  String get key;

  /// 用户可见名称（设置页显示）
  String get displayName;

  /// 冲突处理策略。设置型模块默认使用整体快照的 last-write-wins。
  SyncMergePolicy get mergePolicy => SyncMergePolicy.lastWriteWins;

  /// 该模块本地最后变更时间。用于判断本地 / 远端谁更新。
  Future<DateTime?> getLocalUpdatedAt();

  /// 序列化整个模块的同步数据。结构由模块自己定。
  Future<Map<String, dynamic>> exportData();

  /// 导入远端数据。该方法负责合并到本地存储；最简单实现可整体覆盖。
  ///
  /// 设置型模块用 [remoteUpdatedAt] 对齐本地变更追踪器，避免导入后立刻被
  /// 误判为“本地新改动”并推回。记录型模块可忽略该值。
  Future<void> importData(
    Map<String, dynamic> data, {
    DateTime? remoteUpdatedAt,
  });
}

/// 注册中心：统一收集所有 SyncableModule
class CloudSyncRegistry {
  CloudSyncRegistry._();
  static final CloudSyncRegistry instance = CloudSyncRegistry._();

  final List<SyncableModule> _modules = [];

  void register(SyncableModule module) {
    if (_modules.any((m) => m.key == module.key)) return;
    _modules.add(module);
  }

  List<SyncableModule> get modules => List.unmodifiable(_modules);

  SyncableModule? byKey(String key) {
    for (final m in _modules) {
      if (m.key == key) return m;
    }
    return null;
  }
}
