import 'package:my_nas/core/errors/errors.dart';

final _windowsDrivePath = RegExp(r'^[a-zA-Z]:[\\/]');
final _windowsUriPath = RegExp('^/[a-zA-Z]:/');

/// 把本机路径编码为规范的 `file:` URI。
///
/// 不依赖当前运行平台：在 Linux CI 中处理 Windows 路径时仍会生成
/// `file:///C:/...`，因此同步数据与跨端测试不会受宿主机影响。
String localPathToFileUri(String path) {
  final windows =
      _windowsDrivePath.hasMatch(path) ||
      path.startsWith(r'\\') ||
      path.startsWith('//');
  return Uri.file(path, windows: windows).toString();
}

/// 从规范或旧版非规范 `file:` URL 还原本机路径。
///
/// 兼容历史版本产生的 `file://C:\dir\cover.jpg`；新数据必须通过
/// [localPathToFileUri] 写入。
String? localPathFromFileUri(String value) {
  if (!value.toLowerCase().startsWith('file:')) return null;

  final legacyBody = value.startsWith('file://') ? value.substring(7) : null;
  if (legacyBody != null && _windowsDrivePath.hasMatch(legacyBody)) {
    return Uri.decodeFull(legacyBody);
  }

  final uri = Uri.tryParse(value);
  if (uri == null || uri.scheme.toLowerCase() != 'file') return null;
  try {
    final windows = uri.host.isNotEmpty || _windowsUriPath.hasMatch(uri.path);
    return uri.toFilePath(windows: windows);
  } on Object catch (e, st) {
    AppError.ignore(e, st, '无效的本地 file URI，交由调用方显示占位内容');
    return null;
  }
}
