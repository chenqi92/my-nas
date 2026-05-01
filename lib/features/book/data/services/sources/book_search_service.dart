import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/book/data/services/sources/book_source_manager_service.dart';
import 'package:my_nas/features/book/data/services/sources/rule_parser.dart';
import 'package:my_nas/features/book/domain/entities/book_source.dart';

/// 在线书籍搜索服务
///
/// 支持多书源并行搜索，返回聚合结果
class BookSearchService {
  BookSearchService._();

  static final instance = BookSearchService._();

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

  /// 搜索进度信息
  int _totalSources = 0;
  int _completedSources = 0;
  
  /// 获取搜索书源总数
  int get totalSources => _totalSources;
  
  /// 获取已完成搜索的书源数  
  int get completedSources => _completedSources;

  /// 搜索书籍（多书源并行）
  ///
  /// 返回一个 Stream，每当有书源返回结果时就 yield
  /// 同时更新 completedSources 和 totalSources 用于显示进度
  Stream<OnlineBook> search(String keyword, {int page = 1}) async* {
    logger.d('📚 BookSearchService.search() 开始搜索: keyword="$keyword", page=$page');
    
    final sources = await BookSourceManagerService.instance.getEnabledSources();
    logger.d('📚 已启用的书源数量: ${sources.length}');

    if (sources.isEmpty) {
      logger.w('📚 没有可用的书源（请在书源管理中启用至少一个书源）');
      return;
    }

    // 并行搜索所有书源
    final searchableSources = sources
        .where((s) => s.searchUrl != null && s.searchUrl!.isNotEmpty)
        .toList();
    
    logger.d('📚 有搜索URL的书源数量: ${searchableSources.length}');
    
    if (searchableSources.isEmpty) {
      logger.w('📚 没有配置搜索URL的书源');
      return;
    }
    
    // 重置进度
    _totalSources = searchableSources.length;
    _completedSources = 0;
    
    final futures = searchableSources.map((source) async {
      final results = await _searchSource(source, keyword, page);
      _completedSources++;
      return results;
    });

    // 使用 Stream.fromFutures 处理并行结果
    await for (final results in Stream.fromFutures(futures)) {
      for (final book in results) {
        yield book;
      }
    }
    
    logger.d('📚 BookSearchService.search() 搜索完成');
  }

  /// 搜索单个书源
  Future<List<OnlineBook>> _searchSource(
    BookSource source,
    String keyword,
    int page,
  ) async {
    try {
      // 构建搜索URL
      final searchUrl = _buildSearchUrl(source, keyword, page);
      if (searchUrl == null) return [];

      logger.d('搜索书源: ${source.displayName}, URL: $searchUrl');

      // 发送请求（搜索时减少重试次数以加快速度）
      final response = await _makeRequest(source, searchUrl, maxRetries: 1);
      if (response == null) return [];

      // 解析结果（传入关键词用于相关性过滤）
      return _parseSearchResults(source, response, searchUrl, keyword);
    } catch (e, st) {
      AppError.ignore(e, st, '书源搜索失败: ${source.displayName}');
      return [];
    }
  }

