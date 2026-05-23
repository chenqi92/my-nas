import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/core/network/http_client.dart';
import 'package:my_nas/features/note/data/services/markdown_parser.dart';
import 'package:my_nas/features/note/data/services/note_state_service.dart';
import 'package:my_nas/features/note/domain/entities/note_item.dart';
import 'package:my_nas/features/note/presentation/widgets/task_list_widget.dart';
import 'package:my_nas/shared/mixins/tab_bar_visibility_mixin.dart';
import 'package:my_nas/shared/widgets/error_widget.dart';
import 'package:my_nas/shared/widgets/loading_widget.dart';

/// 笔记编辑器状态
final noteEditorProvider =
    StateNotifierProvider.family<NoteEditorNotifier, NoteEditorState, NoteItem>(
        (ref, note) => NoteEditorNotifier(note));

sealed class NoteEditorState {}

class NoteEditorLoading extends NoteEditorState {}

class NoteEditorLoaded extends NoteEditorState {
  NoteEditorLoaded({
    required this.content,
    required this.tasks,
    this.isEditing = false,
    this.hasChanges = false,
  });

  final String content;
  final List<TaskItem> tasks;
  final bool isEditing;
  final bool hasChanges;

  NoteEditorLoaded copyWith({
    String? content,
    List<TaskItem>? tasks,
    bool? isEditing,
    bool? hasChanges,
  }) => NoteEditorLoaded(
      content: content ?? this.content,
      tasks: tasks ?? this.tasks,
      isEditing: isEditing ?? this.isEditing,
      hasChanges: hasChanges ?? this.hasChanges,
    );
}

class NoteEditorError extends NoteEditorState {
  NoteEditorError(this.message);
  final String message;
}

class NoteEditorNotifier extends StateNotifier<NoteEditorState> {
  NoteEditorNotifier(this.note) : super(NoteEditorLoading()) {
    loadNote();
  }

  final NoteItem note;

  Future<void> loadNote() async {
    state = NoteEditorLoading();

    try {
      String content;
      final uri = Uri.parse(note.url);

      // 检查是否为本地文件 (file:// 协议)
      if (uri.scheme == 'file') {
        // 本地文件直接读取
        final file = File(uri.toFilePath());
        if (!await file.exists()) {
          throw Exception('文件不存在');
        }
        final bytes = await file.readAsBytes();
        try {
          content = utf8.decode(bytes);
        } on FormatException {
          content = String.fromCharCodes(bytes);
        }
      } else {
        // 远程文件通过 HTTP 获取
        final response = await InsecureHttpClient.get(uri);
        if (response.statusCode != 200) {
          throw Exception('加载失败: ${response.statusCode}');
        }
        try {
          content = utf8.decode(response.bodyBytes);
        } on FormatException {
          content = String.fromCharCodes(response.bodyBytes);
        }
      }

      final tasks = MarkdownParser.parseTasks(content);

      state = NoteEditorLoaded(content: content, tasks: tasks);
    } on Exception catch (e) {
      state = NoteEditorError(e.toString());
    }
  }

  void setEditing({required bool editing}) {
    final current = state;
    if (current is NoteEditorLoaded) {
      state = current.copyWith(isEditing: editing);
    }
  }

  void updateContent(String content) {
    final current = state;
    if (current is NoteEditorLoaded) {
      final tasks = MarkdownParser.parseTasks(content);
      state = current.copyWith(
        content: content,
        tasks: tasks,
        hasChanges: true,
      );
    }
  }

  void toggleTask(int index) {
    final current = state;
    if (current is NoteEditorLoaded && index < current.tasks.length) {
      final task = current.tasks[index];
      final newStatus = task.isCompleted ? TaskStatus.pending : TaskStatus.completed;
      final newTasks = [...current.tasks];
      newTasks[index] = task.copyWith(status: newStatus);

      // 更新 Markdown 内容中对应的任务状态
      final newContent = _updateTaskInContent(current.content, index, newStatus);

      state = current.copyWith(
        tasks: newTasks,
        content: newContent,
        hasChanges: true,
      );
    }
  }

