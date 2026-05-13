# CarPlay / Android Auto 接入说明

本文记录车载音乐浏览的实现现状、用法与未完成项。

## 已完成（Dart 侧 + Android 配置）

- `MusicBrowserService` (`lib/features/music/data/services/music_browser_service.dart`)
  统一暴露 `getChildren / getMediaItem / playFromMediaId / playFromSearch / search` 五个方法。
  内置内容树：
  ```
  root
  ├─ favorites      (音乐收藏)
  ├─ recent         (最近播放)
  └─ playlists
     └─ <id>        (播放列表内的曲目)
  ```
- `MusicAudioHandler` 与 `MusicMediaKitAudioHandler` 都覆写了上述五个方法，转发给 `MusicBrowserService`。
- `MusicPlayerNotifier._initPlayer()` 注入 `playFromPathsHandler`：根据路径在 favorites + history 缓存里查 `musicUrl` 还原 `MusicItem` 后调 `playQueue()`。**未命中缓存的路径会被跳过**——避免在车载场景里因为找不到 url 卡死或乱播。
- AndroidManifest 增加 `automotive_app_desc.xml` meta-data，audio_service 已自带 `MediaBrowserService` intent-filter，Android Auto 可以发现并连接。

## Android Auto 测试步骤

1. 真机：手机端安装 [Android Auto](https://play.google.com/store/apps/details?id=com.google.android.projection.gearhead)，进入「开发者设置 → 未知来源」启用。
2. 模拟器（推荐先在桌面调试）：Android Studio → SDK Manager → 安装 *Android Auto Desktop Head Unit emulator (DHU)*。
3. 在手机上把本应用通过 ADB 安装为 release 或 debug build。
4. 启动 DHU，本应用应出现在「音乐」分类。
5. 浏览 `收藏 / 最近播放 / 播放列表`，点击曲目验证回调。

> Google 对正式上架的车载应用要求通过 Driver Distraction Guidelines 评审，详见 [https://developer.android.com/training/cars/media](https://developer.android.com/training/cars/media)。

## 未完成 / 阻塞项

### CarPlay (iOS)

CarPlay 的接入需要 **iOS native** 配合，纯 Dart 改不动。仍需的工作：

1. **Apple 申请 entitlement**：联系 Apple 申请 `com.apple.developer.playable-content`（或新的 `MPPlayableContentManager` 替代品 `CPNowPlayingTemplate`）。这需要 Apple 审核账号，无法离线获取。
2. **Info.plist**：声明 `UIBackgroundModes = audio`（已配）+ CarPlay scene（`UIApplicationSceneManifest.UISceneConfigurations.CPTemplateApplicationSceneSessionRoleApplication`）。
3. **Swift 侧实现 `CPTemplateApplicationSceneDelegate`**，提供 `CPListTemplate` / `CPListItem`，把 Dart 侧的 `MusicBrowserService` 暴露给 CarPlay。需要 MethodChannel 从 Swift 调用 Dart 的浏览方法。
4. **真机测试**：CarPlay 必须真车或 Apple CarPlay simulator（Xcode → Open Developer Tool → CarPlay Simulator），iOS 模拟器无法测。

> 没有 entitlement、没有真机的情况下提交 Swift 代码价值很低（无法验证），所以本仓库当前只做 Dart 浏览侧并保留接入点。等申请下来 entitlement 之后，按上面 1–4 推进即可。

### MusicBrowserService 已知局限

- `search()` 仅在收藏 + 历史里做关键词匹配，不接 NAS 全库索引。
- 没有按流派 / 年代分组——艺术家 / 专辑 / 收藏 / 最近 / 歌单已就绪。
- 跨设备时，如果车载播放的曲目当前 NAS 源未连接，且也不在 favorites/history 缓存里，会被跳过。

### 路径解析 / mediaId 编码

- 曲目 mediaId 编码：`track:<sourceId>|<path>`，sourceId 可为空（兼容老缓存）。
- 播放时优先查 favorites + history 缓存（已带 musicUrl）；未命中则按 sourceId 找
  active connection，调 `connection.adapter.fileSystem.getFileUrl(path)` 解析 URL。
- 全部失败的条目会被跳过；播放层只组队成功解析的条目。
