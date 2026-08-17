import 'package:flutter_test/flutter_test.dart';
import 'package:my_nas/core/utils/book_html_sanitizer.dart';

void main() {
  group('sanitizeBookHtml', () {
    test('drops script elements together with their content', () {
      final result = sanitizeBookHtml(
        '<p>before</p><script>fetch("/steal")</script><p>after</p>',
      );
      expect(result, isNot(contains('script')));
      expect(result, isNot(contains('fetch')));
      expect(result, contains('before'));
      expect(result, contains('after'));
    });

    test('strips inline event handlers', () {
      final result = sanitizeBookHtml('<img src="x" onerror="alert(1)">');
      expect(result, isNot(contains('onerror')));
      expect(result, isNot(contains('alert')));
      expect(result, contains('<img'));
    });

    test('rejects javascript: urls but keeps http ones', () {
      expect(
        sanitizeBookHtml('<a href="javascript:alert(1)">x</a>'),
        isNot(contains('javascript')),
      );
      expect(
        sanitizeBookHtml('<a href="https://example.com">x</a>'),
        contains('https://example.com'),
      );
    });

    test('rejects javascript: urls obfuscated with control characters', () {
      final result = sanitizeBookHtml('<a href="java\nscript:alert(1)">x</a>');
      expect(result, isNot(contains('script')));
    });

    test('keeps relative urls and colons inside paths', () {
      expect(
        sanitizeBookHtml('<img src="images/p1.jpg">'),
        contains('images/p1.jpg'),
      );
      expect(sanitizeBookHtml('<a href="/a:b/c">x</a>'), contains('/a:b/c'));
    });

    test('unwraps document structure without nesting a second document', () {
      // テスト用に結合したマークアップ文字列（missing_whitespace_between_adjacent_strings 回避）
      final markup = [
        '<!DOCTYPE html><html><head><title>t</title>',
        '<meta charset="utf-8"></head><body><p>text</p></body></html>',
      ].join();
      final result = sanitizeBookHtml(markup);
      expect(result, '<p>text</p>');
    });

    test('keeps text of disallowed tags but removes the tag itself', () {
      final result = sanitizeBookHtml('<marquee>visible</marquee>');
      expect(result, isNot(contains('marquee')));
      expect(result, contains('visible'));
    });

    test('survives obfuscated nested script tags', () {
      final result = sanitizeBookHtml('<scr<script>ipt>alert(1)</script>');
      expect(result.toLowerCase(), isNot(contains('<script')));
    });

    test('preserves formatting tags used by book content', () {
      final result = sanitizeBookHtml(
        '<h2>Chapter</h2><p><strong>bold</strong> and <em>italic</em></p>',
      );
      expect(result, contains('<h2>'));
      expect(result, contains('<strong>'));
      expect(result, contains('<em>'));
    });

    test('escapes stray angle brackets in text', () {
      final result = sanitizeBookHtml('<p>1 &lt; 2 &amp; 3</p>');
      expect(result, contains('&lt;'));
      expect(result, contains('&amp;'));
    });
  });

  group('URL policy', () {
    test('拒绝 file 链接与任意 data 链接', () {
      expect(
        sanitizeBookHtml('<a href="file:///etc/passwd">x</a>'),
        '<a>x</a>',
      );
      expect(
        sanitizeBookHtml('<a href="data:text/html;base64,PHNjcmlwdD4=">x</a>'),
        '<a>x</a>',
      );
    });

    test('仅允许限定 MIME 的 base64 图片', () {
      expect(
        sanitizeBookHtml('<img src="data:image/png;base64,iVBORw0KGgo=">'),
        '<img src="data:image/png;base64,iVBORw0KGgo=">',
      );
      expect(
        sanitizeBookHtml('<img src="data:text/html;base64,PHNjcmlwdD4=">'),
        '<img>',
      );
      expect(
        sanitizeBookHtml('<img src="data:image/svg+xml;base64,PHN2Zz4=">'),
        '<img>',
      );
    });

    test('WebView 只内放 about:blank，外链交给系统，危险协议阻断', () {
      expect(
        classifyBookNavigation('about:blank#chapter-2'),
        BookNavigationDecision.allowInternal,
      );
      expect(
        classifyBookNavigation('https://example.com'),
        BookNavigationDecision.launchExternal,
      );
      expect(
        classifyBookNavigation('file:///etc/passwd'),
        BookNavigationDecision.block,
      );
      expect(
        classifyBookNavigation('data:text/html,<script>alert(1)</script>'),
        BookNavigationDecision.block,
      );
    });
  });
}
