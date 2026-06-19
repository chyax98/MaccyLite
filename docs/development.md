# Development

## 本地运行

优先用 Xcode 直接 Run `Maccy` scheme。

原因：

- Xcode 会处理本地开发签名。
- 菜单栏 App 和 Accessibility 粘贴依赖真实 macOS session，交互验收只在人工运行时做。
- `CODE_SIGNING_ALLOWED=NO` 构建出来的 `.app` 只适合验证编译，不适合双击长期运行。

也可以生成一个本地人工验收用的 Release App：

```sh
scripts/build-local-app.sh
```

脚本会编译 `Release`、复制到 `dist/local/MaccyLite.app`、执行 ad-hoc 签名、去掉 quarantine，并验证签名。它不会启动 App，也不会申请 Accessibility 权限。

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

- 先运行 `scripts/build-local-app.sh`。
- 把 `dist/local/MaccyLite.app` 复制到 `/Applications`。
- 第一次自动粘贴前在系统设置里授予 Accessibility 权限。App 会触发系统授权提示；未授权时只会复制到剪贴板，不会继续模拟 Cmd+V。

## 当前测试策略

完整的产品化自动验证入口：

```sh
scripts/validate-productization.sh
```

生成带 commit、时间、性能摘要和完整日志的自动证据文件：

```sh
scripts/write-automatic-evidence.sh
```

默认输出到 `dist/validation/automatic-evidence.md`，属于本地生成物，不提交。

完整压测：

```sh
FULL_PERFORMANCE=1 scripts/validate-productization.sh
```

只跑非 GUI 编译和测试：

```sh
scripts/validate-non-gui.sh
```

Core 逻辑以 SwiftPM 测试为准：

```sh
swift test --package-path ClipboardCore
```

当前 Core 测试覆盖存储、搜索、asset、导出、file URL / 图片 metadata 导出、缩略图、数据库维护、pasteboard payload 还原、每日导出调度策略、长 UTF-8 文本截断、短中文历史搜索、多文件 URL 捕获和 Core-backed History 边界。

## 依赖锁定

`ClipboardCore/Package.resolved` 和 `Maccy.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` 都需要跟随代码提交。产品化守卫会检查 GRDB 锁定版本和已删除依赖，依赖升级应作为单独变更处理。

## Git 交付

当前项目来自上游 Maccy。推送 MaccyLite 改动前，先确认 `origin` 已指向自己的 MaccyLite fork，而不是 `p0deje/Maccy`：

```sh
scripts/validate-git-delivery-safety.sh
```

如果脚本提示 `origin push remote still points to upstream Maccy`，先设置自己的 fork：

```sh
git remote set-url origin <your-maccylite-fork-url>
```

确认安全后再推送：

```sh
git push origin master
```

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

维护 CLI smoke 验证：

```sh
scripts/validate-maintenance.sh
```

默认数据集较小，用于本地快速回归；完整压测可以覆盖默认参数：

```sh
FULL_PERFORMANCE=1 scripts/validate-productization.sh
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

真实快捷键、面板焦点、Accessibility 自动粘贴、TCC 授权提示都属于人工验收，清单见 [manual-acceptance.md](manual-acceptance.md)，结果记录到 [manual-acceptance-record.md](manual-acceptance-record.md)。

人工验收前填充记录元数据：

```sh
scripts/prepare-manual-acceptance-record.sh
```

人工记录填完后运行：

```sh
scripts/validate-manual-acceptance-record.py
```

最终关闭产品化目标前运行：

```sh
scripts/validate-productization-complete.sh
```

产品化是否可以关闭，按 [productization-acceptance-matrix.md](productization-acceptance-matrix.md) 判定。
