# MyNAS 项目需求分析文档

> 最后更新：2026-07-11
> 本文档描述项目的功能/非功能需求与当前实现状态。✅=已实现，🚧=部分实现，📝=规划中。

## 1. 项目概述

MyNAS 是一款跨平台的家用 NAS 连接工具，提供统一、现代化的 NAS 资源访问与管理体验。

### 1.1 目标平台

| 平台 | 状态 | 备注 |
|---|---|---|
| macOS | ✅ | 已适配 Mac App Store 上架（沙盒、entitlements、加密配置） |
| Windows | ✅ | 主开发平台 |
| iOS | ✅ | 麦克风/相机权限、Keychain entitlements 已配置 |
| Android | ✅ | 灵动岛/媒体通知、应用 ID 已规范 |
| Linux | 🚧 | 编译通过，部分依赖（如 share_plus）支持有限 |

### 1.2 核心目标

- ✅ 统一的多端体验
- ✅ 解耦的模块化架构（NAS 适配器 / 媒体服务器适配器 / 下载器适配器三套抽象）
- ✅ 现代化 UI（Material 3 / iOS26 Liquid Glass / 暗色模式）
- ✅ 灵活适配多种 NAS / 媒体服务器 / 下载工具

---

## 2. 功能需求与实现状态

### 2.1 媒体播放模块

#### 2.1.1 视频播放 ✅
- **格式**：MP4 / MKV / AVI / MOV / WMV / FLV / WebM / RMVB / TS / M2TS（容器）；H.264 / H.265 / VP9 / AV1 / MPEG-4（编码）
- **字幕**：SRT / ASS / SSA / VTT / SUB / PGS / 内嵌字幕
- **核心引擎**：media_kit (libmpv)
- **已实现**：
  - ✅ 在线流媒体播放（Direct Play / Direct Stream / 转码）
  - ✅ 进度记忆与恢复（含 Trakt 多设备同步）
  - ✅ 字幕加载、样式自定义、字幕延迟（NativePlayer.setProperty）
  - ✅ OpenSubtitles 字幕在线搜索下载
  - ✅ 倍速播放 0.5x–4x
  - ✅ 画中画（桌面端）
  - ✅ 投屏（AirPlay / DLNA / Chromecast，DLNA 含字幕扩展兼容三种设备协议）
  - ✅ 视频库管理（分类、收藏、观看历史、TMDB 刮削、NFO 解析）
  - ✅ 客户端转码（CPU / Android MediaCodec / Apple VideoToolbox）

#### 2.1.2 音乐播放 ✅
- **格式**：MP3 / AAC / OGG / WMA / M4A / FLAC / APE / WAV / AIFF / ALAC / DSD（DSF/DFF）
- **核心引擎**：just_audio + media_kit（macOS/Linux）
- **已实现**：
  - ✅ 音乐库浏览（艺术家 / 专辑 / 歌曲 / 播放列表 / 收藏 / 历史）
  - ✅ 歌词显示（LRC / 内嵌 / 外挂）+ 桌面歌词（Windows/macOS/Linux 原生窗口）
  - ✅ 元数据写入（audiotags + ffmpeg + tone 三引擎，覆盖所有主流格式包括 DSD）
  - ✅ 后台播放、锁屏控制、播放队列、随机/循环
  - ✅ Android 灵动岛 / iOS Now Playing / macOS Media Widget
  - ✅ NCM 加密格式解密
  - ✅ 10 段均衡器（Android AudioEffect；桌面端 mpv audio filter）
  - ✅ 可配置交叉淡入淡出

#### 2.1.3 漫画阅读 ✅
- **格式**：JPG / PNG / WebP / GIF / BMP / ZIP / RAR / 7Z / CBZ / CBR / PDF
- **已实现**：单页/双页/长条阅读、左右翻页方向、缩放、进度记忆、智能预加载

