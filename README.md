# MaccyLite

MaccyLite 是一个面向自用的 macOS 快捷粘贴工具，基于 Maccy fork 后重构。

目标不是做全功能助手，而是保留剪贴板管理的核心体验：

- 后台捕获剪贴板历史。
- 快捷键打开历史面板。
- 搜索、复制、自动粘贴。
- Pin 常用条目。
- 大文本和图片走文件资产存储，数据库只做索引和列表展示。
- 每日导出 Markdown，给后续 AI 分析使用。

## 当前取舍

已砍掉：

- OCR / Vision。
- Sparkle 更新。
- AppIntents / Shortcuts。
- 通知音效。
- App Store / 多语言发布素材。
- SwiftData 历史存储。
- 默认 GUI / XCUITest 验证路径。

只保留简体中文资源。

MaccyLite 作为新应用处理，不迁移旧 Maccy 历史和设置；发布说明见 `docs/release-notes.md`。

## 技术结构

- App：SwiftUI + NSPanel。
- 系统集成：NSPasteboard、Accessibility、CGEvent。
- Core：`ClipboardCore` SwiftPM 包。
- 存储：GRDB + SQLite + FTS5。
- 大对象：`Application Support/MaccyLite/Assets`。
- 每日导出：`Application Support/MaccyLite/Exports`。

## 开发验证

默认产品化验证不启动 App，不抢桌面焦点：

```sh
scripts/validate-productization.sh
```

完整压测：

```sh
FULL_PERFORMANCE=1 scripts/validate-productization.sh
```

真实快捷键、面板焦点、Accessibility 自动粘贴只做人工验收，清单见 `docs/manual-acceptance.md`。

产品化剩余闭环见 `docs/productization-remaining.md`。

## 维护命令

```sh
swift run --package-path ClipboardCore -c release clipboard-maintenance health /path/to/Clipboard.sqlite
swift run --package-path ClipboardCore -c release clipboard-maintenance reindex /path/to/Clipboard.sqlite
swift run --package-path ClipboardCore -c release clipboard-maintenance search /path/to/Clipboard.sqlite 关键词
swift run --package-path ClipboardCore -c release clipboard-maintenance assets /path/to/Clipboard.sqlite /path/to/Assets
swift run --package-path ClipboardCore -c release clipboard-maintenance cleanup-assets /path/to/Clipboard.sqlite /path/to/Assets
swift run --package-path ClipboardCore -c release clipboard-maintenance cleanup-assets /path/to/Clipboard.sqlite /path/to/Assets --apply
```

## License

MIT。上游项目为 [Maccy](https://github.com/p0deje/Maccy)。
