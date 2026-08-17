import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/l10n/app_localizations.dart';
import 'package:my_nas/shared/widgets/atoms/app_kbd.dart';
import 'package:my_nas/shared/widgets/atoms/glass_panel.dart';
import 'package:my_nas/shared/widgets/desktop_shell/command_registry.dart';

/// 设计稿 `.cmdk`：⌘K 全局命令面板浮层。
///
/// 同时索引 [CmdkRegistry] 里的同步命令和桌面外壳注册的影视、音乐、照片、
/// 阅读、当前目录文件与下载任务内容搜索器。
class CommandPalette extends ConsumerStatefulWidget {
  const CommandPalette({required this.onClose, super.key});

  final VoidCallback onClose;

  @override
  ConsumerState<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends ConsumerState<CommandPalette> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  int _selected = 0;
  String _query = '';
  List<CmdkCommand> _contentResults = const [];
  Timer? _searchDebounce;
  int _searchGeneration = 0;
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// 合并：静态命令（matches query） + 已完成的异步内容搜索结果。
  List<CmdkCommand> _filtered() {
    final commands =
        CmdkRegistry.instance.all.where((c) => c.matches(_query)).toList()
          ..addAll(_contentResults);
    return List.unmodifiable(commands);
  }

  void _scheduleContentSearch(String value) {
    _searchDebounce?.cancel();
    final query = value.trim();
    final generation = ++_searchGeneration;
    if (query.isEmpty) {
      setState(() {
        _contentResults = const [];
        _searching = false;
      });
      return;
    }
    setState(() {
      _contentResults = const [];
      _searching = true;
    });
    _searchDebounce = Timer(const Duration(milliseconds: 220), () {
      AppError.fireAndForget(
        _loadContentResults(query, generation),
        action: 'commandPalette.loadContentResults',
      );
    });
  }

  Future<void> _loadContentResults(String query, int generation) async {
    final results = <CmdkCommand>[];
    for (final searcher in CmdkRegistry.instance.searchers) {
      try {
        results.addAll(await Future.sync(() => searcher(ref, query)));
      } on Object catch (e, st) {
        // 单个数据源搜索失败不应让整个命令面板失效；其余域继续返回结果。
        AppError.ignore(e, st, '命令面板单个内容搜索器失败，继续汇总其它搜索结果');
      }
    }
    if (!mounted || generation != _searchGeneration) return;
    setState(() {
      _contentResults = List.unmodifiable(results);
      _searching = false;
      _selected = 0;
    });
  }

  void _moveSelection(int delta, List<CmdkCommand> items) {
    if (items.isEmpty) return;
    setState(() {
      _selected = (_selected + delta).clamp(0, items.length - 1);
    });
  }

  void _runSelected(List<CmdkCommand> items) {
    if (items.isEmpty) return;
    final c = items[_selected.clamp(0, items.length - 1)];
    widget.onClose();
    c.run(context);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = DesignTokens.of(context);
    final items = _filtered();

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onClose,
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.6),
        child: Align(
          alignment: const Alignment(0, -0.5),
          child: GestureDetector(
            onTap: () {}, // 阻止穿透
            child: CallbackShortcuts(
              bindings: <ShortcutActivator, VoidCallback>{
                const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                    _moveSelection(1, items),
                const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                    _moveSelection(-1, items),
                const SingleActivator(LogicalKeyboardKey.enter): () =>
                    _runSelected(items),
                const SingleActivator(LogicalKeyboardKey.escape):
                    widget.onClose,
              },
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: GlassPanel(
                  strong: true,
                  radius: 14,
                  padding: EdgeInsets.zero,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 16,
                        ),
                        decoration: BoxDecoration(
                          border: Border(bottom: BorderSide(color: t.hairline)),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.search_rounded,
                              size: 20,
                              color: t.text2,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _controller,
                                focusNode: _focusNode,
                                onChanged: (v) {
                                  setState(() {
                                    _query = v;
                                    _selected = 0;
                                  });
                                  _scheduleContentSearch(v);
                                },
                                decoration: InputDecoration(
                                  hintText: l.shellCmdkSearchPlaceholder,
                                  hintStyle: TextStyle(
                                    color: t.text3,
                                    fontSize: 16,
                                  ),
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                ),
                                style: TextStyle(color: t.text0, fontSize: 16),
                              ),
                            ),
                            const AppKbd('ESC'),
                          ],
                        ),
                      ),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 420),
                        child: items.isEmpty && _searching
                            ? const SizedBox(
                                height: 96,
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              )
                            : items.isEmpty
                            ? Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  l.shellCmdkNoResults,
                                  style: TextStyle(color: t.text2),
                                ),
                              )
                            : Stack(
                                children: [
                                  ListView.builder(
                                    shrinkWrap: true,
                                    padding: const EdgeInsets.all(8),
                                    itemCount: items.length,
                                    itemBuilder: (_, i) {
                                      final c = items[i];
                                      final sel = i == _selected;
                                      return _Item(
                                        cmd: c,
                                        selected: sel,
                                        onTap: () {
                                          widget.onClose();
                                          c.run(context);
                                        },
                                        onHover: () {
                                          if (_selected != i) {
                                            setState(() => _selected = i);
                                          }
                                        },
                                      );
                                    },
                                  ),
                                  if (_searching)
                                    const Positioned(
                                      left: 0,
                                      right: 0,
                                      top: 0,
                                      child: LinearProgressIndicator(
                                        minHeight: 2,
                                      ),
                                    ),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({
    required this.cmd,
    required this.selected,
    required this.onTap,
    required this.onHover,
  });

  final CmdkCommand cmd;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onHover;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return MouseRegion(
      onHover: (_) => onHover(),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: selected ? t.chipBgActive : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  cmd.icon,
                  size: 18,
                  color: selected ? t.accentBright : t.text2,
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Text(
                    cmd.label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: t.text0,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (cmd.hint != null)
                  Text(
                    cmd.hint!,
                    style: TextStyle(fontSize: 11.5, color: t.text3),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
