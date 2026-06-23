# MyNAS 桌面端 — 重新设计需求规格 (Feature Spec for Redesign)

> 这份文档**只描述功能、功能持有的数据、功能之间的数据/触发关联、以及关键交互与状态**，**不预设视觉风格、布局网格、控件粒度、手势细节**。
> 你（AI 设计师）可自由重组信息架构与视觉，但**每一个带 ID 锚点的功能点在重设计后都必须仍能被用户触达并使用**，列出的数据关联与状态也必须保留。
>
> 应用：**MyNAS — 跨平台 NAS 客户端**（Flutter）。本规格聚焦**桌面端**（macOS / Windows / Linux），信息架构与移动端共享，只在布局密度与系统集成上差异化。
>
> 技术现状（理解约束用，别因此锁死视觉）：Flutter + Riverpod + go_router（`StatefulShellRoute.indexedStack`，14 branch）+ Hive/SQLite/flutter_secure_storage + media_kit/just_audio/ffmpeg + dlna_dart + shelf（投屏与本地媒体代理）+ tflite/ML Kit（人脸）。
>
> **必须同时给出两套并列方案**（app 内 `uiStyleProvider` 真实开关 `classic` / `glass`）：
> - **A 套 · 玻璃版 (Glass)**：`BackdropFilter` 模糊 + 半透明 + tint + 可选描边发光（`GlassStyle`），按平台优化（macOS 原生级模糊 / Windows 降级 / Linux 视性能降级 / Web 禁用）。
> - **B 套 · 经典版 (Classic)**：不透明卡片 + 阴影分层 + 圆角，无模糊、无玻璃形变动画，降低层叠透明以保性能。
>
> 两套**共享同一信息架构与功能入口**，只在视觉表层差异化，绝不因材质不同导致信息结构分叉。

### 状态图例（每个功能点的成熟度标记）
- **（无标记）= 已实现**：当前代码已具备，重设计必须保留入口与数据关联。
- **【规划】= 预期/计划功能**：尚未实现或仅有数据字段/骨架，但属于产品方向，**重设计需要为其预留位置、入口与状态**（设计稿里要画出来，开发后续补齐）。
- **【受限】= 平台/协议限制**：能力存在但受外部条件约束（如某协议不支持单任务限速），设计需体现降级/置灰/说明。

---

## 0. 应用一句话定位

MyNAS 是一个跨平台（macOS/Windows/Linux/iOS/Android）的 **NAS 全能客户端**：统一接入用户自有的 NAS（群晖/QNAP/绿联/飞牛）、通用协议源（SMB/WebDAV/SFTP/FTP/NFS/UPnP/S3）、媒体服务器（Jellyfin/Emby/Plex）、下载器（aria2/qBittorrent/Transmission）、PT 站点、媒体自动化（NAStool/MoviePilot）与追踪服务（Trakt）；在一个 app 里提供**影视播放、音乐播放、照片库（含 AI 人脸识别）、漫画/电子书阅读、笔记、文件管理、传输/下载队列、媒体刮削、DLNA 投屏、WebDAV 跨设备同步**等完整能力。

---

## 1. 顶层信息架构

容器是用户进入功能的入口；如何呈现（NavigationRail / 侧栏 / Tab / Toolbar / 多窗口 / 浮层）由设计师决定。当前为 `StatefulShellRoute.indexedStack` 的 14 个并行 branch（各自维护导航栈，双击 tab 回首屏），顺序固定为 `home / video / live / music / photo / reading / mine / ops / download / transfer / sources / pt / nastool / files`（移动端底栏仅显示其中 video/music/photo/reading/mine 五项，其余为桌面工具区）。

### 1.1 一级入口（主导航，5 个）
- **影视 Video**（`/video`）— 视频媒体库 + 播放器
- **曲库 Music**（`/music`）— 音乐媒体库 + 播放器
- **相册 Photo**（`/photo`）— 照片/视频库 + AI 人脸
- **阅读 Reading**（`/reading`）— 漫画 / 电子书 / 笔记 三合一
- **我的 Mine**（`/mine`）— 设置与个人内容聚合（所有设置 section 的总入口）

### 1.2 「工具区」一级入口（桌面 NavigationRail 常驻；移动从「我的」进）
- **下载 Download**（`/download`）— 直链/下载器任务总览
- **任务 Transfer**（`/transfer`）— 上传/下载/缓存传输队列
- **连接 Sources**（`/sources`）— 所有连接源管理

> 桌面断点：`width ≥ 1200px` 进入桌面布局；`≥ 1100px` 时 Rail 展开（含文字标签 200px），否则仅图标 64px。Logo 下 5 主 tab，Divider，再 3 工具区。

### 1.3 每个一级 tab 的落地子结构（设计需覆盖）
- **影视**：库网格/列表（海报）+ 顶部「继续观看」行（TRK-05）+ 分类/筛选（库/类型/已看未看）+ 搜索 + 详情页（剧集分季/集、刮削简介/演职/评分）+ 直播入口。
- **曲库**：歌曲/专辑/艺术家/文件夹/歌单/分类 多视图切换 + 搜索 + 迷你播放条常驻 + 全屏播放器入口。
- **相册**：时间线 / 网格 双视图 + 人物（人脸）入口 + 相册/文件夹分组 + 来源筛选 + 搜索 + 重复检测入口。
- **阅读**：图书 / 漫画 / 笔记 三标签 + 本地/书源搜索切换 + 书架（封面网格 + 续读进度）。
- **我的**：账号/连接状态头部 + 11 组设置（§2.2）+ 我的收藏聚合。

### 1.4 二级入口（「我的」/菜单/快捷键）
连接源管理、媒体库目录映射、我的收藏、各媒体统计/设置子页（听歌统计/重复歌曲/回收站/刮削源/字幕源/媒体追踪/媒体管理/PT 站点/图书源/云同步/Hosts 映射/Spotlight 索引/缓存/关于更新）、桌面歌词窗口、全屏播放器、解锁页。

### 1.5 三级入口（播放器/详情/上下文菜单）
正在播放/播放器、投屏设备选择器、添加到歌单/收藏 sheet、文件操作菜单、目录选择器、刮削/元数据编辑面板、2FA 验证 sheet、「发送到下载器」sheet。

---

## 2. 完整功能清单

> 格式「功能 + 数据/状态 + 关联」。**不要合并功能**；ID 锚点必须能一一对应触达。每个域末尾给「交互·状态·菜单」要点。

### 2.0 平台/系统级 (SYS)

| ID | 功能 | 数据/状态 | 关联 |
|----|------|----------|------|
| SYS-01 | 启动闪屏 + 后台初始化（≥1.2s，加载源/各媒体库缓存/元数据服务，不阻塞 UI） | StartupPage | 各库服务 |
| SYS-02 | 桌面窗口几何记忆（尺寸/位置/最大化恢复，最小 1024×720，默认 1280×800） | Hive `window_*` | macOS/Win/Linux |
| SYS-03 | 深链 / URL Scheme `mynas://`（音乐 toggle/next/previous/favorite/player、Trakt OAuth 回调） | DeepLinkService | MUS-*、TRK-01 |
| SYS-04 | 后台任务（视频刮削 / 扫描；前台服务通知 + 实时进度；idle/running/paused/completed/error） | BackgroundTaskService | VID-SCR-* |
| SYS-05 | macOS Spotlight 索引（视频/音乐/图书可被系统搜索，结果深链直达；启用后增量重索引） | SpotlightSettings | SYS-03 |
| SYS-06 | Windows Jump List（右键任务栏快速跳各 tab） | JumpListController | §1.1 |
| SYS-07 | 系统托盘 / 最小化到托盘（Windows/Linux）【规划：未实现，无 tray 依赖/代码】 | tray | — |
| SYS-08 | 全局 Toast/通知队列 | ToastService | 全模块 |
| SYS-09 | 应用更新检查（启动静默 + 手动；非 iOS 下载更新；显示更新日志 + 立即更新） | UpdateService | SET-ABOUT |
| SYS-10 | 剪贴板集成（复制视频/音乐/图书链接，长按/右键） | Clipboard | — |
| SYS-11 | 多语言（中/英；音频/字幕/元数据语言优先级列表，可拖拽排序：auto/原文/简繁中英日韩法德西葡俄意泰越） | LanguagePreference | VID-SUB-*、VID-SCR-* |
| SYS-12 | 桌面歌词独立浮窗（macOS/Windows，透明/可锁定） | DesktopLyricProvider | DLY-* |
| SYS-13 | 网络状态感知 / mDNS(bonsoir) 局域网设备发现 | connectivity | SRC-13 |
| SYS-14 | Live Activity / 灵动岛（iOS）/ Android 动态岛通知（移动端；桌面无） | LiveActivityService | MUS-* |
| SYS-15 | Hosts 映射（域名→IP，绕过 DNS 污染） | Hive | SRC-* |
| SYS-16 | 诊断/日志查看与导出【规划】 | 日志 | SET-ADV |

