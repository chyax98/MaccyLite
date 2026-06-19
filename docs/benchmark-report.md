# Benchmark Report

## Current Gate

Quick regression gate:

```sh
scripts/validate-performance.sh
```

Full productization gate:

```sh
FULL_PERFORMANCE=1 scripts/validate-productization.sh
```

Default thresholds:

- latest page p95 <= `20 ms`
- CJK search p95 <= `50 ms`
- token search p95 <= `50 ms`
- mixed benchmark must create asset files

## Dataset

Text mode inserts synthetic clipboard text rows and measures latest-page lookup, common Chinese search, and common token search.

Mixed mode inserts short text, long text stored through `ClipboardCapture` / `StoragePolicy` / `AssetStore`, HTML, RTF, file URL, and image asset rows. Runtime App captures images by default, while list rendering stays metadata-first and preview generates bounded thumbnails.

## 2026-06-19 Baseline

The full gate previously showed latest-page and search p95 below the thresholds on both text and mixed datasets. The important regression boundary is the p95 threshold in `scripts/validate-performance.sh`; historical raw output is intentionally not duplicated here because benchmark output changes with schema and metric cleanup.

Runtime sampling:

- App logs pasteboard capture samples.
- Slow capture samples are promoted to warning according to `ClipboardRuntimePerformancePolicy`.
