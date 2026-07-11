import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:json_path/json_path.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:xpath_selector_html_parser/xpath_selector_html_parser.dart';

/// 规则解析器
///
/// 支持多种规则语法：
/// - JSONPath: `$.data.list`
/// - XPath: `//div[@class='content']`
/// - CSS选择器: `div.content@text` 或 `class.content`
/// - 正则表达式: `regex:pattern`
/// - 组合规则: 使用 `##` 或 `||` 分隔
class RuleParser {
  static const _maxRegexPatternLength = 512;
  static const _maxRegexInputLength = 1024 * 1024;
  static const _maxReplaceRuleCount = 20;

  /// 解析单条规则，返回第一个匹配结果
  static String? parseRule(String? rule, dynamic source, {String? baseUrl}) {
    if (rule == null || rule.isEmpty) return null;
    if (source == null) return null;

    try {
      // 处理组合规则（使用 || 分隔，表示或关系）
      if (rule.contains('||')) {
        for (final subRule in rule.split('||')) {
          final result = _parseSingleRule(
            subRule.trim(),
            source,
            baseUrl: baseUrl,
          );
          if (result != null && result.isNotEmpty) {
            return result;
          }
        }
        return null;
      }

      // 处理链式规则（使用 ## 分隔，表示顺序执行）
      if (rule.contains('##')) {
        dynamic currentSource = source;
        for (final subRule in rule.split('##')) {
          final result = _parseSingleRule(
            subRule.trim(),
            currentSource,
            baseUrl: baseUrl,
          );
          if (result == null) return null;
          currentSource = result;
        }
        return currentSource?.toString();
      }

      return _parseSingleRule(rule, source, baseUrl: baseUrl);
    } catch (e, st) {
      logger.w('规则解析失败: $rule', e, st);
      return null;
    }
  }

  /// 解析规则，返回所有匹配结果列表
  static List<dynamic> parseRuleList(
    String? rule,
    dynamic source, {
    String? baseUrl,
  }) {
    if (rule == null || rule.isEmpty) return [];
    if (source == null) return [];

    try {
      return _parseSingleRuleList(rule, source, baseUrl: baseUrl);
    } catch (e, st) {
      logger.w('规则列表解析失败: $rule', e, st);
      return [];
    }
  }

