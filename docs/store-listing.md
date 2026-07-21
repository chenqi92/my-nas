# MyNAS 商店发布资料

> 本文不包含签名、公证或凭据配置。方括号内容必须在提交前人工确认。

## 通用信息

| 字段 | 建议内容 |
|---|---|
| 产品名 | MyNAS |
| 副标题 | 一站式跨平台 NAS 媒体管理 |
| 主分类 | 工具 / Utilities |
| 次分类 | 娱乐或照片与视频（按商店实际可选项） |
| 版权 | © 2026 [开发者名称] |
| 支持网址 | [待部署] |
| 隐私政策网址 | 将根目录 `PRIVACY.md` 部署为公开 HTTPS 页面后填写 |
| 联系邮箱 | [待填写] |

## 中文简介

### 短描述

连接 NAS、媒体服务器和下载器，在一个应用中浏览、播放、阅读与管理家庭媒体。

### 完整描述

MyNAS 是面向家庭 NAS 用户的跨平台媒体管理客户端。你可以连接 SMB、WebDAV、群晖、飞牛、绿联及本地存储，也可以接入 Jellyfin、Emby、Plex、qBittorrent、Transmission、Aria2 等服务。

主要功能：

- 统一浏览和管理多个 NAS 与媒体服务器；
- 视频播放、字幕、投屏、进度同步与元数据刮削；
- 音乐库、歌词、播放列表、后台播放和车载媒体浏览；
- EPUB、PDF、MOBI、漫画与 Markdown 笔记阅读；
- 下载器、PT 站搜索和媒体推荐工作流；
- 本地优先的数据存储，可选同步到用户自己的 WebDAV 服务。

MyNAS 不提供或内置媒体内容、书源、PT 资源或第三方账户。所有服务器、数据源和内容均由用户自行配置，并应遵守所在地法律及第三方服务条款。部分功能需要相应服务器、API Key、系统权限或平台授权。

## English listing

### Short description

Browse, play, read, and manage media from your NAS, media servers, and download clients in one app.

### Full description

MyNAS is a cross-platform media client for home NAS users. Connect SMB, WebDAV, Synology, fnOS, UGOS, and local storage, or integrate Jellyfin, Emby, Plex, qBittorrent, Transmission, and Aria2.

Highlights:

- Browse and manage multiple NAS and media-server sources;
- Play video with subtitles, casting, progress sync, and metadata;
- Organize music, lyrics, playlists, background playback, and car media browsing;
- Read EPUB, PDF, MOBI, comics, and Markdown notes;
- Connect download clients and user-configured search services;
- Keep data local by default, with optional sync to your own WebDAV server.

MyNAS does not provide or bundle media, book sources, tracker resources, or third-party accounts. Users configure their own servers and data sources and are responsible for complying with applicable laws and third-party terms. Some features require a compatible server, API key, system permission, or platform entitlement.

## 截图计划

每个平台至少准备以下场景，截图中不要出现真实域名、IP、用户名、Cookie、Token、下载内容或未经授权的海报：

1. 首页与统一媒体入口；
2. NAS 文件浏览器；
3. 视频库与播放界面；
4. 音乐库与正在播放；
5. 阅读与笔记编辑；
6. 数据源连接管理；
7. 下载器或投屏界面；
8. 深色模式和桌面布局。

需要尺寸：

- [ ] App Store Connect 当前要求的 iPhone/iPad/macOS 尺寸；
- [ ] Google Play 手机、平板及适用的大屏尺寸；
- [ ] Microsoft Store 至少一张桌面截图，并补充推荐比例素材；
- [ ] 中文与英文各一套，或确认商店允许复用无文字截图。

## 隐私声明草案

最终答案必须以发布构建和第三方 SDK 的实际行为为准：

- 开发者运营的集中式服务器收集数据：当前代码审计结果为“否”；
- 远程崩溃/错误上报：否；
- 广告或跨应用追踪：否；
- 本地处理用户文件、照片、音视频和文档：是；
- 向用户配置的 NAS/媒体服务器/下载器传输数据：是，属于用户请求的核心功能；
- 向可选元数据、字幕、追踪、翻译服务发送查询：用户启用时是；
- 凭据：保存在设备安全存储或本地加密降级存储中；
- WebDAV 同步：仅在用户配置并启用后执行。

Google Play 的 Data safety 表即使声明不收集数据也必须完成，并需要隐私政策链接。Apple 要求提供公开隐私政策 URL，并申报应用和第三方 SDK 的数据实践。Microsoft Store 至少要求描述和一张截图；涉及个人信息时应提供隐私政策。

官方参考：

- [Apple App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/)
- [Apple App Store Connect - Manage app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/)
- [Google Play - Data safety](https://support.google.com/googleplay/android-developer/answer/10787469)
- [Google Play - Prominent disclosure and consent](https://support.google.com/googleplay/android-developer/answer/11150561)
- [Microsoft Store policies](https://learn.microsoft.com/windows/apps/publish/store-policies)
- [Microsoft Store listing information](https://learn.microsoft.com/windows/apps/publish/publish-your-app/pwa/add-and-edit-store-listing-info)

## 提交前清单

- [ ] 填写并验证支持网址、隐私网址、开发者名称和邮箱；
- [ ] 按最终构建复核权限、SDK 和隐私问卷；
- [ ] 准备无敏感信息的多语言截图；
- [ ] 完成年龄分级和内容权利声明；
- [ ] 提供审核测试说明、演示账号或本地测试服务（如商店要求）；
- [ ] 确认第三方品牌名称和图标的展示符合其商标规则；
- [ ] 确认用户自带内容、书源和 PT 功能的合规说明准确。
