import 'package:dio/dio.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:xml/xml.dart';

/// UPnP ContentDirectory 服务的 Browse 结果项
class UpnpContentItem {
  const UpnpContentItem({
    required this.id,
    required this.parentId,
    required this.title,
    required this.isContainer,
    this.size,
    this.modifiedTime,
    this.contentUrl,
    this.upnpClass,
    this.duration,
    this.protocolInfo,
  });

  /// ContentDirectory 内部的对象 ID（如 "0"、"0$1$2"）
  final String id;

  /// 父对象 ID
  final String parentId;

  /// 显示名称
  final String title;

  /// 是否是容器（目录）；否则是 item（文件）
  final bool isContainer;

  /// 文件大小（字节），仅 item 有
  final int? size;

  /// 修改时间（DIDL-Lite 提供则有）
  final DateTime? modifiedTime;

  /// 直链 URL（res 元素），仅 item 有；多个 res 时取第一个
  final String? contentUrl;

  /// UPnP 类（如 object.item.videoItem.movie）
  final String? upnpClass;

  /// 时长（音视频）
  final Duration? duration;

  /// protocolInfo（如 http-get:*:video/mp4:*）
  final String? protocolInfo;
}

/// UPnP ContentDirectory 浏览客户端
///
/// 通过 SOAP 调用 [SYNOPSIS]:
/// 1. POST 到设备的 ContentDirectory `controlURL`
/// 2. SOAPAction header 为 `urn:schemas-upnp-org:service:ContentDirectory:1#Browse`
/// 3. body 是 envelope + Browse 参数
/// 4. 响应里 `Result` 字段是 entity-encoded 的 DIDL-Lite XML
///
/// 大多数 MediaServer 是只读的——本类不实现写操作。
class UpnpContentDirectoryClient {
  UpnpContentDirectoryClient({
    required String controlUrl,
    Dio? dio,
  })  : _controlUrl = controlUrl,
        _dio = dio ?? Dio();

  final String _controlUrl;
  final Dio _dio;

  static const _serviceType = 'urn:schemas-upnp-org:service:ContentDirectory:1';

  void dispose() => _dio.close();

  /// 浏览指定 [objectId] 的子项目
  ///
  /// [browseFlag] = "BrowseDirectChildren"（列子项）或 "BrowseMetadata"（拿当前对象自身元数据）
  Future<List<UpnpContentItem>> browse(
    String objectId, {
    String browseFlag = 'BrowseDirectChildren',
    int startingIndex = 0,
    int requestedCount = 0,
  }) async {
    final body = _buildBrowseEnvelope(
      objectId: objectId,
      browseFlag: browseFlag,
      startingIndex: startingIndex,
      requestedCount: requestedCount,
    );

    try {
      final response = await _dio.post<String>(
        _controlUrl,
        data: body,
        options: Options(
          headers: {
            'Content-Type': 'text/xml; charset="utf-8"',
            'SOAPAction': '"$_serviceType#Browse"',
          },
          responseType: ResponseType.plain,
        ),
      );
      final xml = response.data;
      if (xml == null || xml.isEmpty) {
        return const [];
      }
      return _parseBrowseResponse(xml);
    } on DioException catch (e, st) {
      AppError.handle(e, st, 'UpnpContentDirectoryClient.browse');
      rethrow;
    }
  }

  String _buildBrowseEnvelope({
    required String objectId,
    required String browseFlag,
    required int startingIndex,
    required int requestedCount,
  }) {
    final escapedId = _xmlEscape(objectId);
    return '''
<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"
            s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
  <s:Body>
    <u:Browse xmlns:u="$_serviceType">
      <ObjectID>$escapedId</ObjectID>
      <BrowseFlag>$browseFlag</BrowseFlag>
      <Filter>*</Filter>
      <StartingIndex>$startingIndex</StartingIndex>
      <RequestedCount>$requestedCount</RequestedCount>
      <SortCriteria></SortCriteria>
    </u:Browse>
  </s:Body>
</s:Envelope>''';
  }

  String _xmlEscape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  /// 解析 SOAP 响应
  List<UpnpContentItem> _parseBrowseResponse(String soapXml) {
    final doc = XmlDocument.parse(soapXml);
    final result = doc.findAllElements('Result').firstOrNull;
    if (result == null) {
      logger.w('UpnpContentDirectoryClient: SOAP 响应缺少 Result');
      return const [];
    }
    final didlLite = result.innerText.trim();
    if (didlLite.isEmpty) return const [];

    return _parseDidlLite(didlLite);
  }

  /// 解析 DIDL-Lite XML
  List<UpnpContentItem> _parseDidlLite(String didl) {
    try {
      final doc = XmlDocument.parse(didl);
      final items = <UpnpContentItem>[];
      // container 元素 = 目录
      for (final c in doc.findAllElements('container')) {
        items.add(_parseEntry(c, isContainer: true));
      }
      // item 元素 = 文件
      for (final i in doc.findAllElements('item')) {
        items.add(_parseEntry(i, isContainer: false));
      }
      return items;
    } on Exception catch (e, st) {
      AppError.ignore(e, st, 'UpnpContentDirectoryClient.parseDidlLite');
      return const [];
    }
  }

  UpnpContentItem _parseEntry(XmlElement el, {required bool isContainer}) {
    final id = el.getAttribute('id') ?? '';
    final parentId = el.getAttribute('parentID') ?? '';
    final title = el
            .findElements('dc:title')
            .firstOrNull
            ?.innerText ??
        // 部分服务器不带命名空间前缀
        el.findElements('title').firstOrNull?.innerText ??
        '(untitled)';
    final upnpClass = el.findElements('upnp:class').firstOrNull?.innerText ??
        el.findElements('class').firstOrNull?.innerText;

    DateTime? modified;
    final dateText = el.findElements('dc:date').firstOrNull?.innerText ??
        el.findElements('date').firstOrNull?.innerText;
    if (dateText != null && dateText.isNotEmpty) {
      modified = DateTime.tryParse(dateText);
    }

    int? size;
    String? url;
    String? protocolInfo;
    Duration? duration;
    final res = el.findElements('res').firstOrNull;
    if (res != null) {
      url = res.innerText.trim();
      protocolInfo = res.getAttribute('protocolInfo');
      final sizeAttr = res.getAttribute('size');
      if (sizeAttr != null) {
        size = int.tryParse(sizeAttr);
      }
      final durAttr = res.getAttribute('duration');
      if (durAttr != null) {
        duration = _parseHmsDuration(durAttr);
      }
    }

    return UpnpContentItem(
      id: id,
      parentId: parentId,
      title: title,
      isContainer: isContainer,
      size: size,
      modifiedTime: modified,
      contentUrl: url,
      upnpClass: upnpClass,
      duration: duration,
      protocolInfo: protocolInfo,
    );
  }

  /// 解析 "HH:MM:SS[.ms]" 格式的时长
  Duration? _parseHmsDuration(String s) {
    final parts = s.split(':');
    if (parts.length < 3) return null;
    try {
      final h = int.parse(parts[0]);
      final m = int.parse(parts[1]);
      final sec = double.parse(parts[2]);
      final ms = (sec * 1000).round();
      return Duration(hours: h, minutes: m, milliseconds: ms);
    } on Exception {
      return null;
    }
  }
}
