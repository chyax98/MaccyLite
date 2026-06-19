# Productization Remaining Work

当前状态：核心架构已切到 `ClipboardCore` + SQLite/FTS5 + asset store，非 GUI 验证可通过。还不能标记产品化完成，下面这些项需要继续闭环。

## 已有自动闸门

- `swift test --package-path ClipboardCore`
  - 覆盖存储、搜索、大对象 asset、每日导出、payload 还原、asset 健康检查、调度策略、History store 边界。
  - 已补组合链路：长文本 + 文件 URL + 图片捕获，搜索、导出、payload 还原、孤儿 asset 清理。
- `python3 scripts/verify-non-gui-validation.py`
  - 禁止 UI/e2e 测试目标。
  - 禁止重新引入 SwiftData/Vision/Sparkle/AppIntents/多语言资源/旧测试目录。
  - 禁止构建产物被 Git 跟踪。
- `xcodebuild ... CODE_SIGNING_ALLOWED=NO build`
  - 只验证 App 编译，不启动 App。

## 还需要自动化补齐

- `ClipboardCoreStore` App 边界：
  - 当前主要靠 Core 测试间接覆盖。
  - 需要抽出可注入时钟/路径/队列后，直接测 export、asset cleanup、selected payload 的 App glue。
- `DailyExportScheduler` App 边界：
  - Core 的 `DailyExportSchedulePolicy` 已测。
  - Scheduler 本体还缺非 GUI 测试，需要避免真实 Timer 依赖。
- `Clipboard.swift` 捕获路径：
  - 真实 `NSPasteboard` 只能人工验收。
  - 可继续把类型选择/过滤/大对象策略拆成纯函数后测试，降低手测压力。
- 性能基准回归：
  - 已有 benchmark 数字和 `scripts/validate-performance.sh` 阈值脚本。
  - 还需要 AppShell runtime sampling，覆盖真实 pasteboard capture 和 thumbnail generation。

## 还需要人工验收

见 `docs/manual-acceptance.md`。重点是这些自动测试无法可靠证明的 macOS 行为：

- 菜单栏启动、快捷键唤起、面板焦点恢复。
- Accessibility 未授权/已授权下的自动粘贴。
- 真实 App 复制的 HTML/RTF/图片/多文件 URL。
- Gatekeeper、本地签名、移动到 `/Applications` 后的启动行为。
- 设置页每日导出操作是否顺手，失败时是否可理解。

## 产品风险

- 旧 Maccy 数据迁移尚未实现。若作为新项目发布，需要明确“不迁移旧历史”。
- 每日导出失败目前主要写日志，App 内用户反馈还比较弱。
- asset 缺失时 Core 能报错，但 UI 层恢复体验还需要人工确认。
- 长期运行的内存、Timer、thumbnail backlog 还需要一轮实际使用观察。

## 当前下一步建议

1. 抽出 `DailyExportScheduler` 可测边界，补非 GUI 测试。
2. 抽出 `Clipboard.swift` 的 pasteboard 类型选择逻辑，补纯函数测试。
3. 跑一次 full release benchmark，更新 `docs/benchmark-report.md`。
4. 按 `docs/manual-acceptance.md` 做人工验收，并把失败项转成可回归测试或明确修复任务。
