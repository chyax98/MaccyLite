# 开发与本地验证

## 本地运行

日常开发优先用 Xcode 运行 `Maccy` scheme。

原因：

- Xcode 会处理本地开发签名。
- 菜单栏 App、全局快捷键、Accessibility 粘贴依赖真实 macOS session。
- `CODE_SIGNING_ALLOWED=NO` 构建出来的 App 只适合验证编译，不适合长期运行。

生成本地人工验收用 Release App：

```sh
scripts/build-local-app.sh
```

脚本会：

- 编译 `Release`。
- 复制到 `dist/local/MaccyLite.app`。
- 执行 ad-hoc 签名。
- 去掉 quarantine。
- 验证签名。

脚本不会启动 App，也不会申请 Accessibility 权限。

## 编译验证

命令行只验证工程能编译：

```sh
xcodebuild \
  -project Maccy.xcodeproj \
  -scheme Maccy \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

生成的 App 可能被 Gatekeeper 拦截，不作为人工验收 App。

## Gatekeeper 提示移到废纸篓

不要点“移到废纸篓”。

确认是本机编译产物后，先去掉 quarantine：

```sh
xattr -dr com.apple.quarantine /path/to/MaccyLite.app
```

如果还不能启动，做本地 ad-hoc 签名：

```sh
codesign --force --deep --sign - /path/to/MaccyLite.app
```

再打开：

```sh
open /path/to/MaccyLite.app
```

## 长期自用安装

推荐流程：

1. 运行 `scripts/build-local-app.sh`。
2. 复制 `dist/local/MaccyLite.app` 到 `/Applications`。
3. 第一次自动粘贴前，在系统设置里授予 Accessibility 权限。

未授权时，MaccyLite 只会复制到系统剪贴板，不会继续模拟 Cmd+V。

## 自动验证分层

产品化默认验证，不启动 App，不抢桌面焦点：

```sh
scripts/validate-productization.sh
```

只跑非 GUI 编译和测试：

```sh
scripts/validate-non-gui.sh
```

Core 逻辑测试：

```sh
swift test --package-path ClipboardCore
```

维护 CLI smoke 验证：

```sh
scripts/validate-maintenance.sh
```

性能回归验证：

```sh
scripts/validate-performance.sh
```

完整压测：

```sh
FULL_PERFORMANCE=1 scripts/validate-productization.sh
```

生成自动证据：

```sh
scripts/write-automatic-evidence.sh
```

默认输出到 `dist/validation/automatic-evidence.md`，这是本地生成物，不提交。

## 测试策略

自动测试只覆盖非 GUI 行为：

- `ClipboardCore` 存储、搜索、asset、导出、payload 恢复。
- file URL / 图片 metadata 导出。
- 数据库健康检查和维护命令。
- 每日导出调度策略。
- 长 UTF-8 文本截断。
- 短中文历史搜索。
- 多文件 URL 捕获。
- Core-backed History 边界。

不保留 UI test target。不要在自动测试里启动菜单栏 App、发送全局快捷键、控制系统设置或依赖 TCC 权限。

真实快捷键、面板焦点、Accessibility 自动粘贴、Gatekeeper 和长期运行只做人工验收，清单见 `docs/manual-acceptance.md`。

## 依赖锁定

需要随代码提交的锁文件：

- `ClipboardCore/Package.resolved`
- `Maccy.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`

依赖升级应作为单独变更处理。产品化守卫会检查 GRDB 锁定版本和已删除依赖，避免 Sparkle、Vision、SwiftData 等旧路径回流。

## Git 交付

推送前确认 `origin` 指向自己的 MaccyLite fork，而不是上游 `p0deje/Maccy`：

```sh
scripts/validate-git-delivery-safety.sh
```

如果脚本提示 `origin push remote still points to upstream Maccy`，先改 remote：

```sh
git remote set-url origin <your-maccylite-fork-url>
```

再推送：

```sh
git push origin master
```

## 维护 CLI

数据库健康检查：

```sh
swift run --package-path ClipboardCore -c release clipboard-maintenance health /path/to/Clipboard.sqlite
```

重建搜索索引：

```sh
swift run --package-path ClipboardCore -c release clipboard-maintenance reindex /path/to/Clipboard.sqlite
```

搜索本地库：

```sh
swift run --package-path ClipboardCore -c release clipboard-maintenance search /path/to/Clipboard.sqlite 数据库
```

检查 asset 健康：

```sh
swift run --package-path ClipboardCore -c release clipboard-maintenance assets \
  /path/to/Clipboard.sqlite \
  "/Users/xd/Library/Application Support/MaccyLite/Assets"
```

清理孤儿 asset，默认只预览：

```sh
swift run --package-path ClipboardCore -c release clipboard-maintenance cleanup-assets \
  /path/to/Clipboard.sqlite \
  "/Users/xd/Library/Application Support/MaccyLite/Assets"
```

确认后执行清理：

```sh
swift run --package-path ClipboardCore -c release clipboard-maintenance cleanup-assets \
  /path/to/Clipboard.sqlite \
  "/Users/xd/Library/Application Support/MaccyLite/Assets" \
  --apply
```

手动导出指定日期：

```sh
swift run --package-path ClipboardCore -c release clipboard-maintenance export \
  /path/to/Clipboard.sqlite \
  "/Users/xd/Library/Application Support/MaccyLite/Assets" \
  "/Users/xd/Library/Application Support/MaccyLite/ManualExports" \
  2026-06-19
```

## 产品化关闭

1. 运行 `scripts/write-automatic-evidence.sh`。
2. 运行 `scripts/prepare-manual-acceptance-record.sh`。
3. 按 `docs/manual-acceptance.md` 做人工验收。
4. 填写 `dist/validation/manual-acceptance-record.md`。
5. 运行 `scripts/validate-manual-acceptance-record.py`。
6. 运行 `scripts/validate-productization-complete.sh`。

产品化是否完成，以 `docs/productization-acceptance-matrix.md` 为准。
