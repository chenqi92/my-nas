# MyNAS

<p align="center">
  <img src="assets/icon.png" alt="MyNAS Logo" width="120" height="120">
</p>

<p align="center">
  <strong>一站式跨平台 NAS 媒体管理客户端</strong>
</p>

<p align="center">
  <a href="#功能特性">功能特性</a> •
  <a href="#nas-适配">NAS 适配</a> •
  <a href="#媒体服务器">媒体服务器</a> •
  <a href="#下载器">下载器</a> •
  <a href="#支持平台">支持平台</a> •
  <a href="#testflight-测试">TestFlight 测试</a> •
  <a href="#xcode-配置macos--ios新手必读">Xcode 配置</a> •
  <a href="#快速开始">快速开始</a> •
  <a href="#文档">文档</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.x-blue?logo=flutter" alt="Flutter">
  <img src="https://img.shields.io/badge/Dart-3.x-blue?logo=dart" alt="Dart">
  <img src="https://img.shields.io/badge/License-MIT-green" alt="License">
</p>

---

## 简介

MyNAS 是一款跨平台的家用 NAS 媒体管理工具，把你常用的多种数据源（NAS 协议 / 媒体服务器 / 下载器 / PT 站 / 字幕站 / 媒体追踪服务）整合到一个客户端，让你能在 macOS、Windows、iOS、Android、Linux 上以统一、现代化的体验访问家里的所有媒体资源。

不绑定特定 NAS 品牌，**用户自带数据源**——你可以同时连接群晖 + Plex + qBittorrent + 任意 PT 站，并在视频详情页一键串联（找资源 → 下载 → 入库 → 播放）。

## TestFlight 测试