#### 2.1.4 书籍阅读 ✅
- **格式**：EPUB / PDF / MOBI / AZW3 / TXT / HTML
- **核心**：
  - EPUB：epubx + flutter_html / WebView 双模式
  - PDF：pdfrx
  - MOBI/AZW3：自研解析器（mobi_parser_service）
- **已实现**：
  - ✅ 自定义字体/字号/行距/主题（日/夜/护眼/纯黑）
  - ✅ 目录导航
  - ✅ 阅读进度同步
  - ✅ 书签（reading_progress_service.Bookmark）
  - ✅ TTS 朗读
  - ✅ 在线书源（兼容 Legado JSON / XPath / JSONPath / CSS / 正则规则解析）
  - ✅ 书源用户自行导入（**应用不内置任何书源**，符合上架合规）

### 2.2 笔记模块 🚧

- ✅ Markdown 渲染（带任务列表 / 代码块 / 表格 / 图片）
- ✅ 笔记目录树形浏览
- ✅ 全文/标题搜索
- 🚧 编辑（基础编辑，缺富文本/附件）
- 📝 多设备冲突处理

### 2.3 NAS / 存储系统适配 ✅

#### NAS 协议支持

| NAS / 协议 | 状态 | 实现位置 |
|---|---|---|
| SMB / CIFS（含 SMB 1/2/3 + 3.1.1） | ✅ 含连接池/心跳/客户端 fallback | nas_adapters/smb |
| WebDAV | ✅ | nas_adapters/webdav |
| 群晖 Synology DSM 6/7 | ✅ File/Video/Audio/Photos Station | nas_adapters/synology |
| 飞牛 fnOS | ✅ 含服务端 copy/upload/search + 客户端 fallback | nas_adapters/fnos |
| 绿联 UGOS | ✅ 含 RSA 加密登录 + 客户端 fallback | nas_adapters/ugreen |
| 本地文件系统 | ✅ | nas_adapters/local |
| 移动端虚拟文件系统（手机本地音乐/相册/文件） | ✅ | nas_adapters/mobile |

#### 媒体服务器适配 ✅

| 服务器 | 状态 | 备注 |
|---|---|---|
| Jellyfin | ✅ | 3 种认证（用户名密码/API Key/Quick Connect）、WebSocket 14 种事件 |
| Emby | ✅ | 2 种认证、WebSocket 18 种事件、deviceId 持久化 |
| Plex | ✅ | PIN 授权、getNextUp 含 viewOffset 优先 |

虚拟文件系统统一为只读（媒体服务器是元数据驱动）。

### 2.4 下载工具管理 ✅

| 工具 | 状态 | 入口 |
|---|---|---|
| qBittorrent | ✅ | service_adapters/qbittorrent |
| Transmission | ✅ | service_adapters/transmission |
| Aria2 | ✅ | service_adapters/aria2（JSON-RPC + token） |
| MoviePilot | ✅ | service_adapters/moviepilot |
| NASTool | ✅ | features/nastool |

PT 站点列表/详情/搜索 → 一键发送至以上下载器。视频详情/TMDB 推荐 → 一键 PT 搜索资源（带年份）→ 一键下载。

### 2.5 PT 站集成 ✅

- ✅ 通用 PT 站爬虫（基于 cookie + 站点规则）
- ✅ 种子搜索 / 列表 / 推广标识
- ✅ 视频详情页云下载图标 → PT 搜索预填关键词
- ✅ TMDB 推荐卡片长按 → PT 搜索（含/不含年份）
- ✅ 缺失剧集自动 PT 搜索

### 2.6 媒体追踪与刮削 ✅

- ✅ TMDB 元数据（电影/剧集/演员/系列）
- ✅ 豆瓣评分整合
- ✅ NFO 文件解析（Kodi/Jellyfin 风格）
- ✅ Trakt.tv 同步
- ✅ 客户端面部识别（人物聚合）
- 📝 照片地图尚未实现；在实现 GPS EXIF 聚合与地图交互前不暴露产品入口

---

## 3. 非功能需求