  /// 解析单条规则
  static String? _parseSingleRule(
    String rule,
    dynamic source, {
    String? baseUrl,
  }) {
    var processedRule = rule.trim();
    String? attrName;

    // 1. 首先处理 Legado 格式的前缀规则
    // @css: 开头表示 CSS 选择器
    if (processedRule.startsWith('@css:')) {
      processedRule = processedRule.substring(5);
      // 检查是否有属性提取 (如 @css:div.title@text)
      if (processedRule.contains('@')) {
        final attrIndex = processedRule.lastIndexOf('@');
        attrName = processedRule.substring(attrIndex + 1);
        processedRule = processedRule.substring(0, attrIndex);
      }
      final result = _parseCssSelector(
        processedRule,
        source,
        attrName: attrName,
      );
      return _processResult(result, attrName, baseUrl);
    }

    // @json: 开头表示 JSONPath
    if (processedRule.startsWith('@json:')) {
      processedRule = processedRule.substring(6);
      final result = _parseJsonPath(
        processedRule.startsWith(r'$') ? processedRule : '\$.$processedRule',
        source,
      );
      return _processResult(result, null, baseUrl);
    }

    // @XPath: 开头表示 XPath
    if (processedRule.startsWith('@XPath:') ||
        processedRule.startsWith('@xpath:')) {
      processedRule = processedRule.substring(7);
      final result = _parseXPath(processedRule, source);
      return _processResult(result, null, baseUrl);
    }

    // 2. 处理 JSOUP 默认语法中的 @ 属性提取
    // 只有非前缀规则才处理 @ 作为属性分隔符
    if (processedRule.contains('@') &&
        !processedRule.startsWith('//') &&
        !processedRule.startsWith('/')) {
      final attrIndex = processedRule.lastIndexOf('@');
      final potentialAttr = processedRule.substring(attrIndex + 1);
      // 确保 @ 后面是有效的属性名（如 text, href, src 等）
      if (_isValidAttributeName(potentialAttr)) {
        attrName = potentialAttr;
        processedRule = processedRule.substring(0, attrIndex);
      }
    }

    String? result;

    // JSONPath 规则
    if (processedRule.startsWith(r'$.') || processedRule.startsWith(r'$[')) {
      result = _parseJsonPath(processedRule, source);
    }
    // XPath 规则
    else if (processedRule.startsWith('//') || processedRule.startsWith('/')) {
      result = _parseXPath(processedRule, source, attrName: attrName);
      attrName = null; // 已在XPath中处理
    }
    // 正则表达式
    else if (processedRule.startsWith('regex:')) {
      result = _parseRegex(processedRule.substring(6), source.toString());
    }
    // 检测隐式正则表达式模式
    else if (_isLikelyRegexPattern(processedRule)) {
      result = source?.toString();
    }
    // CSS选择器 (包含 . # [ 或空格)
    else if (processedRule.contains('.') ||
        processedRule.contains('#') ||
        processedRule.contains('[') ||
        processedRule.contains(' ') ||
        processedRule.contains('>') ||
        processedRule.contains(':')) {
      result = _parseCssSelector(processedRule, source, attrName: attrName);
      attrName = null;
    }
    // 简单字段名（用于JSON对象）- 如 "title", "author"
    else if (source is Map) {
      // 直接从Map中获取字段值
      final value = source[processedRule];
      result = value?.toString();
    }
    // 纯文本返回
    else {
      result = source?.toString();
    }

    // 处理属性提取
    if (attrName != null && result != null) {
      result = _extractAttr(result, attrName);
    }

    // 处理相对URL
    if (baseUrl != null && result != null && result.isNotEmpty) {
      result = _resolveUrl(result, baseUrl);
    }

    return result?.trim();
  }

  /// 解析规则并返回列表
  static List<dynamic> _parseSingleRuleList(
    String rule,
    dynamic source, {
    String? baseUrl,
  }) {
    final trimmedRule = rule.trim();

    // @css: CSS选择器
    if (trimmedRule.startsWith('@css:')) {
      var selector = trimmedRule.substring(5);
      // 移除属性提取部分（列表模式不需要）
      if (selector.contains('@')) {
        selector = selector.substring(0, selector.lastIndexOf('@'));
      }
      return _parseCssSelectorList(selector, source);
    }

    // @json: JSONPath
    if (trimmedRule.startsWith('@json:')) {
      var path = trimmedRule.substring(6);
      if (!path.startsWith(r'$')) {
        path = '\$.$path';
      }
      return _parseJsonPathList(path, source);
    }

    // @XPath: XPath
    if (trimmedRule.startsWith('@XPath:') ||
        trimmedRule.startsWith('@xpath:')) {
      return _parseXPathList(trimmedRule.substring(7), source);
    }

    // JSONPath 规则
    if (trimmedRule.startsWith(r'$.') || trimmedRule.startsWith(r'$[')) {
      return _parseJsonPathList(trimmedRule, source);
    }

    // XPath 规则
    if (trimmedRule.startsWith('//') || trimmedRule.startsWith('/')) {
      return _parseXPathList(trimmedRule, source);
    }

    // CSS选择器
    if (trimmedRule.contains('.') ||
        trimmedRule.contains('#') ||
        trimmedRule.contains('[') ||
        trimmedRule.contains(' ') ||
        trimmedRule.contains('>') ||
        trimmedRule.contains(':')) {
      return _parseCssSelectorList(trimmedRule, source);
    }

    // 默认返回单个结果
    final result = _parseSingleRule(rule, source, baseUrl: baseUrl);
    return result != null ? [result] : [];
  }