**交互·状态·菜单：** 启动有 Logo+Shimmer 加载态；更新有"发现新版本"对话框（更新日志 + 立即更新/稍后）；深链来时若 app 已开直接路由、未开则启动后消费 pending；桌面托盘右键菜单（显示主窗口/播放控制/退出）。

### 2.1 外观与主题 (APP) / 导航 (NAV)

| ID | 功能 | 数据/状态 | 关联 |
|----|------|----------|------|
| APP-01 | 主题模式：浅色 / 深色 / 跟随系统 | `theme_mode` | OS |
| APP-02 | **UI 风格：经典 (classic) / 玻璃 (glass)** —— 两套方案的真实开关 | `ui_style` + `ui_style_user_set` | 全 UI |
| APP-03 | 玻璃参数：模糊强度 / 背景不透明度 / tint 不透明度 / 描边不透明度 / 描边发光 | GlassStyle | APP-02 |
| APP-04 | 平台玻璃优化（macOS 原生模糊 / Android 降级 / Web 禁用） | PlatformGlassConfig | APP-02 |
| APP-05 | 配色方案预设（蓝/紫/绿/红…）+ Material3 动态取色（Android 12+） | `color_scheme_preset` | OS |
| NAV-01 | 一级导航（5 主 tab + 3 工具区），桌面 Rail / 移动 BottomNav 自适应 | StatefulShellRoute | §1 |
| NAV-02 | Rail 展开/折叠（≥1100px 展开含标签；否则仅图标） | screenWidth | NAV-01 |
| NAV-03 | 底栏可见性（仅主 tab 首屏显示，进详情/设置自动隐藏，带 Size/Slide 动画） | BottomNavVisibility | NAV-01 |
| NAV-04 | 双击 tab 回该 branch 首屏（清栈） | Navigator stack | NAV-01 |
| NAV-05 | 桌面密度覆盖（AppBar 48px、ListTile dense、Dialog 小圆角、SnackBar 限宽 480px） | 桌面主题 | — |

**交互·状态·菜单：** UI 风格首次由用户主动设置后记 `ui_style_user_set`，之后不再被系统默认覆盖；切换风格应实时全局生效（无需重启）；配色预设应有色卡预览。

### 2.2 设置总览 (SET) — 「我的」下 11 组 + 附加

> 桌面建议"左侧 section 列表 + 右侧详情卡片"双栏；移动为分组卡片滚动。下列每项都要可达。

| ID | section / 项 | 内容 |
|----|------|------|
| SET-CONN | 连接 | 连接源(SRC-*)、媒体库目录映射(SRC-30) |
| SET-MINE | 我的内容 | 我的收藏（视频/音乐/照片/笔记/图书/漫画聚合） |
| SET-VIDEO | 视频 | 播放器设置（默认清晰度/自适应/记住选择/缓冲阈值/投屏/转码说明）、刮削源(VID-SCR-*)、字幕源、语言偏好(SYS-11)、媒体追踪(TRK-*)、媒体管理(MM-*)、下载器入口、直播设置 |
| SET-MUSIC | 音乐 | 播放器设置（引擎 平台原生/FFmpeg、播放模式、音量、淡入淡出、Gapless、歌词显示、均衡器）、听歌统计、重复歌曲、回收站、Scrobble、音乐刮削源 |
| SET-BOOK | 图书 | 图书源(BK-SRC-*)、图书设置（TTS 等） |
| SET-PT | 站点 | PT 站点配置(PT-*) |
| SET-XFER | 传输 | 实时传输卡片（下载/上传/缓存进度） |
| SET-APP | 外观 | 主题模式/UI 风格/配色(APP-01..05) |
| SET-SEC | 隐私与安全 | 应用锁(LOCK-*) |
| SET-SYNC | 云同步 | WebDAV 同步(SYNC-*) |
| SET-ADV | 高级 | Hosts 映射(SYS-15)、Spotlight 索引(SYS-05)、缓存管理(CACHE-*)、诊断/日志(SYS-16) |
| SET-ABOUT | 关于 | 版本/编译号、检查更新(SYS-09)、开源许可证 |

**交互·状态·菜单：** 设置项类型有 开关/单选/多选/输入/拖拽排序/导航子页；危险项（清缓存/删源/退出登录）需二次确认；连接状态以 chip 显示在头部。

### 2.3 连接与数据源 (SRC)

**支持的源类型：**

| ID | 源类型 | 连接参数 / 认证 | 特殊 |
|----|--------|----------------|------|
| SRC-T01 | 群晖 Synology | host/5001/user/pwd/SSL；QuickConnect ID、2FA(TOTP)、记住设备 | FileStation 浏览、存储信息 |
| SRC-T02 | QNAP | host/8080/user/pwd/SSL | 文件系统 |
| SRC-T03 | 绿联 UGOS | host/9999/user/pwd/SSL | 【规划】已接入未公开 |
| SRC-T04 | 飞牛 fnOS | host/5666/user/pwd/SSL | 【规划】无公开 API |
| SRC-T05 | SMB/CIFS | host(IP)/445/user/pwd/share | 连接池、自动重连、并发、mDNS 预解析 |
| SRC-T06 | WebDAV | host/443/user/pwd/SSL/basePath | 自签证书、TLS 超时 |
| SRC-T07 | SFTP | host/22/user/(pwd 或 PEM 私钥)/path | SSH 密钥认证 |
| SRC-T08 | FTP | host/21/user/pwd/encryption/path | 明文/隐式TLS(990)/显式TLS、匿名 |
| SRC-T09 | NFS | host/2049/export/version | 【规划】Unix 权限，isSupported=false |
| SRC-T10 | UPnP/DLNA 服务器 | host/port（自动发现） | 只读 SOAP Browse、直链流式 |
| SRC-T11 | S3 兼容 | endpoint/access/secret/bucket | 【规划：未实现，无 SourceType.s3/适配器】 |
| SRC-T12 | 本地存储 Local | 文件夹选择 | 移动端自动媒体库 |
| SRC-T13 | Jellyfin | host/8096/SSL；user/pwd \| API Key \| Quick Connect | 虚拟库、转码(直连/转码)、库缓存 |
| SRC-T14 | Emby | host/8096/SSL；user/pwd \| API Key | 虚拟库、转码 |
| SRC-T15 | Plex | host/32400/SSL；PIN(plex.tv/link) \| Token | clientId 持久化、虚拟库、直链 |
| SRC-T16 | qBittorrent | host/8080/SSL；user/pwd \| API Key(v5.2+) | 见 QBT-* |
| SRC-T17 | Transmission | host/9091/SSL/rpcPath；user/pwd | 见 TRM-* |
| SRC-T18 | Aria2 | host/6800/SSL/rpcSecret | 见 ARIA-* |
| SRC-T19 | Trakt | OAuth2(clientId/secret) | 见 TRK-* |
| SRC-T20 | NAStool | host/3000/SSL；user/pwd | 见 NT-* |
| SRC-T21 | MoviePilot | host/3001/SSL；API Token | 见 MM-* |
| SRC-T22 | PT 站点（通用） | host/SSL；Cookie \| 自定义头(x-api-key/authorization) | RSS、签到、浏览器仿真、代理、流控限速 |
| SRC-T23 | OpenSubtitles（字幕站） | 固定服务；user/pwd(可选)/API Key | 语言偏好、排除AI翻译、SDH优先 |

