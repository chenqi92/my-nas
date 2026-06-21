// MOBI 头部解析器
//
// 解析 Palm Database 头部、MOBI 头部、EXTH 头部
// 基于 KindleUnpack 的解析逻辑移植到 Dart
// 参考: https://wiki.mobileread.com/wiki/MOBI

import 'dart:typed_data';

import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/book/data/services/mobi/mobi_record.dart';
import 'package:my_nas/features/book/data/services/mobi/mobi_utils.dart';

/// MOBI 文件头部信息
class MobiHeader {
  const MobiHeader({
    required this.title,
    required this.compression,
    required this.encoding,
    required this.mobiType,
    required this.textRecordCount,
    required this.records,
    this.author,
    this.publisher,
    this.description,
    this.isbn,
    this.publishDate,
    this.firstContentRecord = 1,
    this.firstImageRecord,
    this.firstNonBookRecord,
    this.ncxIndex,
    this.fullNameOffset,
    this.fullNameLength,
    this.mobiVersion = 0,
    this.exthFlags = 0,
    this.hasKf8 = false,
    this.kf8BoundaryRecord,
    this.extraDataFlags = 0,
    this.huffmanFirstRecord = 0,
    this.huffmanRecordCount = 0,
  });

  /// 书籍标题
  final String title;

  /// 压缩类型
  final MobiCompression compression;

  /// 文本编码
  final MobiEncoding encoding;

  /// MOBI 类型
  final MobiType mobiType;

  /// 文本记录数量
  final int textRecordCount;

  /// 所有记录
  final List<MobiRecord> records;

  // EXTH 元数据
  final String? author;
  final String? publisher;
  final String? description;
  final String? isbn;
  final String? publishDate;

  /// 第一个内容记录索引
  final int firstContentRecord;

  /// 第一个图片记录索引
  final int? firstImageRecord;

  /// 第一个非书籍记录索引
  final int? firstNonBookRecord;

  /// NCX 索引记录位置（用于目录）
  final int? ncxIndex;

  /// 完整书名偏移
  final int? fullNameOffset;

  /// 完整书名长度
  final int? fullNameLength;

  /// MOBI 版本
  final int mobiVersion;

  /// EXTH 标志
  final int exthFlags;

  /// 是否包含 KF8 部分
  final bool hasKf8;

  /// KF8 边界记录
  final int? kf8BoundaryRecord;

  /// 额外数据标志
  final int extraDataFlags;

  /// 第一个 HUFF/CDIC 压缩记录索引（仅 HUFF/CDIC 压缩时有效）
  final int huffmanFirstRecord;

  /// HUFF/CDIC 压缩记录数量（1 个 HUFF + 若干 CDIC）
  final int huffmanRecordCount;

  /// 是否有 NCX 目录
  bool get hasNcx => ncxIndex != null && ncxIndex! > 0;

  /// 是否有 EXTH 头部
  bool get hasExth => (exthFlags & 0x40) != 0;

  /// 是否为 UTF-8 编码
  bool get isUtf8 => encoding == MobiEncoding.utf8;

  @override
  String toString() => 'MobiHeader('
      'title=$title, '
      'compression=${compression.label}, '
      'encoding=${encoding.label}, '
      'textRecords=$textRecordCount, '
      'hasNcx=$hasNcx, '
      'hasKf8=$hasKf8)';
}

