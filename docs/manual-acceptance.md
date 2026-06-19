# Manual Acceptance

这份清单只用于人工验收，不放进自动测试、CI、脚本或 agent 默认验证。

## 启动与权限

- 用 Xcode Run `Maccy` scheme 启动。
- 首次自动粘贴前，系统设置里授予 Accessibility 权限。
- 未授权时选择历史项应只复制到剪贴板，不应继续模拟 Cmd+V。

## 捕获

- 复制短文本，历史列表出现该条。
- 复制超过大文本阈值的文本，列表不卡顿，详情可预览前缀，导出包含完整文本。
- 复制多文件 URL，历史列表保留文件信息，重新选择后 Finder/目标 App 能收到文件 URL。
- 复制图片，列表不阻塞，预览显示缩略图或图片信息。

## 运行时性能采样

- 复制短文本、大文本、图片时，日志里应出现 `Clipboard capture sample`。
- 正常样本应为 debug；超过阈值时应出现 warning。
- warning 阈值：
  - pasteboard read > `50 ms`
  - Core insert > `50 ms`
  - capture total > `100 ms`
  - thumbnail generation > `100 ms`
- 如果出现 warning，需要记录复制来源 App、内容类型、`types/read_ms/insert_ms/total_ms`。

## 检索与列表

- 搜索中文短词能命中老历史，不只命中最近几千条。
- 搜索 URL 片段、文件名片段能命中。
- Pin 后条目固定在前面，取消 Pin 后排序恢复。
- 删除、清空未固定、清空全部后 UI 立即响应。

## 粘贴

- 快捷键打开面板后，前台 App 焦点可恢复。
- 选择条目后写回系统剪贴板。
- 开启自动粘贴且已授权时，内容进入原前台 App。
- 自动粘贴失败时，不应造成 App 卡死或面板不可恢复。

## 每日导出

- 默认关闭每日导出。
- 开启后导出目录固定为 `Application Support/MaccyLite/Exports`。
- 手动导出不会卡设置界面。
- 手动导出失败时，设置页显示具体错误信息，不只显示通用失败。
- “打开导出目录”会创建并打开导出目录。
- 导出的 Markdown 按日期生成，包含文本、文件 URL、图片元信息和 asset 路径。