**连接管理交互：**

| ID | 功能 | 数据/状态 | 关联 |
|----|------|----------|------|
| SRC-01 | 添加源（选类型 → 动态表单：基本信息/连接/账户/高级 autoConnect/记住设备） | SourceEntity | SourceManager |
| SRC-02 | 编辑源（预填，改密码/主机等） | SourceEntity/Credential | — |
| SRC-03 | 删除源（级联：断连 + 删凭据 + 删媒体库路径 + 删该源歌曲/媒体） | — | FILE-*、各库 |
| SRC-04 | 测试连接（按类型：登录/列目录/SSH 认证/获取版本/OAuth 验证） | ConnectionResult | 适配器 |
| SRC-05 | 启用/禁用（连接/断开，禁用源不参与扫描/播放） | SourceStatus | 各库 |
| SRC-06 | 连接状态：disconnected/connecting/requires2FA/connected/error | SourceConnection | NAV/列表 |
| SRC-07 | 2FA 验证（群晖 TOTP + 记住此设备 → deviceId） | two_fa_sheet | SRC-T01 |
| SRC-08 | 凭据安全存储（secure_storage/Keychain/EncryptedSharedPrefs；失败静默降级不阻塞） | SourceCredential | — |
| SRC-09 | 自签证书信任（useSsl + verifySSL=false） | DioClient | SRC-T06/13.. |
| SRC-10 | 自动连接（启动连 autoConnect=true 的源） | autoConnect | SYS-01 |
| SRC-11 | 多账号源合并/去重（同账号重复 OAuth 源 UID 匹配迁移） | CloudAccountMigration | SRC-T15..21 |
| SRC-12 | 源排序（sortOrder 拖拽） | — | NAV |
| SRC-13 | mDNS 局域网设备发现（添加时建议候选） | DiscoveredDevice | SYS-13 |
| SRC-30 | 媒体库目录映射（在文件浏览器选文件夹 → 标记为 视频/音乐/照片/漫画/图书 库 → 供扫描/搜索/播放列表；可启用/禁用单路径） | MediaLibraryPath/Config | FILE-*、各库扫描 |

**交互·状态·菜单：** 源卡片显示类型图标 + 名称 + host + 状态点；点击进入文件浏览或库；右键/长按菜单（编辑/删除/重新连接/标记媒体库/排序）；连接失败弹"重新输入凭据"sheet；2FA 失败可重试；空态引导添加第一个源。

### 2.4 文件浏览 (FILE)

| ID | 功能 | 数据/状态 | 关联 |
|----|------|----------|------|
| FILE-01 | 目录浏览（从 initialBrowsePath 进入，递归） | NasFileSystem.list | SRC-* |
| FILE-02 | 返回上级 / 返回根 / 面包屑跳转（支持 Windows 盘符 C:\ 与 Unix /） | path 解析 | — |
| FILE-03 | 源切换（>1 源桌面侧栏/移动下拉，切换重置路径） | selectedSourceId | SRC-* |
| FILE-04 | 排序（名称/大小/修改日期/类型 + 升降序 + 文件夹优先） | SortMode | — |
| FILE-05 | 视图模式（网格缩略图 / 列表详情） | ViewMode | — |
| FILE-06 | 搜索（fileSystem.search，可限范围） | query | — |
| FILE-07 | 刷新（下拉/按钮，保持路径） | — | — |
| FILE-08 | 多选（进入/退出、单选、全选/取消、显示已选数） | selectedFiles Set | — |
| FILE-09 | 新建文件夹 | createFolder | 写权限 |
| FILE-10 | 重命名（保留扩展名逻辑） | rename | — |
| FILE-11 | 删除（单/批量，确认） | delete | — |
| FILE-12 | 复制到（目录选择器，递归） | copyTo | — |
| FILE-13 | 移动到（目录选择器） | moveTo | — |
| FILE-14 | 查看属性（名/大小/修改时间） | FileItem | — |
| FILE-15 | 上传（file_picker 多选 → 当前目录，转 Transfer 任务带进度） | XFER-* | XFER-* |
| FILE-16 | 下载（单/批量 → 生成 URL → 队列） | DownloadService/Transfer | DL-*、XFER-* |
| FILE-17 | 分享（流式下载到临时文件 → 系统分享面板；5min 清理） | share_plus | — |
| FILE-18 | 写权限识别（仅 NAS 支持增删改传；媒体服务器虚拟库只读，禁用对应操作） | supportsWriteOperations | SRC-T13..15 |
| FILE-19 | 错误恢复（无权限/超时 30s → 重试 / 浏览所有共享 入口） | FileListError | — |
| FILE-20 | 文件类型识别 + 打开策略（图/视/音/文档/PDF/电子书/压缩包/漫画/代码/文本；扩展名+MIME；Live Photo 关联视频） | FileType | 各播放/阅读器 |
| FILE-21 | 缩略图（NAS 缩略图 URL，small/medium/large/xlarge） | getThumbnailUrl | FILE-05 |
| FILE-22 | 媒体服务器虚拟库浏览（库→集合→项目树，点项目取流播放） | 虚拟 FS | SRC-T13..15 |
| FILE-23 | 压缩包识别（zip/rar/7z/tar；CBZ/CBR/CB7 交漫画阅读器；其余下载后系统工具） | archive | CMC-* |
| FILE-24 | 解压到当前目录【规划】 | — | FILE-23 |

**交互·状态·菜单：** 文件项右键/长按 → BottomSheet 菜单（打开/下载/分享/复制/移动/重命名/删除/属性，头部显示文件信息）；加载用 Skeleton；多选浮出批量操作条；网格/列表视图切换有过渡动画；下拉刷新；面包屑可横向滚动。

### 2.5 传输队列 (XFER) 与直链下载 (DL)

| ID | 功能 | 数据/状态 | 关联 |
|----|------|----------|------|
| XFER-01 | 任务类型：上传 / 下载 / 缓存（缓存完成保留，下载完成移除） | TransferType | FILE-15/16 |
| XFER-02 | 状态机：pending/queued/transferring/paused/completed/failed/cancelled | TransferStatus | — |
| XFER-03 | 三页签展示（下载/上传/缓存；桌面左侧栏 + 右内容） | TransferManagerPage | — |
| XFER-04 | 排序（状态优先级 + 创建时间倒序） | — | — |
| XFER-05 | 进度/速度/ETA/已传-总大小 展示 | TransferProgress | — |
| XFER-06 | 并发控制（最多 3，超出排队，完成自动取下一个） | maxConcurrent=3 | — |
| XFER-07 | 后台传输（切后台继续，全局单例 + DB 持久化） | TransferService | — |
| XFER-08 | 暂停/继续/取消（取消删未完成文件）/重试/删除任务 | canPause/Resume/Cancel/Retry | — |
| XFER-09 | 清除已完成（批量删 completed/failed/cancelled，不删 cache） | — | — |
| XFER-10 | 持久化 + 启动恢复（重启加载未完成，transferring 重置 paused） | SQLite | — |
| XFER-11 | 通知反馈（创建/完成/失败 SnackBar，可跳传输管理） | — | SYS-08 |
| XFER-12 | 上传去重标记（记录已上传文件，防重复） | UploadedMark | — |
| DL-01 | 直链 HTTP(S) 下载（独立于 Transfer，Dio） | DownloadTask | — |
| DL-02 | 断点续传（HTTP Range，校验本地已下字节） | Range | — |
| DL-03 | 状态：pending/downloading/paused/completed/failed/cancelled | — | — |
| DL-04 | 下载目录（平台默认 + 自定义 customPath） | downloadDirectory | — |
| DL-05 | 新建/开始/暂停/继续/取消/重试 | — | — |
| DL-06 | 完成后：打开文件(open_filex) / 打开所在目录(open/explorer/xdg-open) / 删除任务 | — | — |
| DL-07 | 磁力/种子下载交由下载器集成【受限】（直链模块本身不解析磁力） | — | ARIA/QBT/TRM |

