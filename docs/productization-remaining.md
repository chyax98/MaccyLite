# 产品化剩余事项

当前状态：核心架构已切到 `ClipboardCore` + SQLite/FTS5 + asset store。非 GUI 验证和性能闸门可以通过。还不能只靠自动化标记完成，因为真实 macOS 交互、TCC 权限和长期运行只能人工验收。

最终验收矩阵见 `docs/productization-acceptance-matrix.md`。

## 已有自动闸门

- `swift test --package-path ClipboardCore`
  - 覆盖存储、搜索、大对象 asset、每日导出、payload 还原、asset 健康检查、调度策略、History store 边界。
  - 覆盖组合链路：长文本、文件 URL、图片捕获、搜索、导出、payload 还原、孤儿 asset 清理。
- `python3 scripts/verify-non-gui-validation.py`
  - 禁止 UI/e2e 测试目标。
  - 禁止重新引入 SwiftData、Vision、Sparkle、AppIntents、多语言资源、旧测试目录。
  - 禁止构建产物被 Git 跟踪。
- `scripts/validate-performance.sh`
  - 对 latest/search 查询设置 p95 阈值。
  - mixed benchmark 必须产生 asset 文件。
- `scripts/validate-maintenance.sh`
  - 覆盖 `clipboard-maintenance` 的 health、reindex、search、export、assets、cleanup-assets smoke path。
  - 验证空库可初始化、空日报可生成、资产检查和清理命令可执行。
- `xcodebuild ... CODE_SIGNING_ALLOWED=NO build`
  - 只验证 App 编译，不启动 App。

## 已收口模块

- `ClipboardCoreStore`
  - App 通过它访问列表、搜索、item、pin、删除、导出和 payload。
  - 读路径失败时降级为空结果，写路径失败时记录 error。
- `DailyExportScheduler`
  - 调度策略已有单测。
  - 手动导出失败显示设置页错误。
  - 定时/启动补导出失败会短暂显示状态栏提示。
- `Clipboard.swift`
  - 真实 `NSPasteboard` 行为只做人工验收。
  - 类型选择和过滤规则下沉到 `ClipboardPasteboardCaptureRules`。
- 性能基线
  - benchmark 有阈值脚本。
  - pasteboard capture 有运行时采样。
  - UI 列表只读轻量元数据，右侧预览才读 asset。

## 还需要人工验收

按 `docs/manual-acceptance.md` 执行；模板是 `docs/manual-acceptance-record.md`，实际结果写到 `dist/validation/manual-acceptance-record.md`。

重点：

- 菜单栏启动、快捷键唤起、面板焦点恢复。
- Accessibility 未授权/已授权下的自动粘贴。
- 真实 App 复制的 HTML、RTF、多文件 URL、图片。
- Gatekeeper、本地签名、移动到 `/Applications` 后的启动行为。
- 设置页每日导出操作是否顺手，失败提示是否可理解。

## 产品风险

- 旧 Maccy 数据迁移明确不做；MaccyLite 从独立 Application Support 目录和空历史开始。
- 图片默认捕获，性能风险主要在系统 pasteboard 读取和预览缩略图生成；列表路径不解码图片。
- 每日导出失败会写日志；手动失败显示在设置页，定时/启动补导出失败会短暂显示在状态栏。
- asset 缺失时 Core 能报错，App 会记录 warning 并短暂显示“复制失败”；还需要人工确认真实恢复体验。
- 长期运行的内存和 Timer 需要实际使用观察。

## 当前下一步

1. 运行 `scripts/write-automatic-evidence.sh`。
2. 运行 `scripts/prepare-manual-acceptance-record.sh`。
3. 按 `docs/manual-acceptance.md` 做人工验收。
4. 填写 `dist/validation/manual-acceptance-record.md`。
5. 运行 `scripts/validate-manual-acceptance-record.py`。
6. 运行 `scripts/validate-productization-complete.sh`。
7. 推送前运行 `scripts/validate-git-delivery-safety.sh`。
8. 人工验收失败项转成修复任务；能自动化的尽量补测试。
