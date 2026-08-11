# MyNASTV — tvOS 客户端

## 概述

v1 video-only，仅支持 HTTP 源（WebDAV/Jellyfin/Emby/Plex）。进度通过 WebDAV 同步到 `<webdav_root>/my-nas-sync/video_progress.json`，使用和 Flutter 端完全相同的 last-wins 合并规则。

SMB / FTP / SFTP / NFS 未实现，UI 不显示。

## 技术栈

- **Swift Package Manager** library target 放同步逻辑（`Sources/MyNASSync/`），可在 Mac 上跑 `swift test` 验证协议正确性（不需要 Xcode project、不需要 tvOS simulator）
- **SwiftUI + AVKit** app target，tvOS 17+
- **Keychain** 存凭证（`kSecAttrAccessibleAfterFirstUnlock`）
- **ISO8601 parser** 手写，接受 0/3/6 位小数秒 + 可选后缀（no-suffix → local time，见 `Iso8601Tests.swift`）
- **Grouped-optional 模型** 让类型系统执行合约不变量（`progressUpdatedAt` 暗示 `positionMs` 和 `durationMs` 必存在）
- **`JSONValue` enum** 保证 manifest 里其他 7 个模块的字段不被丢弃（一开始只想用 `[String: Int]` 存 `updatedAt`，那会在写回时把其他模块的键全删）

## 跨客户端 sync 协议

见 `docs/sync-contract-video-progress.md`（在主仓库根目录）。

30 个协议测试在 `Tests/MyNASSyncTests/VideoProgressContractTests.swift` + `VideoProgressMergeTests.swift`，镜像 Dart 端的 30 个测试。

### 关键规则（已在代码和测试中强制）

1. **Manifest 共享**：`manifest.json` 存 8 个模块（`video_progress` / `app_settings` / `favorites` / …）的 `updatedAt` 时间戳（epoch ms int）。单模块客户端必须 round-trip 所有键，否则会把其他 7 个模块的时间戳擦掉、让 Flutter 每次都重推。
2. **空 `items` 不截断本地历史**：`remote.items.isEmpty` 时直接退出 merge，不动 local history。Dart 同样在 `items.isEmpty` 时早退。
3. **Last-wins 是严格 `>`**：三组字段（progress / watched / history）各自按最近时间合并，**相等时保留本地**。
4. **`watchedAt == nil` 不覆盖已看状态**：Dart 只在 `remoteWatchedAt != null` 时进 watched 合并分支。tvOS 同样跳过空 `watchedAt` 记录。
5. **历史上限 100**：merge 后按 `addedAt` 倒序截断。

## 已知问题和 v1 局限

### 1. Plex 路径是扁平的，同名集会冲突

Flutter 端 `plex_virtual_fs.dart` 每层都用 `/${item.title}` 构造 path，不拼父层前缀。这导致不同剧的同名集会共用一个 `videoPath`（sync key），进度混在一起。

例子：

- 剧 A 第一集《凛冬将至》→ `/凛冬将至`
- 剧 B 第一集《凛冬将至》→ `/凛冬将至`（同一个键）

tvOS 端刻意复制了这个逻辑（见 `PlexCatalog.swift` 类型注释），因为改成层级路径会让 tvOS 和 Flutter 的 sync key 失配，两端各存一份进度、永远同步不上。

**解法**（后续 v2）：在 Flutter / tvOS 同时改成 `/<library>/<parent>/<item>` 层级路径，并约定一个迁移时间点，两端同时升级（或写迁移逻辑把旧键映射到新键）。v1 先保持 byte-for-byte 兼容。

### 2. 播放器不会自动标记「已看」

Flutter 端播到最后只 `clearProgress`，不 `markAsWatched`（手动标记来自详情页的已看按钮）。tvOS 复制同样行为，避免一端自动标、另一端不标的分歧。

### 3. v1 不做转码协商

WebDAV 直出文件，Jellyfin/Emby/Plex 走 `/stream?static=true` 直流原文件。tvOS AVPlayer 原生支持 HEVC / H.264 / ProRes，但一些旧编码（MPEG-2、VC-1）或非标容器可能不播。v1 不做 transcode profile 判断，播不了就播不了（Flutter 端也是 v1 不转码，后续才加）。

### 4. 媒体服务器不 sync 进度

Jellyfin / Emby / Plex 跨客户端进度通过服务端 API 同步（`POST /Users/{id}/PlayingItems/{itemId}/Progress`），v1 只实现了本地播放+目录浏览，没有上报 progress 到服务端，所以服务端不知道 tvOS 播到哪了。

这和 Flutter 端一致 — Flutter 也是只从媒体服务器读 continue-watching，不写回（见 `jellyfin_adapter.dart`）。

### 5. 字幕 / 音轨选择 v1 不做

AVPlayer 可以通过 `AVMediaSelectionGroup` 选音轨和字幕，但 v1 只拿第一轨播。后续可参考 Flutter 的 `SubtitleTrack` / `AudioTrack` 实现。