  String _updateTaskInContent(String content, int taskIndex, TaskStatus newStatus) {
    final lines = content.split('\n');
    var currentTaskIndex = 0;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (RegExp(r'^[-*+]\s*\[([ xX/\-])\]').hasMatch(line.trim())) {
        if (currentTaskIndex == taskIndex) {
          // 替换状态字符
          final statusChar = switch (newStatus) {
            TaskStatus.completed => 'x',
            TaskStatus.inProgress => '/',
            TaskStatus.cancelled => '-',
            TaskStatus.pending => ' ',
          };
          lines[i] = line.replaceFirstMapped(
            RegExp(r'\[([ xX/\-])\]'),
            (m) => '[$statusChar]',
          );
          break;
        }
        currentTaskIndex++;
      }
    }

    return lines.join('\n');
  }
}

class NoteEditorPage extends ConsumerStatefulWidget {
  const NoteEditorPage({required this.note, super.key});

  final NoteItem note;

  @override
  ConsumerState<NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends ConsumerState<NoteEditorPage>
    with SingleTickerProviderStateMixin, ConsumerTabBarVisibilityMixin {
  late TabController _tabController;
  final TextEditingController _editController = TextEditingController();
  final ScrollController _previewScrollController = ScrollController();
  final NoteStateService _noteStateService = NoteStateService();

  @override
  void initState() {
    super.initState();
    hideTabBar();
    _tabController = TabController(length: 3, vsync: this);
    _restoreNoteState();
  }

  Future<void> _restoreNoteState() async {
    await _noteStateService.init();
    await _noteStateService.markOpened(
      widget.note.path,
      modifiedAt: widget.note.modifiedAt,
    );
    final state = _noteStateService.getState(widget.note.path);
    final offset = state?.scrollOffset;
    if (offset == null || offset <= 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_previewScrollController.hasClients) return;
      final max = _previewScrollController.position.maxScrollExtent;
      _previewScrollController.jumpTo(offset.clamp(0.0, max));
    });
  }

  @override
  void dispose() {
    if (_previewScrollController.hasClients) {
      final offset = _previewScrollController.offset;
      // ignore: discarded_futures
      _noteStateService.setScrollOffset(widget.note.path, offset);
    }
    _previewScrollController.dispose();
    _tabController.dispose();
    _editController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(noteEditorProvider(widget.note));
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : null,
      appBar: AppBar(
        title: Text(widget.note.displayName),
        backgroundColor: isDark ? AppColors.darkSurface : null,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '预览', icon: Icon(Icons.visibility_rounded, size: 20)),
            Tab(text: '任务', icon: Icon(Icons.checklist_rounded, size: 20)),
            Tab(text: '编辑', icon: Icon(Icons.edit_rounded, size: 20)),
          ],
          labelColor: AppColors.primary,
          unselectedLabelColor: isDark ? AppColors.darkOnSurfaceVariant : null,
          indicatorColor: AppColors.primary,
        ),
      ),
      body: switch (state) {
        NoteEditorLoading() => const LoadingWidget(message: '加载中...'),
        NoteEditorError(:final message) => AppErrorWidget(
            message: message,
            onRetry: () =>
                ref.read(noteEditorProvider(widget.note).notifier).loadNote(),
          ),
        NoteEditorLoaded() => TabBarView(
            controller: _tabController,
            children: [
              _buildPreviewTab(context, state, isDark),
              _buildTasksTab(context, state, isDark),
              _buildEditTab(context, state, isDark),
            ],
          ),
      },
    );
  }

  Widget _buildPreviewTab(BuildContext context, NoteEditorLoaded state, bool isDark) => SingleChildScrollView(
      controller: _previewScrollController,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: _MarkdownPreview(
        content: state.content,
        isDark: isDark,
      ),
    );

  Widget _buildTasksTab(BuildContext context, NoteEditorLoaded state, bool isDark) {
    if (state.tasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.checklist_rounded,
              size: 64,
              color: isDark
                  ? AppColors.darkOnSurfaceVariant.withValues(alpha: 0.5)
                  : context.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              '暂无待办任务',
              style: context.textTheme.titleMedium?.copyWith(
                color: isDark ? AppColors.darkOnSurfaceVariant : null,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '使用 - [ ] 语法添加任务',
              style: context.textTheme.bodyMedium?.copyWith(
                color: isDark
                    ? AppColors.darkOnSurfaceVariant.withValues(alpha: 0.7)
                    : context.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return TaskListWidget(
      tasks: state.tasks,
      onToggle: (index) =>
          ref.read(noteEditorProvider(widget.note).notifier).toggleTask(index),
      isDark: isDark,
    );
  }

  Widget _buildEditTab(BuildContext context, NoteEditorLoaded state, bool isDark) {
    // 初始化编辑器内容
    if (_editController.text != state.content && !state.hasChanges) {
      _editController.text = state.content;
    }

    return Column(
      children: [
        // 工具栏
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurfaceVariant : context.colorScheme.surfaceContainerHighest,
            border: Border(
              bottom: BorderSide(
                color: isDark
                    ? AppColors.darkOutline.withValues(alpha: 0.2)
                    : context.colorScheme.outlineVariant,
              ),
            ),
          ),
          child: Row(
            children: [
              _buildToolButton(
                icon: Icons.format_bold_rounded,
                tooltip: '粗体',
                onTap: () => _insertMarkdown('**', '**'),
              ),
              _buildToolButton(
                icon: Icons.format_italic_rounded,
                tooltip: '斜体',
                onTap: () => _insertMarkdown('*', '*'),
              ),
              _buildToolButton(
                icon: Icons.strikethrough_s_rounded,
                tooltip: '删除线',
                onTap: () => _insertMarkdown('~~', '~~'),
              ),
              const VerticalDivider(width: 16),
              _buildToolButton(
                icon: Icons.title_rounded,
                tooltip: '标题',
                onTap: () => _insertMarkdown('## ', ''),
              ),
              _buildToolButton(
                icon: Icons.format_list_bulleted_rounded,
                tooltip: '列表',
                onTap: () => _insertMarkdown('- ', ''),
              ),
              _buildToolButton(
                icon: Icons.check_box_outlined,
                tooltip: '任务',
                onTap: () => _insertMarkdown('- [ ] ', ''),
              ),
              const VerticalDivider(width: 16),
              _buildToolButton(
                icon: Icons.code_rounded,
                tooltip: '代码',
                onTap: () => _insertMarkdown('`', '`'),
              ),
              _buildToolButton(
                icon: Icons.link_rounded,
                tooltip: '链接',
                onTap: () => _insertMarkdown('[', '](url)'),
              ),
            ],
          ),
        ),
        // 编辑区域
        Expanded(
          child: TextField(
            controller: _editController,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 14,
              color: isDark ? AppColors.darkOnSurface : null,
              height: 1.6,
            ),
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.all(AppSpacing.md),
              border: InputBorder.none,
              hintText: '开始编写...',
              hintStyle: TextStyle(
                color: isDark
                    ? AppColors.darkOnSurfaceVariant.withValues(alpha: 0.5)
                    : null,
              ),
            ),
            onChanged: (value) => ref
                .read(noteEditorProvider(widget.note).notifier)
                .updateContent(value),
          ),
        ),
      ],
    );
  }

  Widget _buildToolButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) => IconButton(
      onPressed: onTap,
      icon: Icon(icon, size: 20),
      tooltip: tooltip,
      splashRadius: 20,
    );

  void _insertMarkdown(String prefix, String suffix) {
    final text = _editController.text;
    final selection = _editController.selection;

    if (selection.isValid) {
      final selectedText = text.substring(selection.start, selection.end);
      final newText = '$prefix$selectedText$suffix';
      _editController.value = TextEditingValue(
        text: text.replaceRange(selection.start, selection.end, newText),
        selection: TextSelection.collapsed(
          offset: selection.start + prefix.length + selectedText.length,
        ),
      );
    } else {
      final offset = _editController.selection.baseOffset;
      _editController.value = TextEditingValue(
        text: text.substring(0, offset) + prefix + suffix + text.substring(offset),
        selection: TextSelection.collapsed(offset: offset + prefix.length),
      );
    }

    ref
        .read(noteEditorProvider(widget.note).notifier)
        .updateContent(_editController.text);
  }
}

