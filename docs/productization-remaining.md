# Productization Remaining Work

当前状态：核心架构已切到 `ClipboardCore` + SQLite/FTS5 + asset store，非 GUI 验证和性能闸门可通过。还不能标记产品化完成，因为真实 macOS 交互、TCC 权限和长期运行只能人工验收。

最终验收矩阵见 `docs/productization-acceptance-matrix.md`。

## 已有自动闸门

- `swift test --package-path ClipboardCore`
  - 覆盖存储、搜索、大对象 asset、每日导出、payload 还原、asset 健康检查、调度策略、History store 边界。
  - 已补组合链路：长文本 + 文件 URL + 图片捕获，搜索、导出、payload 还原、孤儿 asset 清理。
- `python3 scripts/verify-non-gui-validation.py`
  - 禁止 UI/e2e 测试目标。
  - 禁止重新引入 SwiftData/Vision/Sparkle/AppIntents/多语言资源/旧测试目录。
  - 禁止构建产物被 Git 跟踪。
- `scripts/validate-performance.sh`
  - 对 latest/search/thumbnail 查询设置 p95 阈值。
  - mixed benchmark 必须产生 asset 文件和 pending thumbnail jobs。
- `xcodebuild ... CODE_SIGNING_ALLOWED=NO build`
  - 只验证 App 编译，不启动 App。

## 自动化已收口

- `ClipboardCoreStore` App 边界：
  - `ClipboardHistoryStore` / payload resolver / daily exporter 覆盖核心行为。
  - App glue 仍保留少量 `try?` 降级路径，靠 App build 和人工验收确认 UX。
- `DailyExportScheduler` App 边界：
  - `DailyExportSchedulePolicy` 已覆盖 next fire date、catch-up、已导出判定。
  - 手动导出失败有设置页错误；定时/启动补导出失败有状态栏提示。
- `Clipboard.swift` 捕获路径：
  - 真实 `NSPasteboard` 只能人工验收。
  - 类型选择/过滤规则已下沉到 `ClipboardPasteboardCaptureRules` 并覆盖空文本、富文本、禁用类型、动态类型、Microsoft link 和 sidecar 类型。
- 性能基准回归：
  - 已有 benchmark 数字和 `scripts/validate-performance.sh` 阈值脚本。
  - AppShell 已对 pasteboard capture 和 thumbnail generation 做运行时采样，慢样本打 warning。
  - 还需要人工运行时观察真实 App 来源的 warning 样本。

## 还需要人工验收

见 `docs/manual-acceptance.md`。重点是这些自动测试无法可靠证明的 macOS 行为：

- 菜单栏启动、快捷键唤起、面板焦点恢复。
- Accessibility 未授权/已授权下的自动粘贴。
- 真实 App 复制的 HTML/RTF/图片/多文件 URL。
- Gatekeeper、本地签名、移动到 `/Applications` 后的启动行为。
- 设置页每日导出操作是否顺手，失败时是否可理解。

## 产品风险

- 旧 Maccy 数据迁移尚未实现。若作为新项目发布，需要明确“不迁移旧历史”。
- 每日导出失败会写日志；手动失败显示在设置页，定时/启动补导出失败会短暂显示在状态栏。
- asset 缺失时 Core 能报错，App 会记录 warning 并短暂显示“复制失败”；还需要人工确认真实恢复体验。
- 长期运行的内存、Timer、thumbnail backlog 还需要一轮实际使用观察。

## 当前下一步

1. 按 `docs/manual-acceptance.md` 做人工验收。
2. 明确旧 Maccy 数据不迁移，或另开迁移任务。
3. 人工验收失败项转成可回归测试或明确修复任务。
