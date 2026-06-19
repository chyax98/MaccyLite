# Storage and Search Research

Date: 2026-06-19

## Problem

The fork is not just a clipboard popup. The target shape is:

- Fast quick-paste UI.
- Persistent daily clipboard history.
- Large clipboard payloads should not make DB, search, or popup slow.
- Search should feel instant for realistic clipboard queries:
  - URLs
  - commands
  - short text fragments
  - Chinese fragments
  - rare exact terms

## Findings

### 1. Current Maccy Architecture Does Not Fit Long History

Upstream pain points are already visible:

- Maccy loads history into memory and UI state.
- Large history requests mention 10k-100k items and UI struggling around 30k+ items.
- Older issues also report slow popup opening after idle periods.

Implication:

- The first bottleneck is not only search.
- Loading and rendering too much data is equally important.
- The popup should query a small page from storage, not own the whole history.

### 2. SwiftData Is a Poor Long-Term Core Store

SwiftData is convenient but too opaque for this product:

- Harder to control indexes.
- Harder to use FTS5 directly.
- Harder to reason about fetch plans.
- Current tests already expose SwiftData temporary-ID instability.
- Large BLOB behavior is hidden behind the model layer.

Implication:

- Keep SwiftData only as transition code.
- Long-term storage should be explicit SQLite, likely through GRDB.

### 3. Store Large Bodies Outside the Hot Index

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

### 6. Rust Search Is Not First Move

Rust options like Tantivy are real and fast, but they add:

- Swift/Rust bridge.
- Packaging complexity.
- Index lifecycle complexity.
- Tokenizer/CJK decisions anyway.
- More crash/debug surface.

Implication:

- Do not start with Rust.
- Prove SQLite cannot hit the UX target first.
- Rust becomes reasonable only after measured SQLite failure at target scale.

## Local Microbenchmark

Environment:

- macOS local Python sqlite3
- SQLite 3.53.2
- FTS5 available
- `unicode61` and `trigram` tokenizers available

Dataset:

- 100k synthetic clipboard rows.
- Mix of:
  - short token text
  - URLs
  - continuous Chinese text
  - rare terms

Results summary:

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

Conclusion:

- `LIKE` is not automatically bad when constrained to recent rows and `LIMIT 20`.
- FTS is excellent for rare terms and larger search scope.
- `unicode61` is not enough for Chinese substring search.
- `trigram` helps substring search but increases index size and has 3-character limits.

## Recommended Product Design

### Storage

Use explicit SQLite + asset store.

Do not store all pasteboard data as DB BLOBs.

Use policy:

```text
Small text:
  inline in DB

Large text:
  full body in asset file
  DB stores bounded prefix and path/hash

HTML/RTF:
  store plain extracted prefix for search
  full original body as asset if large

Images:
  default off or asset-only
  runtime App capture removed

File URLs:
  store paths/URLs, not file contents
```

### Search

Use hybrid search:

```text
If query is empty:
  fetch latest page by copied_at desc

If query is short Chinese or very short substring:
  search recent bounded rows with LIKE

If query is token-like / URL-like / 3+ chars:
  search FTS/trigram index

If user explicitly deep-searches:
  scan or separately index asset bodies in background
```

### UI

Popup should never load full history.

Use:

- latest page query
- paginated results
- bounded display string
- asset read only on paste/preview/export

## Next Implementation Steps

Implemented in the current fork:

1. `StoragePolicy` now decides inline vs file-backed content at capture time.
2. `AssetStore` writes large payloads under `~/Library/Application Support/MaccyLite/Assets/yyyy/MM/dd/`.
3. `HistoryItemContent` stores `value` as small inline data or preview prefix, and `assetPath` as the full object pointer.
4. Restore/paste reads `pasteboardValue`, so large file-backed content can still paste the original payload.

Next implementation steps:

1. Add explicit SQLite/GRDB spike beside current SwiftData.
2. Write migration-free prototype table:
   - `items`
   - `item_contents`
   - `search_fts`
3. Add a local benchmark command against real copied fixture data.
4. Replace `History.load()` full fetch with latest-page query.
5. Keep image handling out of the App runtime capture path.
6. Add daily export over DB metadata + asset bodies, off the popup hot path.