**交互·状态·菜单：** 每任务行：图标 + 名称 + 进度条 + 速度/ETA + 操作按钮（暂停/继续/取消/重试/删除/打开）；空态分页签各自引导；失败行展开显示错误原因；桌面右键菜单。

### 2.6 音乐播放 (MUS)

| ID | 功能 | 数据/状态 | 关联 |
|----|------|----------|------|
| MUS-01 | 播放/暂停 | isPlaying | AudioHandler |
| MUS-02 | 上一首/下一首 | currentIndex/queue | MUS-05 |
| MUS-03 | 进度拖拽/seek | position/duration/buffered | LYR-04 |
| MUS-04 | 音量 / 静音 | volume | MUS-OUT-* |
| MUS-05 | 队列（增/删/重排/查看 上一段-当前-Up Next） | playQueue | MUS-02 |
| MUS-06 | 添加到下一首 | insertIndex | MUS-05 |
| MUS-07 | 随机播放 | PlayMode.shuffle | MUS-05 |
| MUS-08 | 列表循环/单曲循环/顺序 | PlayMode | MUS-05 |
| MUS-09 | 歌单：创建/编辑/删除/详情 | Playlist | SYNC、MUS-BIN |
| MUS-10 | 专辑浏览（分组+详情） | Album | — |
| MUS-11 | 艺术家浏览（分组+详情） | Artist | — |
| MUS-12 | 文件夹浏览（目录结构） | MusicFolder | FILE-* |
| MUS-13 | 分类/流派网格 | genre | — |
| MUS-14 | 收藏/喜欢（自动"我喜欢的"歌单） | MusicFavorite | SYNC |
| MUS-15 | 倍速 0.5x–2x | speed | — |
| MUS-16 | Gapless 无缝 | gaplessPlayback | — |
| MUS-17 | 交叉淡入淡出 | crossfadeDuration | — |
| MUS-18 | 10 段均衡器 + 8 预设 + 自定义保存 | EqualizerState | — |
| MUS-19 | 多格式解码（AAC/MP3/FLAC/OGG/WAV/M4A/APE/AIFF/DSD/Opus…；引擎 平台原生/FFmpeg 可选） | mimeType | media_kit/just_audio |
| MUS-20 | 音频直通 passthrough（AC3/DTS/TrueHD） | AudioCodec | MUS-OUT-* |
| MUS-21 | 网易云 NCM 解密播放 | NCM→pcm | — |
| MUS-22 | 封面显示 + 本地缓存 | coverUrl/Data | CACHE-* |
| MUS-23 | 元数据编辑（标题/艺人/专辑/年份…，后台异步写标签队列） | tags | MUS-24 |
| MUS-24 | 自动刮削（MusicBrainz/AcoustID/网易云…，缺失补全/全量覆盖） | MusicScraperResult | SET-MUSIC |
| MUS-25 | 音频指纹识别（Chromaprint/AcoustID） | fingerprint | MUS-24 |
| MUS-26 | 播放历史 | PlayHistoryEntry | MUS-STAT-* |
| MUS-DUP | 重复歌曲检测（多版本 mp3+flac） | DuplicateInfo | — |
| MUS-BIN | 回收站（删歌单 30 天恢复） | deletedAt | MUS-09 |
| MUS-STAT-01 | 听歌统计（周/月/年/全部；总数/总时长/活跃天数/不重复曲目） | PlayHistorySummary | — |
| MUS-STAT-02 | Top 排行（歌曲/艺人/专辑） | RankedItem | — |
| MUS-STAT-03 | 按天播放热力图 | dailyPlayCounts | — |
| MUS-STAT-04 | 年度报告【规划】（故事卡片/音乐人格，对齐姊妹产品） | aggregate | — |
| MUS-SCROB-01 | Last.fm Scrobble（授权 + 播完 50%/4min 上报） | session key | — |
| MUS-SCROB-02 | ListenBrainz Scrobble（token） | token | — |
| MUS-SCROB-03 | 上报离线队列 + 失败重试 | queue | — |
| LYR-01 | 行级 LRC | LyricLine | — |
| LYR-02 | 字级歌词（LRC A2 / TTML） | LyricSyllable | — |
| LYR-03 | 卡拉OK 实时高亮（逐字插值） | interpolatedTime | — |
| LYR-04 | 点击歌词行 seek | seek | MUS-03 |
| LYR-05 | 当前行高亮 + 自动滚动居中 | currentIndex | — |
| LYR-06 | 歌词翻译（双行） | translation | SYNC(字号) |
| LYR-07 | 歌词来源（本地 LRC / 内嵌标签 / 在线查询） | LyricsFormat | MUS-24 |
| MUS-OUT-01 | 输出设备选择（系统/蓝牙/AirPlay/DAC）+ 杜比全景声 | AudioOutputCapability | — |
| MUS-OUT-02 | 媒体通知/锁屏/蓝牙耳机/车载 控制 | MediaItem/playbackState | audio_service |

**交互·状态·菜单：** 歌曲行右键菜单（播放/下一首播放/加入队列/加入歌单/收藏/编辑标签/刮削/显示专辑·艺术家/删除）；迷你播放条常驻；全屏播放器有封面/歌词/队列三态；空态引导映射音乐媒体库。

### 2.7 视频播放 (VID)

| ID | 功能 | 数据/状态 | 关联 |
|----|------|----------|------|
| VID-01 | 播放/暂停/进度拖拽/快进快退(10s/30s) | position | media_kit/原生 |
| VID-02 | 章节导航 | chapters | — |
| VID-03 | 倍速 0.5x–2x（记忆） | speed | — |
| VID-04 | 画面比例（16:9/4:3/21:9/1:1/自定义）+ 缩放（适应/填充/拉伸/智能） | aspectRatio/ScaleType | — |
| VID-05 | 续播（保存进度，下次续看） | VideoProgress | SYNC |
| VID-06 | 播放历史 + 标记已观看 | history/watched | TRK-* |
| VID-07 | 自动播放下一集 | episode list | VID-EP-* |
| VID-SUB-01 | 内挂字幕（轨道选择） | SubtitleTrackInfo | — |
| VID-SUB-02 | 外挂字幕（同目录/手动 SRT/ASS/VTT） | SubtitleItem | — |
| VID-SUB-03 | 在线字幕下载（OpenSubtitles） | subtitle URL | SRC-T23 |
| VID-SUB-04 | 字幕样式（字号/颜色/背景/位置） | SubtitleStyle | — |
| VID-SUB-05 | 字幕翻译（实时翻译） | translated | SYS-11 |
| VID-SUB-06 | 字幕语言优先级自动选择 | language list | SYS-11 |
| VID-AUD-01 | 音轨切换 + 自动按语言优先 + 信息(编码/声道/采样率) | AudioTrackInfo | SYS-11 |
| VID-PIP-01 | 画中画 进入/退出 + 窗口管理（桌面手动/移动系统） | isPiP | — |
| VID-EP-01 | 剧集分组（按季）+ 季选择器 + 集数导航 | TvShowGroup | VID-07 |
| VID-SCR-01 | NFO 解析（Kodi/Emby 样式） | NfoMetadata | — |
| VID-SCR-02 | TMDB 在线刮削 | TmdbScraperResult | SET-VIDEO |
| VID-SCR-03 | 豆瓣刮削 | DoubanScraperResult | — |
| VID-SCR-04 | 海报/背景缓存 + 视频关键帧缩略图 | poster/backdrop/thumb | — |
| VID-BK-01 | 播放器后端（media_kit/libmpv ⟷ 原生 AVPlayer，自动按 HDR/杜比切换） | PlayerBackendType | — |
| VID-HDR-01 | 杜比视界检测 + HDR 能力 + 色彩空间(SDR/HDR10/HLG/DV) | HdrCapability | VID-BK-01 |
| VID-TR-01 | 服务端转码（Jellyfin/群晖 转码流） | transcoding profile | SRC-T13.. |
| VID-TR-02 | 客户端转码（Android MediaCodec 硬解）【受限：桌面策略不同】 | codec pipeline | — |
| VID-Q-01 | 清晰度：网络自适应 + 手动切换 | VideoQuality | SET-VIDEO |
| VID-LIVE-01 | 直播：M3U8/HLS 解析 + 频道列表 + 播放 | LiveStream | SET-VIDEO |
| VID-OUT-01 | 音频输出设备 + 杜比全景声 | AudioOutputCapability | — |

