# MyNAS 开发任务进度

> 最后更新：2026-07-11
> ✅ 已完成 / 🚧 部分完成 / 📝 规划中 / ❌ 已放弃

## 阶段总览

```
Phase 1: 基础架构     ████████████████  ✅ 完成
Phase 2: 核心功能     ████████████████  ✅ 完成（持续打磨）
Phase 3: 平台优化     ██████████████░░  🚧 进行中（多数已完成，少数 backlog）
Phase 4: 生态扩展     ██████████░░░░░░  🚧 进行中（媒体服务器/PT/Trakt 已加入）
```

---

## Phase 1: 基础架构 ✅

### 1.1 项目初始化 ✅
- [x] Flutter 项目创建与多平台配置（iOS/Android/macOS/Windows/Linux）
- [x] 依赖管理（pubspec + lockfile）
- [x] 代码规范（analysis_options.yaml + 自定义禁用规则）
- [x] CI 静态检查
- [x] Git pre-commit hooks（仓库内置 `.githooks/pre-commit`，运行 `script/setup_git_hooks.sh` 启用）

### 1.2 核心基础设施 ✅
- [x] 网络层（DioClient + 拦截器 + 自签证书可选）
- [x] 本地存储（Hive + SQLite + AES Cipher Box）
- [x] 凭证存储（FlutterSecureStorage + Keychain 降级到 Hive AES）
- [x] 路由（自研 Routes 类）
- [x] 错误处理机制（AppError 统一工具类，移除远程上报）
- [x] 日志系统（基于 logger，按级别输出）
- [x] AppError.guard / fireAndForget / ignore 全员推广

### 1.3 主题与设计系统 ✅
- [x] Material 3 主题
- [x] 亮/暗 / 系统跟随
- [x] iOS 26 Liquid Glass 模式
- [x] AppColors / AppSpacing 设计 token
- [x] 通用组件（按钮 / 卡片 / 输入 / 对话框 / 加载 / 空 / 错误状态）
- [x] 自适应布局（手机 / 平板 / 桌面）

### 1.4 NAS 适配器抽象 ✅
- [x] NasFileSystem 抽象接口
- [x] NasAdapter / NasConnection / FileItem / ThumbnailSize 等基础实体
- [x] 适配器工厂模式
- [x] 连接管理器 + 自动重连

---

## Phase 2: 核心功能 ✅（持续打磨）

### 2.1 连接管理 ✅
- [x] 多源管理（NAS / 媒体服务器 / 下载器 / 字幕站）
- [x] 连接状态监控
- [x] 自动重连 + 心跳保活（SMB 连接池）
- [x] 连接历史 + 凭证持久化

### 2.2 NAS 协议适配

| 协议 | 状态 |
|---|---|
| SMB / CIFS（含 SMB3.1.1） | ✅ 含连接池 + 客户端 fallback（copy/search/url-stream） |
| WebDAV | ✅ |
| Synology DSM 6/7 | ✅ File/Video/Audio/Photos Station + QuickConnect + 二次验证 |
| 飞牛 fnOS | ✅ 含服务端 copy/upload/search + 客户端 fallback |
| 绿联 UGOS | ✅ 含 RSA 加密登录 + 客户端 fallback |
| 本地文件系统 | ✅ |
| 移动端虚拟 fs | ✅（手机本地音乐 / 相册 / 文件） |

### 2.3 媒体服务器适配 ✅

| 服务器 | 认证 | WebSocket | 进度同步 | 备注 |
|---|---|---|---|---|
| Jellyfin (10.8+) | 用户名密码 / API Key / Quick Connect | ✅ 14 种事件 | ✅ | |
| Emby (4.6+) | 用户名密码 / API Key | ✅ 18 种事件 | ✅ 含音轨/字幕索引 | deviceId 持久化 |
| Plex | PIN 授权 | ❌（协议限制） | ✅ | getNextUp 含 viewOffset 优先 |

