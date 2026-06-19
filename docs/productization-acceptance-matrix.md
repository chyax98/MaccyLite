# Productization Acceptance Matrix

这份矩阵用于判断 MaccyLite 是否可以标记产品化收口完成。自动证据可以由脚本证明；人工证据需要真实 macOS session 验收。

| 目标 | 自动证据 | 人工证据 | 当前状态 |
| --- | --- | --- | --- |
| 核心剪贴板捕获稳定 | `ClipboardCapture`、`ClipboardPasteboardCaptureRules`、`ClipboardHistoryStore` 测试 | 真实 App 复制文本、HTML、RTF、图片、多文件 URL | 自动已覆盖，待人工 |
| 粘贴和自动粘贴稳定 | payload resolver 和大对象 round-trip 测试 | Accessibility 未授权/已授权、前台 App 焦点恢复、自动粘贴结果 | 自动已覆盖 payload，待人工 |
| 大对象存储闭环 | 大文本 asset、图片 asset、thumbnail、missing asset、orphan cleanup 测试 | 大文本/大图复制不卡，缺 asset 时状态栏提示 | 自动已覆盖，待人工 |
| 搜索性能闭环 | FTS/短中文/URL token/多词搜索测试，`scripts/validate-performance.sh` | 面板打开和搜索体感不卡 | 自动已覆盖，待人工 |
| 每日导出可用 | exporter、schedule policy、catch-up、file URL、图片 metadata、Markdown fence 测试 | 设置页启停、手动导出、打开目录、失败反馈、定时/补导出失败状态栏提示 | 自动已覆盖核心，待人工 |
| 非必要功能清理 | `scripts/verify-non-gui-validation.py` 禁止旧路径回归 | 设置页和菜单无明显无效入口 | 自动已覆盖文件/target，待人工 |
| 中文优先 | 静态验证仅允许 `zh-Hans.lproj` | UI 文案可接受，无混乱英文主路径 | 自动已覆盖资源，待人工 |
| 长期自用安装 | App build 通过，文档包含签名/quarantine 处理 | `/Applications` 启动、权限授权、长期运行观察 | 待人工 |

## Required Commands

发布前至少跑：

```sh
scripts/validate-non-gui.sh
scripts/validate-performance.sh
```

完整压测再跑：

```sh
TEXT_ITEMS=100000 MIXED_ITEMS=10000 RUNS=20 scripts/validate-performance.sh
```

## Completion Rule

- 自动证据必须全部通过。
- `docs/manual-acceptance.md` 的人工项必须完成。
- 人工发现的问题如果属于核心捕获、搜索、粘贴、导出或大对象恢复，必须修复并尽量转成自动测试。
- 旧 Maccy 数据迁移必须明确取舍：本项目作为新项目时可接受不迁移，但需要在发布说明中写清楚。
