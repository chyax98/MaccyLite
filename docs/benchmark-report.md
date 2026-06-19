# Benchmark Report

## 2026-06-19 ClipboardCore 100k Text

Quick regression gate:

```sh
scripts/validate-performance.sh
```

Full benchmark gate:

```sh
TEXT_ITEMS=100000 MIXED_ITEMS=10000 RUNS=20 scripts/validate-performance.sh
```

Default thresholds:

- latest page p95 <= `20 ms`
- CJK search p95 <= `50 ms`
- token search p95 <= `50 ms`
- pending thumbnail job query p95 <= `50 ms`
- mixed benchmark must create asset files and pending thumbnail jobs

Command:

```sh
cd /Users/xd/p/Maccy/ClipboardCore
swift run -c release clipboard-benchmark 100000 text --runs 20
```

Environment:

- macOS target: arm64
- Build: SwiftPM release
- Database: SQLite via GRDB
- Dataset: 100,000 synthetic clipboard text rows
- Query mode: latest page, common Chinese query, common token query
- Samples: 20 runs after insert

Result:

```text
mode=text
items=100000
runs=20
insert_ms=33908.846
latest_ms=0.1073955
latest_min_ms=0.099708
latest_p50_ms=0.1073955
latest_p95_ms=0.1437777000000002
latest_max_ms=0.444333
cjk_search_ms=0.0948125
cjk_search_min_ms=0.084958
cjk_search_p50_ms=0.0948125
cjk_search_p95_ms=0.10548395
cjk_search_max_ms=0.113083
token_search_ms=0.08602099999999999
token_search_min_ms=0.08375
token_search_p50_ms=0.08602099999999999
token_search_p95_ms=0.08930239999999999
token_search_max_ms=0.0895
pending_thumbnail_jobs=0
pending_thumbnail_jobs_ms=7.281791500000001
pending_thumbnail_jobs_min_ms=6.976417
pending_thumbnail_jobs_p50_ms=7.281791500000001
pending_thumbnail_jobs_p95_ms=7.5389774
pending_thumbnail_jobs_max_ms=8.119625
asset_bytes=0
```

## 2026-06-19 ClipboardCore 10k Mixed

Command:

```sh
cd /Users/xd/p/Maccy/ClipboardCore
swift run -c release clipboard-benchmark 10000 mixed --runs 20
```

Dataset:

- Short text
- Long text stored through `ClipboardCapture` / `StoragePolicy` / `AssetStore`
- HTML
- RTF
- File URL
- PNG image asset

Result:

```text
mode=mixed
items=10000
runs=20
insert_ms=7887.974958
latest_ms=0.078625
latest_min_ms=0.07575
latest_p50_ms=0.078625
latest_p95_ms=0.10635830000000021
latest_max_ms=0.395791
cjk_search_ms=0.224604
cjk_search_min_ms=0.216375
cjk_search_p50_ms=0.224604
cjk_search_p95_ms=0.23660450000000005
cjk_search_max_ms=0.287667
token_search_ms=0.18512450000000003
token_search_min_ms=0.179666
token_search_p50_ms=0.18512450000000003
token_search_p95_ms=0.19281905
token_search_max_ms=0.193333
pending_thumbnail_jobs=1666
pending_thumbnail_jobs_ms=1.7884585
pending_thumbnail_jobs_min_ms=1.773458
pending_thumbnail_jobs_p50_ms=1.7884585
pending_thumbnail_jobs_p95_ms=1.8517598000000006
pending_thumbnail_jobs_max_ms=2.585042
asset_bytes=114651068
```

Interpretation:

- Latest page query is comfortably below the `20 ms` target.
- Common Chinese and token queries are below the `50 ms` search target.
- The first failed run exposed a real issue: common terms routed directly to full FTS + recency sort took `200 ms+`.
- The fix is now implemented in `ClipboardDatabase.search`: search recent bounded rows first, return immediately when enough results exist, and only expand to FTS when recent results are insufficient.

Remaining benchmark work:

- Add AppShell runtime sampling for pasteboard capture and thumbnail generation.
