import 'package:dio/dio.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:xml/xml.dart';

/// UPnP 设备描述（用于查找 ContentDirectory 服务的 controlURL）
class UpnpDeviceDescription {
  const UpnpDeviceDescription({
    required this.friendlyName,
    required this.contentDirectoryControlUrl,
    this.manufacturer,
    this.modelName,
  });

  /// 设备友好名（用作 UI 显示）
  final String friendlyName;

  /// ContentDirectory 服务的绝对 controlURL（已经基于设备地址解析过相对路径）
  final String contentDirectoryControlUrl;

  final String? manufacturer;
  final String? modelName;
}

/// 抓取设备描述 XML 并解析出 ContentDirectory controlURL
class UpnpDeviceFetcher {
  UpnpDeviceFetcher({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  void dispose() => _dio.close();

  /// [descriptionUrl] 通常是 UPnP 设备的根描述 XML，如
  /// `http://192.168.1.100:8200/rootDesc.xml`
  Future<UpnpDeviceDescription> fetch(String descriptionUrl) async {
    try {
      final response = await _dio.get<String>(
        descriptionUrl,
        options: Options(responseType: ResponseType.plain),
      );
      final xml = response.data;
      if (xml == null || xml.isEmpty) {
        throw Exception('设备描述为空');
      }
      return _parse(xml, descriptionUrl);
    } on DioException catch (e, st) {
      AppError.handle(e, st, 'UpnpDeviceFetcher.fetch');
      rethrow;
    }
  }

  UpnpDeviceDescription _parse(String xml, String descriptionUrl) {
    final doc = XmlDocument.parse(xml);

    // friendlyName / manufacturer / modelName
    final device = doc.findAllElements('device').firstOrNull;
    if (device == null) {
      throw Exception('设备描述缺少 <device>');
    }
    final friendlyName =
        device.findElements('friendlyName').firstOrNull?.innerText ??
            'UPnP Device';
    final manufacturer =
        device.findElements('manufacturer').firstOrNull?.innerText;
    final modelName =
        device.findElements('modelName').firstOrNull?.innerText;

    // 找 ContentDirectory 服务
    String? controlUrl;
    for (final svc in doc.findAllElements('service')) {
      final type = svc.findElements('serviceType').firstOrNull?.innerText ?? '';
      if (type.contains('ContentDirectory')) {
        controlUrl = svc.findElements('controlURL').firstOrNull?.innerText;
        if (controlUrl != null) break;
      }
    }
    if (controlUrl == null || controlUrl.isEmpty) {
      throw Exception('设备未提供 ContentDirectory 服务');
    }

    // controlURL 可能是相对路径——拼接成绝对 URL
    final base = Uri.parse(descriptionUrl);
    final absolute = Uri.parse(controlUrl).hasScheme
        ? controlUrl
        : base.resolve(controlUrl).toString();

    logger.i(
      'UpnpDeviceFetcher: 设备 $friendlyName ($modelName) ContentDirectory=$absolute',
    );

    return UpnpDeviceDescription(
      friendlyName: friendlyName,
      contentDirectoryControlUrl: absolute,
      manufacturer: manufacturer,
      modelName: modelName,
    );
  }
}
