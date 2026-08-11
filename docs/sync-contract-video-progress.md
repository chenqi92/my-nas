# video_progress 同步契约 v1

`video_progress` 是跨客户端共享的同步模块。Dart 端（本仓库）与 Swift 端（独立 TV 客户端）
读写同一份远端文件，双方都必须按本文解析。

**改动流程**：先改本文 → 再改
[`video_progress_sync_module.dart`](../lib/features/video/data/services/sync/video_progress_sync_module.dart)
→ 跑
[`video_progress_sync_contract_test.dart`](../test/features/video/data/services/sync/video_progress_sync_contract_test.dart)。
该测试逐条断言下面的字段集与合并规则，Dart 侧改字段名 / 可选性 / 单位都会让它失败。

## 存放位置

WebDAV 后端（[`cloud_sync_backend.dart`](../lib/core/sync/cloud_sync_backend.dart)）：

```
/<rootPath>/manifest.json
/<rootPath>/video_progress.json
```

文件名由 `SyncableModule.key` 决定，值为 `video_progress`，不能改。

`manifest.json` 记录每个模块的版本时间：

```json
{ "video_progress": { "updatedAt": 1767225600000 } }
```

> `manifest.updatedAt` 是 **epoch 毫秒整数**；模块文件内部的时间戳是 **ISO8601 字符串**。
> 两者格式不同，不要互相套用。

## 顶层结构

```json
{
  "version": 1,
  "items": [ { "videoPath": "...", "...": "..." } ]
}
```

- `version`：整数，当前恒为 `1`。
- `items`：记录数组。无数据时是空数组，不是 `null`，也不省略。

## 记录字段（v1）

主键是 `videoPath`。一条记录聚合三个来源，字段按来源分三组，**任何一组都可能整组缺失**。

| 字段 | 类型 | 来源 box | 可选性 | 含义 |
|---|---|---|---|---|
| `videoPath` | string | — | 必有 | 主键。远端 NAS 路径，POSIX 分隔符 |
| `positionMs` | int | `video_progress` | 整组可选 | 播放位置，毫秒 |
| `durationMs` | int | `video_progress` | 整组可选 | 片长，毫秒 |
| `progressUpdatedAt` | string | `video_progress` | 整组可选 | 进度写入时间，ISO8601 |
| `watchedAt` | string | `video_watched` | 可选 | **已观看标记**时间，ISO8601 |
| `videoName` | string | `video_history` | 整组可选 | 显示名 |
| `videoUrl` | string | `video_history` | 整组可选 | 播放地址 |
| `sourceId` | string | `video_history` | 可选 | 来源源 ID；为空时**省略该键** |
| `thumbnailUrl` | string | `video_history` | 可选 | 缩略图；为空时**省略该键** |
| `size` | int | `video_history` | 随组必有 | 文件字节数，无值时写 `0`（不省略） |
| `historyAddedAt` | string | `video_history` | 整组可选 | 进入历史的时间，ISO8601 |
| `historyLastPositionMs` | int | `video_history` | 可选 | 历史里记的位置；为空时**省略该键** |
| `historyDurationMs` | int | `video_history` | 可选 | 历史里记的片长；为空时**省略该键** |

三组的判定：

- 有 `progressUpdatedAt` ⇒ `positionMs` + `durationMs` 一定同时存在。
- 有 `historyAddedAt` ⇒ `videoName` + `videoUrl` + `size` 一定同时存在。
- `watchedAt` 独立存在，可以单独出现（只标记已看、既无进度也无历史）。

最小合法记录只有两个键，例如只标记已观看：

```json
{ "videoPath": "/media/Movie.mkv", "watchedAt": "2026-04-01T00:00:00.000" }
```

### 三个容易踩的命名陷阱

1. **`watchedAt` 不是历史时间。** 它是「已观看」标记的时间戳（来自 `video_watched` box）。
   历史条目的时间是 `historyAddedAt`。同一条记录里两者可以差很远。
2. **`durationMs` 和 `historyDurationMs` 是两个独立来源**，不保证相等：
   前者来自 `video_progress`，后者来自 `video_history`。同理
   `positionMs` 与 `historyLastPositionMs`。以进度组（`positionMs` / `durationMs`）为准做续播。
