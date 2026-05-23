/// 字幕格式枚举：与 [subtitleExtensions] 对应。
enum SubtitleFormat {
  srt,
  ass,
  vtt;

  static SubtitleFormat? fromExtension(String ext) {
    final e = ext.toLowerCase();
    if (e == 'srt' || e == '.srt') return SubtitleFormat.srt;
    if (e == 'ass' || e == '.ass' || e == 'ssa' || e == '.ssa') {
      return SubtitleFormat.ass;
    }
    if (e == 'vtt' || e == '.vtt') return SubtitleFormat.vtt;
    return null;
  }

  String get extension {
    switch (this) {
      case SubtitleFormat.srt:
        return 'srt';
      case SubtitleFormat.ass:
        return 'ass';
      case SubtitleFormat.vtt:
        return 'vtt';
    }
  }
}

/// 单条字幕。
/// - [originalText] 原文（保留换行；ASS 里是 Dialogue Text 字段）
/// - [extra] 仅供序列化时还原的非文本信息（如 ASS 一整行的前 9 字段）
class SubtitleCue {
  SubtitleCue({
    required this.index,
    required this.start,
    required this.end,
    required this.originalText,
    this.extra,
  });

  final int index;
  final Duration start;
  final Duration end;
  final String originalText;
  final Map<String, String>? extra;
}

/// 已解析的字幕：原始内容 + 提取的 cues + 序列化所需的 header。
class ParsedSubtitle {
  ParsedSubtitle({
    required this.format,
    required this.cues,
    this.header = '',
    this.eventFormat,
  });

  final SubtitleFormat format;
  final List<SubtitleCue> cues;

  /// ASS / VTT 的头部（[Script Info] / [V4+ Styles] / WEBVTT 之前的元数据），
  /// 序列化时会原样拼回。
  final String header;

  /// ASS Events 段的 Format 行（顺序）：序列化 Dialogue 时需要按这个顺序输出。
  final List<String>? eventFormat;
}