## 环境约束

这个 tvOS 模块在 **Windows 环境**写的。没有 `swift` 命令、没有 `xcodebuild`、没有 tvOS simulator，所以：

- ✅ 代码语法和类型检查已在编辑器里做了（IDE autocomplete 和 linter）
- ❌ 没编译过
- ❌ 没跑过测试
- ❌ 没在 tvOS 真机或模拟器运行过

在 Mac 上首次构建会爆一堆小错（import 路径、`Sendable` 约束、typo 等），预计几十行改动就能过编译，但**不可能零改**。

## 如何在 Mac 上构建

### 1. 跑测试（验证协议正确性）

```bash
cd apple_tv
swift build          # 构建 MyNASSync library
swift test           # 跑 30 个协议测试，应该全过（或者全过 + 几个 ISO8601 精度边界 case）
```

### 2. 创建 Xcode 项目并添加 app target

**当前状态**：`apple_tv/` 下没有 `.xcodeproj` 文件，只有 Swift Package（`Package.swift`）定义了 `MyNASSync` library + tests。`MyNASTV/` 目录存放 SwiftUI app 源码，但未配置为 Xcode app target。

**首次构建步骤**：

1. 在 Xcode 中创建新项目：
   - File → New → Project
   - 平台选 tvOS → App
   - Product Name: `MyNASTV`
   - Interface: SwiftUI
   - Language: Swift
   - 保存到 `apple_tv/` 目录，与现有 `MyNASTV/` 文件夹同级

2. 将现有源码添加到项目：
   - 删除 Xcode 自动生成的 `MyNASTV/` 模板文件
   - 在 Project Navigator 中右键 → Add Files to "MyNASTV"
   - 选择现有的 `MyNASTV/` 目录（包含 `MyNASTVApp.swift` 等文件）
   - 勾选 "Copy items if needed"（如果文件已在正确位置可不勾选）
   - Target 选 `MyNASTV`

3. 添加 `MyNASSync` library 依赖：
   - Project Settings → `MyNASTV` target → General → Frameworks, Libraries, and Embedded Content
   - 点 `+` → Add Other → Add Package Dependency
   - 选择本地路径：`apple_tv/`（包含 `Package.swift` 的目录）
   - 或者在 Project Settings → Package Dependencies 中添加本地 package

4. 配置 Signing & Capabilities：
   - 选择你的 Apple Developer Team
   - Bundle Identifier 改为你自己的（如 `com.yourname.mynas.tv`）

5. 运行：
   - Target 选 `MyNASTV`
   - 设备选 `Apple TV` 或 `Apple TV 4K (2nd generation)` simulator（tvOS 17.0+）
   - Cmd+R 运行

**注意**：初次编译可能遇到 import 路径、`Sendable` 约束、typo 等小错误（代码在 Windows 环境编写，未在 Mac 上验证过），预计几十行改动即可通过编译。

### 3. 真机部署

需要 Apple Developer 账号 + provisioning profile。Xcode 会提示 `Signing & Capabilities` 页配置 Team。

## 目录结构

```
apple_tv/
├── Package.swift                 # Swift Package Manager 配置（library + tests）
├── Sources/
│   └── MyNASSync/               # 同步逻辑 library（可独立测试）
│       ├── VideoProgressState.swift
│       ├── VideoProgressMerge.swift
│       ├── VideoProgressStore.swift
│       ├── VideoProgressService.swift
│       ├── CloudSyncBackend.swift
│       ├── CloudSyncCoordinator.swift
│       ├── SyncManifest.swift
│       ├── JSONValue.swift
│       └── Iso8601.swift
├── Tests/
│   └── MyNASSyncTests/
│       ├── Iso8601Tests.swift
│       ├── VideoProgressContractTests.swift
│       ├── VideoProgressMergeTests.swift
│       └── CloudSyncCoordinatorTests.swift
├── MyNASTV/                     # SwiftUI app
│   ├── MyNASTVApp.swift
│   ├── SourceListView.swift
│   ├── LibraryListView.swift
│   ├── PlayerView.swift
│   ├── Model/
│   │   ├── TVSource.swift
│   │   └── KeychainCredentialStore.swift
│   └── Catalog/
│       ├── VideoCatalog.swift
│       ├── WebDavCatalog.swift
│       ├── JellyfinCatalog.swift
│       └── PlexCatalog.swift
└── README.md                    # 本文件
```

## 后续扩展

- [ ] 字幕 / 音轨选择
- [ ] 媒体服务器上报 progress（双向 sync）
- [ ] 转码协商（DirectPlay 不可用时 fallback transcode）
- [ ] 音乐播放（需要单独的 `music_progress` module）
- [ ] 图书 / 漫画（需要自定义阅读器，tvOS 没有 `PDFKit` / `WKWebView` 的 EPUB 支持）
- [ ] Plex 路径改成层级（需要同时改 Flutter 端）
- [ ] 灵动岛 / Now Playing widget（tvOS 上是 Control Center 卡片）
