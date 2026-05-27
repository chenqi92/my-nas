import 'dart:async';
import 'dart:convert';

import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/network/host_mapping_entry.dart';
import 'package:my_nas/core/utils/hive_utils.dart';
import 'package:my_nas/core/utils/logger.dart';

/// 应用内 hosts 映射服务
///
/// 类似系统 `/etc/hosts` 的作用：在建立 TCP 连接前把域名替换为指定 IP，
/// 用于绕过 DNS 污染。HTTPS 的 SNI / 证书校验仍然使用原域名，
/// 由 [resolved_http_client.dart] 中的 connectionFactory 处理。
class HostsResolverService {
  HostsResolverService._();

  static final HostsResolverService instance = HostsResolverService._();

  /// Hive key（settings box）
  static const _storageKey = 'network.hosts_mappings';

  /// 内存缓存：host（小写）→ entry
  final Map<String, HostMappingEntry> _entries = {};

  /// 变更广播：UI 列表实时刷新用
  final _changesController = StreamController<List<HostMappingEntry>>.broadcast();

  bool _loaded = false;

  Stream<List<HostMappingEntry>> get changes => _changesController.stream;

  /// 启动时调用一次：从 Hive 加载所有映射到内存
  Future<void> init() async {
    if (_loaded) return;
    try {
      final box = await HiveUtils.getSettingsBox();
      final raw = box.get(_storageKey) as String?;
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List;
        for (final item in list) {
          if (item is Map) {
            final entry = HostMappingEntry.fromJson(Map<String, dynamic>.from(item));
            _entries[entry.host.toLowerCase()] = entry;
          }
        }
        logger.i('HostsResolverService: 加载 ${_entries.length} 条映射');
      }
      _loaded = true;
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'HostsResolverService.init');
      _loaded = true; // 即使加载失败也标记为已初始化，避免重试
    }
  }

  /// 同步解析：返回启用的映射 IP，若无则返回 null（调用方走系统 DNS）
  String? resolve(String host) {
    final entry = _entries[host.toLowerCase()];
    if (entry == null || !entry.enabled) return null;
    return entry.ip;
  }

  /// 列出全部映射（用于 UI 展示），按 host 字母序
  List<HostMappingEntry> list() {
    final all = _entries.values.toList()
      ..sort((a, b) => a.host.compareTo(b.host));
    return all;
  }

  /// 新增或更新一条映射
  ///
  /// 同一 host 只保留一条（DoH 自动结果会覆盖手动条目，反之亦然）。
  Future<void> upsert(HostMappingEntry entry) async {
    final key = entry.host.toLowerCase();
    _entries[key] = entry;
    await _persist();
    _emit();
  }

  /// 删除一条映射
  Future<void> remove(String host) async {
    final key = host.toLowerCase();
    if (_entries.remove(key) != null) {
      await _persist();
      _emit();
    }
  }

  /// 切换启用状态
  Future<void> toggle(String host, {required bool enabled}) async {
    final key = host.toLowerCase();
    final entry = _entries[key];
    if (entry == null) return;
    _entries[key] = entry.copyWith(enabled: enabled, updatedAt: DateTime.now());
    await _persist();
    _emit();
  }

  /// 批量更新（DoH 一次解析多个 host 后调用）
  Future<void> upsertBatch(Iterable<HostMappingEntry> entries) async {
    for (final entry in entries) {
      _entries[entry.host.toLowerCase()] = entry;
    }
    await _persist();
    _emit();
  }

  /// 清空全部映射（慎用）
  Future<void> clear() async {
    _entries.clear();
    await _persist();
    _emit();
  }

  Future<void> _persist() async {
    try {
      final box = await HiveUtils.getSettingsBox();
      final list = _entries.values.map((e) => e.toJson()).toList();
      await box.put(_storageKey, jsonEncode(list));
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'HostsResolverService._persist');
    }
  }

  void _emit() {
    if (!_changesController.isClosed) {
      _changesController.add(list());
    }
  }
}