**交互·状态·菜单：** 播放器控制条（播放/进度/音量/字幕/音轨/倍速/比例/投屏/PiP/全屏/下一集）；详情页（海报+简介+演职+评分+剧集列表+继续观看进度条）；库网格项右键（播放/继续观看/标记已看/刮削/删除/属性）；缓冲/转码/错误态提示。

### 2.8 照片 (PHO) 与人脸 AI (FACE)

| ID | 功能 | 数据/状态 | 关联 |
|----|------|----------|------|
| PHO-01 | 网格视图（响应式列数 移动 3 / 桌面 5–10） | PhotoItem | — |
| PHO-02 | 时间线视图（日/月/年自适应分组 + 年月跳转导航 + 月统计） | PhotoGroup/YearMonth | — |
| PHO-03 | 按相册 / 文件夹分组 | MediaLibraryPath/folderName | SRC-30 |
| PHO-04 | 大图查看器（双击回弹/捏合≤4x/拖拽，沉浸式自动隐藏控制栏） | PhotoViewerPage | — |
| PHO-05 | 幻灯片自动播放（翻页预载原图，停 Live Photo） | pageController | — |
| PHO-06 | 视频混排（缩略图+播放，Live Photo 长按播放视频） | FileType/isLivePhoto | VID-* |
| PHO-07 | 键盘快捷键（←→/Home-End/Space 覆盖层/L 收藏/I 信息/Esc/? 帮助） | shortcuts | — |
| PHO-08 | 来源筛选（全部/本机/NAS） | sourceFilter | SRC-* |
| PHO-09 | 时间筛选（选年/月） | filterYear/Month | PHO-02 |
| PHO-10 | 排序（日期 / 文件名【规划】 / 大小【规划】） | PhotoSortType | — |
| PHO-11 | 收藏（Hive 持久化）+ 收藏视图 | PhotoFavorite | SYNC |
| PHO-12 | 多选（全选/逐个；桌面拖框选【规划】）+ 批量删除/上传/下载 | selectedPaths | XFER-* |
| PHO-13 | 上传到 NAS（批量 Transfer） | — | XFER-01 |
| PHO-14 | 智能下载（HTTP→Dio / SMB-WebDAV→流式，带进度/取消） | PhotoSaveService | DL-* |
| PHO-15 | 保存到系统相册（gal，请求权限） | gal | — |
| PHO-16 | 分享（移动系统分享 / 桌面复制链接或下载分享） | share_plus | — |
| PHO-17 | 删除（源文件删除，同步清收藏+人脸记录）/ 从库移除（仅删 DB 记录） | delete | FACE-* |
| PHO-18 | EXIF 查看（时间/分辨率/大小/相机型号/GPS） | takenAt/camera/GPS | — |
| PHO-19 | 重复检测：快速(名+大小) / 精确(MD5,跨源) / 视觉相似(pHash 汉明距离阈值) + 重复组管理 + 取消扫描 | hash/pHash | — |
| PHO-20 | 系统相册访问（photo_manager，移动端本地库） | MobileGalleryFS | — |
| PHO-21 | 自动/增量扫描（先读 SQLite 缓存，新文件增量 upsert，边扫边显示每 50 张） | PhotoEntity | SRC-30 |
| PHO-22 | 地点（EXIF GPS）查看 / 地图聚类展示【规划】 | lat/lng | PHO-18 |
| PHO-23 | 隐藏照片【规划】（isHidden 逻辑删除，单独隐藏相册） | isHidden | — |
| PHO-24 | 照片回收站【规划】（deletedAt 逻辑删除 + 恢复） | deletedAt | — |
| PHO-25 | 照片编辑【规划】（裁剪/旋转/滤镜/标注） | editImage | — |
| PHO-26 | 修改 EXIF/元数据【规划】（拍摄日期/GPS/标签） | editExif | — |
| PHO-27 | 导出照片【规划】（批量导出本地目录/打包压缩） | export | XFER-* |
| PHO-28 | 设为壁纸【规划】（桌面/锁屏） | setWallpaper | — |
| PHO-29 | 批量分类【规划】（移动到相册/打标签） | moveToAlbum/tags | — |
| PHO-30 | 自动备份【规划】（按计划上传新照片到 NAS 目录 + 备份策略：目标/频率/条件） | BackupPolicy | XFER-01 |
| PHO-31 | 分页/无限滚动加载【规划】（大库分页避免一次全载） | pageSize/offset | — |
| FACE-01 | 人脸检测（TFLite BlazeFace / ML Kit 定位人脸框） | FaceEntity/FaceBox | — |
| FACE-02 | 特征提取（MobileFaceNet 128 维向量） | embedding | — |
| FACE-03 | 人脸聚类（欧氏距离分组 → 人物簇） | PersonEntity | — |
| FACE-04 | 人物浏览（人物卡片 → 该人物全部照片） | PersonEntity | — |
| FACE-05 | 人物命名（编辑名字）+ 代表头像（自动/指定） | name/representativeFaceId | — |
| FACE-06 | 识别进度流（已处理/总数 + 检测人脸数）+ 后台 compute 隔离 | FaceProcessProgress | — |
| FACE-07 | 物体识别【规划】（ML Kit/TFLite 通用物体检测 → object_labels） | labels | — |
| FACE-08 | 智能分类/场景标签【规划】（人物/风景/食物等自动归类） | category/tags | FACE-07 |

**交互·状态·菜单：** 查看器控制层自动隐藏 + 顶/底信息栏；多选浮出批量条；人物页可重命名/合并人物；重复检测页三模式 tab + 扫描进度 + 重复组批量删非主副本；人脸/哈希扫描在后台跑且可取消，有进度流；空态引导映射照片媒体库或开系统相册权限。

### 2.9 漫画阅读 (CMC)

| ID | 功能 | 数据/状态 | 关联 |
|----|------|----------|------|
| CMC-01 | 漫画库扫描/缓存（递归识别文件夹/压缩包，增量，监听媒体库变化） | ComicItem | SRC-30 |
| CMC-02 | 书架分组（按源）+ 搜索 + 详情（页数/大小/格式） | — | — |
| CMC-03 | 收藏/书签 + 移除库/删源文件 | mediaFavorites | SYNC |
| CMC-04 | 单页模式（PhotoView 缩放平移） | currentPage | — |
| CMC-05 | 双页模式（并排，RTL 自动交换） | totalDoublePages | — |
| CMC-06 | 长条 Webtoon 模式（垂直滚动 + 页间距） | scrollOffset/gap | — |
| CMC-07 | 阅读方向（LTR/RTL/垂直） | ReadingDirection | — |
| CMC-08 | 缩放模式（适应宽/高/屏/原始） | ScaleMode | — |
| CMC-09 | 背景色（黑/深灰/灰/白） | BackgroundColor | — |
| CMC-10 | 点击翻页（左右上翻下翻、中间控制栏）+ 快捷键（前后/首尾/菜单/设置） | tapZones/shortcuts | — |
| CMC-11 | 页面列表抽屉（网格缩略图跳页）+ 进度条滑块跳页 | pages/currentPage | — |
| CMC-12 | 进度续读（离开保存，重入恢复） | ReadingProgress | RD-* |
| CMC-13 | 屏幕常亮 | keepScreenOn | — |
| CMC-14 | 压缩包解压：CBZ(zip 纯Dart)/CBR(rar 桌面系统命令)/CB7(7z 桌面系统命令)，图片过滤+排序 | ArchiveExtract | FILE-23 |
| CMC-15 | 资源加载（文件夹漫画 SMB/WebDAV 流式逐页 + 压缩包内存加载 + 相邻页预加载） | StreamImage | — |

