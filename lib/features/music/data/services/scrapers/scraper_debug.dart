import 'package:flutter/foundation.dart';

/// 音乐刮削器调试日志。
///
/// 仅 debug 构建输出到控制台；release 构建因 [kDebugMode] 为编译期常量被
/// tree-shake 整段移除，避免把搜索词 / 请求 URL / 响应片段写进发布版日志。
/// 各刮削器统一用它替代裸 `debugPrint`，收敛发布版日志噪音与潜在信息泄露。
void scraperDebug(Object? message) {
  if (kDebugMode) {
    debugPrint('$message');
  }
}
