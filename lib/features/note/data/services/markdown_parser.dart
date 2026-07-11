import 'package:my_nas/features/note/domain/entities/note_item.dart';

/// Markdown 解析器 - 支持任务和特殊语法
class MarkdownParser {
  MarkdownParser._();

  /// 从 Markdown 内容解析任务列表
  static List<TaskItem> parseTasks(String content) {
    final tasks = <TaskItem>[];
    final lines = content.split('\n');

    for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
      final task = _parseTaskLine(lines[lineIndex], sourceLine: lineIndex);
      if (task != null) {
        tasks.add(task);
      }
    }

    return tasks;
  }

  /// 解析单行任务
  /// 支持格式:
  /// - [ ] 待办任务
  /// - [x] 已完成任务
  /// - [/] 进行中任务
  /// - [-] 已取消任务
  /// - [ ] !重要 任务内容
  /// - [ ] !!紧急 任务内容
  /// - [ ] @2024-12-31 带截止日期的任务
  /// - [ ] #标签 任务内容
  static TaskItem? _parseTaskLine(String line, {int? sourceLine}) {
    final trimmed = line.trim();

    // 匹配任务格式: - [ ] 或 * [ ] 或 + [ ]
    final taskRegex = RegExp(r'^[-*+]\s*\[([ xX/\-])\]\s*(.+)$');
    final match = taskRegex.firstMatch(trimmed);

    if (match == null) return null;

    final statusChar = match.group(1)!.toLowerCase();
    var content = match.group(2)!;

    // 解析状态
    final status = switch (statusChar) {
      'x' => TaskStatus.completed,
      '/' => TaskStatus.inProgress,
      '-' => TaskStatus.cancelled,
      _ => TaskStatus.pending,
    };

    // 解析优先级
    var priority = 0;
    if (content.startsWith('!!')) {
      priority = 2;
      content = content.substring(2).trim();
    } else if (content.startsWith('!')) {
      priority = 1;
      content = content.substring(1).trim();
    }

    // 解析截止日期 @YYYY-MM-DD
    DateTime? dueDate;
    final dateRegex = RegExp(r'@(\d{4}-\d{2}-\d{2})');
    final dateMatch = dateRegex.firstMatch(content);
    if (dateMatch != null) {
      try {
        dueDate = DateTime.parse(dateMatch.group(1)!);
      } on FormatException {
        // 忽略无效日期
      }
      content = content.replaceFirst(dateRegex, '').trim();
    }

    // 解析标签 #tag
    final tags = <String>[];
    final tagRegex = RegExp(r'#(\w+)');
    for (final tagMatch in tagRegex.allMatches(content)) {
      tags.add(tagMatch.group(1)!);
    }
    content = content.replaceAll(tagRegex, '').trim();

    return TaskItem(
      content: content,
      status: status,
      dueDate: dueDate,
      priority: priority,
      tags: tags,
      sourceLine: sourceLine,
    );
  }

  /// 将任务列表转换回 Markdown
  static String tasksToMarkdown(List<TaskItem> tasks) {
    final buffer = StringBuffer();

    for (final task in tasks) {
      buffer.writeln(_taskToMarkdownLine(task));
    }

    return buffer.toString();
  }

  /// 将单个任务转换为 Markdown 行
  static String _taskToMarkdownLine(TaskItem task) {
    final buffer = StringBuffer('- [')
      // 状态
      ..write(switch (task.status) {
        TaskStatus.completed => 'x',
        TaskStatus.inProgress => '/',
        TaskStatus.cancelled => '-',
        TaskStatus.pending => ' ',
      })
      ..write('] ');

    // 优先级
    if (task.priority == 2) {
      buffer.write('!! ');
    } else if (task.priority == 1) {
      buffer.write('! ');
    }

    // 内容
    buffer.write(task.content);

    // 截止日期
    if (task.dueDate != null) {
      final date = task.dueDate!;
      buffer.write(
        ' @${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
      );
    }

    // 标签
    for (final tag in task.tags) {
      buffer.write(' #$tag');
    }

    return buffer.toString();
  }

  /// 检测笔记类型
  static NoteType detectNoteType(String content) {
    final lines = content.split('\n');
    var taskCount = 0;
    var totalLines = 0;

    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      totalLines++;
      if (_parseTaskLine(line) != null) {
        taskCount++;
      }
    }

    // 如果超过 50% 的非空行是任务，则认为是待办清单
    if (totalLines > 0 && taskCount / totalLines > 0.5) {
      return NoteType.todo;
    }

    // 检查是否是日记（以日期开头）
    final firstLine = lines.firstWhere(
      (l) => l.trim().isNotEmpty,
      orElse: () => '',
    );
    if (RegExp(r'^\d{4}[-/]\d{2}[-/]\d{2}').hasMatch(firstLine)) {
      return NoteType.diary;
    }

    // 检查是否是会议记录
    final lowerContent = content.toLowerCase();
    if (lowerContent.contains('会议') ||
        lowerContent.contains('meeting') ||
        lowerContent.contains('参会人') ||
        lowerContent.contains('attendees')) {
      return NoteType.meeting;
    }

    return NoteType.normal;
  }

  /// 提取笔记中的所有标签
  static List<String> extractTags(String content) {
    final tags = <String>{};
    final tagRegex = RegExp(r'#(\w+)');

    for (final match in tagRegex.allMatches(content)) {
      tags.add(match.group(1)!);
    }

    return tags.toList();
  }

  /// 提取笔记摘要（前 N 个字符）
  static String extractSummary(String content, {int maxLength = 100}) {
    // 移除 Markdown 标记
    final text = content
        .replaceAll(RegExp(r'^#+\s*', multiLine: true), '') // 标题
        .replaceAll(RegExp(r'\*\*(.+?)\*\*'), r'$1') // 粗体
        .replaceAll(RegExp(r'\*(.+?)\*'), r'$1') // 斜体
        .replaceAll(RegExp('`(.+?)`'), r'$1') // 代码
        .replaceAll(RegExp(r'\[(.+?)\]\(.+?\)'), r'$1') // 链接
        .replaceAll(RegExp(r'^[-*+]\s*\[.\]\s*', multiLine: true), '') // 任务
        .replaceAll(RegExp(r'\n+'), ' ') // 换行
        .trim();

    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}...';
  }
}
