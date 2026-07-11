import 'package:my_nas/nas_adapters/base/nas_file_system.dart';

/// 笔记类型
enum NoteType {
  /// 普通笔记
  normal,

  /// 待办清单
  todo,

  /// 日记
  diary,

  /// 会议记录
  meeting,
}

/// 任务状态
enum TaskStatus { pending, inProgress, completed, cancelled }

/// 任务项
class TaskItem {
  const TaskItem({
    required this.content,
    this.status = TaskStatus.pending,
    this.dueDate,
    this.priority = 0,
    this.tags = const [],
    this.sourceLine,
  });

  final String content;
  final TaskStatus status;
  final DateTime? dueDate;
  final int priority; // 0: 普通, 1: 重要, 2: 紧急
  final List<String> tags;
  final int? sourceLine;

  bool get isCompleted => status == TaskStatus.completed;
  bool get isPending => status == TaskStatus.pending;
  bool get isOverdue =>
      dueDate != null && dueDate!.isBefore(DateTime.now()) && !isCompleted;

  TaskItem copyWith({
    String? content,
    TaskStatus? status,
    DateTime? dueDate,
    int? priority,
    List<String>? tags,
    int? sourceLine,
  }) => TaskItem(
    content: content ?? this.content,
    status: status ?? this.status,
    dueDate: dueDate ?? this.dueDate,
    priority: priority ?? this.priority,
    tags: tags ?? this.tags,
    sourceLine: sourceLine ?? this.sourceLine,
  );
}

/// 笔记实体
class NoteItem {
  const NoteItem({
    required this.id,
    required this.name,
    required this.path,
    required this.url,
    this.content,
    this.type = NoteType.normal,
    this.tasks = const [],
    this.tags = const [],
    this.size = 0,
    this.modifiedAt,
    this.createdAt,
  });

  /// 从 FileItem 创建
  factory NoteItem.fromFileItem(FileItem file, String url) => NoteItem(
    id: file.path,
    name: file.name,
    path: file.path,
    url: url,
    size: file.size,
    modifiedAt: file.modifiedTime,
  );

  final String id;
  final String name;
  final String path;
  final String url;
  final String? content;
  final NoteType type;
  final List<TaskItem> tasks;
  final List<String> tags;
  final int size;
  final DateTime? modifiedAt;
  final DateTime? createdAt;

  /// 显示的名称（去除扩展名）
  String get displayName {
    final dotIndex = name.lastIndexOf('.');
    return dotIndex > 0 ? name.substring(0, dotIndex) : name;
  }

  /// 任务统计
  int get totalTasks => tasks.length;
  int get completedTasks => tasks.where((t) => t.isCompleted).length;
  int get pendingTasks => tasks.where((t) => t.isPending).length;
  int get overdueTasks => tasks.where((t) => t.isOverdue).length;

  /// 任务完成进度
  double get taskProgress => totalTasks > 0 ? completedTasks / totalTasks : 0;

  /// 是否有待办任务
  bool get hasTasks => tasks.isNotEmpty;

  NoteItem copyWith({
    String? id,
    String? name,
    String? path,
    String? url,
    String? content,
    NoteType? type,
    List<TaskItem>? tasks,
    List<String>? tags,
    int? size,
    DateTime? modifiedAt,
    DateTime? createdAt,
  }) => NoteItem(
    id: id ?? this.id,
    name: name ?? this.name,
    path: path ?? this.path,
    url: url ?? this.url,
    content: content ?? this.content,
    type: type ?? this.type,
    tasks: tasks ?? this.tasks,
    tags: tags ?? this.tags,
    size: size ?? this.size,
    modifiedAt: modifiedAt ?? this.modifiedAt,
    createdAt: createdAt ?? this.createdAt,
  );
}
