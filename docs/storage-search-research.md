# 存储与搜索调研

> 档案说明：这份文档记录早期技术调研，用于理解取舍背景。当前实现以 `docs/target-architecture.md` 和代码为准。

日期：2026-06-19

## 问题

这个 fork 不是只做一个剪贴板弹窗。目标形态是：

- 快速粘贴 UI。
- 持久化每日剪贴板历史。
- 大剪贴板 payload 不应拖慢数据库、搜索或弹窗。
- 面向真实剪贴板 query 的搜索要足够快：
  - URLs
  - commands
  - short text fragments
  - Chinese fragments
  - rare exact terms

## 调研结论

### 1. 原 Maccy 架构不适合长期历史

Upstream pain points are already visible:

- Maccy loads history into memory and UI state.
- Large history requests mention 10k-100k items and UI struggling around 30k+ items.
- Older issues also report slow popup opening after idle periods.

Implication:

- The first bottleneck is not only search.
- Loading and rendering too much data is equally important.
- The popup should query a small page from storage, not own the whole history.

### 2. SwiftData 不适合做长期核心存储

SwiftData is convenient but too opaque for this product:

- Harder to control indexes.
- Harder to use FTS5 directly.
- Harder to reason about fetch plans.
- 既有测试已经暴露 SwiftData 临时 ID 不稳定问题。
- Large BLOB behavior is hidden behind the model layer.

Implication:

- Keep SwiftData only as transition code.
- Long-term storage should be explicit SQLite, likely through GRDB.

### 3. 大对象应离开热索引

The robust shape is:

```text
Application Support/MaccyLite/
  index.sqlite
  assets/
    2026/06/19/
      <hash>.txt
      <hash>.html
      <hash>.rtf
      <hash>.png
```

SQLite stores:

- id
- copied_at
- source_app
- pasteboard types
- byte sizes
- small display/search prefix copied from original content
- asset references
- content hash
- pin/copy count

Assets store:

- full large text
- full large HTML/RTF
- images
- optional export material

Implication:

- DB remains small and queryable.
- Full paste restore can still read the asset file.
- Daily export can walk assets off the popup hot path.

### 4. Search Is Not One Mechanism

Clipboard search is not document search.

Real queries split into several cases:

- Recent substring lookup.
- URL/domain lookup.
- Rare exact token lookup.
- Chinese fragment lookup.
- Optional deep search through large bodies.

So the search stack should be tiered:

```text
Tier 0: Recent page filter in memory
Tier 1: SQLite indexed metadata and prefix fields
Tier 2: SQLite FTS/trigram index over bounded searchable text
Tier 3: Offline/deep asset search, not used by popup by default
```

### 5. SQLite FTS5 Is Useful, But Tokenizer Matters

SQLite FTS5 is suitable for local full-text search and supports multiple tokenizers.

Important detail:

- `unicode61` works well for whitespace/token based text.
- It does not solve general Chinese substring search.
- `trigram` supports substring matching for 3+ character sequences.
- `trigram` does not solve 1-2 character Chinese queries by itself.

Implication:

- A single FTS table is not enough.
- Use either:
  - `unicode61` for token search plus fallback `LIKE` over recent/bounded rows, or
  - `trigram` for substring search, accepting larger index size,
  - or a custom CJK ngram column/table later.

### 6. Rust 搜索不是第一步

Tantivy 这类 Rust 搜索方案确实快，但会引入：

- Swift / Rust 桥接。
- 打包复杂度。
- 索引生命周期复杂度。
- 仍然要处理 tokenizer / 中文分词。
- 更多崩溃和调试面。

结论：

- 不从 Rust 开始。
- 先证明 SQLite 不能满足体感目标。
- 只有在目标规模下实测 SQLite 失败，Rust 才值得引入。

## 本地微基准

环境：

- macOS 本机 Python sqlite3
- SQLite 3.53.2
- FTS5 可用
- `unicode61` 和 `trigram` tokenizer 可用

数据集：

- 10 万条合成剪贴板记录。
- 混合内容：
  - 短 token 文本
  - URLs
  - 连续中文文本
  - 罕见词

结果摘要：

```text
unicode61 FTS, rare term:
  p50 ~0.006 ms

LIKE '%rare%':
  p50 ~15 ms

unicode61 FTS, common token with ORDER BY newest LIMIT 20:
  p50 ~8-10 ms

LIKE '%common%' with ORDER BY newest LIMIT 20:
  can be <0.1 ms because it stops after recent matches

unicode61 FTS, continuous Chinese substring:
  often 0 matches

trigram FTS, Chinese 3+ char substring:
  p50 ~0.03 ms for rare match

trigram FTS, English substring:
  works for 3+ chars, index larger
```

结论：

- `LIKE` 限制在近期记录和小 limit 下不一定差。
- FTS 适合罕见词和更大搜索范围。
- `unicode61` 不适合中文连续子串。
- `trigram` 能改善子串搜索，但会增加索引体积，并有 3 字符限制。

## 推荐产品设计

### 存储

使用显式 SQLite + asset store。

不要把所有 pasteboard data 都当 DB BLOB 存。

当前策略：

```text
小文本：
  inline 存 DB

大文本：
  完整内容进 asset 文件
  DB 保存受限前缀、path、hash

HTML/RTF：
  搜索只用提取文本/前缀
  原始 payload 保留；大对象写 asset

图片：
  默认捕获
  asset-backed
  列表只读元数据
  右侧预览生成受限缩略图

File URL：
  存路径/URL，不复制文件内容
```

### 搜索

使用混合搜索：

```text
query 为空：
  按 copied_at / pin 读取最新页

query 很短：
  先查近期 LIKE
  结果不足时全量 LIKE 兜底

query 是 token / URL / 3+ 字符：
  查 FTS/trigram 索引并合并 LIKE 结果

如果以后要深度全文搜索：
  单独后台索引 asset body，不进入弹窗热路径
```

### UI

弹窗不加载全量历史。

使用：

- 最新页查询
- 分页结果
- 受限 display string
- 只有粘贴、预览、导出才读 asset

## 当前落地状态

当前 fork 已实现：

1. `StoragePolicy` 在捕获时决定 inline 还是 asset-backed。
2. `AssetStore` 把大 payload 写到 `~/Library/Application Support/MaccyLite/Assets/yyyy/MM/dd/`。
3. `ClipboardDatabase` 保存元数据、inline 前缀、asset path、hash 和图片尺寸。
4. 粘贴通过 payload resolver 读取完整 payload，所以 asset-backed 内容仍能按原始语义粘贴。
5. 搜索使用近期 LIKE、FTS5 unicode61、FTS5 trigram 和全量 LIKE 兜底。
6. 每日导出读取 DB 元数据和 asset body，不进入弹窗热路径。

后续如果继续优化：

1. 用真实个人数据跑更长时间的性能观察。
2. 如果 10 万级以后搜索仍不够，再考虑独立全文索引。
3. 对图片和文件预览继续做取消、debounce 和缓存。
