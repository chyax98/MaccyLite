# 性能基准报告

## 验证入口

快速性能回归：

```sh
scripts/validate-performance.sh
```

完整产品化验证：

```sh
FULL_PERFORMANCE=1 scripts/validate-productization.sh
```

默认阈值：

- 最新列表 p95 <= `20 ms`
- 中文搜索 p95 <= `50 ms`
- token 搜索 p95 <= `50 ms`
- mixed benchmark 必须生成 asset 文件

## 数据集

`text` 模式会插入合成文本历史，测量最新列表、常见中文搜索和常见 token 搜索。

`mixed` 模式会插入短文本、大文本、HTML、RTF、file URL 和图片记录。大文本、富文本和图片通过 `ClipboardCapture` / `StoragePolicy` / `AssetStore` 进入 asset 文件；列表路径只读摘要和元数据，预览路径生成受限缩略图。

## 当前基线

最近一次完整闸门显示：`text` 和 `mixed` 数据集的最新列表、中文搜索、token 搜索 p95 都低于阈值。具体数值会随 schema、机器状态和 benchmark 参数变化，最终以 `scripts/validate-performance.sh` 的阈值为准。

运行时采样：

- App 会记录 pasteboard 捕获耗时。
- 慢样本由 `ClipboardRuntimePerformancePolicy` 提升为 warning。
- 如果真实使用中出现卡顿，先看 `Clipboard capture sample` 日志，再判断是 pasteboard 读取、Core 插入还是 UI 预览路径。
