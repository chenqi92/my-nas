/// 本地文件名清洗工具。
///
/// 远端 NAS / 媒体服务器返回的文件名可能包含 Windows 文件系统禁止的字符
/// （`\ / : * ? " < > |`）、以保留设备名命名（`CON` / `NUL` / `COM1` …）、
/// 以点或空格结尾，或长度超过单段上限。这些名字直接拼进本地路径后
/// `File()` 会抛 `FileSystemException` / `PathTooLongException`。
///
/// 清洗只针对**本地落地的单个文件名**，不处理路径分隔符语义 —— 传入的
/// `/` 会被当作非法字符替换掉。拼接远端路径请用 `nas_path.dart`。
library;

import 'dart:convert';

/// Windows 禁止出现在文件名里的字符（POSIX 只禁 `/` 和 NUL，取并集以保证
/// 同一份文件名在各平台都能落地，避免跨设备同步时行为分叉）。
final RegExp _illegalChars = RegExp(r'[<>:"/\\|?*]');

/// C0 控制字符（0x00-0x1F）在两个平台都不合法。
final RegExp _controlChars = RegExp(r'[\x00-\x1F\x7F]');

/// Windows 保留设备名，带扩展名同样被拒（`CON.txt` 也不行）。
const Set<String> _reservedNames = {
  'CON', 'PRN', 'AUX', 'NUL',
  'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9',
  'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9',
};

/// 单个路径段的字节上限。NTFS/ext4/APFS 都是 255，这里留出余量给调用方
/// 可能追加的前缀（如 `share_` / `photo_download_`）。
const int _maxNameBytes = 200;

/// 清洗 [name]，返回可安全用于本地文件系统的文件名。
///
/// - 非法字符与控制字符替换为 [replacement]
/// - 剥除首尾空白、尾部的点和空格（Windows 会静默丢弃，导致名字对不上）
/// - Windows 保留设备名加下划线前缀
/// - 按 UTF-8 字节截断到 [maxBytes]，保留扩展名，不切裂多字节字符
/// - 空结果回退为 [fallback]
String sanitizeFileName(
  String name, {
  String replacement = '_',
  int maxBytes = _maxNameBytes,
  String fallback = 'unnamed',
}) {
  var result = name
      .replaceAll(_illegalChars, replacement)
      .replaceAll(_controlChars, replacement)
      .trim();

  // Windows 丢弃尾部的点和空格：`a.txt.` 实际落地为 `a.txt`，
  // 后续按原名查找会失配，因此这里主动剥掉。
  result = result.replaceAll(RegExp(r'[. ]+$'), '');

  if (result.isEmpty) return fallback;

  // 保留名判断基于首个点之前的部分，大小写不敏感。
  final stem = result.split('.').first.toUpperCase();
  if (_reservedNames.contains(stem)) {
    result = '_$result';
  }

  return _truncateToBytes(result, maxBytes, fallback);
}

/// 按 UTF-8 字节长度截断，尽量保留扩展名且不切裂多字节字符。
String _truncateToBytes(String name, int maxBytes, String fallback) {
  if (utf8.encode(name).length <= maxBytes) return name;

  final dotIndex = name.lastIndexOf('.');
  // 只有点不在首位、且扩展名长度合理时才当作扩展名保留。
  final hasExt = dotIndex > 0 && name.length - dotIndex <= 16;
  final ext = hasExt ? name.substring(dotIndex) : '';
  final extBytes = utf8.encode(ext).length;

  // 扩展名本身就超限时整体丢弃扩展名，退化为纯截断。
  if (extBytes >= maxBytes) {
    return _truncateStem(name, maxBytes, fallback);
  }

  final stem = hasExt ? name.substring(0, dotIndex) : name;
  final truncatedStem = _truncateStem(stem, maxBytes - extBytes, fallback);
  return '$truncatedStem$ext';
}

/// 逐 rune 累加字节数，超限即停，保证不产生半个字符。
String _truncateStem(String stem, int maxBytes, String fallback) {
  final buffer = StringBuffer();
  var bytes = 0;
  for (final rune in stem.runes) {
    final char = String.fromCharCode(rune);
    final charBytes = utf8.encode(char).length;
    if (bytes + charBytes > maxBytes) break;
    buffer.write(char);
    bytes += charBytes;
  }
  final result = buffer.toString().trimRight();
  return result.isEmpty ? fallback : result;
}