3. **同步记录的键名 ≠ 本地 box 里的键名。** 本地 `video_history` 条目内部用
   `lastPositionMs` / `durationMs` / `watchedAt`；同步记录里同样的三个值叫
   `historyLastPositionMs` / `historyDurationMs` / `historyAddedAt`。
   直接把本地 history JSON 当同步记录发出去会对不上。

### 时间戳格式

`DateTime.toIso8601String()` 的输出：

- UTC 时间带 `Z` 后缀：`2026-03-03T12:00:00.000Z`
- 本地时间不带后缀也不带偏移：`2026-03-01T10:00:00.000`
- **小数位是 0 / 3 / 6 位三种都可能**：微秒非 0 时输出 6 位
  （`2026-03-01T10:00:00.123456`）。`DateTime.now()` 通常带微秒，所以 6 位是
  实际最常见的形态，不是边缘情况。

> ⚠️ 对端解析器必须同时接受 0 / 3 / 6 位小数和「有无 `Z`」。
> Swift 的 `ISO8601DateFormatter` 配 `.withFractionalSeconds` **只接受 3 位**，
> 直接用会在多数真实时间戳上解析失败。需要自己按 0/3/6 位分别处理。

解析用 `DateTime.tryParse`，**无后缀的字符串被当作本地时间**。这意味着不带后缀的
时间戳在两个不同时区的客户端上解析出不同的绝对时刻，会影响 last-wins 的胜负。

比较精度到微秒：同一秒内仅微秒不同也会决出 last-wins 胜负，对端不要截断到秒或毫秒。

> Swift 端写入时**建议统一写 UTC 带 `Z`**。Dart 端当前会把本地时间原样写出
> （取决于该 `DateTime` 是否 UTC），这是 v1 的既有行为，跨时区场景下的
> 已知不精确点。

无法解析的时间戳一律当作「无此字段」处理，不会抛错。

## 合并规则（importData）

按字段组分别 last-wins，不是整条记录 last-wins。

**进度组** — 按 `progressUpdatedAt` 比较：
- 远端更新 → 覆盖本地。
- 远端更旧或本地无记录时间 → 保留本地。
- 缺 `progressUpdatedAt`，或 `positionMs` / `durationMs` 不是整数 → **整组丢弃**，本地不动。

**观看标记** — 按 `watchedAt` 比较：
- 远端更新 → 覆盖。
- **远端没有 `watchedAt` 时不会清除本地标记。** 即已完成不会被未完成覆盖。
  代价是 v1 无法同步「取消已观看」。

**历史组** — 按 `historyAddedAt` 比较：
- 远端更新 → 覆盖该条元数据。
- 缺 `historyAddedAt` / `videoName` / `videoUrl` 任一 → 跳过该条历史。
- **本地独有的历史条目保留**，不会因为远端没有就删掉。
- 合并后按时间倒序排序，**截断到 100 条**（与本地写入上限一致）。

**批次容错**：
- `items` 缺失或为空 → no-op，不清空本地。
- 单条记录格式错误（不是 map、`videoPath` 不是字符串、字段类型不对）→ 跳过该条，
  同批其他记录照常写入。

## v1 的已知限制

- **没有 tombstone，删除不同步。** 删掉进度 / 历史 / 已观看标记只在本地生效，
  下次同步会被其他客户端的记录恢复。
- **`watchedAt` 单向。** 见上，取消已观看无法传播。
- **历史上限 100 条**，跨端合并后同样按 100 截断，条目多的一侧会丢尾部。
- **无冲突提示。** last-wins 静默取胜，两端同时看同一部片子时进度会互相覆盖。
- **无时区归一。** 见「时间戳格式」。

## 加字段怎么做（不破 v1）

Swift 与 Dart 两侧都必须容忍未知键：读到不认识的字段直接忽略。因此：

- **新增可选字段** 保持 `version: 1`，旧客户端忽略即可。
- **改字段含义 / 单位 / 必有性，或删字段** 需要 `version: 2`，并在
  `importData` 里按 `version` 分支，旧版本数据仍能读。

`importData` 当前**不校验 `version`**：任何 `version` 都会按 v1 解析。加 v2 时
必须同时补上分支判断，否则 v2 数据会被旧逻辑误读。
