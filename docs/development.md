# Development

## 本地运行

优先用 Xcode 直接 Run `Maccy` scheme。

原因：

- Xcode 会处理本地开发签名。
- 菜单栏 App 和 Accessibility 粘贴依赖真实 macOS session，交互验收只在人工运行时做。
- `CODE_SIGNING_ALLOWED=NO` 构建出来的 `.app` 只适合验证编译，不适合双击长期运行。

## 命令行编译验证

```sh
xcodebuild \
  -project Maccy.xcodeproj \
  -scheme Maccy \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

这个命令的目标是确认工程能编译。生成的 App 可能被 Gatekeeper 拦截。

## Gatekeeper 提示移到废纸篓

不要点“移到废纸篓”。

如果确认这是本机编译产物，可以去掉 quarantine：

```sh
xattr -dr com.apple.quarantine /path/to/MaccyLite.app
```

如果还不能启动，做本地 ad-hoc 签名：

```sh
codesign --force --deep --sign - /path/to/MaccyLite.app
```

然后再打开：

```sh
open /path/to/MaccyLite.app
```

## 长期自用安装

长期放到 `/Applications` 使用时，建议：

- 用 Xcode archive 或 Debug/Release build 生成 App。
- 执行 ad-hoc 签名。
- 去掉 quarantine。
- 第一次自动粘贴前在系统设置里授予 Accessibility 权限。App 会触发系统授权提示；未授权时只会复制到剪贴板，不会继续模拟 Cmd+V。

## 当前测试策略

完整的非 GUI 验证入口：

```sh
scripts/validate-non-gui.sh
```

Core 逻辑以 SwiftPM 测试为准：

```sh
swift test --package-path ClipboardCore
```

当前 Core 测试覆盖存储、搜索、asset、导出、file URL / 图片 metadata 导出、缩略图、数据库维护、pasteboard payload 还原、每日导出调度策略、长 UTF-8 文本截断、短中文历史搜索、多文件 URL 捕获和 Core-backed History 边界。

静态验证默认测试不会启动 App：

```sh
python3 scripts/verify-non-gui-validation.py
```

Core benchmark：

```sh
swift run --package-path ClipboardCore -c release clipboard-benchmark 100000 text --runs 20
swift run --package-path ClipboardCore -c release clipboard-benchmark 10000 mixed --runs 20
```

带阈值的性能回归验证：

```sh
scripts/validate-performance.sh
```

默认数据集较小，用于本地快速回归；完整压测可以覆盖默认参数：

```sh
TEXT_ITEMS=100000 MIXED_ITEMS=10000 RUNS=20 scripts/validate-performance.sh
```

数据库健康检查和重建索引：

```sh
swift run --package-path ClipboardCore -c release clipboard-maintenance health /path/to/Clipboard.sqlite
swift run --package-path ClipboardCore -c release clipboard-maintenance reindex /path/to/Clipboard.sqlite
swift run --package-path ClipboardCore -c release clipboard-maintenance assets \
  /path/to/Clipboard.sqlite \
  "/Users/xd/Library/Application Support/MaccyLite/Assets"
swift run --package-path ClipboardCore -c release clipboard-maintenance cleanup-assets \
  /path/to/Clipboard.sqlite \
  "/Users/xd/Library/Application Support/MaccyLite/Assets"
swift run --package-path ClipboardCore -c release clipboard-maintenance cleanup-assets \
  /path/to/Clipboard.sqlite \
  "/Users/xd/Library/Application Support/MaccyLite/Assets" \
  --apply
```

本地库搜索和手动导出：

```sh
swift run --package-path ClipboardCore -c release clipboard-maintenance search /path/to/Clipboard.sqlite 数据库
swift run --package-path ClipboardCore -c release clipboard-maintenance export \
  /path/to/Clipboard.sqlite \
  "/Users/xd/Library/Application Support/MaccyLite/Assets" \
  "/Users/xd/Library/Application Support/MaccyLite/ManualExports" \
  2026-06-19
```

App 编译以 Xcode build 为准：

```sh
xcodebuild \
  -project Maccy.xcodeproj \
  -scheme Maccy \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

旧 `MaccyTests` 已删除。那些测试依赖旧 SwiftData `HistoryItem` / `Search` / `Sorter`，和当前 Core-backed 架构不一致。

项目不保留 UI test target。不要用 UI test 给系统发全局快捷键，也不要在自动测试里启动菜单栏 App。全局快捷键、Accessibility 自动粘贴依赖真实 GUI session、焦点和 TCC 权限，只做人工验收。

## 人工 GUI 验收

默认自动验证只覆盖 Core、静态配置和 App 编译，不启动菜单栏 App。

真实快捷键、面板焦点、Accessibility 自动粘贴、TCC 授权提示都属于人工验收，清单见 [manual-acceptance.md](manual-acceptance.md)。

产品化是否可以关闭，按 [productization-acceptance-matrix.md](productization-acceptance-matrix.md) 判定。