**交互·状态·菜单：** 阅读器顶/底栏可隐藏（中间区点击切换）；设置面板（方向/缩放/背景/页间距/常亮）；解压/加载有进度与失败重试；书架项右键（阅读/收藏/详情/移除/删除）。

### 2.10 电子书阅读 (BK)

| ID | 功能 | 数据/状态 | 关联 |
|----|------|----------|------|
| BK-01 | 格式：EPUB(原生 foliate / WebView foliate.js)、PDF(pdfrx 流式)、TXT(编码推断)、MOBI/AZW3(转 EPUB/文本)；扩展名自动识别 | BookFormat | — |
| BK-02 | 字号/字体/行距/段间距/页边距 调整 | BookReaderSettings | RD-* |
| BK-03 | 阅读主题（白/护眼绿/夜间黑/纯黑 + 自定义前景色） | BookReaderTheme | — |
| BK-04 | 翻页模式（滚动/滑动/仿真/覆盖）+ 点击翻页（左中右）+ 音量键翻页 | PageTurnMode | — |
| BK-05 | 目录导航（章节树跳转） | TocItem | — |
| BK-06 | 进度条（页码/百分比）+ 进度自动保存（位置/章节/时间戳，多格式 CFI/页号/进度值） | ReadingProgress | RD-* |
| BK-07 | 书签（增删 + 备注） | Bookmark | RD-* |
| BK-08 | TTS 朗读（Edge TTS，100+ 语音，0.5–2x 速率，音量，浮窗控制，朗读高亮句子，文本净化） | TTSSettings | SET-BOOK |
| BK-SRC-01 | 在线书源管理（导入/编辑/启用/禁用 Legado 格式 + 搜索书源） | BookSource | SET-BOOK、SYNC |
| BK-SRC-02 | 书源规则引擎（搜索/探索/正文/目录 CSS-XPath 提取 + 净化替换） | Rules | — |
| BK-SRC-03 | 在线阅读（WebView 渲染在线章节）+ 在线书加入本地书架 | OnlineBook | — |
| BK-09 | EPUB 图片提取 + 封面缓存/预加载 | EpubImageExtractor | — |
| BK-10 | 缓存（文件流式缓存防 OOM、库缓存 24h、SQLite 元数据、大文本渐进分页） | Book*CacheService | CACHE-* |
| BK-11 | 笔记/高亮标注【规划】（划线高亮 + 想法批注） | annotation | — |

**交互·状态·菜单：** 阅读器中央点击呼出/隐藏控制层；设置抽屉（字号/字体/主题/翻页/边距）；目录与书签抽屉；TTS 浮窗（播/停/快进退/语音选择/速率）；分页/加载有进度。

### 2.11 阅读聚合 (RD) 与笔记 (NOTE)

| ID | 功能 | 数据/状态 | 关联 |
|----|------|----------|------|
| RD-01 | 三标签聚合（图书/漫画/笔记统一入口） | readingTab | BK/CMC/NOTE |
| RD-02 | 统一阅读进度模型（itemType=book/comic/epub/pdf 共享 ReadingProgress） | ReadingProgress | SYNC |
| RD-03 | 本地/书源 搜索切换 | BookSearchMode | BK-SRC-* |
| RD-04 | 全局阅读设置管理（漫画/图书设置 Hive 持久化，新书继承上次设置） | ReaderSettings | — |
| RD-05 | 阅读历史/统计【规划】（最近阅读、阅读时长聚合书架） | aggregate | RD-02 |
| NOTE-01 | Markdown 编辑器（编辑/实时预览切换，实时自动保存，未保存提示） | NoteItem.content | — |
| NOTE-02 | 待办解析（从 `- [ ]` 抽取任务）+ 待办清单 UI（勾选/进度统计） | TaskItem/TaskStatus | — |
| NOTE-03 | 任务优先级（普通/重要/紧急）+ 截止日期 + 逾期提示 + 完成统计 | TaskItem | — |
| NOTE-04 | 多层目录树（文件夹/笔记嵌套，展开折叠） | NoteTreeNode | — |
| NOTE-05 | 笔记扫描（递归 Markdown/TXT）+ 搜索（名/全文）+ 标签 + 排序 | NoteItem | — |
| NOTE-06 | 笔记同步（状态：最后打开/滚动位置；书签：行号+备注并集；冲突取较新） | NoteSyncModule | SYNC |

**交互·状态·菜单：** 笔记列表/目录树双栏；编辑器编辑↔预览切换；任务勾选实时更新进度；离开未保存提示；笔记项右键（重命名/删除/标签/移动）。

### 2.12 下载客户端集成 (ARIA / QBT / TRM)

| ID | 功能 | 数据/状态 | 关联 |
|----|------|----------|------|
| ARIA-01 | aria2 连接配置 + 状态轮询 | Aria2ConnectionStatus | SRC-T18 |
| ARIA-02 | 任务列表（2s 刷新）+ 全局统计（总下/上速、数量） | Aria2Download/GlobalStat | — |
| ARIA-03 | 添加任务（URI/磁力/HTTP，指定 dir/filename）→ GID | addUri | PT-08 |
| ARIA-04 | 暂停/恢复单个 + 全部 + 删除 + 清除结果 | gid | — |
| ARIA-05 | 排序（名/大小/进度/状态/速度）+ 状态过滤 | SortMode/Filter | — |
| ARIA-06 | 全局限速【受限：UI 实现，非 aria2 原生】 | — | — |
| QBT-01 | qBittorrent 连接（登录/登出/自动重连） | QBConnectionStatus | SRC-T16 |
| QBT-02 | 种子列表（3s 刷新）+ 传输统计 | QBTorrent/TransferInfo | — |
| QBT-03 | 添加种子（URL/磁力/文件上传，分类，暂停添加） | addTorrent | PT-08 |
| QBT-04 | 暂停/恢复（单/批/全）+ 删除（含删文件）+ 重命名 | hashes | — |
| QBT-05 | 分类管理（建/设保存路径/归类） | QBCategory | — |
| QBT-06 | 标签管理（建/加/移除） | tags | — |
| QBT-07 | 设置保存位置（单/批量） | location | — |
| QBT-08 | 全局限速 + 备用限速切换/设置 | dl/upLimit | — |
| QBT-09 | 偏好设置读取（端口/限速等） | QBPreferences | — |
| QBT-10 | 排序（名/大小/进度/状态/速度/时间/比率/ETA）+ 分类/标签过滤 | SortMode/filter | — |
| TRM-01 | Transmission 连接（会话验证） | TransmissionConnectionStatus | SRC-T17 |
| TRM-02 | 种子列表（3s 刷新）+ 会话统计 | TransmissionTorrent/Stats | — |
| TRM-03 | 添加（URL/磁力/文件，下载路径，暂停） | addTorrent | PT-08 |
| TRM-04 | 启动/停止（单/批/全）+ 删除（含删文件）+ 验证数据 | ids | — |
| TRM-05 | 全局限速 | — | — |
| TRM-06 | 排序（名/大小/进度/状态/速度/时间/比率/上传量）+ 状态过滤 | SortMode | — |
| TRM-07 | 单种子限速【受限：Transmission 原生不支持】 | — | — |

**交互·状态·菜单：** 三客户端共享一致的任务管理形态（顶部统计条 + 任务列表 + 排序/过滤 + 批量操作）；种子行右键（暂停/继续/删除/删文件/重命名/分类/标签/保存位置/验证）；连接失败有重连入口；空态引导添加对应下载器源。

### 2.13 PT 站点 (PT) / NAStool (NT) / 媒体管理-追踪 (MM / TRK)

