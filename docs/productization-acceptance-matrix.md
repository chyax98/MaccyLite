# Productization Acceptance Matrix

这份矩阵用于判断 MaccyLite 是否可以标记产品化收口完成。自动证据可以由脚本证明；人工证据需要真实 macOS session 验收。

| 目标 | 自动证据 | 人工证据 | 当前状态 |
| --- | --- | --- | --- |
| 核心剪贴板捕获稳定 | `ClipboardCapture`、`ClipboardPasteboardCaptureRules`、`ClipboardHistoryStore` 测试 | 真实 App 复制文本、HTML、RTF、多文件 URL，图片不会新增历史 | 自动已覆盖，待人工 |
| 粘贴和自动粘贴稳定 | payload resolver 和大对象 round-trip 测试 | Accessibility 未授权/已授权、前台 App 焦点恢复、自动粘贴结果 | 自动已覆盖 payload，待人工 |
| 大对象存储闭环 | 大文本 asset、旧图片 asset metadata、missing asset、orphan cleanup 测试 | 大文本复制不卡，缺 asset 时状态栏提示 | 自动已覆盖，待人工 |
| 搜索性能闭环 | FTS/短中文/URL token/多词搜索测试，`scripts/validate-performance.sh` | 面板打开和搜索体感不卡 | 自动已覆盖，待人工 |
| 每日导出可用 | exporter、schedule policy、catch-up、file URL、图片 metadata、Markdown fence 测试 | 设置页启停、手动导出、打开目录、失败反馈、定时/补导出失败状态栏提示 | 自动已覆盖核心，待人工 |
| 非必要功能清理 | `scripts/verify-non-gui-validation.py` 禁止旧路径回归 | 设置页和菜单无明显无效入口 | 自动已覆盖文件/target，待人工 |
| 中文优先 | 静态验证仅允许 `zh-Hans.lproj` | UI 文案可接受，无混乱英文主路径 | 自动已覆盖资源，待人工 |
| 旧数据迁移取舍 | `docs/release-notes.md` 明确不迁移旧 Maccy 历史/设置 | 用户接受新应用从空历史开始 | 已明确取舍，待人工确认 |
| 长期自用安装 | App build 通过，文档包含签名/quarantine 处理 | `/Applications` 启动、权限授权、长期运行观察 | 待人工 |

## Required Commands

发布前至少跑一键闸门：

```sh
scripts/validate-productization.sh
```

需要留存自动证据时运行：

```sh
scripts/write-automatic-evidence.sh
```

人工验收前填充记录元数据：

```sh
scripts/prepare-manual-acceptance-record.sh
```

人工验收记录填完后运行：

```sh
scripts/validate-manual-acceptance-record.py
```

最终关闭产品化目标前运行：

```sh
scripts/validate-productization-complete.sh
```

推送前确认不会误推上游：

```sh
scripts/validate-git-delivery-safety.sh
```

它会依次运行：

```sh
scripts/validate-non-gui.sh
scripts/validate-maintenance.sh
scripts/validate-performance.sh
```

完整压测使用同一个入口：

```sh
FULL_PERFORMANCE=1 scripts/validate-productization.sh
```

## Completion Rule

- 自动证据必须全部通过。
- `docs/manual-acceptance.md` 的人工项必须完成；`docs/manual-acceptance-record.md` 是模板，实际结果必须记录到 `dist/validation/manual-acceptance-record.md`。
- `scripts/validate-manual-acceptance-record.py` 必须通过。
- `scripts/validate-productization-complete.sh` 必须通过。
- 推送前 `scripts/validate-git-delivery-safety.sh` 必须通过。
- 人工发现的问题如果属于核心捕获、搜索、粘贴、导出或大对象恢复，必须修复并尽量转成自动测试。
- 旧 Maccy 数据迁移取舍见 `docs/release-notes.md`：本项目作为新应用，不迁移旧历史和设置。