/// MOBI 头部解析器
class MobiHeaderParser {
  /// 解析 MOBI 文件头部
  ///
  /// 返回 MobiHeader，如果解析失败则返回 null
  static MobiHeader? parse(Uint8List bytes) {
    try {
      // 验证最小长度
      if (bytes.length < 78) {
        logger.w('MOBI 文件太小: ${bytes.length} bytes');
        return null;
      }

      // 1. 解析 Palm Database 头部
      final pdbHeader = _parsePdbHeader(bytes);
      if (pdbHeader == null) {
        return null;
      }

      // 2. 读取记录偏移表
      final records = _readRecords(bytes, pdbHeader.numRecords);
      if (records.isEmpty) {
        logger.w('MOBI 无有效记录');
        return null;
      }

      // 3. 解析第一个记录（包含 PalmDOC、MOBI、EXTH 头部）
      final record0 = records[0].data;
      if (record0.length < 16) {
        logger.w('Record 0 太小');
        return null;
      }

      // 4. 解析 PalmDOC 头部
      final compression = MobiCompression.fromValue(readUint16BE(record0, 0));
      final textLength = readUint32BE(record0, 4);
      final textRecordCount = readUint16BE(record0, 8);
      // maxRecordSize at offset 10 (unused)

      logger.d('PalmDOC: compression=${compression.label}, '
          'textLength=$textLength, textRecords=$textRecordCount');

      // 5. 检查是否有 MOBI 头部
      var encoding = MobiEncoding.cp1252;
      var mobiType = MobiType.mobipocketBook;
      var mobiVersion = 0;
      var exthFlags = 0;
      var firstImageRecord = 0;
      var firstNonBookRecord = 0;
      int? ncxIndex;
      int? fullNameOffset;
      int? fullNameLength;
      var extraDataFlags = 0;
      var huffmanFirstRecord = 0;
      var huffmanRecordCount = 0;

      String? author;
      String? publisher;
      String? description;
      String? isbn;
      String? publishDate;

      // MOBI 头部从 offset 16 开始
      if (record0.length >= 132) {
        final mobiId = readFixedString(record0, 16, 4);
        if (mobiId == 'MOBI') {
          // 解析 MOBI 头部
          final mobiHeaderLength = readUint32BE(record0, 20);
          mobiType = MobiType.fromValue(readUint32BE(record0, 24));
          encoding = MobiEncoding.fromValue(readUint32BE(record0, 28));

          // 更多 MOBI 头部字段
          if (record0.length >= 84) {
            firstNonBookRecord = readUint32BE(record0, 80);
          }
          if (record0.length >= 88) {
            fullNameOffset = readUint32BE(record0, 84);
          }
          if (record0.length >= 92) {
            fullNameLength = readUint32BE(record0, 88);
          }
          if (record0.length >= 112) {
            firstImageRecord = readUint32BE(record0, 108);
          }
          // HUFF/CDIC 压缩记录定位（绝对偏移，自 record0 起始）
          // 0x70=112: 第一个 HUFF/CDIC 记录索引
          // 0x74=116: HUFF/CDIC 记录数量
          if (record0.length >= 120) {
            huffmanFirstRecord = readUint32BE(record0, 112);
            huffmanRecordCount = readUint32BE(record0, 116);
          }
          if (record0.length >= 132) {
            exthFlags = readUint32BE(record0, 128);
          }
          if (record0.length >= 180) {
            mobiVersion = readUint32BE(record0, 104);
          }
          if (record0.length >= 248) {
            ncxIndex = readUint32BE(record0, 244);
            // 0xFFFFFFFF 表示没有 NCX
            if (ncxIndex == 0xFFFFFFFF || ncxIndex == 0) {
              ncxIndex = null;
            }
          }
          // Extra Record Data Flags 是 0xF0 起的 4 字节字段，有效标志位在低 16 位（大端 → 0xF2=242）
          if (record0.length >= 244) {
            extraDataFlags = readUint16BE(record0, 242);
          }

          logger.d('MOBI: type=${mobiType.label}, encoding=${encoding.label}, '
              'version=$mobiVersion, exthFlags=$exthFlags, '
              'firstImage=$firstImageRecord, ncxIndex=$ncxIndex');

          // 6. 解析 EXTH 头部（如果存在）
          if ((exthFlags & 0x40) != 0) {
            final exthStart = 16 + mobiHeaderLength;
            final exthData = _parseExth(record0, exthStart);
            author = exthData['author'];
            publisher = exthData['publisher'];
            description = exthData['description'];
            isbn = exthData['isbn'];
            publishDate = exthData['publishDate'];
          }
        }
      }

      // 7. 获取完整书名
      var title = pdbHeader.name;
      if (fullNameOffset != null &&
          fullNameLength != null &&
          fullNameLength > 0) {
        final nameBytes = safeSublist(
          record0,
          fullNameOffset,
          fullNameOffset + fullNameLength,
        );
        if (nameBytes.isNotEmpty) {
          // 正确解码 UTF-8 文本
          if (encoding == MobiEncoding.utf8) {
            try {
              title = utf8Decode(nameBytes);
            } on FormatException {
              // 解码失败，尝试作为 Latin-1 处理
              title = String.fromCharCodes(nameBytes);
            }
          } else {
            title = readFixedString(nameBytes, 0, nameBytes.length);
          }
        }
      }

      // 8. 检查 KF8 边界
      int? kf8BoundaryRecord;
      var hasKf8 = false;
      if (mobiType == MobiType.kf8) {
        hasKf8 = true;
      } else {
        // 检查是否为 MOBI7+KF8 混合文件
        for (var i = records.length - 1; i > 0; i--) {
          final rec = records[i].data;
          if (rec.length >= 8) {
            final marker = readFixedString(rec, 0, 8);
            if (marker == 'BOUNDARY') {
              kf8BoundaryRecord = i;
              hasKf8 = true;
              logger.d('发现 KF8 边界记录: $i');
              break;
            }
          }
        }
      }

      return MobiHeader(
        title: title.trim(),
        compression: compression,
        encoding: encoding,
        mobiType: mobiType,
        textRecordCount: textRecordCount,
        records: records,
        author: author,
        publisher: publisher,
        description: description,
        isbn: isbn,
        publishDate: publishDate,
        firstContentRecord: 1,
        firstImageRecord: firstImageRecord > 0 ? firstImageRecord : null,
        firstNonBookRecord: firstNonBookRecord > 0 ? firstNonBookRecord : null,
        ncxIndex: ncxIndex,
        fullNameOffset: fullNameOffset,
        fullNameLength: fullNameLength,
        mobiVersion: mobiVersion,
        exthFlags: exthFlags,
        hasKf8: hasKf8,
        kf8BoundaryRecord: kf8BoundaryRecord,
        extraDataFlags: extraDataFlags,
        huffmanFirstRecord: huffmanFirstRecord,
        huffmanRecordCount: huffmanRecordCount,
      );
    } on Exception catch (e, st) {
      logger.e('MOBI 头部解析失败', e, st);
      return null;
    }
  }