| ID | 功能 | 数据/状态 | 关联 |
|----|------|----------|------|
| PT-01 | 站点连接（API Key/Cookie）+ 认证失败检测 + 用户信息 | PTSiteConnection | SRC-T22 |
| PT-02 | 种子搜索（关键词/分页/分类/排序）+ 最新种子列表（加载更多） | PTTorrent | — |
| PT-03 | 种子详情（IMDB/豆瓣 ID、描述、标签） | detailUrl | — |
| PT-04 | 分类列表 | PTCategory | — |
| PT-05 | 用户信息（等级/上下传/分享率/魔力/邀请） | PTUserInfo | — |
| PT-06 | 签到【规划：桌面页仅 plan 占位标签，未实现】/ 传输统计（做种/下载/已完成/H&R）/ 做种统计 | PTTransferStats/Log | — |
| PT-07 | 免费/折扣标签（Free/2xFree/50%↓/2x↑ + 剩余免费时间） | promotionLabel | — |
| PT-08 | **发送到下载器**（一键推送种子到 aria2/qBittorrent/Transmission） | send_to_downloader | ARIA/QBT/TRM-03 |
| NT-01 | NAStool 连接 + 媒体库统计（电影/剧集/番剧数） | NasToolConnection/Stats | SRC-T20 |
| NT-02 | 订阅列表（电影/剧集，进度 当前集/总集）+ 添加订阅（年份/季/搜资源）+ 删除 | NtSubscribe | — |
| NT-03 | 搜索资源（PT/RSS）→ 下载任务列表（进度/速度/ETA，启停删）+ 下载历史 | NtDownloadTask/History | — |
| NT-04 | 站点管理（列表/测试）+ 站点统计（上下传/分享率/做种） | NtSite/Statistics | — |
| NT-05 | 转移历史（整理/刮削历史） | NtTransferHistory | — |
| NT-06 | 刷流任务（获取/运行/统计） | NtBrushTask | — |
| NT-07 | RSS 任务（列表/预览文章）+ RSS 解析器管理 | NtRssTask/Parser | — |
| NT-08 | 插件管理（已装/商店安装-卸载） | NtPlugin | — |
| NT-09 | 目录同步（配置/执行）+ 库刷新 + 重启服务 + 检查更新 + 系统信息（版本/磁盘空间） | NtSyncDir/SystemInfo | — |
| MM-01 | 媒体管理工具统一入口（NAStool/MoviePilot 源配置 + 增删改） | mediaManagement | SRC-T20/21 |
| MM-02 | MoviePilot 订阅/自动化【规划：与 NAStool 对齐】 | API Token | SRC-T21 |
| TRK-01 | Trakt 连接（OAuth2 设备码/深链回调 + Token 自动刷新）+ 用户统计 | TraktConnectionState | SRC-T19、SYS-03 |
| TRK-02 | 播放进度同步（拉在看清单 + 进度%；删进度记录） | TraktPlaybackItem | VID-05 |
| TRK-03 | 观看历史 + 待看清单（想看） | TraktHistory/Watchlist | — |
| TRK-04 | 按 TMDB/IMDB ID + 季/集 匹配本地视频进度；进度%↔时长换算 | tmdbId/imdbId | VID-SCR-* |
| TRK-05 | "继续观看"合并视图（本地播放历史 + Trakt 进度，本地优先，偏好语言标题） | ContinueWatchingItem | VID-06、§1.3 影视 |
| TRK-06 | Trakt 自动上报（开始/暂停/停止；进度≥80% 自动标记已看） | TraktScrobble | VID-06 |

**交互·状态·菜单：** PT 种子行 → 详情 / 发送到下载器（选目标客户端 + 分类/路径）；NAStool 各子功能可视为子页（订阅/下载/站点/刷流/RSS/插件/同步/系统）；Trakt 连接走系统浏览器授权回调；列表统一加载/空/错误态。

### 2.14 云同步 (SYNC) — 基于 WebDAV

| ID | 功能 | 数据/状态 | 关联 |
|----|------|----------|------|
| SYNC-01 | WebDAV 后端配置（endpoint/user/pwd/rootPath，默认 `/my-nas-sync`） | CloudSyncSettings | — |
| SYNC-02 | 模块开关（音乐收藏/歌单/音乐设置/视频收藏/视频进度/阅读进度/书源/笔记/应用设置） | enabledModuleKeys | MUS/VID/RD/NOTE/APP |
| SYNC-03 | 手动「立即同步」+ 进度/结果（pulled/pushed/skipped/failed） | CloudSyncOutcome | — |
| SYNC-04 | 自动同步（启动/定时，可选） | — | SYS-01 |
| SYNC-05 | 冲突处理（manifest.json 时间戳对比，"最后修改优先"，单模块失败重试 3 次） | manifest | — |
| SYNC-06 | 健康检查（测 WebDAV 连接） | healthCheck | — |

**交互·状态·菜单：** 配置后显示上次同步时间 + 各模块状态；同步中显示逐模块进度；失败给错误报告。

### 2.15 应用锁/安全 (LOCK) 与缓存 (CACHE)

| ID | 功能 | 数据/状态 | 关联 |
|----|------|----------|------|
| LOCK-01 | 应用锁启用/关闭 | enabled | SET-SEC |
| LOCK-02 | PIN（4–6 位）设置/修改 | Hive | — |
| LOCK-03 | 生物识别（指纹/面容，平台支持时） | local_auth | — |
| LOCK-04 | 自动锁定超时（立即/1min/5min/15min/仅退出时）+ 后台进前台校验 | AppLockTimeout | SYS |
| LOCK-05 | 解锁页（PIN/生物识别） | UnlockPage | — |
| CACHE-01 | 三类缓存（媒体/音乐音频/图书）聚合视图 | allCachedItems | MUS-19/PHO/BK |
| CACHE-02 | 缓存统计（每类项数 + 总大小） | cacheStats | — |
| CACHE-03 | 缓存上限配置（每类大小上限，超限 LRU 清理） | CacheConfig | — |
| CACHE-04 | 删除单项 / 按类型清空 / 全清 | deleteCache | SET-ADV |

### 2.16 投屏 (CAST)

| ID | 功能 | 数据/状态 | 关联 |
|----|------|----------|------|
| CAST-01 | DLNA 设备发现 + 选择 + 投出当前播放（音乐/视频） | CastDevice/Session | MUS-*/VID-* |
| CAST-02 | 投屏远程控制（播/停/音量/进度） | playback state | CAST-01 |
| CAST-03 | 本地媒体代理服务器（shelf，为 SMB 等不可直链协议给投屏设备提供 HTTP 代理） | proxyUrl | MediaProxyServer |
| CAST-04 | AirPlay 音频路由（iOS/macOS） | CastDevice(airplay) | MUS-OUT-01 |
| CAST-05 | 投屏状态显示（底栏/播放器高亮 cast icon） | isCastingMode | NP-* |

### 2.17 播放器/正在播放 形态 (NP) 与桌面歌词 (DLY)

| ID | 形态 | 用途 / 触发 |
|----|------|------------|
| NP-MusicMini | 音乐底栏迷你条（传输键+进度+二级控件，主界面常驻不可关） | 有播放即显示 |
| NP-MusicFull | 音乐全屏播放器（大封面+歌词+队列入口，`/music/player`） | 底栏/深链 |
| NP-VideoPlayer | 视频播放器（控制条 + 字幕/音轨/倍速/比例/投屏/PiP/剧集导航） | 点视频 |
| NP-VideoFull | 视频全屏 | 全屏键 |
| DLY-01 | 桌面歌词独立浮窗（macOS/Windows，透明/可锁定点击穿透） | SYS-12 / 快捷键 / 菜单栏 |
| DLY-02 | 桌面歌词布局（单/双行/纵向）+ 色板 + 字号缩放 + 背景开关 + 内嵌 prev/play/next | DesktopLyricProvider |

---

## 3. 功能关联图（数据流要保留）

