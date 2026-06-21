import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:xml/xml.dart';

/// 一条电子节目单（EPG）节目。
class EpgProgramme {
  const EpgProgramme({
    required this.channelId,
    required this.start,
    required this.stop,
    required this.title,
    this.desc,
  });

  final String channelId;
  final DateTime start;
  final DateTime stop;
  final String title;
  final String? desc;

  bool isLiveAt(DateTime t) => !t.isBefore(start) && t.isBefore(stop);
}

/// XMLTV 解析器：把 `<tv>` 文档解析为 `channelId -> 按开始时间排序的节目列表`。
///
/// 节目时间格式形如 `20240614120000 +0800`（含时区偏移）或无偏移；统一转本地时区。
class XmltvParser {
  const XmltvParser._();

  static Map<String, List<EpgProgramme>> parse(String xmlString) {
    final result = <String, List<EpgProgramme>>{};
    final doc = XmlDocument.parse(xmlString);
    for (final node in doc.findAllElements('programme')) {
      final channel = node.getAttribute('channel');
      final startRaw = node.getAttribute('start');
      if (channel == null || channel.isEmpty || startRaw == null) continue;
      final start = _parseTime(startRaw);
      if (start == null) continue;
      final stopRaw = node.getAttribute('stop');
      final stop = stopRaw != null ? _parseTime(stopRaw) : null;
      final title = node.getElement('title')?.innerText.trim() ?? '';
      final desc = node.getElement('desc')?.innerText.trim();
      result.putIfAbsent(channel, () => []).add(
            EpgProgramme(
              channelId: channel,
              start: start,
              stop: stop ?? start.add(const Duration(minutes: 30)),
              title: title.isEmpty ? appL10n.xmltvParserDefaultProgramTitle : title,
              desc: (desc?.isEmpty ?? true) ? null : desc,
            ),
          );
    }
    for (final list in result.values) {
      list.sort((a, b) => a.start.compareTo(b.start));
    }
    return result;
  }

  /// 解析 XMLTV 时间戳 `YYYYMMDDHHMMSS [±HHMM]` → 本地时区 DateTime。
  static DateTime? _parseTime(String s) {
    final t = s.trim();
    if (t.length < 14) return null;
    try {
      final year = int.parse(t.substring(0, 4));
      final month = int.parse(t.substring(4, 6));
      final day = int.parse(t.substring(6, 8));
      final hour = int.parse(t.substring(8, 10));
      final minute = int.parse(t.substring(10, 12));
      final second = int.parse(t.substring(12, 14));

      var offset = Duration.zero;
      final tz = t.length > 15 ? t.substring(15).trim() : '';
      if (tz.length >= 5 && (tz[0] == '+' || tz[0] == '-')) {
        final sign = tz[0] == '-' ? -1 : 1;
        final oh = int.parse(tz.substring(1, 3));
        final om = int.parse(tz.substring(3, 5));
        offset = Duration(hours: oh, minutes: om) * sign;
      }
      // 先按 UTC 构造再减去偏移得到真实 UTC，最后转本地时区。
      final utc = DateTime.utc(year, month, day, hour, minute, second)
          .subtract(offset);
      return utc.toLocal();
    } on FormatException {
      return null;
    }
  }
}
