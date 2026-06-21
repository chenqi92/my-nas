// MOBI 文本解压缩
//
// 支持 PalmDOC (LZ77) 和 HUFF/CDIC 压缩
// 基于 KindleUnpack 的解析逻辑移植到 Dart

import 'dart:typed_data';
import 'package:my_nas/core/i18n/app_l10n.dart';

import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/book/data/services/mobi/mobi_header.dart';
import 'package:my_nas/features/book/data/services/mobi/mobi_huffcdic.dart';
import 'package:my_nas/features/book/data/services/mobi/mobi_record.dart';
import 'package:my_nas/features/book/data/services/mobi/mobi_utils.dart';

/// MOBI 文本提取器
class MobiTextExtractor {
  /// 提取文本内容
  ///
  /// 返回解压后的 HTML 内容
  static Future<String> extractText(MobiHeader header) async {
    final chunks = <Uint8List>[];

    // 计算文本记录范围
    final firstRecord = header.firstContentRecord;
    final lastRecord = firstRecord + header.textRecordCount;

    logger.d('提取文本: records $firstRecord-${lastRecord - 1}');

    // HUFF/CDIC 压缩：先构建解码器（失败则保持 null，后续优雅降级为空）
    final huffReader = header.compression == MobiCompression.huffCdic
        ? _buildHuffCdicReader(header)
        : null;

    for (var i = firstRecord; i < lastRecord && i < header.records.length; i++) {
      final record = header.records[i];
      var data = record.data;

      // 移除尾部额外数据
      data = _removeTrailingData(data, header.extraDataFlags);

      // 解压缩
      final decompressed = _decompress(data, header.compression, huffReader);
      if (decompressed.isNotEmpty) {
        chunks.add(decompressed);
      }
    }

    // 合并所有块
    final totalLength = chunks.fold<int>(0, (sum, c) => sum + c.length);
    final result = Uint8List(totalLength);
    var offset = 0;
    for (final chunk in chunks) {
      result.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }

    // 解码文本
    return decodeText(result, isUtf8: header.isUtf8);
  }

  /// 移除记录尾部的额外数据（与 mobi_parser_service._removeTrailingEntries 一致）。
  ///
  /// 顺序很重要：先按 bit15..1 剥离后向变长编码的尾部数据块，最后才处理
  /// bit0 的多字节字符重叠（其重叠计数要在 entries 已剥离后的末字节读取）。
  static Uint8List _removeTrailingData(Uint8List data, int extraDataFlags) {
    if (extraDataFlags == 0 || data.isEmpty) return data;

    var end = data.length;

    // bit1..bit15：后向变长编码的尾部数据块（不含 bit0 多字节重叠）
    for (var bit = 15; bit >= 1; bit--) {
      if ((extraDataFlags & (1 << bit)) != 0) {
        final size = _sizeOfTrailingDataEntry(data, end);
        end -= size;
        if (end <= 0) return Uint8List(0);
      }
    }

    // bit0：多字节字符重叠，末字节低 2 位为重叠字节数（+1 含该计数字节）
    if ((extraDataFlags & 0x1) != 0 && end > 0) {
      final overlap = data[end - 1] & 0x03;
      end = end - overlap - 1;
      if (end < 0) end = 0;
    }

    return end < data.length ? data.sublist(0, end) : data;
  }

  /// 计算尾部数据条目的总字节数（含其变长编码自身）。
  /// 对应 KindleUnpack getSizeOfTrailingDataEntry：读末尾最多 4 字节，遇最高位为 1 的字节重置累加。
  static int _sizeOfTrailingDataEntry(Uint8List data, int end) {
    var num = 0;
    final start = end - 4 < 0 ? 0 : end - 4;
    for (var i = start; i < end; i++) {
      final v = data[i];
      if ((v & 0x80) != 0) num = 0;
      num = (num << 7) | (v & 0x7F);
    }
    return num;
  }

  /// 解压缩数据
  static Uint8List _decompress(
    Uint8List data,
    MobiCompression compression,
    MobiHuffCdicReader? huffReader,
  ) {
    switch (compression) {
      case MobiCompression.none:
        return data;
      case MobiCompression.palmDoc:
        return _decompressPalmDoc(data);
      case MobiCompression.huffCdic:
        // HUFF/CDIC：解码器未就绪或单条记录解码异常时回退为空
        if (huffReader == null || !huffReader.isReady) {
          return Uint8List(0);
        }
        try {
          return huffReader.unpack(data);
        } on Object catch (e) {
          logger.w('HUFF/CDIC 记录解压失败，跳过该记录', e);
          return Uint8List(0);
        }
    }
  }