  /// 检测是否可能是正则表达式模式
  ///
  /// 正则表达式通常包含特殊元字符，与 CSS 选择器区分开
  static bool _isLikelyRegexPattern(String pattern) {
    // 包含明显的正则元字符组合
    // *、+、? 前有字符（如 .*, \w+, \d?）
    // 或者包含 |、^、$ 等
    // 或者类似 <.*?> 的 HTML 标签匹配模式
    if (pattern.contains('.*') ||
        pattern.contains('.+') ||
        pattern.contains('.?') ||
        pattern.contains(r'\') || // 转义字符
        pattern.contains('^') || // 行首
        pattern.contains(r'$') || // 行尾
        pattern.contains('|') || // 或
        (pattern.contains('<') && pattern.contains('>')) // HTML标签模式
        ) {
      return true;
    }
    return false;
  }

  /// 检查是否是有效的属性名
  static bool _isValidAttributeName(String name) {
    const validAttrs = {
      'text',
      'textNodes',
      'ownText',
      'html',
      'innerHTML',
      'outerHtml',
      'href',
      'src',
      'alt',
      'title',
      'value',
      'data-',
      'id',
      'class',
      'content',
      'name',
      'type',
      'action',
      'method',
      'target',
    };
    final lowerName = name.toLowerCase();
    return validAttrs.any(
      (attr) => lowerName == attr || lowerName.startsWith(attr),
    );
  }

  /// 处理结果（属性提取和URL解析）
  static String? _processResult(
    String? result,
    String? attrName,
    String? baseUrl,
  ) {
    if (result == null) return null;

    String? value = result;

    // 处理属性提取
    if (attrName != null && value.isNotEmpty) {
      value = _extractAttr(value, attrName);
    }

    // 处理相对URL
    if (baseUrl != null && value != null && value.isNotEmpty) {
      value = _resolveUrl(value, baseUrl);
    }

    return value?.trim();
  }

  /// 解析 JSONPath
  static String? _parseJsonPath(String path, dynamic json) {
    try {
      final dynamic data = json;
      if (json is String) {
        // 如果是字符串，尝试解析为JSON
        // 注意：这里不做JSON解析，假设调用者已经提供了正确的数据类型
        return null;
      }

      final jsonPath = JsonPath(path);
      final matches = jsonPath.read(data);
      if (matches.isEmpty) return null;

      final value = matches.first.value;
      return value?.toString();
    } catch (e) {
      logger.d('JSONPath解析失败: $path - $e');
      return null;
    }
  }

  /// 解析 JSONPath 返回列表
  static List<dynamic> _parseJsonPathList(String path, dynamic json) {
    try {
      final jsonPath = JsonPath(path);
      final matches = jsonPath.read(json);

      if (matches.isEmpty) return [];

      final firstMatch = matches.first.value;
      if (firstMatch is List) {
        return firstMatch;
      }

      return matches.map((m) => m.value).toList();
    } catch (e) {
      logger.d('JSONPath列表解析失败: $path - $e');
      return [];
    }
  }

  /// 解析 XPath
  static String? _parseXPath(String xpath, dynamic source, {String? attrName}) {
    try {
      String htmlContent;
      if (source is String) {
        htmlContent = source;
      } else if (source is html_dom.Element) {
        htmlContent = source.outerHtml;
      } else if (source is html_dom.Document) {
        htmlContent = source.outerHtml;
      } else {
        return null;
      }

      final document = html_parser.parse(htmlContent);
      final htmlXPath = HtmlXPath.html(document.outerHtml);
      final result = htmlXPath.query(xpath);

      if (result.nodes.isEmpty) return null;

      final node = result.nodes.first;

      // 如果指定了属性名
      if (attrName != null) {
        if (attrName == 'text') {
          return node.text?.trim();
        } else if (attrName == 'html' || attrName == 'outerHtml') {
          return node.toString();
        } else if (node is html_dom.Element) {
          return node.attributes[attrName];
        }
      }

      return node.text?.trim();
    } catch (e) {
      logger.d('XPath解析失败: $xpath - $e');
      return null;
    }
  }

  /// 解析 XPath 返回列表
  static List<dynamic> _parseXPathList(String xpath, dynamic source) {
    try {
      String htmlContent;
      if (source is String) {
        htmlContent = source;
      } else if (source is html_dom.Element) {
        htmlContent = source.outerHtml;
      } else if (source is html_dom.Document) {
        htmlContent = source.outerHtml;
      } else {
        return [];
      }

      final document = html_parser.parse(htmlContent);
      final htmlXPath = HtmlXPath.html(document.outerHtml);
      final result = htmlXPath.query(xpath);

      // 返回节点的HTML内容，供后续规则解析
      return result.nodes.map((node) => node.toString()).toList();
    } catch (e) {
      logger.d('XPath列表解析失败: $xpath - $e');
      return [];
    }
  }

  /// 解析 CSS 选择器
  static String? _parseCssSelector(
    String selector,
    dynamic source, {
    String? attrName,
  }) {
    try {
      html_dom.Document document;
      if (source is String) {
        document = html_parser.parse(source);
      } else if (source is html_dom.Element) {
        document = html_parser.parse(source.outerHtml);
      } else if (source is html_dom.Document) {
        document = source;
      } else {
        return null;
      }

      // 尝试转换 Legado 格式选择器
      final legadoResult = _parseLegadoSelector(
        selector,
        document,
        attrName: attrName,
      );
      if (legadoResult != null) {
        return legadoResult;
      }

      final element = document.querySelector(selector);
      if (element == null) return null;

      if (attrName != null) {
        if (attrName == 'text') {
          return element.text.trim();
        } else if (attrName == 'html' || attrName == 'innerHTML') {
          return element.innerHtml;
        } else if (attrName == 'outerHtml') {
          return element.outerHtml;
        } else {
          return element.attributes[attrName];
        }
      }

      return element.text.trim();
    } catch (e) {
      logger.d('CSS选择器解析失败: $selector - $e');
      return null;
    }
  }

  /// 解析 CSS 选择器返回列表
  static List<dynamic> _parseCssSelectorList(String selector, dynamic source) {
    try {
      // 处理 @ 属性
      var processedSelector = selector;
      if (selector.contains('@')) {
        final attrIndex = selector.lastIndexOf('@');
        processedSelector = selector.substring(0, attrIndex);
      }

      html_dom.Document document;
      if (source is String) {
        document = html_parser.parse(source);
      } else if (source is html_dom.Element) {
        document = html_parser.parse(source.outerHtml);
      } else if (source is html_dom.Document) {
        document = source;
      } else {
        logger.d('CSS选择器: 无效的源类型: ${source.runtimeType}');
        return [];
      }

      // 尝试转换 Legado 格式选择器
      final legadoResult = _parseLegadoSelectorList(
        processedSelector,
        document,
      );
      if (legadoResult.isNotEmpty) {
        return legadoResult;
      }

      logger.d(
        'CSS选择器解析: selector="$processedSelector", HTML长度=${source is String ? source.length : "N/A"}',
      );

      final elements = document.querySelectorAll(processedSelector);

      if (elements.isEmpty) {
        // 诊断信息：显示HTML前200字符
        final htmlPreview = source is String
            ? (source.length > 200 ? '${source.substring(0, 200)}...' : source)
            : 'N/A';
        logger.d('CSS选择器匹配0个元素. HTML预览: $htmlPreview');
      } else {
        logger.d('CSS选择器匹配到 ${elements.length} 个元素');
      }

      return elements.map((e) => e.outerHtml).toList();
    } catch (e) {
      logger.d('CSS选择器列表解析失败: $selector - $e');
      return [];
    }
  }

  /// 解析 Legado 格式的选择器
  ///
  /// 支持的格式:
  /// - `class.classname.index` - 获取指定类名的第 N 个元素 (0-based)
  /// - `tag.tagname.index` - 获取指定标签的第 N 个元素
  /// - `id.idname` - 获取指定 ID 的元素
  /// - 链式操作用 `@` 分隔: `class.a@tag.b@attr.href`
  static String? _parseLegadoSelector(
    String selector,
    html_dom.Document document, {
    String? attrName,
  }) {
    // 检查是否是 Legado 格式
    if (!_isLegadoFormat(selector)) {
      return null;
    }

    try {
      // 处理链式操作
      final parts = selector.split('@');
      dynamic currentElement = document.documentElement;

      for (var i = 0; i < parts.length; i++) {
        final part = parts[i].trim();
        if (part.isEmpty) continue;

        final isLastPart = i == parts.length - 1;

        // 处理属性提取 (attr.xxx 或 text, html 等)
        if (part == 'text' || part == 'textNodes' || part == 'ownText') {
          if (currentElement is html_dom.Element) {
            return currentElement.text.trim();
          }
          return null;
        }
        if (part == 'html' || part == 'innerHTML') {
          if (currentElement is html_dom.Element) {
            return currentElement.innerHtml;
          }
          return null;
        }
        if (part == 'outerHtml') {
          if (currentElement is html_dom.Element) {
            return currentElement.outerHtml;
          }
          return null;
        }
        if (part.startsWith('attr.')) {
          final attrNamePart = part.substring(5);
          if (currentElement is html_dom.Element) {
            return currentElement.attributes[attrNamePart];
          }
          return null;
        }
        if (part == 'href' ||
            part == 'src' ||
            part == 'title' ||
            part == 'alt') {
          if (currentElement is html_dom.Element) {
            return currentElement.attributes[part];
          }
          return null;
        }

        // 解析元素选择器
        final element = _selectLegadoElement(part, currentElement);
        if (element == null) {
          return null;
        }
        currentElement = element;

        // 如果是最后一部分且没有指定属性，返回文本
        if (isLastPart && attrName == null) {
          if (currentElement is html_dom.Element) {
            return currentElement.text.trim();
          }
        }
      }

      // 处理指定的属性
      if (attrName != null && currentElement is html_dom.Element) {
        if (attrName == 'text') {
          return currentElement.text.trim();
        } else if (attrName == 'html' || attrName == 'innerHTML') {
          return currentElement.innerHtml;
        } else if (attrName == 'outerHtml') {
          return currentElement.outerHtml;
        } else {
          return currentElement.attributes[attrName];
        }
      }

      if (currentElement is html_dom.Element) {
        return currentElement.text.trim();
      }
      return null;
    } catch (e) {
      logger.d('Legado选择器解析失败: $selector - $e');
      return null;
    }
  }

  /// 解析 Legado 格式的选择器返回列表
  static List<dynamic> _parseLegadoSelectorList(
    String selector,
    html_dom.Document document,
  ) {
    // 检查是否是 Legado 格式
    if (!_isLegadoFormat(selector)) {
      return [];
    }

    try {
      // 处理链式操作，取最后一个部分作为列表选择器
      final parts = selector.split('@');
      dynamic currentElement = document.documentElement;

      for (var i = 0; i < parts.length - 1; i++) {
        final part = parts[i].trim();
        if (part.isEmpty) continue;

        final element = _selectLegadoElement(part, currentElement);
        if (element == null) {
          return [];
        }
        currentElement = element;
      }

      // 最后一个部分作为列表选择器
      final lastPart = parts.last.trim();
      if (lastPart.isEmpty) return [];

      final elements = _selectLegadoElements(lastPart, currentElement);
      return elements.map((e) => e.outerHtml).toList();
    } catch (e) {
      logger.d('Legado选择器列表解析失败: $selector - $e');
      return [];
    }
  }

  /// 检查是否是 Legado 格式的选择器
  static bool _isLegadoFormat(String selector) {
    // Legado 格式特征:
    // 1. class.xxx.N 或 tag.xxx.N
    // 2. 使用 @ 作为链式分隔符（不是 @css:, @json: 等前缀）
    // 3. 以 class. 或 tag. 或 id. 开头

    // 如果包含标准 CSS 选择器特征，不是 Legado 格式
    if (selector.contains('[') ||
        selector.contains('>') ||
        selector.contains(':') ||
        selector.contains(' ')) {
      return false;
    }

    // 检查是否符合 Legado 格式
    final pattern = RegExp(
      r'^(class|tag|id)\.[a-zA-Z_][a-zA-Z0-9_-]*(\.[0-9]+)?(@.*)?$',
    );
    if (pattern.hasMatch(selector)) {
      return true;
    }

    // 检查简化的 tag.index 格式 (如 a.0, li.1, div.2)
    // 这是 tag.tagName.index 的简写形式
    final bareTagIndexPattern = RegExp(r'^[a-zA-Z][a-zA-Z0-9]*\.[0-9]+$');
    if (bareTagIndexPattern.hasMatch(selector)) {
      return true;
    }

    // 检查链式格式
    if (selector.contains('@')) {
      final parts = selector.split('@');
      for (final part in parts) {
        final trimmed = part.trim();
        if (trimmed.isEmpty) continue;
        // 属性部分
        if (trimmed == 'text' ||
            trimmed == 'html' ||
            trimmed == 'href' ||
            trimmed == 'src' ||
            trimmed.startsWith('attr.')) {
          continue;
        }
        // 元素选择器部分
        if (RegExp(
          r'^(class|tag|id)\.[a-zA-Z_][a-zA-Z0-9_-]*(\.[0-9]+)?$',
        ).hasMatch(trimmed)) {
          return true;
        }
        // 简化的 tag.index 格式
        if (bareTagIndexPattern.hasMatch(trimmed)) {
          return true;
        }
      }
    }

    return false;
  }

  /// 根据 Legado 格式选择单个元素
  ///
  /// 格式: `type.name.index` 或 `tagName.index`
  /// - type: class, tag, id (或直接使用 tagName)
  /// - name: 类名/标签名/ID
  /// - index: 可选，第 N 个元素 (0-based)
  static html_dom.Element? _selectLegadoElement(String part, dynamic parent) {
    final segments = part.split('.');
    if (segments.length < 2) return null;

    final type = segments[0].toLowerCase();
    final name = segments[1];
    // 对于简化格式 tagName.index，index 在 segments[1]
    // 对于标准格式 type.name.index，index 在 segments[2]

    var elements = <html_dom.Element>[];
    int? index;

    // 检查是否是简化的 tagName.index 格式 (如 a.0, li.1)
    final isSimplifiedFormat =
        !['class', 'tag', 'id'].contains(type) && int.tryParse(name) != null;

    if (isSimplifiedFormat) {
      // 简化格式: tagName.index (如 a.0)
      index = int.tryParse(name);
      if (parent is html_dom.Document) {
        elements = parent.getElementsByTagName(type);
      } else if (parent is html_dom.Element) {
        elements = parent.getElementsByTagName(type);
      }
    } else {
      // 标准格式: type.name.index
      index = segments.length > 2 ? int.tryParse(segments[2]) : null;

      if (parent is html_dom.Document) {
        switch (type) {
          case 'class':
            elements = parent.getElementsByClassName(name);
          case 'tag':
            elements = parent.getElementsByTagName(name);
          case 'id':
            final el = parent.getElementById(name);
            if (el != null) return el;
            return null;
          default:
            // 尝试作为标签名处理
            elements = parent.getElementsByTagName(type);
            if (elements.isEmpty) return null;
        }
      } else if (parent is html_dom.Element) {
        switch (type) {
          case 'class':
            elements = parent.getElementsByClassName(name);
          case 'tag':
            elements = parent.getElementsByTagName(name);
          case 'id':
            return parent.querySelector('#$name');
          default:
            // 尝试作为标签名处理
            elements = parent.getElementsByTagName(type);
            if (elements.isEmpty) return null;
        }
      } else {
        return null;
      }
    }

    if (elements.isEmpty) return null;

    if (index != null) {
      if (index >= 0 && index < elements.length) {
        return elements[index];
      }
      return null;
    }

    return elements.first;
  }

  /// 根据 Legado 格式选择多个元素
  static List<html_dom.Element> _selectLegadoElements(
    String part,
    dynamic parent,
  ) {
    final segments = part.split('.');
    if (segments.length < 2) return [];

    final type = segments[0].toLowerCase();
    final name = segments[1];

    var elements = <html_dom.Element>[];

    if (parent is html_dom.Document) {
      switch (type) {
        case 'class':
          elements = parent.getElementsByClassName(name);
        case 'tag':
          elements = parent.getElementsByTagName(name);
        case 'id':
          final el = parent.getElementById(name);
          if (el != null) return [el];
          return [];
        default:
          return [];
      }
    } else if (parent is html_dom.Element) {
      switch (type) {
        case 'class':
          elements = parent.getElementsByClassName(name);
        case 'tag':
          elements = parent.getElementsByTagName(name);
        case 'id':
          final el = parent.querySelector('#$name');
          if (el != null) return [el];
          return [];
        default:
          return [];
      }
    }

    return elements;
  }

  /// 解析正则表达式
  static String? _parseRegex(String pattern, String source) {
    if (!_isSafeRegex(pattern) || source.length > _maxRegexInputLength) {
      logger.w(
        '正则表达式已跳过: patternLength=${pattern.length}, sourceLength=${source.length}',
      );
      return null;
    }
    try {
      final regex = RegExp(pattern);
      final match = regex.firstMatch(source);
      if (match == null) return null;

      // 如果有分组，返回第一个分组，否则返回整个匹配
      if (match.groupCount > 0) {
        return match.group(1);
      }
      return match.group(0);
    } catch (e) {
      logger.d('正则表达式解析失败: $pattern - $e');
      return null;
    }
  }

  /// 提取属性
  static String? _extractAttr(String htmlOrText, String attrName) {
    if (attrName == 'text') {
      // 去除HTML标签
      return htmlOrText.replaceAll(RegExp('<[^>]*>'), '').trim();
    }

    // 尝试解析为HTML并提取属性
    try {
      final document = html_parser.parse(htmlOrText);
      final element = document.body?.children.firstOrNull;
      if (element != null) {
        return element.attributes[attrName];
      }
    } catch (e, st) {
      AppError.ignore(e, st, 'HTML 解析失败，返回 null');
    }

    return null;
  }

  /// 解析相对URL为绝对URL
  static String _resolveUrl(String url, String baseUrl) {
    if (url.isEmpty) return url;

    // 已经是绝对URL
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }

    // 协议相对URL
    if (url.startsWith('//')) {
      final baseUri = Uri.tryParse(baseUrl);
      return '${baseUri?.scheme ?? 'https'}:$url';
    }

    // 相对URL
    try {
      final baseUri = Uri.parse(baseUrl);
      final resolvedUri = baseUri.resolve(url);
      return resolvedUri.toString();
    } catch (_) {
      return url;
    }
  }

