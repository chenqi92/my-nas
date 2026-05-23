/// Spotlight 索引条目类型。
///
/// 与 macos/Runner/SpotlightChannel.swift 的 contentType 映射一一对应。
enum SpotlightItemKind {
  video,
  music,
  book,
  comic,
  note;

  /// 用于深链与 native channel 的 wire format。
  String get wireName => name;
}

/// Spotlight 索引条目模型（标题级元数据）。
class SpotlightItem {
  const SpotlightItem({
    required this.id,
    required this.kind,
    required this.title,
    this.subtitle,
    this.thumbPath,
  });

  /// 全局唯一 id。
  ///
  /// 形如 `mynas://video/<encodedRawId>`，落到 macOS NSUserActivity
  /// `userInfo[CSSearchableItemActivityIdentifier]`，
  /// 由 SpotlightDeepLinkHandler 反解出 [kind] 与原始 id。
  final String id;

  final SpotlightItemKind kind;

  final String title;

  final String? subtitle;

  /// 本地缩略图绝对路径（仅本地 file path 有效，远端 URL 不支持）。
  final String? thumbPath;

  Map<String, Object?> toChannelMap() => {
        'id': id,
        'kind': kind.wireName,
        'title': title,
        'subtitle': subtitle,
        'thumbPath': thumbPath,
      };
}
