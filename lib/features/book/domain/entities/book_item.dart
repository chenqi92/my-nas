import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';

/// 支持的电子书格式
enum BookFormat {
  epub,
  pdf,
  txt,
  mobi,
  azw3,
  unknown,
}

/// 电子书实体
class BookItem {
  const BookItem({
    required this.id,
    required this.name,
    required this.path,
    required this.url,
    this.sourceId,
    this.format = BookFormat.unknown,
    this.coverUrl,
    this.author,
    this.description,
    this.size = 0,
    this.lastReadPosition,
    this.lastReadAt,
    this.totalPages,
    this.currentPage,
  });

  /// 从 FileItem 创建
  factory BookItem.fromFileItem(
    FileItem file,
    String url, {
    String? sourceId,
  }) =>
      BookItem(
        id: file.path,
        name: file.name,
        path: file.path,
        url: url,
        sourceId: sourceId,
        format: formatFromExtension(file.name),
        size: file.size,
      );

  final String id;
  final String name;
  final String path;
  final String url;
  final String? sourceId; // 数据源ID，用于流式加载
  final BookFormat format;
  final String? coverUrl;
  final String? author;
  final String? description;
  final int size;
  final String? lastReadPosition; // 阅读位置（如 EPUB 的 CFI）
  final DateTime? lastReadAt;
  final int? totalPages;
  final int? currentPage;

  /// 显示的书名（去除扩展名）
  String get displayName {
    final dotIndex = name.lastIndexOf('.');
    return dotIndex > 0 ? name.substring(0, dotIndex) : name;
  }

  /// 显示的作者
  String get displayAuthor => author ?? appL10n.bookUnknownAuthor;

  /// 显示的文件大小
  String get displaySize {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// 阅读进度百分比
  double get readProgress {
    if (totalPages == null || totalPages == 0 || currentPage == null) return 0;
    return currentPage! / totalPages!;
  }

  /// 从文件扩展名获取格式
  static BookFormat formatFromExtension(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    return switch (ext) {
      'epub' => BookFormat.epub,
      'pdf' => BookFormat.pdf,
      'txt' => BookFormat.txt,
      'mobi' => BookFormat.mobi,
      'azw3' => BookFormat.azw3,
      _ => BookFormat.unknown,
    };
  }

  BookItem copyWith({
    String? id,
    String? name,
    String? path,
    String? url,
    String? sourceId,
    BookFormat? format,
    String? coverUrl,
    String? author,
    String? description,
    int? size,
    String? lastReadPosition,
    DateTime? lastReadAt,
    int? totalPages,
    int? currentPage,
  }) =>
      BookItem(
        id: id ?? this.id,
        name: name ?? this.name,
        path: path ?? this.path,
        url: url ?? this.url,
        sourceId: sourceId ?? this.sourceId,
        format: format ?? this.format,
        coverUrl: coverUrl ?? this.coverUrl,
        author: author ?? this.author,
        description: description ?? this.description,
        size: size ?? this.size,
        lastReadPosition: lastReadPosition ?? this.lastReadPosition,
        lastReadAt: lastReadAt ?? this.lastReadAt,
        totalPages: totalPages ?? this.totalPages,
        currentPage: currentPage ?? this.currentPage,
      );
}
