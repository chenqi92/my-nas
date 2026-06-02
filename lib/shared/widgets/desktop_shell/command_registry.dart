import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 命令面板（⌘K）的一条命令。
class CmdkCommand {
  const CmdkCommand({
    required this.id,
    required this.label,
    required this.icon,
    required this.run,
    this.hint,
    this.group = '命令',
    this.keywords = const [],
  });

  final String id;
  final String label;
  final IconData icon;
  final String? hint;
  final String group;
  final List<String> keywords;
  final void Function(BuildContext context) run;

  bool matches(String query) {
    if (query.isEmpty) return true;
    final q = query.toLowerCase();
    if (label.toLowerCase().contains(q)) return true;
    for (final k in keywords) {
      if (k.toLowerCase().contains(q)) return true;
    }
    return false;
  }
}

/// 跨域搜索器：query 为空时返回空；非空时返回该域匹配的命令条目。
typedef CmdkSearcher = List<CmdkCommand> Function(
  WidgetRef ref,
  String query,
);

/// 全局命令注册表。`desktop_scaffold` 在初始化时注入路由跳转 / 主题切换 /
/// "立即同步" / "添加数据源" 等命令；后续每个 feature 可在自己的 init
/// hook 里 [register] 自己的命令（如 PT 搜索、传输管理）。
///
/// 跨域内容搜索（视频 / 音乐 / 照片 / 文件 / PT）通过 [registerSearcher]
/// 注入异步生成器：query 非空时被调用，返回值合并进结果。
class CmdkRegistry {
  CmdkRegistry._();
  static final instance = CmdkRegistry._();

  final List<CmdkCommand> _commands = [];
  final List<CmdkSearcher> _searchers = [];

  /// 当前注册的所有静态命令快照。
  List<CmdkCommand> get all => List.unmodifiable(_commands);

  /// 当前注册的所有内容搜索器快照。
  List<CmdkSearcher> get searchers => List.unmodifiable(_searchers);

  void register(CmdkCommand c) {
    _commands
      ..removeWhere((x) => x.id == c.id)
      ..add(c);
  }

  void registerAll(Iterable<CmdkCommand> cs) {
    for (final c in cs) {
      register(c);
    }
  }

  void unregister(String id) {
    _commands.removeWhere((c) => c.id == id);
  }

  void registerSearcher(CmdkSearcher s) {
    _searchers.add(s);
  }
}
