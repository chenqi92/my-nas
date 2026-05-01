// ignore_for_file: unnecessary_null_comparison, dead_code

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:charset_converter/charset_converter.dart';
import 'package:flutter/foundation.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/book/data/services/mobi/mobi_to_epub.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// MOBI 解析结果
class MobiParseResult {
  const MobiParseResult({
    required this.success,
    this.title,
    this.author,
    this.content,
    this.htmlContent,
    this.epubPath, // 转换后的 EPUB 文件路径
    this.error,
  });

  factory MobiParseResult.failure(String error) => MobiParseResult(
        success: false,
        error: error,
      );

  factory MobiParseResult.fromContent({
    required String content,
    String? htmlContent,
    String? title,
    String? author,
  }) =>
      MobiParseResult(
        success: true,
        content: content,
        htmlContent: htmlContent,
        title: title,
        author: author,
      );

  factory MobiParseResult.fromEpub(String epubPath) => MobiParseResult(
        success: true,
        epubPath: epubPath,
      );

  final bool success;
  final String? title;
  final String? author;
  final String? content;
  final String? htmlContent; // 原始 HTML 内容
  final String? epubPath; // 转换后的 EPUB 文件路径（Calibre 转换结果）
  final String? error;

  /// 是否应该使用 EPUB 阅读器打开
  bool get shouldUseEpubReader => epubPath != null;
}

/// MOBI/AZW3 解析服务
///
/// 支持的格式：
/// - MOBI (PalmDOC 压缩)
/// - AZW3 (KF8 格式)
///
/// 桌面平台优先使用 Calibre 的 ebook-convert 工具
/// 如果没有安装 Calibre，则使用内置解析器（仅支持简单格式）
class MobiParserService {
  factory MobiParserService() => _instance ??= MobiParserService._();
  MobiParserService._();

  static MobiParserService? _instance;

  /// 解析 MOBI/AZW3 文件
  ///
  /// 优先使用新的模块化解析器（支持 NCX 目录和多章节）
  /// 桌面平台可选使用 Calibre 的 ebook-convert 工具
  Future<MobiParseResult> parse(Uint8List bytes, String fileName) async {
    // 桌面平台优先使用 Calibre（转换质量最高）
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      final calibreResult = await _parseWithCalibre(bytes, fileName);
      if (calibreResult.success) {
        return calibreResult;
      }
      // Calibre 不可用，尝试新的内置解析器
      logger.i('Calibre 不可用，使用内置解析器');
    }

    // 使用新的模块化解析器（支持 NCX 目录、多章节）
    final newParserResult = await _parseWithNewParser(bytes, fileName);
    if (newParserResult.success) {
      return newParserResult;
    }

    // 如果新解析器失败，回退到旧解析器
    logger.w('新解析器失败，回退到旧解析器: ${newParserResult.error}');
    final builtInResult = await _parseWithBuiltIn(bytes);

    // 移动端：将解析结果打包为 EPUB
    if ((Platform.isIOS || Platform.isAndroid) && builtInResult.success) {
      return _convertToEpub(builtInResult, fileName);
    }