```
用户操作
 ├── 添加源 (SRC-01..) → SourceManager → (媒体库目录映射 SRC-30)
 │         │                                   ↓
 │         │                          各库扫描(PHO-21/CMC-01/BK/VID/MUS) → SQLite/Hive 缓存
 │         │                                   ↓
 │         │                          刮削(VID-SCR/MUS-24) + 人脸 AI(FACE-*) + 缩略图/封面缓存
 │         └── 凭据 → flutter_secure_storage（失败静默降级）
 │
 ├── 文件浏览 (FILE-*) ──┬→ 播放(MUS/VID) → 本地媒体代理(CAST-03) → 投屏(CAST-01)
 │                       ├→ 阅读(CMC/BK) → 统一阅读进度(RD-02)
 │                       ├→ 照片(PHO-*) → 人脸(FACE) / 物体识别【规划 FACE-07】
 │                       └→ 上传/下载/缓存(XFER-*) / 直链下载(DL-*)
 │
 ├── 播放 → 播放历史(MUS-26/VID-06) → 统计(MUS-STAT) / Scrobble(MUS-SCROB) / Trakt(TRK-*)
 │            └→ 歌词(LYR-*) → 迷你/全屏/桌面歌词(NP/DLY)
 │
 ├── PT 站点(PT-*) → 发送到下载器(PT-08) → aria2/qBittorrent/Transmission(ARIA/QBT/TRM)
 │            └→ NAStool 订阅/搜索(NT-*) → 下载 → 转移整理 → 媒体库刮削 → Trakt 同步
 │
 ├── 设置(SET-*) → Hive / SecureStorage / 各 Provider → 对应服务
 │
 └── 云同步(SYNC-*) ←→ WebDAV manifest ←→ 其他设备（歌单/进度/收藏/书源/笔记/设置）
```

**关键不可破坏的关联：**
1. **媒体库目录映射 (SRC-30)** 是所有媒体库的数据来源——删源级联删该源媒体与映射。
2. **本地媒体代理 (CAST-03)** 是 SMB 等非直链协议能投屏/被 media_kit 播放的前提。
3. **统一阅读进度 (RD-02)** 漫画/图书/PDF 共享；书签系统图书/漫画共用。
4. **"继续观看" (TRK-05)** 合并本地播放历史与 Trakt 远端进度，本地优先。
5. **PT → 下载器 (PT-08)** 一键发送，目标是三个下载客户端之一。
6. **凭据存储失败要静默降级**，不能阻塞 app。
7. **UI 风格 (APP-02 classic/glass)** 是真实持久化开关，两套设计都要成立。
8. **云同步 (SYNC)** 走 WebDAV manifest 时间戳，非 CloudKit；冲突"最后修改优先"。
9. **OAuth（Trakt 等）** 走系统浏览器 + `mynas://` 回调，不嵌 WebView。
10. **桌面歌词 (DLY)** 在 macOS/Windows 独立浮窗，锁定后点击穿透仍需有解锁入口。
11. **【规划】功能**（人脸物体识别/照片编辑/自动备份/回收站/笔记高亮/年度报告/绿联飞牛 NFS 源等）需在设计里**预留入口与状态**（可显示"即将推出"占位或可见但置灰），不要因未实现而省略。

---

## 4. 桌面平台关键约束

### 4.1 布局与窗口
- 桌面布局断点 `≥ 1200px`；Rail 展开断点 `≥ 1100px`。
- 主窗口几何记忆（最小 1024×720，默认 1280×800），跨 macOS/Windows/Linux。
- 桌面密度：AppBar 48px、ListTile dense、Dialog 小圆角、SnackBar 限宽 480px。
- 设置桌面形态建议"左 section 列表 + 右详情卡片"双栏。

### 4.2 两套视觉版本（A 玻璃 / B 经典）
- **A 套 · 玻璃 (glass)**：`BackdropFilter` 模糊 + 半透明 + tint + 可选描边发光（`GlassStyle`）。建议铺在：导航 Rail、播放器底栏/控制条、浮层（迷你播放器/桌面歌词/菜单/sheet）。
  - 平台优化：macOS 原生级模糊；Windows 降低模糊强度；Linux 视性能降级；Web 禁用模糊；模糊层数受控。
  - 降级策略：用 `PlatformGlassConfig` 在不支持/低性能平台自动落回经典材质。
- **B 套 · 经典 (classic)**：不透明卡片 `surface/secondary` + 阴影 + 圆角；**禁用玻璃形变动画**（改阴影 + opacity 渐入）；减少层叠透明。
- **信息层级两套一致**：导航/控制条/卡片/列表的视觉重量级关系不变，只换材质。

### 4.3 桌面系统集成
- macOS：Spotlight 索引(SYS-05)、透明标题栏选项、桌面歌词浮窗。
- Windows：Jump List(SYS-06)、任务栏集成、最小化到托盘。
- Linux：标准窗管集成、系统托盘。
- 通用：窗口几何记忆、深链 `mynas://`(SYS-03)、应用更新下载(SYS-09)。

### 4.4 键盘 / 快捷键（保留并尽量补全桌面常用项）
- 媒体：播放/暂停、上/下一首、音量加减、倍速、全屏。
- 照片查看器：←→ 翻页、Home/End、Space 覆盖层、L 收藏、I 信息、Esc、? 帮助。
- 漫画/图书：前后页、首尾页、菜单切换、设置、目录。
- 桌面歌词：显示/隐藏、锁定切换。
- 通用：设置、搜索、Esc 收起浮层。

### 4.5 持久化键（保留命名）
- `theme_mode` / `color_scheme_preset` / `ui_style` / `ui_style_user_set`
- `language_preference`
- `app_lock_settings`(enabled/biometricEnabled/timeout)
- `desktop_window_width|height|offset_x|offset_y|maximized`
- `music_settings` / `video_quality_settings` / `music_favorites` / `media_favorites`
- `cloud_sync_settings`(endpoint/username/password/rootPath/enabledModuleKeys/lastSyncedAt)

### 4.6 i18n
- 用户可见字符串走本地化（中/英，`lib/l10n` arb）；音频/字幕/元数据三类语言优先级可拖拽排序。不要硬编码。

---

## 5. 你的设计任务

基于上面功能清单，输出**两套并列**的 MyNAS **桌面端**重设计方案（桌面优先，说明与移动共享的 IA）。

### 通用规则
- **覆盖 §2 全部 ID（含【规划】项）**：每个功能点都要落到某屏/组件/状态。【规划】项要画出入口与占位（可标"即将推出"或可见置灰），不得省略。
- 给一张 **ID → 屏/组件/状态 对照表**（覆盖全部 ID，标注是否【规划】）。
- 覆盖每个域的 **空态 / 加载态(Skeleton) / 错误态 / 多选态 / 右键-上下文菜单 / 对话框**。
- 不要新增功能、也不要删功能 —— 仅做视觉与信息组织的重设计。

### A 套 · 玻璃版 (Glass)
- 自由发挥 `BackdropFilter` 玻璃层叠/半透明/浮层（导航、播放控制、浮窗、sheet）。
- 必须保留 §1.2 §1.4 §1.5 的工具区/二级/三级入口。
- 明确写出玻璃用在哪些组件、以及在低性能/不支持平台经 `PlatformGlassConfig` 如何降级。

### B 套 · 经典版 (Classic)
- 不透明卡片 + 阴影 + 圆角 fallback，**信息架构与 A 套一致**，只换视觉表层。

### 关键场景视觉描述（两套各至少 10 张）
1. 桌面空态（未加源引导）
2. 影视库（海报网格 + 继续观看行 + 筛选）
3. 视频播放器（字幕/音轨/倍速/比例/投屏/PiP/剧集导航）+ 影视详情页（剧集分季）
4. 曲库多视图 + 音乐全屏播放器（歌词三态）
5. 相册时间线 + 大图查看器
6. 相册人物页（人脸聚类）+ 重复检测三模式
7. 阅读：漫画双页/Webtoon + 图书阅读器（设置抽屉/TTS 浮窗）+ 笔记（目录树 + Markdown + 待办）
8. 下载器（aria2/qBittorrent/Transmission 任务管理）+ PT 站点（种子列表 + 发送到下载器）
9. 传输/下载队列（三类任务 + 并发 + 进度）
10. 设置（左 section 右详情）+ 连接源管理（添加源动态表单 + 2FA + 状态）+ NAStool 子功能面板
- 额外建议补：桌面歌词三布局、投屏设备选择器、媒体库目录映射、云同步状态、应用锁解锁页、各【规划】功能的占位形态。
```