/// 简单的 Markdown 预览组件
class _MarkdownPreview extends StatelessWidget {
  const _MarkdownPreview({
    required this.content,
    required this.isDark,
  });

  final String content;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final lines = content.split('\n');
    final widgets = <Widget>[];

    for (final line in lines) {
      widgets.add(_buildLine(context, line));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  Widget _buildLine(BuildContext context, String line) {
    final trimmed = line.trim();

    // 空行
    if (trimmed.isEmpty) {
      return const SizedBox(height: 8);
    }

    // 标题
    if (trimmed.startsWith('# ')) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12, top: 16),
        child: Text(
          trimmed.substring(2),
          style: context.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: isDark ? AppColors.darkOnSurface : null,
          ),
        ),
      );
    }
    if (trimmed.startsWith('## ')) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10, top: 14),
        child: Text(
          trimmed.substring(3),
          style: context.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: isDark ? AppColors.darkOnSurface : null,
          ),
        ),
      );
    }
    if (trimmed.startsWith('### ')) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 12),
        child: Text(
          trimmed.substring(4),
          style: context.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: isDark ? AppColors.darkOnSurface : null,
          ),
        ),
      );
    }

    // 任务项
    final taskMatch = RegExp(r'^[-*+]\s*\[([ xX/\-])\]\s*(.+)$').firstMatch(trimmed);
    if (taskMatch != null) {
      final isCompleted = taskMatch.group(1)!.toLowerCase() == 'x';
      final taskContent = taskMatch.group(2)!;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isCompleted ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
              size: 20,
              color: isCompleted ? AppColors.success : (isDark ? AppColors.darkOnSurfaceVariant : null),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                taskContent,
                style: context.textTheme.bodyMedium?.copyWith(
                  decoration: isCompleted ? TextDecoration.lineThrough : null,
                  color: isCompleted
                      ? (isDark ? AppColors.darkOnSurfaceVariant : Colors.grey)
                      : (isDark ? AppColors.darkOnSurface : null),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // 列表项
    if (trimmed.startsWith('- ') || trimmed.startsWith('* ') || trimmed.startsWith('+ ')) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '•  ',
              style: TextStyle(
                color: isDark ? AppColors.darkOnSurface : null,
                fontWeight: FontWeight.bold,
              ),
            ),
            Expanded(
              child: _buildRichText(context, trimmed.substring(2)),
            ),
          ],
        ),
      );
    }

    // 代码块
    if (trimmed.startsWith('```')) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurfaceVariant : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          trimmed.substring(3),
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 13,
            color: isDark ? AppColors.darkOnSurface : null,
          ),
        ),
      );
    }

    // 引用
    if (trimmed.startsWith('> ')) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: AppColors.primary,
              width: 4,
            ),
          ),
          color: isDark
              ? AppColors.darkSurfaceVariant.withValues(alpha: 0.5)
              : Colors.grey.shade50,
        ),
        child: Text(
          trimmed.substring(2),
          style: context.textTheme.bodyMedium?.copyWith(
            fontStyle: FontStyle.italic,
            color: isDark ? AppColors.darkOnSurfaceVariant : null,
          ),
        ),
      );
    }

    // 普通段落
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: _buildRichText(context, line),
    );
  }

  Widget _buildRichText(BuildContext context, String text) => Text(
      _stripMarkdown(text),
      style: context.textTheme.bodyMedium?.copyWith(
        color: isDark ? AppColors.darkOnSurface : null,
        height: 1.6,
      ),
    );

  String _stripMarkdown(String text) => text
        .replaceAllMapped(RegExp(r'\*\*(.+?)\*\*'), (m) => m.group(1)!)
        .replaceAllMapped(RegExp(r'\*(.+?)\*'), (m) => m.group(1)!)
        .replaceAllMapped(RegExp('~~(.+?)~~'), (m) => m.group(1)!)
        .replaceAllMapped(RegExp('`(.+?)`'), (m) => m.group(1)!)
        .replaceAllMapped(RegExp(r'\[(.+?)\]\(.+?\)'), (m) => m.group(1)!);
}