### 2.4 文件浏览器 ✅
- [x] 列表 / 网格视图 + 切换记忆
- [x] 文件类型识别 + 图标
- [x] 面包屑导航
- [x] 排序（名称 / 大小 / 修改时间） + 筛选
- [x] 搜索（服务端优先 + 客户端 BFS fallback）
- [x] 收藏
- [x] 下拉刷新
- [x] 分享（远端文件流式下载到本地后 Share.shareXFiles）
- [x] 复制 / 移动 / 重命名 / 删除
- [x] 上传（含进度回调）
- [x] 目录选择器（浏览树形结构 + 新建文件夹）

### 2.5 视频模块 ✅
- [x] media_kit 播放器核心
- [x] 视频列表 + 详情页
- [x] 控制栏 + 手势进度 / 亮度 / 音量
- [x] 字幕加载 + 样式 + **延迟（NativePlayer.setProperty）**
- [x] 在线字幕搜索（OpenSubtitles）
- [x] 音轨切换
- [x] 倍速 0.5x–4x
- [x] 画中画
- [x] 投屏（AirPlay / DLNA / Chromecast）
- [x] **DLNA 字幕扩展**（三星 sec / 通用 res / Sony pv 三套兼容）
- [x] 观看历史
- [x] 进度本地 + 远程双向同步
- [x] 离线缓存
- [x] 客户端转码（CPU / Android MediaCodec / Apple VideoToolbox）
- [x] TMDB 元数据刮削
- [x] 豆瓣评分整合
- [x] NFO 解析
- [x] 系列 / 季 / 集组织
- [x] 推荐 / 相似内容（TMDB）
- [x] **TMDB 推荐 → PT 站搜索一键跳转**

### 2.6 音乐模块 ✅
- [x] just_audio + media_kit 双引擎
- [x] 音乐库（艺术家 / 专辑 / 歌曲 / 播放列表）
- [x] 收藏 / 历史
- [x] 正在播放 + 迷你播放器
- [x] 歌词（LRC 解析 + 内嵌 + 外挂）
- [x] **桌面歌词**（Windows/macOS/Linux 原生窗口）
- [x] 后台播放 + 锁屏 + 媒体键
- [x] iOS Now Playing / Android 灵动岛 / macOS Media Widget
- [x] 播放队列 + 随机 / 循环 / 单曲
- [x] **元数据写入**（audiotags + ffmpeg + tone 三引擎，覆盖 DSD/无损/有损）
- [x] **NCM 加密格式解密**
- [x] 自动刮削（封面 / 歌词 / 标签）
- [x] **10 段均衡器**（Android AudioEffect；桌面端 mpv audio filter）
- [x] **交叉淡入淡出**（可配置时长，预加载辅助播放器）

### 2.7 漫画模块 ✅
- [x] 图片阅读器
- [x] 单页 / 双页 / 长条模式
- [x] 左右翻页方向
- [x] 手势缩放与翻页
- [x] 进度记忆
- [x] CBZ / ZIP / RAR / 7Z 解析
- [x] 智能预加载

### 2.8 书籍模块 ✅
- [x] EPUB（epubx + flutter_html / WebView 双模式）
- [x] PDF（pdfrx）
- [x] MOBI / AZW3（自研解析）
- [x] TXT
- [x] 字体 / 字号 / 行距 / 主题（日 / 夜 / 护眼 / 纯黑）
- [x] 目录导航 + 章节跳转
- [x] **书签**（reading_progress_service.Bookmark）
- [x] 进度同步
- [x] TTS 朗读
- [x] 在线书源（兼容 Legado JSON / XPath / JSONPath / CSS / 正则）
- [x] **应用不内置任何书源 + 导入界面免责声明（合规）**
- [x] **书源编辑**（JSON 编辑对话框）

### 2.9 笔记模块 🚧
- [x] Markdown 渲染（任务列表 / 代码块 / 表格 / 图片）
- [x] 笔记目录树形浏览
- [x] **笔记搜索**（递归过滤已加载节点）
- [x] 阅读进度记忆
- [x] Markdown 编辑与写回（格式工具栏 / 实时预览 / 附件上传 / 未保存提醒）
- [x] 多设备写入冲突解决（保存前版本检测，可选择重新加载或覆盖远端）

### 2.10 相册模块 ✅
- [x] 相册浏览
- [x] EXIF 元数据
- [x] **人脸识别 + 人物聚合**
- [x] **人物相册导航**（点击人物头像跳到该人物所有照片）
- [x] 上传到 NAS
- [ ] 照片地图（未实现；入口已隐藏）

