# 发布说明

## MaccyLite 内部初始版本

MaccyLite 按新应用处理，不是上游 Maccy 的原地升级。

## 数据兼容性

- 不迁移旧 Maccy 剪贴板历史。
- 不迁移旧 Maccy 设置。
- 启动时不读取旧 Maccy 的 SwiftData / CoreData 存储。
- MaccyLite 使用独立目录：

```text
~/Library/Application Support/MaccyLite/
├── Clipboard.sqlite
├── Assets/
└── Exports/
```

这样可以避免启动期迁移风险，保持 SQLite + asset store 架构干净。以后如果确实需要导入旧历史，应做成一次性导入工具，不要变成 App 启动兼容逻辑。

## 已移除范围

- OCR / Vision。
- Sparkle 更新。
- AppIntents / Shortcuts。
- 通知音效。
- App Store 和多语言发布素材。
- SwiftData 历史存储。
- GUI / XCUITest 自动验收路径。

## 使用前验证

非 GUI 自动验证：

```sh
scripts/validate-productization.sh
```

完整性能验证：

```sh
FULL_PERFORMANCE=1 scripts/validate-productization.sh
```

真实快捷键、面板焦点、Accessibility 自动粘贴、Gatekeeper 和长期运行必须按 `docs/manual-acceptance.md` 做人工验收。