  /// 解析 Palm Database 头部
  static _PdbHeader? _parsePdbHeader(Uint8List bytes) {
    // Palm Database 头部结构:
    // 0-31: 名称 (32 bytes)
    // 32-33: 属性
    // 34-35: 版本
    // 60-63: 类型
    // 64-67: 创建者
    // 76-77: 记录数量

    final name = readFixedString(bytes, 0, 32);
    final type = readFixedString(bytes, 60, 4);
    final creator = readFixedString(bytes, 64, 4);
    final numRecords = readUint16BE(bytes, 76);

    logger.d('PDB: name=$name, type=$type, creator=$creator, '
        'records=$numRecords');

    // 验证类型
    if (type != 'BOOK' || creator != 'MOBI') {
      logger.w('不是有效的 MOBI 文件: type=$type, creator=$creator');
      return null;
    }

    return _PdbHeader(name: name, numRecords: numRecords);
  }

  /// 读取所有记录
  static List<MobiRecord> _readRecords(Uint8List bytes, int numRecords) {
    final records = <MobiRecord>[];

    // 记录偏移表从 offset 78 开始
    // 每条记录 8 字节 (4 字节偏移 + 4 字节属性)
    final offsets = <int>[];

    for (var i = 0; i < numRecords; i++) {
      final tableOffset = 78 + i * 8;
      if (tableOffset + 4 > bytes.length) break;

      final offset = readUint32BE(bytes, tableOffset);
      if (offset < bytes.length) {
        offsets.add(offset);
      } else {
        break;
      }
    }

    // 读取记录数据
    for (var i = 0; i < offsets.length; i++) {
      final start = offsets[i];
      final end = i + 1 < offsets.length ? offsets[i + 1] : bytes.length;

      if (start < end && end <= bytes.length) {
        records.add(MobiRecord(
          index: i,
          offset: start,
          data: bytes.sublist(start, end),
        ));
      }
    }

    return records;
  }

  /// 解析 EXTH 头部
  static Map<String, String?> _parseExth(Uint8List record, int exthStart) {
    final result = <String, String?>{
      'author': null,
      'publisher': null,
      'description': null,
      'isbn': null,
      'publishDate': null,
    };

    if (exthStart + 12 > record.length) return result;

    final exthId = readFixedString(record, exthStart, 4);
    if (exthId != 'EXTH') return result;

    // headerLength at offset 4 (unused)
    final recordCount = readUint32BE(record, exthStart + 8);

    var offset = exthStart + 12;

    for (var i = 0; i < recordCount && offset + 8 <= record.length; i++) {
      final recordType = readUint32BE(record, offset);
      final recordLength = readUint32BE(record, offset + 4);

      if (recordLength < 8 || offset + recordLength > record.length) break;

      final dataLength = recordLength - 8;
      final data = safeSublist(record, offset + 8, offset + 8 + dataLength);

      // EXTH 记录类型
      // 100: 作者
      // 101: 出版社
      // 103: 描述
      // 104: ISBN
      // 106: 出版日期
      switch (recordType) {
        case 100:
          result['author'] = String.fromCharCodes(data).trim();
        case 101:
          result['publisher'] = String.fromCharCodes(data).trim();
        case 103:
          result['description'] = String.fromCharCodes(data).trim();
        case 104:
          result['isbn'] = String.fromCharCodes(data).trim();
        case 106:
          result['publishDate'] = String.fromCharCodes(data).trim();
      }

      offset += recordLength;
    }

    return result;
  }
}

/// Palm Database 头部
class _PdbHeader {
  const _PdbHeader({required this.name, required this.numRecords});

  final String name;
  final int numRecords;
}