  /// 应用替换规则净化内容
  static String applyReplaceRules(String content, String? replaceRegex) {
    if (replaceRegex == null || replaceRegex.isEmpty) return content;
    if (content.length > _maxRegexInputLength) {
      logger.w('替换规则已跳过: contentLength=${content.length}');
      return content;
    }

    var result = content;

    // 支持多个替换规则，用 && 分隔
    for (final rule in replaceRegex.split('&&').take(_maxReplaceRuleCount)) {
      final trimmedRule = rule.trim();
      if (trimmedRule.isEmpty) continue;

      // 格式: pattern##replacement 或 pattern（删除匹配内容）
      final parts = trimmedRule.split('##');
      final pattern = parts[0];
      final replacement = parts.length > 1 ? parts[1] : '';
      if (!_isSafeRegex(pattern)) {
        logger.w('替换规则正则已跳过: patternLength=${pattern.length}');
        continue;
      }

      try {
        final regex = RegExp(pattern);
        result = result.replaceAll(regex, replacement);
      } catch (e) {
        logger.d('替换规则执行失败: $trimmedRule - $e');
      }
    }

    return result;
  }

  static bool _isSafeRegex(String pattern) {
    if (pattern.isEmpty || pattern.length > _maxRegexPatternLength) {
      return false;
    }
    if (RegExp(r'\\[1-9]').hasMatch(pattern)) {
      return false;
    }
    if (RegExp(
      r'\((?:[^()\\]|\\.)*[+*](?:[^()\\]|\\.)*\)\s*(?:[+*]|\{\d*,?\d*\})',
    ).hasMatch(pattern)) {
      return false;
    }
    if (RegExp(r'(?:\.\*){2,}|(?:\.\+){2,}').hasMatch(pattern)) {
      return false;
    }
    return true;
  }
}