### 2.11 下载工具 ✅
- [x] qBittorrent 集成
- [x] Transmission 集成
- [x] **Aria2 集成**（JSON-RPC + token + pause 选项）
- [x] MoviePilot 集成
- [x] NASTool 集成
- [x] 统一发送下载器 sheet

### 2.12 PT 站集成 ✅
- [x] 通用 PT 站爬虫框架
- [x] 种子搜索 / 列表 / 详情
- [x] 推广标识
- [x] **视频 / 推荐 → PT 搜索一键跳转**（带年份）
- [x] **PT 搜索 → 一键发送下载器**

### 2.13 媒体追踪 ✅
- [x] Trakt.tv OAuth 授权 + 同步
- [x] 待看 / 在看 / 已看
- [x] 评分同步

---

## Phase 3: 平台优化与发布

### 3.1 平台特定 ✅（多数完成）

#### macOS ✅
- [x] 原生菜单栏
- [x] 触控板手势
- [x] 画中画
- [x] **Mac App Store 上架适配**（沙盒 / entitlements / 加密配置）
- [x] **Keychain 降级方案**（entitlement 缺失时 Hive AES box 兜底）
- [x] 桌面歌词原生窗口
- [x] **Spotlight 索引**（设置开关默认关；视频/音乐/书籍/漫画/笔记标题级元数据；点击系统聚焦结果跳回 App 对应入口）

#### Windows ✅
- [x] 媒体键支持
- [x] 任务栏
- [x] 系统主题跟随
- [x] 桌面歌词原生窗口
- [x] **跳转列表**（任务栏图标右键 Tasks 4 项 + Recent 最近 5 视频 / 5 音乐，单实例转发）

#### iOS ✅
- [x] AirPlay
- [x] Now Playing 信息
- [x] **灵动岛**
- [x] 媒体小组件
- [x] **麦克风 / 相机权限配置 + 应用签名**
- [x] **CarPlay**（音乐浏览：艺术家 / 专辑 / 歌单 / 收藏；需 `com.apple.developer.carplay-audio` entitlement）
- [ ] Siri 快捷指令
- [ ] Handoff

#### Android ✅
- [x] 媒体通知
- [x] 应用 ID + SDK 版本规范
- [x] 灵动岛风格通知
- [x] Android Auto（MediaBrowserService + automotive app descriptor；待 DHU / 真车验收）
- [x] 应用快捷方式（音乐 / 视频 / 阅读 / 下载四个静态启动器快捷方式）
- [x] 画中画
- [ ] 分屏适配专项验收

### 3.2 性能优化 ✅
- [x] 启动时间优化
- [x] ListView.builder 全员
- [x] 流式下载（避免大文件占内存）
- [x] 缓存策略（视频缩略图 / 元数据 / 图片）
- [x] 网络连接池（SMB / HTTP）

### 3.3 用户体验 🚧
- [x] 暗色 / 亮色 / 系统跟随
- [x] iOS 26 Liquid Glass
- [x] 触觉反馈（移动端）
- [x] 手势快捷操作（视频亮度 / 音量 / 进度）
- [x] 引导页 / 教程
- [ ] 完整无障碍（Semantics 标注未覆盖全部）

### 3.4 国际化 🚧
- [x] 多语言框架（flutter_localizations + intl）
- [x] 中文本地化
- [x] 英文本地化（中英文 ARB 消息键已对齐；仍需发布前 UI 巡检）
- [ ] RTL 支持

### 3.5 安全 ✅
- [x] **远程错误上报已移除**（避免客户端凭证泄露）
- [x] 凭证 SecureStorage + Keychain 降级
- [x] HTTPS / 自签证书可选信任
- [x] **不内嵌书源**（合规设计）
- [x] **公共 API key 用户可覆盖**（OpenSubtitles 等）
- [x] 应用锁（PIN / 生物识别 / 后台超时 / 切换器遮蔽）

### 3.6 测试 🚧
- [x] Widget 测试（核心组件）
- [x] 单元测试（解析器 / 工具类）
- [ ] 集成测试 / E2E 测试（已加入应用首帧 smoke test；NAS 连接 → 浏览 → 播放仍待自动化）
- [x] 性能测试基线（首个 10,000 行 Markdown 解析回归门槛）

