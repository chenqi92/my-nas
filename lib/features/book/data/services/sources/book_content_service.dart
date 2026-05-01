import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/book/data/services/sources/rule_parser.dart';
import 'package:my_nas/features/book/domain/entities/book_source.dart';

/// 书籍详情信息
class BookInfo {
  const BookInfo({
    required this.name,
    required this.author,
    required this.bookUrl,
    this.coverUrl,
    this.intro,
    this.kind,
    this.lastChapter,
    this.wordCount,
    this.tocUrl,
  });

  final String name;
  final String author;
  final String bookUrl;
  final String? coverUrl;
  final String? intro;
  final String? kind;
  final String? lastChapter;
  final String? wordCount;
  final String? tocUrl;
}

/// 书籍内容服务
///
/// 获取书籍详情、目录和章节内容
class BookContentService {
  BookContentService._();

  static final instance = BookContentService._();

  final _dio = Dio();
  final _random = Random();
  
  /// User-Agent 列表，模拟不同浏览器
  static const _userAgents = [
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36',
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:121.0) Gecko/20100101 Firefox/121.0',
    'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
  ];

  /// 获取书籍详情
  Future<BookInfo?> getBookInfo(OnlineBook book) async {
    try {
      final source = book.source;
      final rule = source.ruleBookInfo;

      // 发送请求
      final response = await _makeRequest(source, book.bookUrl);
      if (response == null) return null;

      // 📋 记录原始响应数据结构（便于分析可用字段）
      logger.w('📋 [${source.displayName}] 书籍详情原始数据:');
      if (response is Map) {
        for (final key in response.keys.take(15)) {
          final value = response[key];
          final valueStr = value?.toString() ?? 'null';
          logger.w('   $key: ${valueStr.length > 100 ? '${valueStr.substring(0, 100)}...' : valueStr}');
        }
      } else if (response is String) {
        logger.w('   [HTML内容] 长度: ${response.length} 字符');
      }

      // 如果没有详情规则，使用搜索结果的信息
      if (rule == null) {
        logger.i('📖 [${source.displayName}] 无详情规则，使用搜索结果信息');
        return BookInfo(
          name: book.name,
          author: book.author,
          bookUrl: book.bookUrl,
          coverUrl: book.coverUrl,
          intro: book.intro,
          kind: book.kind,
          lastChapter: book.lastChapter,
          wordCount: book.wordCount,
        );
      }

      // 解析详情并记录
      final parsedName = RuleParser.parseRule(rule.name, response, baseUrl: book.bookUrl);
      final parsedAuthor = RuleParser.parseRule(rule.author, response, baseUrl: book.bookUrl);
      final parsedCoverUrl = RuleParser.parseRule(rule.coverUrl, response, baseUrl: book.bookUrl);
      final parsedIntro = RuleParser.parseRule(rule.intro, response, baseUrl: book.bookUrl);
      
      // 详细日志：记录各字段的规则和解析结果
      logger.i('📖 [${source.displayName}] 详情解析结果:');
      logger.i('   书名规则: "${rule.name}" → "$parsedName" (默认: ${book.name})');
      logger.i('   作者规则: "${rule.author}" → "$parsedAuthor" (默认: ${book.author})');
      logger.i('   封面规则: "${rule.coverUrl}" → "$parsedCoverUrl"');
      logger.i('   简介规则: "${rule.intro}" → "${parsedIntro?.length ?? 0}字"');

      // 解析详情
      return BookInfo(
        name: parsedName ?? book.name,
        author: parsedAuthor ?? book.author,
        bookUrl: book.bookUrl,
        coverUrl: parsedCoverUrl ?? book.coverUrl,
        intro: parsedIntro ?? book.intro,
        kind: RuleParser.parseRule(rule.kind, response, baseUrl: book.bookUrl) ?? book.kind,
        lastChapter: RuleParser.parseRule(rule.lastChapter, response, baseUrl: book.bookUrl),
        wordCount: RuleParser.parseRule(rule.wordCount, response, baseUrl: book.bookUrl),
        tocUrl: RuleParser.parseRule(rule.tocUrl, response, baseUrl: book.bookUrl),
      );
    } catch (e, st) {
      AppError.handle(e, st, 'getBookInfo');
      return null;
    }
  }

  /// 获取章节目录
  Future<List<OnlineChapter>> getChapterList(
    BookSource source,
    String bookUrl, {
    String? tocUrl,
  }) async {
    try {
      final rule = source.ruleToc;
      if (rule == null) {
        logger.w('书源 ${source.displayName} 没有目录规则');
        return [];
      }

      // 确定目录URL
      final url = tocUrl ?? bookUrl;
      
      // 获取所有页的目录
      var allChapters = <OnlineChapter>[];
      var currentUrl = url;
      var pageCount = 0;
      const maxPages = 50; // 防止无限循环

      while (currentUrl.isNotEmpty && pageCount < maxPages) {
        final response = await _makeRequest(source, currentUrl);
        if (response == null) break;

        final chapters = _parseChapterList(source, response, currentUrl);
        if (chapters.isEmpty) break;

        // 添加章节，设置索引
        for (final chapter in chapters) {
          allChapters.add(OnlineChapter(
            name: chapter.name,
            url: chapter.url,
            isVolume: chapter.isVolume,
            updateTime: chapter.updateTime,
            index: allChapters.length,
          ));
        }

        // 检查是否有下一页
        final nextUrl = RuleParser.parseRule(rule.nextTocUrl, response, baseUrl: currentUrl);
        if (nextUrl == null || nextUrl.isEmpty || nextUrl == currentUrl) {
          break;
        }
        currentUrl = nextUrl;
        pageCount++;
      }

      logger.i('获取目录完成: ${allChapters.length} 章');
      return allChapters;
    } catch (e, st) {
      AppError.handle(e, st, 'getChapterList');
      return [];
    }
  }

  /// 常用的备用章节列表选择器
  /// 从最具体到最通用排列
  static const _fallbackChapterSelectors = [
    // 具体的章节列表选择器
    '.listmain dd a',        // 笔趣阁类站点
    '#list dd a',            // 笔趣阁变体
    '.chapter-list a',       // 通用章节列表
    '.chapter-list li a',
    '.catalog li a',         // 目录类
    '.mulu li a',            // 目录(中文)
    '#chapterList a',        // ID形式
    '#chapterlist a',
    '#chapterList li a',     // ID+li形式
    'ul.chapter li a',
    '.volume dd a',          // 卷章结构
    '.box_con dd a',
    '#info dd a',
    '.zjlist dd a',          // 章节列表
    '.dirlist li a',         // 目录列表
    '.read-content-wrap li a',
    '.novel_list li a',
    // 365小说网及类似站点
    '.novel-chapter a',
    '.book-chapter a',
    '.chapter a',
    '.chapters a',
    '.toc a',
    '.table-of-contents a',
    // 表格形式的章节列表
    'table.chapterlist a',
    'table td a',
    'table tbody tr td a',
    '.grid a',
    '.chapter-grid a',
    // 更通用的选择器
    'dd a',                  // 直接dd里的链接
    'dl a',                  // dl里的链接
    '.content a',            // 内容区域链接
    '#content a',
    '.main a',               // 主体区域链接
    '#main a',
    '.article a',            // 文章区域
    'article a',
    '.body a',
    // 非常通用的选择器（最后尝试）
    'ul li a',               // 任何列表链接
    'ol li a',
  ];

  /// 解析章节列表
  List<OnlineChapter> _parseChapterList(
    BookSource source,
    dynamic responseData,
    String baseUrl,
  ) {
    final rule = source.ruleToc;
    if (rule == null) {
      logger.d('书源 ${source.displayName} 没有目录规则 (ruleToc is null)');
      // 尝试使用备用选择器
      return _parseChapterListWithFallback(responseData, baseUrl);
    }

    final chapterListRule = rule.chapterList;
    if (chapterListRule == null || chapterListRule.isEmpty) {
      logger.d('书源 ${source.displayName} 没有章节列表规则 (chapterList is empty)');
      return _parseChapterListWithFallback(responseData, baseUrl);
    }

    logger.d('解析章节列表, 规则: $chapterListRule');
    var chapterList = RuleParser.parseRuleList(chapterListRule, responseData, baseUrl: baseUrl);
    
    // 如果主规则解析失败，尝试备用选择器
    if (chapterList.isEmpty) {
      logger.d('章节列表解析结果为空, 响应数据类型: ${responseData.runtimeType}');
      logger.d('尝试使用备用选择器...');
      return _parseChapterListWithFallback(responseData, baseUrl, primaryRule: rule);
    }
    
    logger.d('解析到 ${chapterList.length} 个章节项');
    return _extractChaptersFromList(chapterList, rule, baseUrl);
  }

  /// 使用备用选择器解析章节列表
  List<OnlineChapter> _parseChapterListWithFallback(
    dynamic responseData,
    String baseUrl, {
    TocRule? primaryRule,
  }) {
    // 跟踪最佳结果
    List<OnlineChapter> bestChapters = [];
    String? bestSelector;
    
    for (final selector in _fallbackChapterSelectors) {
      final chapterList = RuleParser.parseRuleList(selector, responseData, baseUrl: baseUrl);
      if (chapterList.isEmpty) continue;
      
      logger.d('备用选择器 "$selector" 匹配到 ${chapterList.length} 个元素');
      
      // 使用通用规则提取章节信息
      final chapters = <OnlineChapter>[];
      for (var i = 0; i < chapterList.length; i++) {
        final item = chapterList[i];
        try {
          // 尝试从HTML元素中提取信息
          // 首先尝试直接获取（当 item 本身就是 <a> 元素时）
          String? name = RuleParser.parseRule('text', item, baseUrl: baseUrl);
          String? url = RuleParser.parseRule('href', item, baseUrl: baseUrl);
          
          // 如果直接获取失败，尝试获取嵌套的 <a> 元素
          if ((name == null || name.isEmpty) && (url == null || url.isEmpty)) {
            name = RuleParser.parseRule('@css:a@text', item, baseUrl: baseUrl);
            url = RuleParser.parseRule('@css:a@href', item, baseUrl: baseUrl);
          }
          
          // 也尝试 outerHtml 提取 (用于调试)
          if (i < 3 && (name == null || name.isEmpty || url == null || url.isEmpty)) {
            final html = RuleParser.parseRule('outerHtml', item, baseUrl: baseUrl);
            logger.d('备用选择器元素[$i]: name=$name, url=$url, html=${html?.substring(0, html.length > 100 ? 100 : html.length)}...');
          }
          
          if (name != null && name.isNotEmpty && url != null && url.isNotEmpty) {
            // 清理 URL（可能包含 HTML 片段）
            url = _sanitizeChapterUrl(url, baseUrl);
            
            // 智能清理章节名称（仅在检测到问题时清理）
            var cleanedName = _smartCleanChapterName(name);
            if (cleanedName.isEmpty) {
              cleanedName = _extractNameFromUrl(url) ?? 'Unknown';
            }
            
            // 过滤非章节链接
            if (_isLikelyChapterUrl(url, cleanedName)) {
              chapters.add(OnlineChapter(
                name: cleanedName,
                url: url,
                isVolume: false,
              ));
            }
          }
        } catch (e) {
          // 忽略单个章节解析失败
        }
      }
      
      // 如果解析出足够多的章节（高置信度），立即返回
      if (chapters.length >= 10) {
        logger.i('备用选择器成功: "$selector", 解析出 ${chapters.length} 个章节 (高置信度)');
        return chapters;
      }
      
      // 记录最佳结果
      if (chapters.length > bestChapters.length) {
        bestChapters = chapters;
        bestSelector = selector;
        logger.d('选择器 "$selector" 解析出 ${chapters.length} 个章节 (当前最佳)');
      }
    }
    
    // 如果最佳结果包含至少3个章节，使用它
    if (bestChapters.length >= 3) {
      logger.i('使用最佳备用选择器: "$bestSelector", 解析出 ${bestChapters.length} 个章节');
      return bestChapters;
    }
    
    // 所有选择器都失败，输出HTML结构帮助调试
    if (responseData is String && responseData.length > 100) {
      // 提取 body 部分
      final bodyMatch = RegExp(r'<body[^>]*>([\s\S]*)', caseSensitive: false)
          .firstMatch(responseData);
      if (bodyMatch != null) {
        final bodyContent = bodyMatch.group(1) ?? '';
        // 显示更多内容用于调试
        final preview = bodyContent.length > 2000 
            ? '${bodyContent.substring(0, 2000)}...' 
            : bodyContent;
        logger.w('所有选择器失败，HTML body 预览:\n$preview');
        
        // 额外分析：查找所有 <a> 标签
        final linkPattern = RegExp(r'<a[^>]+href="([^"]+)"[^>]*>([^<]*)</a>', caseSensitive: false);
        final allLinks = linkPattern.allMatches(responseData).toList();
        if (allLinks.isNotEmpty) {
          logger.w('HTML中包含 ${allLinks.length} 个链接，示例:');
          var count = 0;
          for (final match in allLinks) {
            if (count >= 10) break;
            final href = match.group(1);
            final text = match.group(2);
            logger.w('  链接: $text -> $href');
            count++;
          }
        }
      }
    }
    
    logger.w('所有备用选择器均未能解析章节列表');
    return [];
  }

  /// 判断URL是否可能是章节链接
  bool _isLikelyChapterUrl(String url, String name) {
    final lowerUrl = url.toLowerCase();
    final lowerName = name.toLowerCase();
    
    // 排除明显的非章节链接
    final excludePatterns = [
      'javascript:', 'mailto:', '#', 
      'login', 'register', 'search', 
      'index', 'home', 'about', 'contact',
      'category', 'tag', 'author',
    ];
    for (final pattern in excludePatterns) {
      if (lowerUrl.contains(pattern)) return false;
    }
    
    // 章节链接通常包含这些特征
    final chapterPatterns = [
      r'\d+\.html?$',           // 以数字.html结尾
      r'/\d+/?$',               // 以数字结尾
      r'chapter',               // 包含chapter
      r'chap',
      r'zhang',                 // 中文拼音
      r'/\d{1,6}/',             // URL路径中有数字
    ];
    
    for (final pattern in chapterPatterns) {
      if (RegExp(pattern).hasMatch(lowerUrl)) return true;
    }
    
    // 章节名称通常包含这些特征
    final chapterNamePatterns = [
      r'第.+章',                // 第X章
      r'第.+节',                // 第X节
      r'chapter\s*\d',          // Chapter N
      r'^\d+[\.\s]',            // 以数字开头
      r'第\d+',                 // 第N
    ];
    
    for (final pattern in chapterNamePatterns) {
      if (RegExp(pattern).hasMatch(lowerName)) return true;
    }
    
    // 如果名称看起来像正常的中文章节名（2-50字符，非纯符号）
    if (name.length >= 2 && name.length <= 50) {
      final hasChinese = RegExp(r'[\u4e00-\u9fa5]').hasMatch(name);
      if (hasChinese) return true;
    }
    
    return false;
  }

  /// 从解析结果列表中提取章节信息
  List<OnlineChapter> _extractChaptersFromList(
    List<dynamic> chapterList,
    TocRule rule,
    String baseUrl,
  ) {
    final chapters = <OnlineChapter>[];

    for (var i = 0; i < chapterList.length; i++) {
      final item = chapterList[i];
      try {
        var name = RuleParser.parseRule(rule.chapterName, item, baseUrl: baseUrl);
        var url = RuleParser.parseRule(rule.chapterUrl, item, baseUrl: baseUrl);

        // 修复 URL：如果返回的是 HTML 片段，提取其中的 href
        if (url != null && url.isNotEmpty) {
          url = _sanitizeChapterUrl(url, baseUrl);
        }

        if (url == null || url.isEmpty) {
          if (i < 3) {
            logger.d('章节项[$i] URL解析失败');
          }
          continue;
        }

        // 智能章节名修复：如果 name 为空或看起来像 URL，尝试从 HTML 提取文本
        if (name == null || name.isEmpty || _isUrlLike(name)) {
          final extractedName = _extractTextFromHtml(item);
          if (extractedName != null && extractedName.isNotEmpty && !_isUrlLike(extractedName)) {
            logger.d('章节名修复: 从URL/空值恢复为 "$extractedName"');
            name = extractedName;
          }
        }

        // 如果仍然没有有效名称，尝试从 URL 提取
        if (name == null || name.isEmpty || _isUrlLike(name)) {
          name = _extractNameFromUrl(url);
        }

        if (name == null || name.isEmpty) {
          if (i < 3) {
            logger.d('章节项[$i] 解析失败: name=$name, url=$url');
          }
          continue;
        }

        final isVolumeStr = RuleParser.parseRule(rule.isVolume, item, baseUrl: baseUrl);
        final isVolume = isVolumeStr == 'true' || isVolumeStr == '1';

        // 智能清理章节名称（仅在检测到问题时清理）
        var cleanedName = _smartCleanChapterName(name);
        if (cleanedName.isEmpty) {
          cleanedName = _extractNameFromUrl(url) ?? 'Unknown';
        }

        chapters.add(OnlineChapter(
          name: cleanedName,
          url: url,
          isVolume: isVolume,
          updateTime: RuleParser.parseRule(rule.updateTime, item, baseUrl: baseUrl),
        ));
      } catch (e, st) {
        AppError.ignore(e, st, '解析章节项失败');
      }
    }

    logger.d('成功解析 ${chapters.length} 个章节');
    return chapters;
  }

  /// 智能清理章节名称 - 只有在检测到问题时才进行清理
  /// 
  /// 检测规则：
  /// 1. 包含 URL 编码的 HTML（%3C, %3E 等）→ 解码后提取文本
  /// 2. 包含 HTML 标签（< 和 >）→ 解析 HTML 提取文本
  /// 3. 以 http 开头 → 可能是 URL，尝试从中提取名称
  /// 4. 否则 → 保持原样，不做任何处理
  String _smartCleanChapterName(String name) {
    if (name.isEmpty) return name;
    
    final trimmed = name.trim();
    
    // 1. 检测 URL 编码的 HTML 内容
    if (trimmed.contains('%3C') || trimmed.contains('%3c') || 
        trimmed.contains('%3E') || trimmed.contains('%3e')) {
      try {
        final decoded = Uri.decodeComponent(trimmed);
        // 如果解码后包含 HTML，继续处理
        if (decoded.contains('<') && decoded.contains('>')) {
          final cleaned = _extractTextFromHtmlString(decoded);
          if (cleaned != null && cleaned.isNotEmpty && !_isUrlLike(cleaned)) {
            logger.d('章节名清理(URL编码): "$trimmed" => "$cleaned"');
            return cleaned;
          }
        }
        // 如果解码后不是 HTML，但解码成功，返回解码结果
        if (!decoded.contains('<') && !_isUrlLike(decoded)) {
          return decoded;
        }
      } catch (_) {
        // URL 解码失败，继续检查其他情况
      }
    }
    
    // 2. 检测 HTML 标签
    if (trimmed.contains('<') && trimmed.contains('>')) {
      final cleaned = _extractTextFromHtmlString(trimmed);
      if (cleaned != null && cleaned.isNotEmpty && !_isUrlLike(cleaned)) {
        logger.d('章节名清理(HTML): "$trimmed" => "$cleaned"');
        return cleaned;
      }
    }
    
    // 3. 检测纯 URL（不应作为章节名）
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      // 已经是 URL，返回空让调用者用 _extractNameFromUrl 处理
      return '';
    }
    
    // 4. 正常名称，不需要清理
    return trimmed;
  }

  /// 从 HTML 字符串中提取纯文本
  String? _extractTextFromHtmlString(String html) {
    try {
      final document = html_parser.parse(html);
      
      // 优先从 <a> 标签提取
      final aElement = document.querySelector('a');
      if (aElement != null) {
        // 首选：链接文本
        final text = aElement.text.trim();
        if (text.isNotEmpty && !_isUrlLike(text)) {
          return text;
        }
        // 备选：title 属性
        final title = aElement.attributes['title'];
        if (title != null && title.isNotEmpty && !_isUrlLike(title)) {
          return title;
        }
      }
      
      // 获取 body 中的所有文本
      final bodyText = document.body?.text.trim();
      if (bodyText != null && bodyText.isNotEmpty && !_isUrlLike(bodyText)) {
        return bodyText;
      }
    } catch (_) {
      // 降级到正则提取
      final match = RegExp(r'>([^<]+)<').firstMatch(html);
      if (match != null) {
        final text = match.group(1)?.trim();
        if (text != null && text.isNotEmpty && !_isUrlLike(text)) {
          return text;
        }
      }
    }
    return null;
  }

  /// 清理章节URL：从HTML片段中提取href
  String _sanitizeChapterUrl(String url, String baseUrl) {
    // 首先检查是否包含 URL 编码的 HTML（如 %3C = <）
    // 即使 URL 以 http:// 开头也可能包含编码的 HTML
    if (url.contains('%3C') || url.contains('%3c') || url.contains('%22') || url.contains('%27')) {
      try {
        final decodedUrl = Uri.decodeComponent(url);
        // 如果解码后包含 HTML 标签，尝试提取 href
        if (decodedUrl.contains('<') && decodedUrl.contains('href=')) {
          final hrefMatch = RegExp(r'''href=["']([^"']+)["']''').firstMatch(decodedUrl);
          if (hrefMatch != null) {
            var extractedUrl = hrefMatch.group(1)!;
            // 如果是相对路径，拼接 baseUrl
            if (!extractedUrl.startsWith('http')) {
              // 尝试从原 URL 提取域名
              final urlMatch = RegExp(r'^(https?://[^/]+)').firstMatch(url);
              if (urlMatch != null) {
                extractedUrl = '${urlMatch.group(1)}$extractedUrl';
              } else if (baseUrl.isNotEmpty) {
                final baseUri = Uri.parse(baseUrl);
                extractedUrl = '${baseUri.scheme}://${baseUri.host}$extractedUrl';
              }
            }
            logger.d('URL修复: 从HTML提取 "$extractedUrl"');
            return extractedUrl;
          }
        }
      } catch (e) {
        logger.d('URL解码失败: $e');
      }
    }
    
    // 如果已经是有效URL且不包含HTML编码，直接返回
    if (url.startsWith('http://') || url.startsWith('https://') || url.startsWith('/')) {
      return url;
    }
    
    // 如果包含 HTML 标签（未编码），尝试提取 href
    if (url.contains('<') && url.contains('href=')) {
      final hrefMatch = RegExp(r'''href=["']([^"']+)["']''').firstMatch(url);
      if (hrefMatch != null) {
        var extractedUrl = hrefMatch.group(1)!;
        if (!extractedUrl.startsWith('http') && baseUrl.isNotEmpty) {
          final baseUri = Uri.parse(baseUrl);
          extractedUrl = '${baseUri.scheme}://${baseUri.host}$extractedUrl';
        }
        logger.d('URL修复: 从HTML提取 "$extractedUrl"');
        return extractedUrl;
      }
    }
    
    return url;
  }

  /// 检查字符串是否看起来像 URL
  bool _isUrlLike(String text) {
    if (text.startsWith('http://') || text.startsWith('https://') || text.startsWith('//')) {
      return true;
    }
    // 检查是否包含 URL 编码字符占比过高
    final encodedCount = RegExp(r'%[0-9A-Fa-f]{2}').allMatches(text).length;
    if (encodedCount > 5 && encodedCount > text.length / 10) {
      return true;
    }
    // 检查是否是路径格式
    if (text.contains('/') && !text.contains(' ') && RegExp(r'\.\w{2,5}$').hasMatch(text)) {
      return true;
    }
    return false;
  }

  /// 从 HTML 字符串中提取文本内容
  String? _extractTextFromHtml(dynamic item) {
    if (item == null) return null;
    
    final html = item.toString();
    if (html.isEmpty) return null;

    try {
      final document = html_parser.parse(html);
      
      // 尝试找 <a> 标签的文本
      final aElement = document.querySelector('a');
      if (aElement != null) {
        final text = aElement.text.trim();
        if (text.isNotEmpty) return text;
        // 尝试获取 title 属性
        final title = aElement.attributes['title'];
        if (title != null && title.isNotEmpty) return title;
      }
      
      // 直接获取所有文本
      final allText = document.body?.text.trim();
      if (allText != null && allText.isNotEmpty) return allText;
    } catch (_) {
      // 降级到正则提取
      // 匹配 <a> 标签内的文本
      final aMatch = RegExp(r'<a[^>]*>([^<]+)</a>', caseSensitive: false).firstMatch(html);
      if (aMatch != null) {
        final text = aMatch.group(1)?.trim();
        if (text != null && text.isNotEmpty) return text;
      }
      
      // 匹配 title 属性
      final titleMatch = RegExp(r'title="([^"]+)"', caseSensitive: false).firstMatch(html);
      if (titleMatch != null) {
        final text = titleMatch.group(1)?.trim();
        if (text != null && text.isNotEmpty) return text;
      }
      
      // 去除所有 HTML 标签
      final stripped = html.replaceAll(RegExp(r'<[^>]*>'), '').trim();
      if (stripped.isNotEmpty) return stripped;
    }
    
    return null;
  }

  /// 从 URL 中提取可能的章节名
  String? _extractNameFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      var path = uri.pathSegments.lastOrNull ?? '';
      
      // 去除扩展名
      path = path.replaceAll(RegExp(r'\.(html?|php|aspx?|jsp)$', caseSensitive: false), '');
      
      // URL 解码
      path = Uri.decodeComponent(path);
      
      // 如果只是数字，返回 "第X章"
      if (RegExp(r'^\d+$').hasMatch(path)) {
        return '第${path}章';
      }
      
      // 如果包含中文，直接返回
      if (RegExp(r'[\u4e00-\u9fa5]').hasMatch(path)) {
        return path;
      }
    } catch (e, st) {
      AppError.ignore(e, st, 'URL \u7ae0\u8282\u540d\u63d0\u53d6\u5931\u8d25');
    }

    return null;
  }

  /// 备用内容选择器列表 - 常见的正文容器
  static const List<String> _fallbackContentSelectors = [
    '#chaptercontent',
    '#content',
    '#bookcontent',
    '#readcontent',
    '#article',
    '#txtContent',
    '#nr',
    '#nr1',
    '.content',
    '.chaptercontent',
    '.bookcontent',
    '.readcontent',
    '.article-content',
    '.chapter-content',
    '.novel-content',
    '.read-content',
    '.txt',
    '.nr',
    'article.content',
    'article',
    '.entry-content',
    '.post-content',
    'div.txt',
    'div.text',
    '#text',
    '.text',
  ];

  /// 使用备用选择器解析正文内容
  String? _parseContentWithFallback(dynamic response) {
    if (response == null) return null;
    
    String htmlContent;
    if (response is String) {
      htmlContent = response;
    } else {
      return null;
    }
    
    try {
      final document = html_parser.parse(htmlContent);
      
      for (final selector in _fallbackContentSelectors) {
        final element = document.querySelector(selector);
        if (element != null) {
          final text = element.text.trim();
          // 至少包含100个字符才认为是有效内容
          if (text.length >= 100) {
            logger.i('备用内容选择器成功: "$selector", 内容长度: ${text.length}');
            return text;
          }
        }
      }
      
      // 如果所有选择器都失败，尝试找最长的文本块
      final allDivs = document.querySelectorAll('div, p, article, section');
      String? bestContent;
      int bestLength = 0;
      
      for (final div in allDivs) {
        final text = div.text.trim();
        if (text.length > bestLength && text.length >= 200) {
          // 排除明显的非正文区域
          final className = div.className.toLowerCase();
          final id = (div.id).toLowerCase();
          if (!className.contains('header') && 
              !className.contains('footer') &&
              !className.contains('nav') &&
              !className.contains('menu') &&
              !className.contains('sidebar') &&
              !id.contains('header') &&
              !id.contains('footer') &&
              !id.contains('nav') &&
              !id.contains('menu') &&
              !id.contains('sidebar')) {
            bestContent = text;
            bestLength = text.length;
          }
        }
      }
      
      if (bestContent != null) {
        logger.i('使用最长文本块作为正文, 长度: $bestLength');
        return bestContent;
      }
    } catch (e) {
      logger.w('备用内容选择器解析失败: $e');
    }
    
    return null;
  }

  /// 获取章节内容
  Future<String?> getChapterContent(
    BookSource source,
    OnlineChapter chapter,
  ) async {
    try {
      final rule = source.ruleContent;
      if (rule == null) {
        logger.w('书源 ${source.displayName} 没有正文规则');
        return null;
      }

      // 获取所有页的内容
      final allContent = StringBuffer();
      // 清理可能被污染的章节URL（如包含HTML片段）
      final baseUrl = source.bookSourceUrl;
      final originalUrl = chapter.url;
      var currentUrl = _sanitizeChapterUrl(originalUrl, baseUrl);
      
      // 调试：记录URL处理结果
      if (originalUrl != currentUrl) {
        logger.i('章节URL已修复: 原始="$originalUrl" => 修复后="$currentUrl"');
      } else {
        logger.d('章节URL获取: "$currentUrl"');
      }
      var pageCount = 0;
      const maxPages = 20; // 防止无限循环

      while (currentUrl.isNotEmpty && pageCount < maxPages) {
        final response = await _makeRequest(source, currentUrl);
        if (response == null) {
          logger.w('章节内容请求失败: $currentUrl');
          break;
        }
        
        // 调试：记录响应信息
        final responsePreview = response is String 
            ? (response.length > 200 ? '${response.substring(0, 200)}...' : response)
            : 'non-string response';
        logger.d('章节内容响应(前200字): $responsePreview');

        // 解析正文
        final contentRule = rule.content;
        logger.d('正文解析规则: $contentRule');
        var content = RuleParser.parseRule(contentRule, response, baseUrl: currentUrl);
        
        // 如果主规则解析失败，尝试备用选择器
        if (content == null || content.isEmpty) {
          logger.d('主规则解析失败，尝试备用内容选择器...');
          content = _parseContentWithFallback(response);
        }
        
        if (content == null || content.isEmpty) {
          logger.w('正文解析结果为空, 规则: $contentRule');
          break;
        }

        // 应用净化规则
        content = RuleParser.applyReplaceRules(content, rule.replaceRegex);

        allContent.write(content);

        // 检查是否有下一页
        final nextUrl = RuleParser.parseRule(rule.nextContentUrl, response, baseUrl: currentUrl);
        if (nextUrl == null || nextUrl.isEmpty || nextUrl == currentUrl) {
          break;
        }
        currentUrl = nextUrl;
        pageCount++;

        // 添加分页分隔
        allContent.write('\n\n');
      }

      final result = allContent.toString().trim();
      if (result.isEmpty) {
        logger.w('获取章节内容为空: ${chapter.name}');
        return null;
      }

      logger.d('获取章节内容成功: ${chapter.name}, 长度: ${result.length}');
      return result;
    } catch (e, st) {
      AppError.handle(e, st, 'getChapterContent');
      return null;
    }
  }

  /// 发送HTTP请求（带重试机制）
  Future<dynamic> _makeRequest(BookSource source, String url, {int maxRetries = 3}) async {
    Exception? lastError;
    
    for (var attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final options = Options(
          headers: _buildHeaders(source, url),
          responseType: ResponseType.plain,
        );

        final response = await _dio.get<String>(
          url,
          options: options,
        );

        if (response.statusCode != 200) {
          logger.w('请求失败: $url, 状态码: ${response.statusCode}');
          return null;
        }

        final data = response.data;
        if (data == null) return null;

        // 尝试解析为JSON
        try {
          return jsonDecode(data);
        } catch (_) {
          // 不是JSON，返回HTML
          return data;
        }
      } on DioException catch (e) {
        lastError = e;
        if (attempt < maxRetries) {
          // 指数退避延迟: 500ms, 1000ms, 2000ms
          final delay = Duration(milliseconds: 500 * (1 << (attempt - 1)));
          logger.d('请求失败，${delay.inMilliseconds}ms 后重试 ($attempt/$maxRetries): $url');
          await Future<void>.delayed(delay);
        }
      } catch (e, st) {
        AppError.ignore(e, st, '请求失败: $url');
        return null;
      }
    }
    
    if (lastError != null) {
      AppError.ignore(lastError, StackTrace.current, '请求失败(重试$maxRetries次后): $url');
    }
    return null;
  }

  /// 构建请求头（带随机 User-Agent）
  Map<String, String> _buildHeaders(BookSource source, String url) {
    // 从 URL 提取 Referer
    String referer;
    try {
      final uri = Uri.parse(url);
      referer = '${uri.scheme}://${uri.host}/';
    } catch (_) {
      referer = source.bookSourceUrl;
    }
    
    final headers = <String, String>{
      'User-Agent': _userAgents[_random.nextInt(_userAgents.length)],
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8,en-US;q=0.7',
      'Accept-Encoding': 'gzip, deflate',
      'Connection': 'keep-alive',
      'Upgrade-Insecure-Requests': '1',
      'Referer': referer,
      'Cache-Control': 'max-age=0',
    };

    // 解析书源中的自定义请求头
    if (source.header != null && source.header!.isNotEmpty) {
      try {
        final customHeaders = jsonDecode(source.header!) as Map<String, dynamic>;
        for (final entry in customHeaders.entries) {
          headers[entry.key] = entry.value.toString();
        }
      } catch (_) {
        // 可能是 key=value 格式
        for (final line in source.header!.split('\n')) {
          final parts = line.split(':');
          if (parts.length >= 2) {
            headers[parts[0].trim()] = parts.sublist(1).join(':').trim();
          }
        }
      }
    }

    return headers;
  }
}