  /// 构建 HUFF/CDIC 解码器
  ///
  /// 从 header 定位 HUFF 记录（首条）与后续 CDIC 记录并加载码表/字典。
  /// 任何异常都返回 null，由调用方优雅降级（返回空文本 + 警告）。
  static MobiHuffCdicReader? _buildHuffCdicReader(MobiHeader header) {
    try {
      final first = header.huffmanFirstRecord;
      final count = header.huffmanRecordCount;
      if (first <= 0 || count <= 0 || first >= header.records.length) {
        logger.w('HUFF/CDIC 记录定位无效: first=$first count=$count');
        return null;
      }

      // 第一条为 HUFF 记录，其余为 CDIC 记录
      final reader = MobiHuffCdicReader()..loadHuff(header.records[first].data);
      for (var i = 1; i < count; i++) {
        final idx = first + i;
        if (idx >= header.records.length) break;
        reader.loadCdic(header.records[idx].data);
      }

      if (!reader.isReady) {
        logger.w('HUFF/CDIC 码表或字典为空');
        return null;
      }
      return reader;
    } on Object catch (e) {
      logger.w('HUFF/CDIC 解码器构建失败，回退为不支持', e);
      return null;
    }
  }

  /// PalmDOC (LZ77) 解压缩
  ///
  /// PalmDOC 使用简化的 LZ77 算法:
  /// - 0x00: 字面量 null
  /// - 0x01-0x08: 复制接下来的 1-8 个字节
  /// - 0x09-0x7F: 字面量字节
  /// - 0x80-0xBF: 距离-长度对
  /// - 0xC0-0xFF: 空格 + 字符
  static Uint8List _decompressPalmDoc(Uint8List compressed) {
    final output = <int>[];
    var i = 0;

    while (i < compressed.length) {
      final byte = compressed[i++];

      if (byte == 0) {
        // 字面量 0
        output.add(byte);
      } else if (byte >= 1 && byte <= 8) {
        // 复制接下来的 1-8 个字节
        for (var j = 0; j < byte && i < compressed.length; j++) {
          output.add(compressed[i++]);
        }
      } else if (byte >= 9 && byte <= 0x7F) {
        // 字面量字节
        output.add(byte);
      } else if (byte >= 0x80 && byte <= 0xBF) {
        // 距离-长度对
        if (i >= compressed.length) break;

        final nextByte = compressed[i++];
        final distance = ((byte & 0x3F) << 5) | (nextByte >> 3);
        final length = (nextByte & 0x07) + 3;

        // 从输出缓冲区复制
        if (distance > 0 && distance <= output.length) {
          for (var j = 0; j < length; j++) {
            final srcIndex = output.length - distance;
            if (srcIndex >= 0 && srcIndex < output.length) {
              output.add(output[srcIndex]);
            }
          }
        }
      } else {
        // 0xC0-0xFF: 空格 + 字符
        output
          ..add(0x20) // 空格
          ..add(byte ^ 0x80);
      }
    }

    return Uint8List.fromList(output);
  }
}

/// 从 HTML 内容中提取章节
///
/// 当没有 NCX 索引时，通过分析 HTML 标题标签提取章节
class MobiChapterExtractor {
  /// 从 HTML 内容提取章节
  static List<MobiChapter> extractFromHtml(
    String html, {
    int maxChapters = 200,
  }) {
    final chapters = <MobiChapter>[];

    // 匹配 h1-h3 标题
    final pattern = RegExp(
      r'<h([1-3])[^>]*>([^<]{1,100})</h\1>',
      caseSensitive: false,
    );

    for (final match in pattern.allMatches(html)) {
      if (chapters.length >= maxChapters) break;

      final level = int.tryParse(match.group(1) ?? '1') ?? 1;
      var title = match.group(2)?.trim() ?? '';

      // 移除内部 HTML 标签
      title = title.replaceAll(RegExp('<[^>]*>'), '').trim();

      if (title.isNotEmpty && title.length < 100) {
        chapters.add(MobiChapter(
          title: title,
          startOffset: match.start,
          level: level,
        ));
      }
    }

    // 如果没有找到 h1-h3，尝试查找 mbp:pagebreak
    if (chapters.isEmpty) {
      final pageBreakPattern = RegExp(
        r'<mbp:pagebreak\s*/?>',
        caseSensitive: false,
      );

      var chapterNum = 1;
      for (final match in pageBreakPattern.allMatches(html)) {
        if (chapters.length >= maxChapters) break;

        chapters.add(MobiChapter(
          title: appL10n.bookChapterTitle(chapterNum),
          startOffset: match.end,
          level: 1,
        ));
        chapterNum++;
      }
    }

    return chapters;
  }
}
