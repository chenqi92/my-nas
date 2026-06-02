import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/shared/widgets/atoms/app_kbd.dart';
import 'package:my_nas/shared/widgets/atoms/glass_panel.dart';
import 'package:my_nas/shared/widgets/desktop_shell/command_registry.dart';

/// 设计稿 `.cmdk`：⌘K 全局命令面板浮层。
///
/// 现阶段只索引 [CmdkRegistry] 里的同步命令；跨域内容搜索（视频 / 音乐 /
/// 照片 / 文件 / PT）作为后续 Group B 的迭代项接入。
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// 合并：静态命令（matches query） + 所有 searcher 在 query 非空时的输出。
  List<CmdkCommand> _filtered() {
    final commands = CmdkRegistry.instance.all
        .where((c) => c.matches(_query))
        .toList();
    if (_query.isNotEmpty) {
      for (final s in CmdkRegistry.instance.searchers) {
        commands.addAll(s(ref, _query));
      }
    }
    return List.unmodifiable(commands);
  }

  void _onKey(KeyEvent ev, List<CmdkCommand> items) {
    if (ev is! KeyDownEvent && ev is! KeyRepeatEvent) return;
    if (ev.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _selected = (_selected + 1).clamp(0, items.length - 1);
      });
    } else if (ev.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _selected = (_selected - 1).clamp(0, items.length - 1);
      });
    } else if (ev.logicalKey == LogicalKeyboardKey.enter) {
      if (items.isEmpty) return;
      final c = items[_selected];
      widget.onClose();
      c.run(context);
    } else if (ev.logicalKey == LogicalKeyboardKey.escape) {
      widget.onClose();
    }
  }

  @override
  Widget build(BuildContext context) {
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
            child: KeyboardListener(
              focusNode: FocusNode()..canRequestFocus = false,
              onKeyEvent: (ev) => _onKey(ev, items),
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
                          border: Border(
                            bottom: BorderSide(color: t.hairline),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.search_rounded,
                                size: 20, color: t.text2),
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
                                },
                                decoration: InputDecoration(
                                  hintText: '搜索媒体、文件、任务，或输入命令…',
                                  hintStyle:
                                      TextStyle(color: t.text3, fontSize: 16),
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                ),
                                style:
                                    TextStyle(color: t.text0, fontSize: 16),
                              ),
                            ),
                            const AppKbd('ESC'),
                          ],
                        ),
                      ),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 420),
                        child: items.isEmpty
                            ? Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  '无匹配命令。',
                                  style: TextStyle(color: t.text2),
                                ),
                              )
                            : ListView.builder(
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
                Icon(cmd.icon,
                    size: 18, color: selected ? t.accentBright : t.text2),
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