    return builtInResult;
  }

  /// 使用新的模块化解析器
  ///
  /// 支持 NCX 目录解析、多章节 EPUB 生成
  Future<MobiParseResult> _parseWithNewParser(
    Uint8List bytes,
    String fileName,
  ) async {
    try {
      final result = await MobiToEpubConverter.convert(bytes, fileName);

      if (result.success && result.epubPath != null) {
        logger.i('新解析器成功: ${result.chapterCount} 个章节');
        return MobiParseResult.fromEpub(result.epubPath!);
      }

      return MobiParseResult.failure(result.error ?? '转换失败');
    } on Exception catch (e, st) {
      logger.e('新解析器异常', e, st);
      return MobiParseResult.failure('解析失败: $e');
    }
  }

  /// 使用 Calibre 解析 - 转换为 EPUB 格式
  Future<MobiParseResult> _parseWithCalibre(
    Uint8List bytes,
    String fileName,
  ) async {
    // 检查 ebook-convert 是否可用
    final convertCmd = await _findCalibreConvert();
    if (convertCmd == null) {
      return MobiParseResult.failure('Calibre 未安装');
    }

    // 创建临时目录
    final tempDir = await getTemporaryDirectory();
    final workDir = Directory(
      path.join(
        tempDir.path,
        'mobi_parse_${DateTime.now().millisecondsSinceEpoch}',
      ),
    );
    await workDir.create(recursive: true);

    try {
      // 写入临时文件
      final inputFile = File(path.join(workDir.path, fileName));
      await inputFile.writeAsBytes(bytes);

      // 转换为 EPUB（而不是 TXT，保留格式和图片）
      final outputFile = File(
        path.join(workDir.path, '${path.basenameWithoutExtension(fileName)}.epub'),
      );

      logger.i('Calibre 转换: $fileName -> EPUB');
      final result = await Process.run(
        convertCmd,
        [inputFile.path, outputFile.path],
      );

      if (result.exitCode != 0) {
        logger.e('Calibre 转换失败: ${result.stderr}');
        return MobiParseResult.failure('转换失败: ${result.stderr}');
      }

      // 返回 EPUB 文件路径，让调用方使用 EPUB 阅读器打开
      if (await outputFile.exists()) {
        // 复制到持久化缓存目录
        final cacheDir = Directory(path.join(tempDir.path, 'mobi_epub_cache'));
        if (!await cacheDir.exists()) {
          await cacheDir.create(recursive: true);
        }
        final cachedEpub = File(
          path.join(cacheDir.path, '${path.basenameWithoutExtension(fileName)}.epub'),
        );
        await outputFile.copy(cachedEpub.path);

        logger.i('MOBI 转换 EPUB 成功: ${cachedEpub.path}');
        return MobiParseResult.fromEpub(cachedEpub.path);
      }

      return MobiParseResult.failure('转换后的文件不存在');
    } finally {
      // 清理临时目录
      try {
        await workDir.delete(recursive: true);
      } on Exception catch (e) {
        logger.w('清理临时目录失败', e);
      }
    }
  }

  /// 查找 Calibre 的 ebook-convert 命令
  Future<String?> _findCalibreConvert() async {
    final commands = <String>[];

    if (Platform.isMacOS) {
      commands.addAll([
        '/Applications/calibre.app/Contents/MacOS/ebook-convert',
        'ebook-convert',
      ]);
    } else if (Platform.isWindows) {
      commands.addAll([
        r'C:\Program Files\Calibre2\ebook-convert.exe',
        r'C:\Program Files (x86)\Calibre2\ebook-convert.exe',
        'ebook-convert',
      ]);
    } else {
      commands.add('ebook-convert');
    }

    for (final cmd in commands) {
      if (await _isCommandAvailable(cmd)) {
        return cmd;
      }
    }

    return null;
  }

  /// 检查命令是否可用
  Future<bool> _isCommandAvailable(String command) async {
    try {
      // 如果是完整路径，检查文件是否存在
      if (command.contains('/') || command.contains(r'\')) {
        return File(command).existsSync();
      }

      final whichCmd = Platform.isWindows ? 'where' : 'which';
      final result = await Process.run(whichCmd, [command]);
      return result.exitCode == 0;
    } on Exception catch (_) {
      return false;
    }
  }

  /// 将解析结果打包为 EPUB 格式
  ///
  /// 此方法将内置解析器得到的 HTML 内容封装为有效的 EPUB 文件，
  /// 用于漫画阅读器等需要 EPUB 格式的场景。
  Future<MobiParseResult> _convertToEpub(
    MobiParseResult parseResult,
    String fileName,
  ) async {
    if (!parseResult.success || parseResult.htmlContent == null) {
      return parseResult;
    }

    try {
      final title = parseResult.title ??
          path.basenameWithoutExtension(fileName);
      final author = parseResult.author ?? '未知作者';
      final htmlContent = parseResult.htmlContent!;

      // 清理 HTML 内容，确保是有效的 XHTML
      final cleanedHtml = _sanitizeHtmlForEpub(htmlContent);

      // 获取缓存目录
      final tempDir = await getTemporaryDirectory();
      final cacheDir = Directory(path.join(tempDir.path, 'mobi_epub_cache'));
      if (!await cacheDir.exists()) {
        await cacheDir.create(recursive: true);
      }

      // 生成唯一的 EPUB 文件名
      final epubFileName = '${title.hashCode.abs()}_${DateTime.now().millisecondsSinceEpoch}.epub';
      final epubPath = path.join(cacheDir.path, epubFileName);

      // 创建 EPUB 内容
      await _createEpubFile(
        epubPath: epubPath,
        title: title,
        author: author,
        htmlContent: cleanedHtml,
      );

      logger.i('MOBI 打包 EPUB 成功: $epubPath');
      return MobiParseResult.fromEpub(epubPath);
    } on Exception catch (e, st) {
      logger.e('MOBI 打包 EPUB 失败', e, st);
      // 失败时返回原始结果，让调用方使用备用渲染
      return parseResult;
    }
  }

  /// 清理 HTML 内容，使其成为有效的 XHTML
  String _sanitizeHtmlForEpub(String html) {
    var cleaned = html;

    // 移除可能存在的 DOCTYPE、html、head、body 标签
    cleaned = cleaned.replaceAll(
      RegExp('<!DOCTYPE[^>]*>', caseSensitive: false),
      '',
    );
    cleaned = cleaned.replaceAll(
      RegExp('</?html[^>]*>', caseSensitive: false),
      '',
    );
    cleaned = cleaned.replaceAll(
      RegExp('<head[^>]*>.*?</head>', caseSensitive: false, dotAll: true),
      '',
    );
    cleaned = cleaned.replaceAll(
      RegExp('</?body[^>]*>', caseSensitive: false),
      '',
    );
    cleaned = cleaned.replaceAll(
      RegExp('<meta[^>]*/?>',caseSensitive: false),
      '',
    );
    cleaned = cleaned.replaceAll(
      RegExp(r'<\?xml[^>]*\?>', caseSensitive: false),
      '',
    );

    // 转义 XHTML 中不允许的字符
    // 注意：不能简单替换 &，因为可能有有效的 HTML 实体
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'&(?!(amp|lt|gt|quot|apos|#\d+|#x[0-9a-fA-F]+);)'),
      (match) => '&amp;',
    );

    // 自闭合标签需要加斜杠（XHTML 规范）
    cleaned = cleaned.replaceAllMapped(
      RegExp('<(br|hr|img|input|meta|link)([^/>]*)(?<!/)>',
          caseSensitive: false),
      (match) => '<${match.group(1)}${match.group(2) ?? ''}/>',
    );

    return cleaned.trim();
  }

  /// 创建 EPUB 文件
  Future<void> _createEpubFile({
    required String epubPath,
    required String title,
    required String author,
    required String htmlContent,
  }) async {
    final archive = Archive();
    final uuid = const Uuid().v4();
    final timestamp = DateTime.now().toUtc().toIso8601String();

    // 1. mimetype 文件（必须是第一个，且不压缩）
    archive.addFile(ArchiveFile(
      'mimetype',
      utf8.encode('application/epub+zip').length,
      utf8.encode('application/epub+zip'),
    ));

    // 2. META-INF/container.xml
    const containerXml = '''
<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>''';
    archive.addFile(ArchiveFile(
      'META-INF/container.xml',
      utf8.encode(containerXml).length,
      utf8.encode(containerXml),
    ));

    // 3. OEBPS/content.opf
    final contentOpf = '''
    <?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="uid">urn:uuid:$uuid</dc:identifier>
    <dc:title>${_escapeXml(title)}</dc:title>
    <dc:creator>${_escapeXml(author)}</dc:creator>
    <dc:language>zh-CN</dc:language>
    <meta property="dcterms:modified">$timestamp</meta>
  </metadata>
  <manifest>
    <item id="chapter1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
  </manifest>
  <spine>
    <itemref idref="chapter1"/>
  </spine>
</package>
''';
    archive.addFile(ArchiveFile(
      'OEBPS/content.opf',
      utf8.encode(contentOpf).length,
      utf8.encode(contentOpf),
    ));

    // 4. OEBPS/chapter1.xhtml（主要内容）
    final chapterXhtml = '''
    <?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="zh-CN">
<head>
  <meta charset="UTF-8"/>
  <title>${_escapeXml(title)}</title>
  <style type="text/css">
    body { 
      font-family: sans-serif; 
      line-height: 1.6; 
      padding: 1em;
    }
    p { 
      text-indent: 2em; 
      margin: 0.5em 0; 
    }
    h1, h2, h3, h4, h5, h6 { 
      text-indent: 0; 
      margin: 1em 0 0.5em 0;
    }
  </style>
</head>
<body>
$htmlContent
</body>
</html>
''';
    archive.addFile(ArchiveFile(
      'OEBPS/chapter1.xhtml',
      utf8.encode(chapterXhtml).length,
      utf8.encode(chapterXhtml),
    ));

    // 5. OEBPS/nav.xhtml（导航文件）
    final navXhtml = '''
    <?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="zh-CN">
<head>
  <meta charset="UTF-8"/>
  <title>导航</title>
</head>
<body>
  <nav epub:type="toc" id="toc">
    <h1>目录</h1>
    <ol>
      <li><a href="chapter1.xhtml">${_escapeXml(title)}</a></li>
    </ol>
  </nav>
</body>
</html>
''';
    archive.addFile(ArchiveFile(
      'OEBPS/nav.xhtml',
      utf8.encode(navXhtml).length,
      utf8.encode(navXhtml),
    ));

    // 编码为 ZIP 并写入文件
    final zipData = ZipEncoder().encode(archive);
    if (zipData == null) {
      throw StateError('EPUB ZIP 编码失败');
    }

    await File(epubPath).writeAsBytes(zipData);
  }

  /// XML 特殊字符转义
  String _escapeXml(String text) => text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  /// 使用内置解析器解析 MOBI
  Future<MobiParseResult> _parseWithBuiltIn(Uint8List bytes) async {
    try {
      // 验证 Palm Database 格式
      if (bytes.length < 78) {
        return MobiParseResult.failure('文件太小，不是有效的 MOBI 文件');
      }

      // 读取数据库名称（标题）
      final nameBytes = bytes.sublist(0, 32);
      final nullIndex = nameBytes.indexOf(0);
      final title = utf8.decode(
        nameBytes.sublist(0, nullIndex > 0 ? nullIndex : 32),
        allowMalformed: true,
      );

      // 检查类型和创建者 ID
      final type = String.fromCharCodes(bytes.sublist(60, 64));
      final creator = String.fromCharCodes(bytes.sublist(64, 68));

      if (type != 'BOOK' || creator != 'MOBI') {
        return MobiParseResult.failure('不是有效的 MOBI 文件');
      }

      // 读取记录数量
      final numRecords = _readUint16(bytes, 76);
      if (numRecords == 0) {
        return MobiParseResult.failure('MOBI 文件没有记录');
      }

      // 读取记录偏移表
      // Palm Database 格式：每条记录 8 字节（4字节偏移 + 4字节属性）
      // 某些 MOBI 文件可能包含超出文件范围的偏移（如被截断或含 DRM）
      final recordOffsets = <int>[];
      for (var i = 0; i < numRecords; i++) {
        final tableOffset = 78 + i * 8;
        // 确保记录表本身不超出文件范围
        if (tableOffset + 4 > bytes.length) break;

        final offset = _readUint32(bytes, tableOffset);
        // 只添加有效的偏移（在文件范围内）
        if (offset < bytes.length) {
          recordOffsets.add(offset);
        } else {
          // 遇到无效偏移后停止读取，后续记录可能都无效
          break;
        }
      }

      if (recordOffsets.isEmpty) {
        return MobiParseResult.failure('MOBI 文件记录偏移无效');
      }

      // 读取第一个记录（PalmDOC 头部）
      final record0Start = recordOffsets[0];
      final record0End =
          recordOffsets.length > 1 ? recordOffsets[1] : bytes.length;
      final record0 = bytes.sublist(record0Start, record0End);

      // 解析 PalmDOC 头部
      final compression = _readUint16(record0, 0);
      final textLength = _readUint32(record0, 4);
      final recordCount = _readUint16(record0, 8);

      // 检查是否有 MOBI 头部
      String? author;
      var textEncoding = 'cp1252';

      if (record0.length >= 132) {
        final mobiId = String.fromCharCodes(record0.sublist(16, 20));
        if (mobiId == 'MOBI') {
          // 读取编码
          final encoding = _readUint32(record0, 28);
          if (encoding == 65001) {
            textEncoding = 'utf-8';
          }

          // 检查 EXTH 头部
          final exthFlags = _readUint32(record0, 128);
          if ((exthFlags & 0x40) != 0) {
            // 有 EXTH 头部
            final mobiHeaderLength = _readUint32(record0, 20);
            final exthStart = 16 + mobiHeaderLength;
            if (record0.length > exthStart + 12) {
              author = _parseExthAuthor(record0, exthStart);
            }
          }
        }
      }

      // 解压文本记录
      final textBuffer = StringBuffer();
      final textRecordCount = recordCount < recordOffsets.length
          ? recordCount
          : recordOffsets.length - 1;

      for (var i = 1; i <= textRecordCount; i++) {
        if (i >= recordOffsets.length) break;

        final recordStart = recordOffsets[i];
        final recordEnd =
            i + 1 < recordOffsets.length ? recordOffsets[i + 1] : bytes.length;
        final recordData = bytes.sublist(recordStart, recordEnd);

        String text;
        if (compression == 1) {
          // 无压缩
          text = await _decodeText(recordData, textEncoding);
        } else if (compression == 2) {
          // PalmDOC 压缩
          final decompressed = _decompressPalmDoc(recordData);
          text = await _decodeText(decompressed, textEncoding);
        } else {
          // HUFF/CDIC 压缩，暂不支持
          return MobiParseResult.failure(
            'MOBI 文件使用 HUFF/CDIC 压缩\n\n'
            '此压缩格式较复杂，建议使用 Calibre 转换为 EPUB 格式\n\n'
            '${_getCalibreInstallHint()}',
          );
        }

        textBuffer.write(text);

        // 检查是否已达到文本长度
        if (textBuffer.length >= textLength) break;
      }

      // 保留原始 HTML 内容用于渲染
      final rawHtml = textBuffer.toString();
      // 清理 HTML 标签，提取纯文本（用于备用显示）
      final cleanedContent = _cleanHtml(rawHtml);

      return MobiParseResult.fromContent(
        content: cleanedContent,
        htmlContent: rawHtml,
        title: title.isNotEmpty ? title : null,
        author: author,
      );
    } on Exception catch (e) {
      logger.e('MOBI 解析失败', e);
      return MobiParseResult.failure('MOBI 解析失败: $e');
    }
  }

  /// 读取 16 位无符号整数（大端序）
  int _readUint16(List<int> bytes, int offset) =>
      (bytes[offset] << 8) | bytes[offset + 1];

  /// 读取 32 位无符号整数（大端序）
  int _readUint32(List<int> bytes, int offset) =>
      (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];

  /// 解码文本
  /// 支持 UTF-8、GBK/GB2312、CP1252 编码
  Future<String> _decodeText(List<int> bytes, String encoding) async {
    if (encoding == 'utf-8') {
      return utf8.decode(bytes, allowMalformed: true);
    }

    // 尝试检测是否为中文编码（GBK/GB2312）
    if (_looksLikeGbk(bytes)) {
      try {
        // 移动平台使用 charset_converter
        if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
          return await CharsetConverter.decode('gbk', Uint8List.fromList(bytes));
        }
        // 桌面平台尝试使用系统编码或 fallback
        return _decodeGbkFallback(bytes);
      } on Exception catch (e) {
        logger.w('GBK 解码失败，尝试其他编码', e);
      }
    }

    // CP1252 编码，使用 latin1 作为近似
    return latin1.decode(bytes);
  }

  /// 检测字节序列是否可能是 GBK 编码
  /// GBK 编码特征：高字节在 0x81-0xFE 范围，低字节在 0x40-0xFE 范围
  bool _looksLikeGbk(List<int> bytes) {
    if (bytes.isEmpty) return false;

    var gbkPairs = 0;
    var totalPairs = 0;

    for (var i = 0; i < bytes.length - 1; i++) {
      final high = bytes[i];
      final low = bytes[i + 1];

      // 检查是否符合 GBK 双字节特征
      if (high >= 0x81 && high <= 0xFE) {
        totalPairs++;
        if ((low >= 0x40 && low <= 0x7E) || (low >= 0x80 && low <= 0xFE)) {
          gbkPairs++;
          i++; // 跳过低字节
        }
      }
    }

    // 如果超过 30% 的高字节后面跟着有效的低字节，认为是 GBK
    return totalPairs > 10 && gbkPairs > totalPairs * 0.3;
  }

  /// GBK 解码回退方案（桌面平台）
  /// 使用简单的 GBK 到 Unicode 映射表进行解码
  String _decodeGbkFallback(List<int> bytes) {
    final result = StringBuffer();
    var i = 0;

    while (i < bytes.length) {
      final byte = bytes[i];

      if (byte < 0x80) {
        // ASCII 字符
        result.writeCharCode(byte);
        i++;
      } else if (byte >= 0x81 && byte <= 0xFE && i + 1 < bytes.length) {
        // GBK 双字节字符
        final high = byte;
        final low = bytes[i + 1];

        // 尝试转换为 Unicode
        final unicode = _gbkToUnicode(high, low);
        if (unicode != null) {
          result.writeCharCode(unicode);
        } else {
          // 无法转换时使用替代字符
          result.write('\uFFFD');
        }
        i += 2;
      } else {
        // 无效字节，使用替代字符
        result.write('\uFFFD');
        i++;
      }
    }

    return result.toString();
  }

  /// GBK 到 Unicode 转换（常用字符映射）
  int? _gbkToUnicode(int high, int low) {
    // 常用中文字符范围
    // GBK 区域1: B0A1-F7FE (一级汉字)
    // GBK 区域2: 8140-A0FE (二级汉字)

    // 这里只实现一个简化版本，实际应用中建议使用完整的 GBK 映射表
    // 或者在桌面平台使用其他库

    // 简单的 GB2312 一级汉字映射估算
    if (high >= 0xB0 && high <= 0xF7 && low >= 0xA1 && low <= 0xFE) {
      // GB2312 一级汉字区
      final offset = (high - 0xB0) * 94 + (low - 0xA1);
      // Unicode 中文基本区从 0x4E00 开始
      // 这是一个近似映射，实际转换需要完整的映射表
      return 0x4E00 + offset;
    }

    return null;
  }

  /// PalmDOC 解压缩 (LZ77)
  Uint8List _decompressPalmDoc(List<int> compressed) {
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

        // 安全检查：确保 distance 有效且不超过当前输出长度
        if (distance > 0 && distance <= output.length) {
          for (var j = 0; j < length; j++) {
            // 每次循环都需要重新计算索引，因为 output 在增长
            final srcIndex = output.length - distance;
            if (srcIndex >= 0 && srcIndex < output.length) {
              output.add(output[srcIndex]);
            }
          }
        }
        // 如果 distance 无效，跳过这个指令（容错处理）
      } else {
        // 0xC0-0xFF: 空格 + 字符
        output
          ..add(0x20) // 空格
          ..add(byte ^ 0x80);
      }
    }

    return Uint8List.fromList(output);
  }

  /// 解析 EXTH 头部中的作者信息
  String? _parseExthAuthor(List<int> record, int exthStart) {
    try {
      final exthId =
          String.fromCharCodes(record.sublist(exthStart, exthStart + 4));
      if (exthId != 'EXTH') return null;

      final recordCount = _readUint32(record, exthStart + 8);

      var offset = exthStart + 12;
      for (var i = 0; i < recordCount; i++) {
        if (offset + 8 > record.length) break;

        final recordType = _readUint32(record, offset);
        final recordLength = _readUint32(record, offset + 4);

        if (recordType == 100) {
          // 作者
          final authorBytes = record.sublist(offset + 8, offset + recordLength);
          return utf8.decode(authorBytes, allowMalformed: true);
        }

        offset += recordLength;
      }
    } on Exception catch (_) {
      // 忽略解析错误
    }
    return null;
  }

  /// 清理 HTML 标签，保留段落结构
  String _cleanHtml(String html) {
    var text = html;

    // 移除 script 和 style 标签及其内容
    text = text.replaceAll(
      RegExp('<script[^>]*>.*?</script>', caseSensitive: false, dotAll: true),
      '',
    );
    text = text.replaceAll(
      RegExp('<style[^>]*>.*?</style>', caseSensitive: false, dotAll: true),
      '',
    );

    // 在段落结束标签前添加换行
    text = text.replaceAll(RegExp('</p>', caseSensitive: false), '\n\n');
    text = text.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    text = text.replaceAll(RegExp('</h[1-6]>', caseSensitive: false), '\n\n');
    text = text.replaceAll(RegExp('</div>', caseSensitive: false), '\n');
    text = text.replaceAll(RegExp('</li>', caseSensitive: false), '\n');
    text = text.replaceAll(RegExp('</tr>', caseSensitive: false), '\n');
    text = text.replaceAll(
      RegExp('</blockquote>', caseSensitive: false),
      '\n\n',
    );

    // 移除所有其他 HTML 标签
    text = text.replaceAll(RegExp('<[^>]*>'), '');

    // 解码 HTML 实体
    text = text
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&#39;', "'")
        .replaceAll('&ldquo;', '"')
        .replaceAll('&rdquo;', '"')
        .replaceAll('&lsquo;', '\u2018')
        .replaceAll('&rsquo;', '\u2019')
        .replaceAll('&mdash;', '—')
        .replaceAll('&ndash;', '–')
        .replaceAll('&hellip;', '…');

    // 解码数字实体
    text = text.replaceAllMapped(
      RegExp(r'&#(\d+);'),
      (match) {
        final code = int.tryParse(match.group(1) ?? '');
        if (code != null && code > 0 && code < 0x10FFFF) {
          return String.fromCharCode(code);
        }
        return match.group(0) ?? '';
      },
    );

    text = text.replaceAllMapped(
      RegExp('&#x([0-9a-fA-F]+);'),
      (match) {
        final code = int.tryParse(match.group(1) ?? '', radix: 16);
        if (code != null && code > 0 && code < 0x10FFFF) {
          return String.fromCharCode(code);
        }
        return match.group(0) ?? '';
      },
    );

    // 清理多余的空白，但保留段落换行
    text = text
        .replaceAll(RegExp(r'[ \t]+'), ' ') // 合并多个空格
        .replaceAll(RegExp(r'\n[ \t]+'), '\n') // 移除行首空白
        .replaceAll(RegExp(r'[ \t]+\n'), '\n') // 移除行尾空白
        .replaceAll(RegExp(r'\n{3,}'), '\n\n'); // 最多保留两个换行

    return text.trim();
  }

  /// 获取 Calibre 安装提示
  String _getCalibreInstallHint() {
    // 移动端显示转换建议
    if (Platform.isAndroid || Platform.isIOS) {
      return '📱 移动端暂不支持此格式\n\n'
          '建议在电脑上使用 Calibre 转换为 EPUB 格式后阅读：\n'
          '1. 下载 Calibre: calibre-ebook.com\n'
          '2. 打开 MOBI/AZW3 文件\n'
          '3. 转换 → EPUB\n'
          '4. 将 EPUB 传到手机阅读';
    }

    if (Platform.isMacOS) {
      return '🖥 macOS 安装 Calibre：\n'
          'brew install --cask calibre\n'
          '或从 calibre-ebook.com 下载';
    } else if (Platform.isWindows) {
      return '🖥 Windows 安装 Calibre：\n'
          '从 calibre-ebook.com 下载安装';
    } else {
      return '🖥 Linux 安装 Calibre：\n'
          'sudo apt install calibre\n'
          '或从 calibre-ebook.com 下载';
    }
  }

  /// 提取 MOBI/AZW3 封面图片
  ///
  /// 返回封面图片的字节数据，如果没有封面则返回 null
  Future<Uint8List?> extractCover(Uint8List bytes) async {
    try {
      // 验证 Palm Database 格式
      if (bytes.length < 78) {
        return null;
      }

      // 检查类型和创建者 ID
      final type = String.fromCharCodes(bytes.sublist(60, 64));
      final creator = String.fromCharCodes(bytes.sublist(64, 68));

      if (type != 'BOOK' || creator != 'MOBI') {
        return null;
      }

      // 读取记录数量
      final numRecords = _readUint16(bytes, 76);
      if (numRecords == 0) {
        return null;
      }

      // 读取记录偏移量（验证边界）
      final recordOffsets = <int>[];
      for (var i = 0; i < numRecords; i++) {
        final tableOffset = 78 + i * 8;
        if (tableOffset + 4 > bytes.length) break;

        final offset = _readUint32(bytes, tableOffset);
        if (offset < bytes.length) {
          recordOffsets.add(offset);
        } else {
          break;
        }
      }

      if (recordOffsets.isEmpty) {
        return null;
      }

      // 读取第一个记录（包含 MOBI 头部）
      final record0Start = recordOffsets[0];
      final record0End =
          recordOffsets.length > 1 ? recordOffsets[1] : bytes.length;
      // 确保 record0End 不超出文件边界
      final safeRecord0End = record0End.clamp(record0Start, bytes.length);
      if (safeRecord0End <= record0Start) {
        return null;
      }
      final record0 = bytes.sublist(record0Start, safeRecord0End);

      // 检查是否有 MOBI 头部
      if (record0.length < 132) {
        return null;
      }

      final mobiId = String.fromCharCodes(record0.sublist(16, 20));
      if (mobiId != 'MOBI') {
        return null;
      }

      // 读取第一个图片记录索引
      final firstImageIndex = _readUint32(record0, 108);
      if (firstImageIndex == 0 || firstImageIndex >= numRecords) {
        return null;
      }

      // 检查 EXTH 头部获取封面偏移量
      final exthFlags = _readUint32(record0, 128);
      int? coverOffset;

      if ((exthFlags & 0x40) != 0) {
        // 有 EXTH 头部
        final mobiHeaderLength = _readUint32(record0, 20);
        final exthStart = 16 + mobiHeaderLength;
        if (record0.length > exthStart + 12) {
          coverOffset = _parseExthCoverOffset(record0, exthStart);
        }
      }

      // 计算封面记录索引
      int coverRecordIndex;
      if (coverOffset != null) {
        coverRecordIndex = firstImageIndex + coverOffset;
      } else {
        // 没有 EXTH 封面偏移量，使用第一张图片
        coverRecordIndex = firstImageIndex;
      }

      // 使用 recordOffsets.length 而非 numRecords（因为可能有无效记录被过滤）
      if (coverRecordIndex >= recordOffsets.length) {
        return null;
      }

      // 读取封面记录
      final coverStart = recordOffsets[coverRecordIndex];
      if (coverStart >= bytes.length) {
        return null;
      }
      final coverEnd = coverRecordIndex + 1 < recordOffsets.length
          ? recordOffsets[coverRecordIndex + 1]
          : bytes.length;
      // 确保 coverEnd 不超出文件边界
      final safeCoverEnd = coverEnd.clamp(coverStart, bytes.length);
      if (safeCoverEnd <= coverStart) {
        return null;
      }
      final coverData = bytes.sublist(coverStart, safeCoverEnd);

      // 验证是否是有效的图片数据
      if (_isValidImageData(coverData)) {
        return Uint8List.fromList(coverData);
      }

      return null;
    } on Exception catch (e) {
      logger.w('MOBI 封面提取失败', e);
      return null;
    }
  }

  /// 解析 EXTH 头部中的封面偏移量
  int? _parseExthCoverOffset(List<int> record, int exthStart) {
    try {
      final exthId =
          String.fromCharCodes(record.sublist(exthStart, exthStart + 4));
      if (exthId != 'EXTH') return null;

      final recordCount = _readUint32(record, exthStart + 8);

      var offset = exthStart + 12;
      for (var i = 0; i < recordCount; i++) {
        if (offset + 8 > record.length) break;

        final recordType = _readUint32(record, offset);
        final recordLength = _readUint32(record, offset + 4);

        if (recordType == 201) {
          // 封面偏移量
          if (offset + 8 + 4 <= record.length) {
            return _readUint32(record, offset + 8);
          }
        }

        offset += recordLength;
      }
    } on Exception catch (_) {
      // 忽略解析错误
    }
    return null;
  }

  /// 检查是否是有效的图片数据
  bool _isValidImageData(List<int> data) {
    if (data.length < 8) return false;

    // 检查 JPEG 魔数
    if (data[0] == 0xFF && data[1] == 0xD8 && data[2] == 0xFF) {
      return true;
    }

    // 检查 PNG 魔数
    if (data[0] == 0x89 &&
        data[1] == 0x50 &&
        data[2] == 0x4E &&
        data[3] == 0x47) {
      return true;
    }

    // 检查 GIF 魔数
    if (data[0] == 0x47 && data[1] == 0x49 && data[2] == 0x46) {
      return true;
    }

    // 检查 BMP 魔数
    if (data[0] == 0x42 && data[1] == 0x4D) {
      return true;
    }

    return false;
  }
}
