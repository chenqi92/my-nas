# 音乐元数据源 JSON 配置说明

本应用 **不内嵌任何源**；引擎只在用户主动导入的 JSON 配置上运行。  
本文是配置格式参考，给愿意自行编写规则的用户阅读。

JSON schema 与社区流行的脚本式音乐源格式对齐，便于跨工具复用配置。

## 顶层字段

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `id` | string | 是 | 唯一标识 |
| `name` | string | 是 | 显示名 |
| `version` | int | 是 | schema 版本 |
| `icon` | string | 否 | 图标占位（SF Symbol / emoji） |
| `color` | string | 否 | 主题色，如 `"#FF6B6B"` |
| `rateLimit` | int | 否 | 同源最小请求间隔，单位毫秒 |
| `headers` | object | 否 | 全局 HTTP 头 |
| `capabilities` | string[] | 是 | 至少一个：`metadata` / `cover` / `lyrics` / `lyricsWordLevel` |
| `sslTrustDomains` | string[] | 否 | 占位字段，当前未启用 |
| `cookie` | string | 否 | Cookie 字符串 |
| `search` | EndpointConfig | 否 | 搜索端点 |
| `detail` | EndpointConfig | 否 | 详情端点 |
| `cover` | EndpointConfig | 否 | 封面端点 |
| `lyrics` | EndpointConfig | 否 | 歌词端点 |
| `secrets` | object | 否 | 本地敏感字段（导出分享时会自动剥除） |

## EndpointConfig

```json
{
  "url": "https://api.example.com/search?q={{query}}&limit={{limit}}",
  "method": "GET",
  "params": { "key": "{{secrets.apiKey}}" },
  "headers": { "X-Custom": "value" },
  "bodyTemplate": null,
  "script": "return JSON.parse(response).results.map(item => ({ id: item.id, title: item.title }))"
}
```

- `url` / `bodyTemplate` / `params` / `headers` 内可以使用 `{{name}}` 占位符；引擎从调用上下文（`query` / `id` / `title` / `artist` / `album` / `limit`）以及 `secrets` 里查找替换值。URL 内的占位符会被自动 URL-encode；其它字段不做编码。
- `method` 取 `GET` / `POST`；POST 时 `bodyTemplate` 决定请求体。
- `script` 是一段函数体 JS。引擎按下面骨架运行你的脚本：
  ```
  (function(response, args, secrets) {
    <你的 script>
  })(<响应字符串>, <args 对象>, <secrets 对象>)
  ```
  期望的返回值结构由调用方决定：
  - `search` → `[{ id, title, artist, album, durationMs?, coverUrl? }, ...]`
  - `detail` → `{ title, artist, album, year?, genres?, coverUrl?, ... }`
  - `cover` → `[{ coverUrl, thumbnailUrl? }, ...]` 或单对象
  - `lyrics` → `{ lrcContent, wordLevelLrc? }` 或纯字符串

## 导入支持的 4 种形态

1. 单对象：`{ ... }`
2. 数组：`[ { ... }, { ... } ]`
3. 包裹对象：`{ "schema": 1, "sources": [ { ... }, ... ] }`
4. 多对象拼接：`{ ... } { ... }` 或 `{ ... }\n{ ... }`

UI 提供「粘贴 JSON」/「远端 URL」两种入口，远端 URL 拉到的内容会复用上述解析逻辑。

## 完整示例（搜索 + 详情 + 歌词）

```json
{
  "id": "example-config",
  "name": "Example Source",
  "version": 1,
  "rateLimit": 300,
  "capabilities": ["metadata", "cover", "lyrics"],
  "headers": { "User-Agent": "Mozilla/5.0" },
  "search": {
    "url": "https://api.example.com/search?q={{query}}&limit={{limit}}",
    "method": "GET",
    "script": "return JSON.parse(response).results.map(item => ({ id: item.id, title: item.title, artist: item.artist, album: item.album, durationMs: item.duration * 1000, coverUrl: item.image }))"
  },
  "detail": {
    "url": "https://api.example.com/track/{{id}}",
    "method": "GET",
    "script": "const data = JSON.parse(response); return { title: data.name, artist: data.artist.name, album: data.album.name, year: parseInt((data.release_date || '').split('-')[0]) || null, coverUrl: data.image && data.image.url }"
  },
  "lyrics": {
    "url": "https://api.example.com/lyrics?id={{id}}",
    "method": "GET",
    "script": "const d = JSON.parse(response); return { lrcContent: d.lrc, wordLevelLrc: d.wordLevel }"
  }
}
```

## 安全与版权

- 启动时只从 Hive 读用户导入的源；assets/ 下不放任何 *.json。
- `secrets` 字段是本地敏感配置，**导出分享时自动剥除**；对外只分发结构与脚本。
- 出现 5xx / 网络异常 / JS 异常时按 `AppError` 走本地日志，不主动重试，不主动上传任何数据。
- 用户脚本运行在 flutter_js（QuickJS）沙箱里，不暴露 Dart 侧 API。

## 当前已接入的能力

| 能力 | 接入点 | 备注 |
|---|---|---|
| `lyrics` | `lyric_provider.dart` 第三档 fallback | 文件 → 嵌入 → 已导入源 |
| `metadata` | 暂未接入 | 计划接到音乐刮削流 |
| `cover` | 暂未接入 | 计划接到封面回填 |
| `lyricsWordLevel` | 暂未接入 | 引擎已支持返回 wordLevelLrc，UI 渲染待对接 |