### 3.1 性能要求

| 指标 | 目标 | 现状 |
|---|---|---|
| 应用冷启动 | < 3s | ✅ 多数平台达成 |
| 视频播放延迟 | < 1s | ✅ Direct Play 直读 |
| UI 流畅度 | 60fps | ✅ |
| 内存 | 优化 | ✅ 使用 ListView.builder + 流式下载 + 限定缓存 |
| 增量构建 | < 30s | ✅ Windows 增量约 20s |

### 3.2 安全与合规

- ✅ HTTPS / 自签证书可选信任
- ✅ 凭证存储：FlutterSecureStorage（iOS Keychain / macOS Keychain / Windows Credential Manager / Android EncryptedSharedPreferences），失败时降级到 Hive AES box
- ✅ 远程错误上报已移除（避免客户端凭证泄露）
- ✅ 不内嵌书源、不分发第三方爬虫规则；导入时显示免责声明
- ✅ OpenSubtitles 等公共 API key 提供默认兜底但允许用户用自己的 key 覆盖
- ✅ 应用锁（PIN/生物识别/后台超时/切换器遮蔽）
- 📝 隐私政策与商店隐私披露尚未完成

### 3.3 用户体验

- ✅ 响应式设计（手机 / 平板 / 桌面 / 大屏）
- ✅ 暗色 / 亮色 / 系统跟随
- ✅ iOS 26 Liquid Glass 支持
- ✅ 中文本地化
- 🚧 英文本地化（部分文本已国际化）
- 📝 完整无障碍支持
- 📝 RTL 布局支持

### 3.4 离线能力

- ✅ 视频/书籍下载缓存
- ✅ 阅读进度本地存储
- ✅ 断点续传（Range 请求）
- ✅ 笔记离线浏览

---

## 4. 技术约束

### 4.1 跨平台方案

**已选定：Flutter 3.x + Dart 3.x**

实际验证：iOS / Android / macOS / Windows / Linux 均能跑起来；Web 平台不在目标内（部分 native 依赖未支持）。

### 4.2 架构原则

- ✅ 分层架构（Presentation / Domain / Data / Adapters）
- ✅ 三套适配器抽象（NasFileSystem / MediaServerAdapter / ServiceAdapter）
- ✅ Riverpod 响应式状态管理
- ✅ AppError 统一错误处理（仅本地日志，按分类决定级别）

---

## 5. 用户场景

1. **家庭影院** — 在电视投屏 NAS 中的电影，自动加载字幕 ✅
2. **移动阅读** — 手机阅读 EPUB / 漫画，进度多端同步 ✅
3. **音乐欣赏** — 后台/锁屏/桌面歌词三态 ✅
4. **远程下载** — 在 PT 站点搜索资源，一键发送到 NAS 上的 qBittorrent ✅
5. **媒体管理** — 浏览 Jellyfin/Emby/Plex 媒体库，标记已看，多设备进度同步 ✅
6. **元数据补全** — 自动 TMDB 刮削 + 手动批量编辑（音乐元数据写入支持 DSD 等无损格式）✅

---

## 6. 竞品定位

| 应用 | 定位 | 与本应用差异 |
|---|---|---|
| DS Video / Audio / Photo | 群晖官方 | 本应用一站式，且支持非群晖 NAS |
| Infuse | iOS 视频神器 | 本应用是多端 + 多媒体类型 + 开源开放 |
| VLC | 开源播放器 | 本应用更专注 NAS 工作流 |
| Plex 客户端 | 媒体库 | 本应用作为 Plex 客户端，且支持 SMB/WebDAV/绿联/飞牛 |
| Jellyfin Media Player | Jellyfin 客户端 | 本应用同时支持 Jellyfin/Emby/Plex |

**差异化定位**：一站式跨平台 NAS 工作流（NAS 协议 + 媒体服务器 + 下载器 + PT 站 + 阅读 + 笔记），不绑定特定 NAS 品牌，用户自带数据源。
