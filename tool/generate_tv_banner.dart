// 生成 Android TV 启动器 banner（320x180 xhdpi，Google TV 规范要求图内含应用名）。
// 用法：dart run tool/generate_tv_banner.dart
// 产物：android/app/src/main/res/drawable-xhdpi/tv_banner.png
import 'dart:io';

import 'package:image/image.dart' as img;

void main() {
  final logoBytes = File('assets/logo.png').readAsBytesSync();
  final logo = img.decodePng(logoBytes);
  if (logo == null) {
    stderr.writeln('无法解码 assets/logo.png');
    exit(1);
  }

  const width = 320;
  const height = 180;
  final banner = img.Image(width: width, height: height, numChannels: 4);
  // 背景色与 flutter_native_splash 一致 (#0F0F1A)
  img.fill(banner, color: img.ColorRgba8(15, 15, 26, 255));

  // logo 居中偏上
  final scaled = img.copyResize(
    logo,
    height: 100,
    interpolation: img.Interpolation.cubic,
  );
  img.compositeImage(
    banner,
    scaled,
    dstX: (width - scaled.width) ~/ 2,
    dstY: 20,
  );

  // 应用名文字（TV banner 规范：banner 图内必须包含应用名）
  const appName = 'MyNAS';
  final font = img.arial24;
  // arial24 无内建测宽方法，按字符宽度累加估算居中位置
  var textWidth = 0;
  for (final c in appName.codeUnits) {
    final ch = font.characters[c];
    if (ch != null) textWidth += ch.xAdvance;
  }
  img.drawString(
    banner,
    appName,
    font: font,
    x: (width - textWidth) ~/ 2,
    y: 134,
    color: img.ColorRgba8(255, 255, 255, 255),
  );

  final outFile = File(
    'android/app/src/main/res/drawable-xhdpi/tv_banner.png',
  );
  outFile.parent.createSync(recursive: true);
  outFile.writeAsBytesSync(img.encodePng(banner));
  stdout.writeln('已生成 ${outFile.path} (${width}x$height)');
}
