import 'package:flutter/foundation.dart';

/// 通用调试日志。
///
/// 仅 debug 构建输出到控制台；release 构建因 [kDebugMode] 为编译期常量，整段被
/// tree-shake 移除，确保发布版无任何 `debugPrint` 输出。用于替代散落在 UI /
/// 状态层的裸 `debugPrint`（非敏感开发噪音）；需要落盘追踪的错误仍走 AppError。
void debugLog(Object? message) {
  if (kDebugMode) {
    debugPrint('$message');
  }
}
