# CarPlay / Android Auto 接入说明

本文记录车载音乐浏览的实现现状、用法与未完成项。

## 已完成（Dart 侧 + Android + iOS 配置）

- `MusicBrowserService` (`lib/features/music/data/services/music_browser_service.dart`)
  统一暴露 `getChildren / getMediaItem / playFromMediaId / playFromSearch / search` 五个方法。
  内置内容树：
  ```
  root
  ├─ favorites      (音乐收藏)
  ├─ recent         (最近播放)
  ├─ artists/<name> (按艺术家分组)
  ├─ albums/<name>  (按专辑分组)
  └─ playlists/<id> (播放列表内的曲目)
  ```
- `MusicAudioHandler` 与 `MusicMediaKitAudioHandler` 都覆写了上述五个方法，转发给 `MusicBrowserService`。
- `MusicPlayerNotifier._initPlayer()` 注入 `playFromPathsHandler`：根据路径在 favorites + history 缓存里查 `musicUrl` 还原 `MusicItem` 后调 `playQueue()`。**未命中缓存的路径会被跳过**——避免在车载场景里因为找不到 url 卡死或乱播。
- AndroidManifest 增加 `automotive_app_desc.xml` meta-data，audio_service 已自带 `MediaBrowserService` intent-filter，Android Auto 可以发现并连接。
- **iOS CarPlay**（[CarPlaySceneDelegate.swift](../ios/Runner/CarPlaySceneDelegate.swift) + [CarPlayChannel.swift](../ios/Runner/CarPlayChannel.swift) + [ios_carplay_bridge.dart](../lib/features/music/data/services/ios_carplay_bridge.dart)）：
  - 走 Apple CarPlay framework（`CPTabBarTemplate` + `CPListTemplate` + `CPNowPlayingTemplate`），iOS 13+
  - 根 4 tab：艺术家 / 专辑 / 歌单 / 收藏
  - Swift 通过 `com.kkape.mynas/carplay` MethodChannel 调 Dart `MusicBrowserService`
  - Dart 端 mediaItem 变化时反向通知 Swift，自动 push `CPNowPlayingTemplate`

## Android Auto 测试步骤

1. 真机：手机端安装 [Android Auto](https://play.google.com/store/apps/details?id=com.google.android.projection.gearhead)，进入「开发者设置 → 未知来源」启用。
2. 模拟器（推荐先在桌面调试）：Android Studio → SDK Manager → 安装 *Android Auto Desktop Head Unit emulator (DHU)*。
3. 在手机上把本应用通过 ADB 安装为 release 或 debug build。
4. 启动 DHU，本应用应出现在「音乐」分类。
5. 浏览 `收藏 / 最近播放 / 播放列表`，点击曲目验证回调。

> Google 对正式上架的车载应用要求通过 Driver Distraction Guidelines 评审，详见 [https://developer.android.com/training/cars/media](https://developer.android.com/training/cars/media)。

## iOS CarPlay 测试与发布前提

代码已完整接入，但**真机运行需要 Apple 显式授权** `com.apple.developer.carplay-audio` entitlement——个人 Apple ID 申不到，必须使用付费开发者账号通过 [https://developer.apple.com/contact/carplay/](https://developer.apple.com/contact/carplay/) 提交申请并通过审核。entitlement 拿到之前：

- 编译可以通过，但 **Provisioning Profile 不包含 `carplay-audio`** 时真机签名会失败；本地调试用 free profile 时去掉 entitlements 里的这一行即可，但 CarPlay scene 不会激活。
- 模拟器测试：`Xcode → Open Developer Tool → Simulator`，启动后 `I/O → External Displays → CarPlay`。这种方式不需要真机但仍需要 entitlement 才能弹出 CarPlay scene。

### 测试步骤（已申请 entitlement 后）

1. 真机 + 真车：手机连 USB / 无线 CarPlay，进车机后能看到「My Nas」音乐 App。
2. 模拟器：Xcode CarPlay Simulator，需要先在主设备的「设置 → 通用 → CarPlay → 我的车 → 添加」加一个虚拟车机。
3. 进入 App 后能看到 4 个根 tab（艺术家 / 专辑 / 歌单 / 收藏），下钻到曲目可以播放。
4. 点暂停 / 下一首验证主 App 与 CarPlay 状态同步。

### MusicBrowserService 已知局限

- `search()` 仅在收藏 + 历史里做关键词匹配，不接 NAS 全库索引。
- 没有按流派 / 年代分组——艺术家 / 专辑 / 收藏 / 最近 / 歌单已就绪。
- 跨设备时，如果车载播放的曲目当前 NAS 源未连接，且也不在 favorites/history 缓存里，会被跳过。

### 路径解析 / mediaId 编码

- 曲目 mediaId 编码：`track:<sourceId>|<path>`，sourceId 可为空（兼容老缓存）。
- 播放时优先查 favorites + history 缓存（已带 musicUrl）；未命中则按 sourceId 找
  active connection，调 `connection.adapter.fileSystem.getFileUrl(path)` 解析 URL。
- 全部失败的条目会被跳过；播放层只组队成功解析的条目。