  /// 构建搜索URL
  String? _buildSearchUrl(BookSource source, String keyword, int page) {
    var url = source.searchUrl;
    if (url == null || url.isEmpty) return null;

    // 替换关键词变量
    url = url
        .replaceAll('{{key}}', Uri.encodeComponent(keyword))
        .replaceAll('{{page}}', page.toString())
        .replaceAll(r'${key}', Uri.encodeComponent(keyword))
        .replaceAll(r'${page}', page.toString());

    // 处理相对URL
    if (!url.startsWith('http')) {
      url = '${source.bookSourceUrl}$url';
    }

    return url;
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

  /// 解析搜索结果
  List<OnlineBook> _parseSearchResults(
    BookSource source,
    dynamic responseData,
    String baseUrl,
    String keyword,
  ) {
    final rule = source.ruleSearch;
    if (rule == null) return [];

    // 获取书籍列表
    final bookListRule = rule.bookList;
    if (bookListRule == null || bookListRule.isEmpty) return [];

    final bookList = RuleParser.parseRuleList(bookListRule, responseData, baseUrl: baseUrl);
    if (bookList.isEmpty) return [];

    final books = <OnlineBook>[];

    for (final item in bookList) {
      try {
        // 📋 记录原始数据结构（前2条，便于分析可用字段）
        if (books.isEmpty && bookList.indexOf(item) < 2) {
          logger.w('📋 [${source.displayName}] 原始数据项 #${bookList.indexOf(item)}:');
          if (item is Map) {
            for (final key in item.keys.take(15)) {
              final value = item[key];
              final valueStr = value?.toString() ?? 'null';
              logger.w('   $key: ${valueStr.length > 100 ? '${valueStr.substring(0, 100)}...' : valueStr}');
            }
          } else if (item is String) {
            logger.w('   [HTML内容] ${item.length > 200 ? '${item.substring(0, 200)}...' : item}');
          } else {
            logger.w('   [类型: ${item.runtimeType}] $item');
          }
        }
        
        var name = RuleParser.parseRule(rule.name, item, baseUrl: baseUrl);
        final bookUrl = RuleParser.parseRule(rule.bookUrl, item, baseUrl: baseUrl);

        // 书名和URL是必须的
        if (name == null || name.isEmpty || bookUrl == null || bookUrl.isEmpty) {
          continue;
        }

        // 智能处理书名 - 如果书名看起来像URL，尝试提取真实书名
        name = _sanitizeBookName(name, bookUrl);
        
        // 跳过无法提取有效书名的结果
        if (name.isEmpty || name == bookUrl) {
          continue;
        }
        
        // 验证 bookUrl 格式 - 必须是有效的 URL
        // 跳过 JSON 对象或其他无效格式
        if (!bookUrl.startsWith('http://') && !bookUrl.startsWith('https://')) {
          // 尝试使用 baseUrl 补全
          if (bookUrl.startsWith('/')) {
            // 相对路径，后续会处理
          } else if (bookUrl.startsWith('{') || bookUrl.contains(': ')) {
            // JSON 格式，跳过
            continue;
          }
        }
        
        // 相关性过滤 - 跳过与搜索关键词不相关的结果
        final rawAuthor = RuleParser.parseRule(rule.author, item, baseUrl: baseUrl);
        final author = _smartExtractAuthor(rawAuthor, item);
        
        // 调试日志：追踪作者解析
        if (books.length < 5) { // 只记录前5本以避免日志过多
          logger.d('📖 [${source.displayName}] 书名: "$name"');
          logger.d('   作者规则: "${rule.author}"');
          logger.d('   原始作者: "$rawAuthor" → 智能提取: "$author"');
        }
        
        final isRelevant = _isRelevantResult(name, author, keyword);
        if (!isRelevant) {
          logger.d('过滤不相关结果: "$name" (关键词: "$keyword")');
          continue;
        }

        // 解析其他字段
        final rawCoverUrl = RuleParser.parseRule(rule.coverUrl, item, baseUrl: baseUrl);
        final coverUrl = _smartExtractCoverUrl(rawCoverUrl, item, baseUrl);
        final intro = _sanitizeText(RuleParser.parseRule(rule.intro, item, baseUrl: baseUrl));
        final kind = _sanitizeText(RuleParser.parseRule(rule.kind, item, baseUrl: baseUrl));
        final lastChapter = _sanitizeText(RuleParser.parseRule(rule.lastChapter, item, baseUrl: baseUrl));
        final wordCount = _sanitizeText(RuleParser.parseRule(rule.wordCount, item, baseUrl: baseUrl));
        
        // 详细日志：记录完整解析数据（前3本书）
        if (books.length < 3) {
          logger.i('📚 [${source.displayName}] 解析完成:');
          logger.i('   📖 书名: "$name" | 作者: "$author"');
          logger.i('   🔗 bookUrl: $bookUrl');
          logger.i('   🖼️ coverUrl规则: "${rule.coverUrl}" → 原始: "$rawCoverUrl" → 智能提取: "$coverUrl"');
          logger.i('   📝 intro: "${intro.length > 50 ? '${intro.substring(0, 50)}...' : intro}"');
          logger.i('   🏷️ kind: "$kind" | lastChapter: "$lastChapter" | wordCount: "$wordCount"');
        }

        books.add(OnlineBook(
          name: name,
          author: author,
          bookUrl: bookUrl,
          coverUrl: coverUrl,
          intro: intro,
          kind: kind,
          lastChapter: lastChapter,
          wordCount: wordCount,
          source: source,
        ));
      } catch (e, st) {
        AppError.ignore(e, st, '解析搜索结果项失败');
      }
    }

    logger.i('书源 ${source.displayName} 搜索到 ${books.length} 本书');
    return books;
  }

  /// 智能处理书名
  /// 
  /// 如果书名看起来像URL，尝试从URL路径中提取真实书名
  String _sanitizeBookName(String name, String bookUrl) {
    // 如果书名不像URL，直接返回
    if (!name.startsWith('http://') && !name.startsWith('https://')) {
      // 尝试URL解码（处理 %XX 编码的中文）
      try {
        final decoded = Uri.decodeComponent(name);
        if (decoded != name && !decoded.contains('%')) {
          return decoded.trim();
        }
      } catch (e, st) {
        AppError.ignore(e, st, 'URL 解码书名失败，使用原文本');
      }
      return name.trim();
    }
    
    // 书名看起来像URL，尝试从URL路径中提取书名
    try {
      final uri = Uri.parse(name);
      final path = uri.path;
      
      // 移除常见的路径前缀和后缀
      var extractedName = path
          .replaceAll(RegExp(r'^/+'), '')  // 移除开头的斜杠
          .replaceAll(RegExp(r'\.(html?|php|aspx?|jsp)$', caseSensitive: false), '')  // 移除文件扩展名
          .replaceAll(RegExp(r'/+$'), '');  // 移除结尾的斜杠
      
      // URL解码
      extractedName = Uri.decodeComponent(extractedName);
      
      // 如果提取到的是一堆数字或太短，则无效
      if (extractedName.isEmpty || 
          RegExp(r'^\d+$').hasMatch(extractedName) ||
          extractedName.length < 2) {
        return '';  // 返回空表示无效
      }
      
      // 取路径最后一部分作为书名
      final parts = extractedName.split('/');
      return parts.last.trim();
    } catch (_) {
      return '';
    }
  }
  
  /// 清理文本字段
  /// 
  /// 移除URL前缀，URL解码中文字符
  String _sanitizeText(String? text) {
    if (text == null || text.isEmpty) return '';
    
    var result = text;
    
    // 如果文本是URL，返回空（这些字段不应该是URL）
    if (result.startsWith('http://') || result.startsWith('https://')) {
      return '';
    }
    
    // 尝试URL解码
    try {
      final decoded = Uri.decodeComponent(result);
      if (decoded != result && !decoded.contains('%')) {
        result = decoded;
      }
    } catch (e, st) {
      AppError.ignore(e, st, 'URL 解码结果失败，使用原文本');
    }
    
    // 清理HTML标签
    result = result.replaceAll(RegExp(r'<[^>]*>'), '');
    
    return result.trim();
  }

  /// 智能提取作者信息
  /// 
  /// 处理各种书源的作者字段：
  /// 1. 正常文本 - 直接使用
  /// 2. HTML片段 - 从中提取作者名
  /// 3. URL编码内容 - 解码后提取
  /// 4. 无效数据 - 尝试从原始item中查找
  String _smartExtractAuthor(String? rawAuthor, dynamic item) {
    // 1. 先尝试常规清理
    var author = _sanitizeText(rawAuthor);
    
    // 如果清理后有效，验证是否像作者名
    if (author.isNotEmpty && _isValidAuthorName(author)) {
      return author;
    }
    
    // 2. 如果原始值包含URL编码的HTML，尝试从中提取作者
    if (rawAuthor != null && rawAuthor.isNotEmpty) {
      final extractedFromRaw = _extractAuthorFromHtmlOrText(rawAuthor);
      if (extractedFromRaw.isNotEmpty && _isValidAuthorName(extractedFromRaw)) {
        logger.d('   [智能提取] 从原始值中提取作者: "$extractedFromRaw"');
        return extractedFromRaw;
      }
    }
    
    // 3. 尝试从原始item数据中查找作者
    if (item != null) {
      final extractedFromItem = _extractAuthorFromItem(item);
      if (extractedFromItem.isNotEmpty && _isValidAuthorName(extractedFromItem)) {
        logger.d('   [智能提取] 从item中提取作者: "$extractedFromItem"');
        return extractedFromItem;
      }
    }
    
    return author;
  }

  /// 从HTML或文本中提取作者名
  String _extractAuthorFromHtmlOrText(String text) {
    var decoded = text;
    
    // URL解码
    try {
      decoded = Uri.decodeComponent(text);
    } catch (e, st) {
      AppError.ignore(e, st, 'URL 解码作者文本失败，使用原文本');
    }

    // 查找常见的作者标记模式
    final patterns = <RegExp>[
      // class="authorNm" 或 class="author"
      RegExp(r'''class=["'](?:authorNm|author|writer)["'][^>]*>(?:<[^>]*>)*([^<]+)''', caseSensitive: false),
      // 作者: xxx 或 作者：xxx
      RegExp(r'作者[：:]\s*([^\s<,，]+)'),
      // by XXX
      RegExp(r'\bby\s+([^\s<,，]+)', caseSensitive: false),
      // author: xxx
      RegExp(r'author[：:]\s*([^\s<,，]+)', caseSensitive: false),
    ];
    
    for (final pattern in patterns) {
      final match = pattern.firstMatch(decoded);
      if (match != null && match.group(1) != null) {
        final extracted = match.group(1)!.trim();
        // 清理HTML标签
        final cleaned = extracted.replaceAll(RegExp(r'<[^>]*>'), '').trim();
        if (cleaned.isNotEmpty && cleaned.length <= 20) {
          return cleaned;
        }
      }
    }
    
    return '';
  }

  /// 从item数据中提取作者
  String _extractAuthorFromItem(dynamic item) {
    if (item is Map) {
      // 尝试常见的作者字段名
      final authorKeys = ['author', 'writer', 'authorName', 'bookAuthor', 'zuozhe', 'zz'];
      for (final key in authorKeys) {
        if (item.containsKey(key)) {
          final value = item[key]?.toString().trim() ?? '';
          if (value.isNotEmpty && _isValidAuthorName(value)) {
            return value;
          }
        }
      }
    } else if (item is String) {
      // HTML内容，尝试从中提取
      return _extractAuthorFromHtmlOrText(item);
    }
    return '';
  }

  /// 验证字符串是否像有效的作者名
  bool _isValidAuthorName(String name) {
    if (name.isEmpty || name.length > 30) return false;
    
    // 不应该是URL
    if (name.startsWith('http://') || name.startsWith('https://')) return false;
    
    // 不应该是章节标题模式（包含"章"和数字）
    if (RegExp(r'第\d+章').hasMatch(name)) return false;
    
    // 不应该包含日期时间
    if (RegExp(r'\d{4}-\d{2}-\d{2}').hasMatch(name)) return false;
    if (RegExp(r'\d{2}:\d{2}').hasMatch(name)) return false;
    
    // 不应该只是数字
    if (RegExp(r'^\d+$').hasMatch(name)) return false;
    
    // 不应该是HTML标签
    if (name.startsWith('<') || name.endsWith('>')) return false;
    
    // 不应该包含大量特殊字符
    if (RegExp(r'[<>{}()\[\]]{3,}').hasMatch(name)) return false;
    
    return true;
  }

  /// 智能提取封面URL
  /// 
  /// 当规则解析失败时，尝试从原始item中提取封面URL
  String? _smartExtractCoverUrl(String? rawCoverUrl, dynamic item, String baseUrl) {
    // 1. 如果规则解析成功且是有效URL，直接返回
    if (rawCoverUrl != null && rawCoverUrl.isNotEmpty && _isValidImageUrl(rawCoverUrl)) {
      return _normalizeImageUrl(rawCoverUrl, baseUrl);
    }
    
    // 2. 尝试从原始item中提取封面
    if (item != null) {
      final extracted = _extractCoverFromItem(item);
      if (extracted != null && _isValidImageUrl(extracted)) {
        logger.d('   [智能提取] 封面URL: "$extracted"');
        return _normalizeImageUrl(extracted, baseUrl);
      }
    }
    
    return rawCoverUrl;
  }

  /// 从item数据中提取封面URL
  String? _extractCoverFromItem(dynamic item) {
    if (item is Map) {
      // 尝试常见的封面字段名
      final coverKeys = ['cover', 'coverUrl', 'coverImg', 'img', 'pic', 'image', 'bookCover', 'thumb'];
      for (final key in coverKeys) {
        if (item.containsKey(key)) {
          final value = item[key]?.toString().trim();
          if (value != null && value.isNotEmpty && _isValidImageUrl(value)) {
            return value;
          }
        }
      }
    } else if (item is String) {
      // HTML内容，尝试从中提取
      return _extractCoverFromHtml(item);
    }
    return null;
  }

  /// 从HTML中提取封面URL
  String? _extractCoverFromHtml(String html) {
    var decoded = html;
    
    // URL解码
    try {
      decoded = Uri.decodeComponent(html);
    } catch (e, st) {
      AppError.ignore(e, st, 'URL 解码 HTML 失败，使用原文本');
    }

    // 查找img标签的src或data-src
    // 优先查找带有cover相关class的img
    final patterns = <RegExp>[
      // class包含cover的img
      RegExp(r'''<img[^>]*class=["'][^"']*cover[^"']*["'][^>]*src=["']([^"']+)["']''', caseSensitive: false),
      RegExp(r'''<img[^>]*src=["']([^"']+)["'][^>]*class=["'][^"']*cover[^"']*["']''', caseSensitive: false),
      // class="bookImg" 或 class="book-cover-img"
      RegExp(r'''<img[^>]*class=["'][^"']*(?:bookImg|book-cover|book-list-cover)[^"']*["'][^>]*src=["']([^"']+)["']''', caseSensitive: false),
      // data-src (懒加载图片)
      RegExp(r'''<img[^>]*data-src=["']([^"']+)["']''', caseSensitive: false),
      // 普通img src（作为最后备选）
      RegExp(r'''<img[^>]*src=["'](https?://[^"']+\.(?:jpg|jpeg|png|gif|webp)[^"']*)["']''', caseSensitive: false),
    ];
    
    for (final pattern in patterns) {
      final match = pattern.firstMatch(decoded);
      if (match != null && match.group(1) != null) {
        final url = match.group(1)!.trim();
        if (_isValidImageUrl(url)) {
          return url;
        }
      }
    }
    
    return null;
  }

  /// 验证是否是有效的图片URL
  bool _isValidImageUrl(String url) {
    if (url.isEmpty) return false;
    
    // 不应该是占位图
    if (url.contains('placeholder') || url.contains('default') || url.contains('nocover')) {
      return false;
    }
    
    // 应该是URL格式
    if (!url.startsWith('http://') && !url.startsWith('https://') && !url.startsWith('//')) {
      return false;
    }
    
    return true;
  }

  /// 标准化图片URL
  String _normalizeImageUrl(String url, String baseUrl) {
    // 处理 // 开头的URL
    if (url.startsWith('//')) {
      return 'https:$url';
    }
    
    // 处理相对URL
    if (url.startsWith('/')) {
      try {
        final uri = Uri.parse(baseUrl);
        return '${uri.scheme}://${uri.host}$url';
      } catch (e, st) {
        AppError.ignore(e, st, 'baseUrl 解析失败，返回原相对 URL');
      }
    }
    
    return url;
  }

  /// 检查搜索结果是否与关键词相关
  /// 
  /// 要求书名或作者与关键词有实质关联
  bool _isRelevantResult(String bookName, String author, String keyword) {
    final lowerKeyword = keyword.toLowerCase();
    final lowerName = bookName.toLowerCase();
    final lowerAuthor = author.toLowerCase();
    
    // 1. 直接包含匹配 - 书名包含完整关键词（最优先）
    if (lowerName.contains(lowerKeyword)) {
      return true;
    }
    
    // 2. 作者名包含关键词
    if (lowerAuthor.isNotEmpty && lowerAuthor.contains(lowerKeyword)) {
      return true;
    }
    
    // 3. 对于中文关键词：要求所有字符都出现在书名中（连续）
    // 但只对短关键词(2-4字)启用此规则，且书名必须较短
    // 例如：搜索"鸣龙"，书名"鸣龙少年"应该匹配
    if (lowerKeyword.length >= 2 && lowerKeyword.length <= 4) {
      // 检查书名是否以关键词开头
      if (lowerName.startsWith(lowerKeyword)) {
        return true;
      }
    }
    
    // 4. 不相关
    return false;
  }

  /// 搜索书籍（返回聚合列表）
  ///
  /// 等待所有书源搜索完成后返回去重结果
  Future<List<OnlineBook>> searchAll(String keyword, {int page = 1}) async {
    final books = <OnlineBook>[];
    final seen = <String>{};

    await for (final book in search(keyword, page: page)) {
      // 根据书名+作者去重
      final key = book.uniqueKey;
      if (!seen.contains(key)) {
        seen.add(key);
        books.add(book);
      }
    }

    return books;
  }
}
