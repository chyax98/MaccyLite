# Manual Acceptance

这份清单只用于人工验收，不放进自动测试、CI、脚本或 agent 默认验证。

## 验收记录

- 日期：
- macOS：
- 构建方式：Xcode Run / Debug app / Release app
- App 路径：
- 本地验收 App：`scripts/build-local-app.sh` 输出路径
- 验收人：
- 结论：通过 / 有问题
- 问题记录：

## 启动与权限

- [ ] 用 Xcode Run `Maccy` scheme 启动。
- [ ] 首次自动粘贴前，系统设置里授予 Accessibility 权限。
- [ ] 未授权时选择历史项只复制到剪贴板，不继续模拟 Cmd+V。

## 捕获

- [ ] 复制短文本，历史列表出现该条。
- [ ] 复制超过大文本阈值的文本，列表不卡顿，详情可预览前缀，导出包含完整文本。
- [ ] 复制 HTML 内容，历史列表可展示可读文本，重新选择后保留 HTML payload。
- [ ] 复制 RTF 内容，历史列表出现富文本条目，重新选择后保留 RTF payload。
- [ ] 复制多文件 URL，历史列表保留文件信息，重新选择后 Finder/目标 App 能收到文件 URL。
- [ ] 复制图片不会新增历史记录。

## 运行时性能采样

- [ ] 复制短文本、大文本时，日志里出现 `Clipboard capture sample`。
- [ ] 正常样本为 debug；超过阈值时出现 warning。
- [ ] warning 阈值：
  - pasteboard read > `50 ms`
  - Core insert > `50 ms`
  - capture total > `100 ms`
- [ ] 如果出现 warning，记录复制来源 App、内容类型、`types/read_ms/insert_ms/total_ms`。

## 检索与列表

- [ ] 搜索中文短词能命中老历史，不只命中最近几千条。
- [ ] 搜索 URL 片段、文件名片段能命中。
- [ ] 面板打开和搜索输入没有可感知卡顿。
- [ ] Pin 后条目固定在前面，取消 Pin 后排序恢复。
- [ ] 删除、清空未固定、清空全部后 UI 立即响应。

## 粘贴

- [ ] 快捷键打开面板后，前台 App 焦点可恢复。
- [ ] 选择条目后写回系统剪贴板。
- [ ] 开启自动粘贴且已授权时，内容进入原前台 App。
- [ ] 自动粘贴失败时，不造成 App 卡死或面板不可恢复。
- [ ] 如果历史条目的 asset 缺失或 payload 恢复失败，应记录 warning，状态栏短暂显示“复制失败”，且不继续自动粘贴。

## 每日导出

- [ ] 默认关闭每日导出。
- [ ] 开启后导出目录固定为 `Application Support/MaccyLite/Exports`。
- [ ] 手动导出不会卡设置界面。
- [ ] 手动导出失败时，设置页显示具体错误信息，不只显示通用失败。
- [ ] 定时导出或启动补导出失败时，应记录 error，状态栏短暂显示“每日导出失败...”。
- [ ] “打开导出目录”会创建并打开导出目录。
- [ ] 导出的 Markdown 按日期生成，包含文本、文件 URL、旧图片元信息和 asset 路径。

## 安装与长期运行

- [ ] 本地构建产物去 quarantine / ad-hoc 签名后可启动。
- [ ] `scripts/build-local-app.sh` 生成的 `dist/local/MaccyLite.app` 可启动。
- [ ] 放到 `/Applications` 后可启动。
- [ ] 确认 MaccyLite 从空历史开始，不迁移旧 Maccy 历史和设置。
- [ ] 持续运行观察没有明显内存增长或 Timer 异常。

## 失败处理

- 核心捕获、搜索、粘贴、导出、大对象恢复失败：必须修复，并尽量转成自动测试。
- 权限、签名、Gatekeeper、焦点类失败：记录环境、复现步骤和系统提示文本。
- 文案/UI 问题：记录截图或具体页面位置，作为后续 polish 任务。
