# Benchmark Report

## 2026-06-19 Full Performance Gate

Command:

```sh
TEXT_ITEMS=100000 MIXED_ITEMS=10000 RUNS=20 scripts/validate-performance.sh
```

Result:

```text
mode=text
items=100000
runs=20
insert_ms=35021.141666
latest_ms=0.2762915
latest_min_ms=0.238375
latest_p50_ms=0.2762915
latest_p95_ms=0.4640131500000021
latest_max_ms=3.220042
cjk_search_ms=1.798521
cjk_search_min_ms=1.730542
cjk_search_p50_ms=1.798521
cjk_search_p95_ms=2.0929274
cjk_search_max_ms=2.112125
token_search_ms=1.5670625
token_search_min_ms=1.512
token_search_p50_ms=1.5670625
token_search_p95_ms=1.6792729
token_search_max_ms=1.720083
pending_thumbnail_jobs=0
pending_thumbnail_jobs_ms=8.038499999999999
pending_thumbnail_jobs_min_ms=7.302625
pending_thumbnail_jobs_p50_ms=8.038499999999999
pending_thumbnail_jobs_p95_ms=10.748880600000014
pending_thumbnail_jobs_max_ms=28.489458
asset_bytes=0

mode=mixed
items=10000
runs=20
insert_ms=8777.28025
latest_ms=0.1625625
latest_min_ms=0.152625
latest_p50_ms=0.1625625
latest_p95_ms=0.20756185000000027
latest_max_ms=0.571333
cjk_search_ms=10.923625000000001
cjk_search_min_ms=10.729125
cjk_search_p50_ms=10.923625000000001
cjk_search_p95_ms=11.40943305
cjk_search_max_ms=12.116709
token_search_ms=11.0995205
token_search_min_ms=10.937041
token_search_p50_ms=11.0995205
token_search_p95_ms=11.70220835
token_search_max_ms=11.834417
pending_thumbnail_jobs=1666
pending_thumbnail_jobs_ms=1.9596870000000002
pending_thumbnail_jobs_min_ms=1.885667
pending_thumbnail_jobs_p50_ms=1.9596870000000002
pending_thumbnail_jobs_p95_ms=2.239420800000003
pending_thumbnail_jobs_max_ms=6.341916
asset_bytes=114651068
performance validation passed
```

Interpretation:

- latest page p95 is below the `20 ms` target in both text and mixed datasets.
- CJK and token search p95 are below the `50 ms` target in both datasets.
- mixed mode confirms large text/image asset storage and pending thumbnail jobs.

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

Runtime sampling:

- AppShell logs pasteboard capture and thumbnail generation samples.
- Slow capture/thumbnail samples are promoted to warning according to `ClipboardRuntimePerformancePolicy`.