### 3.7 发布准备 🚧
- [x] 应用图标
- [x] macOS Developer ID 签名与公证工作流配置
- [x] iOS Distribution 签名与 App Store Connect 上传工作流配置
- [x] Android 应用 ID
- [ ] 使用正式 Secrets 跑通 macOS 签名、公证、stapling 与 Gatekeeper 校验
- [ ] 使用正式 Secrets 跑通 iOS 签名与 App Store Connect 上传
- [ ] App Store / Google Play / Microsoft Store 发布资料（描述、截图、分类、分级、支持链接）
- [ ] 隐私政策（仓库已有 `PRIVACY.md` 草案，待填写主体/邮箱、公开部署与法律复核）

> “工作流已配置”不等于“某个发布产物已签名或已公证”。只有对应 CI job
> 使用正式凭据成功完成并通过验证，才能将该次产物标记为可分发。

### 3.8 发布前遗留清单 🚧

- [x] 笔记 Markdown 编辑、保存与附件
- [x] 笔记多设备写入冲突处理
- [ ] 完整无障碍（Semantics、键盘导航、屏幕阅读器与对比度）
- [ ] RTL 布局与镜像行为
- [ ] 隐私政策及商店隐私披露（草案已完成，待公开 URL 与最终构建复核）
- [ ] 各商店发布资料与审核信息（中英文文案和清单已完成，待截图/网址/联系信息）

---

## Phase 4: 生态扩展（持续）

### 已完成
- [x] **Plex / Emby / Jellyfin 三套媒体服务器适配**
- [x] **MoviePilot 集成**
- [x] **NASTool 集成**
- [x] **Trakt 媒体追踪**
- [x] **OpenSubtitles 字幕站**
- [x] **客户端转码（多平台硬解码）**
- [x] **TMDB 推荐 / 相似 → PT 搜索串联**
- [x] **AI 字幕翻译**（视频字幕菜单按需翻译为目标语言、增量注入、落盘缓存）

### Backlog
- [ ] 威联通 QNAP / 铁威马 NAS 适配
- [ ] AI 元数据补全
- [ ] 智能推荐（基于观看历史本地建模）
- [ ] 插件系统（第三方扩展）
- [ ] 自托管同步服务（书签 / 进度跨设备）
  - [x] 视频播放进度 + 已观看状态接入 WebDAV 同步模块
  - [x] 笔记阅读位置 + 书签数据层接入 WebDAV 同步模块

---

## 里程碑回顾

| 里程碑 | 状态 | 完成时间 |
|---|---|---|
| **M1: 可运行** | ✅ | 已达成 |
| **M2: 可连接** | ✅ | 已达成（多源 + 媒体服务器） |
| **M3: 可播放** | ✅ | 已达成（视频 / 音乐 / 漫画 / 书） |
| **M4: 核心功能完整** | 🚧 | PT / 下载 / 刮削 / 投屏 / 字幕 / 笔记写回已完成；无障碍与 RTL 仍在 backlog |
| **M5: 可发布** | 🚧 | 签名/公证工作流已配置，待正式凭据实跑、隐私政策与商店资料 |
| **M6: 正式发布** | 📝 | 待 M5 完成 |

---

## 近期工作记录（2026-04 后半月）

- **2026-04-29** Plex `getNextUp(seriesId)` 算法补全（On Deck 优先 + 季层遍历）；三个媒体服务器适配器统一错误处理至 AppError；视频详情/推荐 → PT 搜索串联（含年份策略 + 多站点选择 sheet + 缺失剧集自动搜）
- **2026-04-下** 17 项完成度审计与修复（空 catch / unawaited / Aria2 / 字幕延迟 / DLNA 字幕 / 书签 / 文件分享 / 书源编辑 / 目录选择器 / 人物相册 / 笔记搜索 / 绿联 / 飞牛 / SMB fallback / Keychain 降级）
- **2026-04-中** 添加 Emby / Jellyfin / Plex 媒体服务器适配
- **2026-04-初** 移除 RabbitMQ 错误上报（避免客户端凭证泄露）；macOS Mac App Store 上架适配
