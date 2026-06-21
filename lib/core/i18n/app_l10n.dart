import 'package:flutter/widgets.dart';
import 'package:my_nas/l10n/app_localizations.dart';

AppLocalizations? _instance;

/// 全局 AppLocalizations 访问器。
///
/// 供 service / notifier / 后台任务等**拿不到 BuildContext** 的层构建用户可见
/// 文案（系统通知、状态消息等）。由 app 根 builder 在每次重建（含 locale 变化）
/// 时通过 [appL10n] setter 更新；首帧之前回退到中文。
AppLocalizations get appL10n =>
    _instance ?? lookupAppLocalizations(const Locale('zh'));

set appL10n(AppLocalizations value) => _instance = value;