[加入 KKNas TestFlight 公开测试](https://testflight.apple.com/join/6UX78cq9)

> 外部测试构建需要先通过 Apple 的 Beta App 审核。若链接暂时提示没有可用构建，请等待当前构建审核完成后再试。

## 功能特性

### 🎬 视频
- 支持主流容器（MP4 / MKV / AVI / MOV / WMV / WebM / RMVB / TS / M2TS）和编码（H.264 / H.265 / VP9 / AV1）
- 字幕：SRT / ASS / SSA / VTT / SUB / PGS / 内嵌；支持样式自定义和**字幕延迟**调节
- 在线字幕搜索（OpenSubtitles，可使用自己的 API key）
- **AI 字幕翻译**：将当前字幕轨翻译为目标语言（默认中文），优先翻译当前播放位置附近的段，结果落盘缓存
- 倍速播放（0.5x–4x）、画中画、手势进度/亮度/音量
- 投屏：AirPlay / DLNA（含字幕扩展） / Chromecast
- 客户端转码（CPU / Android MediaCodec / Apple VideoToolbox）
- TMDB 元数据刮削、豆瓣评分整合、NFO 解析
- 系列 / 季 / 集组织、推荐 / 相似内容
- **TMDB 推荐 → PT 站搜索一键跳转**

![](https://nas.allbs.cn:8888/cloudpic/2026/04/067b17d8152f8b514bdc979853b5ff55.png)

### 🎵 音乐
- 有损 / 无损（FLAC / APE / WAV / AIFF / ALAC / DSD / MP3 / AAC 等）
- 后台播放、锁屏控制、媒体键、iOS Now Playing、Android 灵动岛、macOS Media Widget
- **桌面歌词**（Windows / macOS / Linux 原生悬浮窗）
- 元数据写入（audiotags + ffmpeg + tone 三引擎，覆盖 DSD 等无损）
- NCM 加密格式解密
- 自动刮削（封面 / 歌词 / 标签）
- 10 段均衡器（Android AudioEffect；桌面端 mpv audio filter）
- 可配置交叉淡入淡出

> **音乐刮削功能合规说明**
> 本应用的音乐刮削仅获取元数据 / 封面 / 歌词写入用户本地音频文件，**不下载也不传播音频本体**。
> 默认仅启用 MusicBrainz（CC0 开放数据库）和 AcoustID（声纹识别开放服务）。
> 网易云 / QQ 音乐 / 酷狗 / 酷我 / 咪咕等商业平台刮削源默认关闭，启用前会展示风险提示，
> 请仅用于管理你**合法获取**的音乐，并自行承担相应平台 ToS 合规责任。

![](https://nas.allbs.cn:8888/cloudpic/2026/04/7183e33fb6af7f88f2d9793a890d1a3e.png)

### 📚 漫画 & 📖 书籍
- 漫画：CBZ / CBR / ZIP / RAR / 7Z / PDF；单页 / 双页 / 长条；左右翻页
- 书籍：EPUB / PDF / MOBI / AZW3 / TXT / HTML
- 自定义字体 / 字号 / 主题（日 / 夜 / 护眼 / 纯黑）
- 书签、目录导航、TTS 朗读
- **在线书源**（兼容 Legado JSON / XPath / JSONPath / CSS / 正则规则；用户自行导入，应用不内置任何书源）
  ![](https://nas.allbs.cn:8888/cloudpic/2026/04/2509128918beb534c06f1f971074fa53.jpg)


### 🖼️ 照片
- 相册浏览、时间线、EXIF 元数据
- **人脸识别 + 人物聚合**（点击人物头像跳转该人物所有照片）

![](https://nas.allbs.cn:8888/cloudpic/2026/04/602eb0553cb0a73cd1182f21edcb592c.jpg)

### 📝 笔记
- Markdown 渲染（含任务列表 / 代码块 / 表格 / 图片）
- 树形目录浏览、笔记搜索

### 📁 文件浏览器
- 列表 / 网格视图、面包屑导航
- 排序 / 筛选 / 搜索（服务端优先，客户端 BFS fallback）
- 复制 / 移动 / 重命名 / 删除 / 上传 / 下载
- **分享**（远端文件流式下载到本地后调用系统分享）
- **目录选择器**（树形浏览 + 在线新建文件夹）

### 🔍 PT 站点
- 通用 PT 站爬虫（cookie + 站点规则）
- 种子搜索 / 列表 / 推广标识
- **视频详情页 → PT 搜索一键跳转**（带年份）
- **PT 搜索 → 一键发送下载器**

### 📡 媒体追踪
- Trakt.tv OAuth 同步（待看 / 在看 / 已看 / 评分）

![](https://nas.allbs.cn:8888/cloudpic/2026/04/269b8b60c7661ab033aa061c7a86056b.jpg)

## NAS 适配

| NAS / 协议 | 状态 | 说明 |
|---|---|---|
| 群晖 Synology | ✅ | DSM 6/7、File/Video/Audio/Photos Station、QuickConnect、二次验证 |
| 绿联 UGREEN (UGOS) | ✅ | RSA 加密登录 + 服务端 API + 客户端 fallback |
| 飞牛 fnOS | ✅ | 服务端 copy/upload/search + 客户端 fallback |
| 威联通 QNAP | ✅ | QTS API |
| WebDAV | ✅ | 通用协议 |
| SMB / CIFS | ✅ | 含连接池 / 心跳 / 客户端 fallback（copy/search/url-stream） |
| 本地存储 | ✅ | 本地文件系统 |
| 移动端虚拟 fs | ✅ | 手机本地音乐 / 相册 / 文件 |

## 媒体服务器

| 服务器 | 状态 | 认证方式 | 备注 |
|---|---|---|---|
| Jellyfin (10.8+) | ✅ | 用户名密码 / API Key / Quick Connect | WebSocket 实时同步（14 种事件） |
| Emby (4.6+) | ✅ | 用户名密码 / API Key | WebSocket 实时同步（18 种事件）、deviceId 持久化 |
| Plex | ✅ | PIN 授权 | getNextUp 含 viewOffset 优先 |

进度同步、标记已看、收藏、推荐、继续观看、下一集等功能完整。

## 下载器

| 下载器 | 状态 | 备注 |
|---|---|---|
| qBittorrent | ✅ | Web API |
| Transmission | ✅ | RPC（自定义 rpcPath） |
| Aria2 | ✅ | JSON-RPC + token + pause/dir 选项 |
| MoviePilot | ✅ | 订阅 / 任务 / 媒体管理 |
| NASTool | ✅ | 订阅 / 任务 / 搜索 |

种子卡片一键发送，支持暂停后添加、自定义下载目录。

![](https://nas.allbs.cn:8888/cloudpic/2026/04/ce0f3b75b935111238661939939abf10.png)

## 支持平台

| 平台 | 最低版本 | 状态 |
|---|---|---|
| macOS | 11.0+ | ✅ 含 Mac App Store 上架适配（沙盒 / entitlements） |
| Windows | 10+ | ✅ |
| iOS | 12.0+ | ✅ 含麦克风 / 相机权限、应用签名、**CarPlay 音乐浏览** |
| Android | 6.0+ | ✅ 含媒体通知、应用 ID 规范 |
| Linux | - | 🚧 编译通过，部分依赖支持有限（如 share_plus） |

## Xcode 配置（macOS / iOS，新手必读）

> 这一节面向**第一次拿到这份代码、想在自己 Mac 上把 macOS / iOS 跑起来**的开发者。仓库里所有 Apple 平台的 Bundle ID、Team ID、App Group、Keychain Group 都是作者本人的，**直接 `flutter run` 一定签名失败**，必须先按下面的步骤改成你自己的。整套流程跟着做大约 15–30 分钟。

### 0. 前置工具

| 工具 | 版本 | 安装方式 |
|---|---|---|
| macOS | 12+ 推荐 13/14 | — |
| Xcode | **15.0 及以上**（Live Activity 部分要 16+，对应 iOS 16.1+ SDK） | App Store |
| Xcode Command Line Tools | 跟随 Xcode | `xcode-select --install` |
| CocoaPods | 1.14+ | `sudo gem install cocoapods` 或 `brew install cocoapods` |
| Flutter SDK | ≥ 3.16.0 | [flutter.dev](https://docs.flutter.dev/get-started/install/macos) |
| Apple ID | 个人或付费开发者账号 | [appleid.apple.com](https://appleid.apple.com) |

执行一次自检：

```bash
flutter doctor -v
# 看到 "Xcode - develop for iOS and macOS" 一栏全绿 ✓ 就行
```

`flutter doctor` 提示让你跑 `sudo xcodebuild -runFirstLaunch`、`pod setup` 之类的就照跑。

> **个人 Apple ID 也能跑真机和本地 macOS**，只是不能上架；不需要 99 美元的付费账号。

### 1. 拉代码 + 装依赖

```bash
git clone git@github.com:chenqi92/my-nas.git
cd my-nas
flutter pub get
dart run build_runner build --delete-conflicting-outputs
```

`build_runner` 会生成大量 `*.g.dart` / `*.freezed.dart`，**漏跑这步项目根本编译不过**。

### 2. 在 Xcode 里登录你的 Apple ID

打开 Xcode → 顶部菜单 **Xcode → Settings → Accounts** → 点左下 `+` → **Apple ID** → 登录 → 选中账号 → 右下角 **Manage Certificates...** 确认有 `Apple Development` 证书（没有就点 `+` 新建）。

记下你的 **Team ID**（10 位字母数字，比如 `AB12CDE34F`），下一步要替换。

### 3. 关键：把 Bundle ID / Team / App Group 改成你自己的

仓库里目前的标识：

| 项 | 当前值（作者的） | 你需要改成 |
|---|---|---|
| Team ID | `2U97K3U27A` | 你自己的 10 位 Team ID |
| 主 App Bundle ID | `com.kkape.mynas` | `com.<你的反域名>.mynas` |
| iOS Widget Extension | `com.kkape.mynas.MyNasWidgets` | `com.<你的反域名>.mynas.MyNasWidgets` |
| iOS Live Activity Extension | `com.kkape.mynas.MusicActivityWidget` | `com.<你的反域名>.mynas.MusicActivityWidget` |
| macOS Widget Extension | `com.kkape.mynas.MyNasWidgets` | `com.<你的反域名>.mynas.MyNasWidgets` |
| App Group | `group.com.kkape.mynas.app` | `group.com.<你的反域名>.mynas.app` |
| Keychain Group | `$(AppIdentifierPrefix)com.kkape.mynas` | `$(AppIdentifierPrefix)com.<你的反域名>.mynas` |

> **App Group / Keychain Group 是主 App 与各 Widget / Live Activity 之间共享数据用的**，三方必须保持一致，否则桌面小组件 / 灵动岛 / 音乐持久播放都会拿不到数据。
>
> Bundle ID 用反向域名，建议用一个你拥有或可控的域名（比如 `com.github.<你的用户名>.mynas`）。**不要继续用 `com.kkape.*`**，否则上 TestFlight / App Store 会和作者账号冲突。

下面用 **`com.example.mynas`** 当占位符，请按你自己的来替换。

#### 3.1 改 iOS Bundle ID + Team

```bash
open ios/Runner.xcworkspace      # 必须开 .xcworkspace 不是 .xcodeproj
```

在 Xcode 左侧选中蓝色 `Runner` 项目 → 中间面板顶部选 **TARGETS**，逐个 target 切到 **Signing & Capabilities** 标签页，依次设置：

| Target | Bundle Identifier | Team |
|---|---|---|
| `Runner` | `com.example.mynas` | 你的 Team |
| `RunnerTests` | `com.example.mynas.RunnerTests` | 你的 Team |
| `MyNasWidgetsExtension` | `com.example.mynas.MyNasWidgets` | 你的 Team |
| `MusicActivityWidget` | `com.example.mynas.MusicActivityWidget` | 你的 Team |

每个 target 都勾上 **Automatically manage signing**（自动签名），Xcode 会自动给你生成 Provisioning Profile。

#### 3.2 改 macOS Bundle ID + Team

```bash
open macos/Runner.xcworkspace
```

| Target | Bundle Identifier | Team |
|---|---|---|
| `Runner` | `com.example.mynas` | 你的 Team |
| `RunnerTests` | `com.example.mynas.RunnerTests` | 你的 Team |
| `MyNasWidgetsExtension` | `com.example.mynas.MyNasWidgets` | 你的 Team |

同样勾 **Automatically manage signing**。

#### 3.3 改 App Group / Keychain Group（关键！）

App Group 是 4 个文件里的硬编码字符串，最快的方法是命令行批量替换：

```bash
# 先看看会改哪些（dry run）
grep -rn "group.com.kkape.mynas.app" ios/ macos/

# 替换 App Group（请把右侧换成你的反域名）
LC_ALL=C find ios macos -type f \( -name "*.entitlements" -o -name "*.plist" -o -name "project.pbxproj" \) \
  -exec sed -i '' 's/group\.com\.kkape\.mynas\.app/group.com.example.mynas.app/g' {} +

# 替换 Keychain Group（含在 macOS Release/Debug entitlements）
LC_ALL=C find ios macos -type f -name "*.entitlements" \
  -exec sed -i '' 's/com\.kkape\.mynas/com.example.mynas/g' {} +
```

替换完成后回到 Xcode：

- iOS `Runner` / `MyNasWidgetsExtension` / `MusicActivityWidget` → **Signing & Capabilities** → **App Groups** → 确认勾上 `group.com.example.mynas.app`（如果列表里没有就点 `+` 新建一个，**三个 target 必须勾同一个**）。
- macOS `Runner` / `MyNasWidgetsExtension` → 同上。
- iOS `Runner` 的 **Keychain Sharing** 已默认勾上 `$(AppIdentifierPrefix)com.example.mynas`，确认就行。

#### 3.4 替换 Podfile / Pods 的 DEVELOPMENT_TEAM

`ios/Podfile` 里 hardcode 了一行 `config.build_settings['DEVELOPMENT_TEAM'] = '2U97K3U27A'`，需要换成你的：

```bash
sed -i '' "s/'2U97K3U27A'/'YOURTEAMID'/g" ios/Podfile
```

> 这一行是为了修复某些预编译 framework 的签名问题，**留空会让 Pod 重新签名失败**。

#### 3.5 替换 BGTaskScheduler 标识符（仅 iOS）

`ios/Runner/Info.plist` 里有：

```xml
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
  <string>com.kkape.mynas.scrape</string>
</array>
```

改成你的 Bundle ID 前缀：

```bash
sed -i '' 's/com\.kkape\.mynas\.scrape/com.example.mynas.scrape/g' ios/Runner/Info.plist
```

如果代码里有匹配字符串也要一起改：

```bash
grep -rn "com.kkape.mynas.scrape" lib/ ios/Runner/
```

### 4. Capabilities 一览（确认 Xcode 里都打开了）

#### iOS（target = Runner）

| Capability | 用途 |
|---|---|
| **App Groups** = `group.com.example.mynas.app` | Widget / Live Activity 共享数据 |
| **Keychain Sharing** = `$(AppIdentifierPrefix)com.example.mynas` | Keychain 凭据共享、降级到 Hive AES 前的优先方案 |
| **Background Modes** | 已勾 `Audio, AirPlay, and Picture in Picture` / `Background fetch` / `Background processing` |
| **Push Notifications** | 一般不需要；如果要做远程通知再勾 |

iOS Live Activity 是**靠 Info.plist 的 `NSSupportsLiveActivities=true` + 单独的 widget extension target** 实现的，不需要在 Capabilities 面板单独添加。

#### iOS（target = MyNasWidgetsExtension / MusicActivityWidget）

| Capability | 值 |
|---|---|
| **App Groups** | 跟主 App 一致：`group.com.example.mynas.app` |

#### macOS（target = Runner）

| Capability | 用途 |
|---|---|
| **App Sandbox** | macOS 强制；下面这些是放行项 |
| **App Groups** = `group.com.example.mynas.app` | Widget 共享数据 |
| **Keychain Sharing** = `$(AppIdentifierPrefix)com.example.mynas` | 凭据 |
| **File Access → User Selected File** = Read/Write | 用户在 Finder 选的文件 |
| **File Access → Downloads Folder** = Read/Write | 下载到下载目录 |
| **Network → Incoming Connections (Server)** | DLNA / 局域网服务 |
| **Network → Outgoing Connections (Client)** | 访问 NAS |

> macOS 有 `Debug` / `DebugProfile` / `Release` **三套** entitlements 文件，三个文件里的 App Group 都得对，前面 3.3 步骤的 sed 已经把它们一起改了。

#### macOS（target = MyNasWidgetsExtension）

| Capability | 值 |
|---|---|
| **App Sandbox** | 已勾 |
| **App Groups** | 跟主 App 一致 |

### 5. 装 Pods

每次拉代码、改完 Podfile 或者 `flutter pub get` 之后都要重装 Pods：

```bash
# iOS
cd ios && pod install --repo-update && cd ..

# macOS
cd macos && pod install --repo-update && cd ..
```

如果遇到 `pod install` 失败（常见于 M 系芯片首次装、或 ffmpeg_kit 报 framework 类型不一致），按下面对应处理：

```bash
# 清缓存重装
cd ios && rm -rf Pods Podfile.lock && pod install --repo-update && cd ..
cd macos && rm -rf Pods Podfile.lock && pod install --repo-update && cd ..

# 顽固问题：清掉 Flutter 中间产物再来一遍
flutter clean
flutter pub get
dart run build_runner build --delete-conflicting-outputs
```

### 6. （可选）配置 Chromaprint 音纹识别

音乐刮削里"听声识曲"功能依赖 [Chromaprint](https://acoustid.org/)。**不配置也能跑**，只是音纹识别会自动降级成"按标题/艺术家搜索"。

#### macOS

最简单：

```bash
brew install chromaprint
```

或者把 fpcalc 打包进 app bundle：

```bash
./native/chromaprint/bundle_fpcalc.sh all
./native/chromaprint/bundle_fpcalc.sh install
# 这会把 fpcalc 放到 macos/Runner/Resources/fpcalc，构建时自动打包
```

#### iOS

需要预编译 `Chromaprint.xcframework` 放到 `ios/Frameworks/`（仓库默认不带，因为体积大）。详见 [`native/chromaprint/build_mobile.md`](native/chromaprint/build_mobile.md)。**不放也能编译过**，Podfile 里 `-DCHROMAPRINT_AVAILABLE` 这个宏只是开启代码路径，运行时找不到 framework 会自动降级。

### 7. 启动

到这一步你应该可以跑起来了：

```bash
# macOS（最快验证签名是否搞对）
flutter run -d macos

# iOS 模拟器
open -a Simulator           # 先开一个模拟器
flutter run -d <模拟器名>     # 例如 "iPhone 15"

# iOS 真机：用 USB 接上手机，信任电脑，然后
flutter devices              # 确认能看到你的真机
flutter run -d <真机ID>
```

第一次在真机上跑，iOS 会提示**"未受信任的开发者"**，去手机 **设置 → 通用 → VPN 与设备管理 → 你的 Apple ID → 信任** 即可。

### 8. 常见问题排查

| 现象 | 原因 / 解决 |
|---|---|
| `Signing for "Runner" requires a development team` | 第 3 步没改 Team，或 Xcode 没登录 Apple ID |
| `No profiles for 'com.kkape.mynas' were found` | Bundle ID 没改，还在用作者的；按 3.1 / 3.2 改成自己的 |
| `Provisioning profile doesn't include the com.apple.security.application-groups entitlement` | 3.3 步骤的 App Group 没勾全，回到 Xcode 把每个 target 的 App Groups 都打勾刷新一次 |
| Widget / 灵动岛拿不到主 App 数据 | App Group 在主 App 和 Widget Extension 上不一致；用 `grep -rn "group\." ios macos` 自检 |
| `pod install` 卡在 `Updating spec repo "trunk"` | 网络问题；切换网络或加 `--verbose` 看具体卡在哪 |
| `Sandbox: ... deny file-write-create` | macOS 沙盒问题；确认 4.macOS 那张表里的 File Access 全勾上 |
| 真机安装后立刻闪退 | 大概率是 entitlements 里 App Group / Keychain Group 跟 Provisioning Profile 不匹配；重新 Clean Build Folder（`Cmd+Shift+K`）再 run |
| Live Activity 不显示 | 个人 Apple ID 默认不支持 Live Activity 真机调试，需要付费开发者账号；模拟器上可以跑 |

### 9. 改完别忘了改名（可选但推荐）

如果你打算二次开发，建议把以下也一起改了：

- `ios/Runner/Info.plist` 里 `CFBundleDisplayName`（启动器图标下的名字，目前是 "My Nas"）
- `macos/Runner/Configs/AppInfo.xcconfig` 里 `PRODUCT_NAME` / `PRODUCT_COPYRIGHT`
- `pubspec.yaml` 里 `name`（这个改起来连锁反应大，慎重）

---

## 技术栈

- **框架**：Flutter 3.x + Dart 3.x（启用 sealed classes / records / pattern matching）
- **状态管理**：Riverpod 2.x
- **路由**：go_router 15.x（含 deep link 处理）
- **网络**：Dio 5.x（自签证书可选信任）
- **本地存储**：Hive CE + SQLite + AES Cipher Box
- **凭证存储**：FlutterSecureStorage + Keychain 失败时降级到 Hive AES
- **视频播放**：media_kit (libmpv)
- **音频播放**：just_audio + audio_service + media_kit（macOS/Linux）
- **PDF 阅读**：pdfrx
- **EPUB**：epubx + flutter_html / WebView 双模式
- **MOBI/AZW3**：自研 parser
- **加密**：crypto + pointycastle（sha256 / RSA / AES）

## 快速开始

### 环境要求

- Flutter SDK >= 3.16.0
- Dart SDK >= 3.2.0
- Xcode >= 15.0（macOS / iOS 构建）
- Android Studio >= 2023.1（Android 构建）

### 克隆与依赖

```bash
git clone git@github.com:chenqi92/my-nas.git
cd my-nas
flutter pub get
dart run build_runner build --delete-conflicting-outputs
```

### 运行

```bash
flutter run -d windows    # Windows
flutter run -d macos      # macOS
flutter run -d ios        # iOS（真机或模拟器）
flutter run -d android    # Android
```

### 构建发布

```bash
flutter build windows --release
flutter build macos --release
flutter build ios --release
flutter build apk --release            # Android APK
flutter build appbundle --release      # Android AAB（Play 上架）
```

## 项目结构

```
my-nas/
├── lib/
│   ├── app/                       # 应用入口、路由（go_router）、主题
│   ├── core/                      # 核心基础设施
│   │   ├── errors/                # AppError 统一错误处理工具
│   │   ├── network/               # DioClient、自签证书
│   │   ├── storage/               # 凭证存储（含 Keychain 降级）
│   │   └── utils/                 # logger / hive_utils / platform_capabilities ...
│   ├── features/                  # 功能模块（按业务垂直划分）
│   │   ├── video/                 # 视频列表 / 详情 / 播放 / 转码 / 字幕 / 刮削
│   │   ├── music/                 # 音乐 / 播放器 / 元数据写入 / 灵动岛
│   │   ├── photo/                 # 相册 / 人脸识别
│   │   ├── comic/                 # 漫画
│   │   ├── book/                  # 电子书 + 在线书源（Legado 兼容）
│   │   ├── note/                  # 笔记
│   │   ├── reading/               # 阅读进度 + 书签统一服务
│   │   ├── pt_sites/              # PT 站爬取 / 搜索 / 发送下载器
│   │   ├── nastool/               # NASTool 集成
│   │   ├── media_tracking/        # Trakt 等
│   │   ├── transfer/              # 上传 / 下载 / 共享缓存
│   │   ├── sources/               # 源管理（NAS / 媒体服务器 / 下载器统一抽象）
│   │   ├── file_browser/          # 文件浏览器
│   │   └── ...
│   ├── shared/                    # 跨 feature 共享组件 / providers / services
│   ├── nas_adapters/              # NAS 协议适配（SMB / WebDAV / 群晖 / 飞牛 / 绿联 / QNAP / 本地 / mobile）
│   ├── media_server_adapters/     # 媒体服务器适配（Jellyfin / Emby / Plex）
│   └── service_adapters/          # 服务适配（qBittorrent / Transmission / Aria2 / MoviePilot ...）
├── assets/                        # 静态资源（图标 / 动画 / ML 模型）
├── docs/                          # 设计文档（ANALYSIS / ARCHITECTURE / TASKS 等）
└── test/                          # 测试
```

## 文档

详细的设计与开发文档在 [`docs/`](docs/) 目录：

- [`docs/ANALYSIS.md`](docs/ANALYSIS.md) — 项目需求分析与功能清单
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — 架构设计、核心抽象、关键决策
- [`docs/TASKS.md`](docs/TASKS.md) — 开发进度与里程碑
- [`docs/legado-integration.md`](docs/legado-integration.md) — Legado 书源集成
- [`docs/ebook-implementation.md`](docs/ebook-implementation.md) — 电子书实现
- [`docs/ios26-liquid-glass-*`](docs/) — iOS 26 Liquid Glass 设计与实现
- 其他专题（灵动岛 / 桌面歌词 / TTS / 直播等）

## 路线图

### 已完成
- [x] 跨 5 平台基础架构（iOS/Android/macOS/Windows/Linux）
- [x] 多 NAS 适配（Synology / UGOS / fnOS / QNAP / WebDAV / SMB / 本地）
- [x] 媒体服务器适配（Jellyfin / Emby / Plex）
- [x] 下载器集成（qBittorrent / Transmission / Aria2 / MoviePilot / NASTool）
- [x] PT 站点框架 + 视频/推荐 → PT 搜索串联
- [x] 视频 / 音乐 / 漫画 / 书籍 / 照片 / 笔记 全模块
- [x] 客户端转码（多平台硬解码）
- [x] TMDB 刮削 + 豆瓣 + NFO + Trakt
- [x] 在线字幕搜索（OpenSubtitles）
- [x] 桌面歌词（多平台原生窗口）
- [x] iOS 灵动岛 + macOS / Windows 媒体小组件
- [x] Windows 任务栏跳转列表（Tasks 快捷入口 + Recent 最近播放）
- [x] macOS Spotlight 索引（视频 / 音乐 / 书籍 / 漫画 / 笔记标题级元数据，⌘+Space 直达）
- [x] 人脸识别 + 人物聚合
- [x] iOS 26 Liquid Glass UI
- [x] Mac App Store 上架适配
- [x] Keychain 降级方案
- [x] 应用锁（PIN / 生物识别 / 后台超时 / 切换器遮蔽）

### 进行中
- [ ] 国际化覆盖率（中文已完成，英文部分完成）
- [ ] 应用商店上架（macOS / iOS / Android / Microsoft Store）
- [ ] 完整无障碍支持
- [ ] RTL 布局支持
- [ ] 笔记富文本 / 附件与多设备冲突处理
- [ ] 隐私政策与各商店发布资料

### Backlog
- [ ] 更多 NAS（铁威马、海康等）
- [ ] AI 元数据补全
- [ ] 智能推荐（基于本地观看历史）
- [ ] 插件系统

## 贡献

欢迎贡献代码、提交 Issue 或提出建议！

1. Fork 本仓库
2. 创建功能分支（`git checkout -b feature/amazing-feature`）
3. 提交更改（`git commit -m 'Add amazing feature'`）
4. 推送到分支（`git push origin feature/amazing-feature`)
5. 提交 Pull Request

提交前请确保：
- `flutter analyze` 在 `lib/` 下零 errors
- 涉及功能改动时，已在某个平台手动验证 UI（README 当前未要求自动化 UI 测试）
- 遵循 [`CLAUDE.md`](CLAUDE.md) 中的错误处理规范（所有 catch 块用 `AppError`）

## 许可证

本项目采用 MIT 许可证 — 详见 [LICENSE](LICENSE) 文件

## 联系方式

- GitHub Issues: [提交问题](https://github.com/chenqi92/my-nas/issues)

---

<p align="center">
  Made with ❤️ by MyNAS Team
</p>
