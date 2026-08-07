/// 本文 HTML のサニタイズ。
///
/// オンライン書源やローカルの MOBI/EPUB から取り出した本文は、
/// そのまま WebView に渡すと `<script>` や `onerror=` が実行され、
/// JS ブリッジ経由でアプリ側の機能に到達しうる。
///
/// 正規表現での除去は難読化（`<scr<script>ipt>`、属性内の改行、
/// エンティティ表記など）を取りこぼすため、ここでは `html` パッケージで
/// 実際に DOM としてパースし、**許可リストに載った要素・属性だけ**を
/// 残して組み直す。パーサが解釈した結果を基準にするので、
/// WebView が最終的に見る構造と食い違いが生じにくい。
library;

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// 残す要素。書籍本文の表現に必要なものだけ。
const Set<String> _allowedTags = {
  'p', 'br', 'hr', 'div', 'span', 'section', 'article',
  'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
  'strong', 'b', 'em', 'i', 'u', 's', 'sub', 'sup', 'small', 'mark',
  'ul', 'ol', 'li', 'dl', 'dt', 'dd',
  'blockquote', 'pre', 'code', 'q', 'cite',
  'table', 'thead', 'tbody', 'tfoot', 'tr', 'td', 'th', 'caption',
  'img', 'figure', 'figcaption', 'ruby', 'rt', 'rp', 'a',
};

/// 要素ごとに残す属性。ここに無い属性は落とす。
/// `on*` 系ハンドラや `style` は列挙していないので自動的に除去される。
const Map<String, Set<String>> _allowedAttributes = {
  'a': {'href', 'title'},
  'img': {'src', 'alt', 'title', 'width', 'height'},
  'td': {'colspan', 'rowspan'},
  'th': {'colspan', 'rowspan', 'scope'},
  'ol': {'start'},
};

/// 全要素に共通で残す属性。
const Set<String> _globalAllowedAttributes = {'id', 'class', 'lang', 'dir'};

/// URL 属性で許可するスキーム。`javascript:` / `vbscript:` を弾く。
const Set<String> _allowedSchemes = {'http', 'https', 'data', 'file', 'mailto'};

/// URL を持つ属性（スキーム検査の対象）。
const Set<String> _urlAttributes = {'href', 'src'};

/// 中身ごと捨てる要素。テキストを残すと本文に混ざるため。
const Set<String> _droppedWithContent = {
  'script', 'style', 'iframe', 'object', 'embed', 'applet',
  'form', 'input', 'button', 'select', 'textarea', 'noscript',
  'template', 'svg', 'math', 'link', 'meta', 'base', 'title',
};

/// [html] をパースし、許可リストに沿って組み直した HTML を返す。
///
/// 許可外の要素は中身のテキストだけを残して開閉タグを外す
/// （`_droppedWithContent` に載るものは中身ごと捨てる）。
String sanitizeBookHtml(String html) {
  final document = html_parser.parse(html);
  final body = document.body;
  if (body == null) return '';

  final buffer = StringBuffer();
  for (final node in body.nodes.toList()) {
    _writeNode(node, buffer);
  }
  return buffer.toString().trim();
}

void _writeNode(dom.Node node, StringBuffer out) {
  if (node is dom.Text) {
    out.write(_escapeText(node.text));
    return;
  }
  if (node is! dom.Element) return;

  final tag = node.localName?.toLowerCase() ?? '';
  if (_droppedWithContent.contains(tag)) return;

  final keepTag = _allowedTags.contains(tag);
  if (keepTag) {
    out.write('<$tag');
    _writeAttributes(tag, node.attributes, out);
    if (_isVoid(tag)) {
      out.write('>');
      return;
    }
    out.write('>');
  }

  // 許可外タグでも中身は本文なので再帰して残す。
  for (final child in node.nodes.toList()) {
    _writeNode(child, out);
  }

  if (keepTag) out.write('</$tag>');
}

void _writeAttributes(
  String tag,
  Map<Object, String> attributes,
  StringBuffer out,
) {
  final perTag = _allowedAttributes[tag] ?? const <String>{};
  attributes.forEach((rawName, value) {
    final name = rawName.toString().toLowerCase();
    if (!perTag.contains(name) && !_globalAllowedAttributes.contains(name)) {
      return;
    }
    if (_urlAttributes.contains(name) && !_isSafeUrl(value)) return;
    out.write(' $name="${_escapeAttribute(value)}"');
  });
}

/// スキーム付き URL は許可リストのみ通す。相対 URL は許可。
bool _isSafeUrl(String value) {
  // 制御文字を挟んで `java\nscript:` のように偽装されるのを防ぐ。
  final normalized = value
      .replaceAll(RegExp(r'[\x00-\x20]'), '')
      .toLowerCase();
  final colon = normalized.indexOf(':');
  if (colon < 0) return true; // 相対 URL

  // `/path:with:colon` のようにスキームでない場合を除外。
  final slash = normalized.indexOf('/');
  if (slash >= 0 && slash < colon) return true;

  return _allowedSchemes.contains(normalized.substring(0, colon));
}

bool _isVoid(String tag) => tag == 'br' || tag == 'hr' || tag == 'img';

String _escapeText(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

String _escapeAttribute(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
