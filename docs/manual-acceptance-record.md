# 人工验收记录模板

这份文件是人工验收记录模板。产品化关闭前，把 `docs/manual-acceptance.md` 的检查结果同步到 `dist/validation/manual-acceptance-record.md`。

开始人工验收前可先运行：

```sh
scripts/prepare-manual-acceptance-record.sh
```

脚本会从这个模板生成 `dist/validation/manual-acceptance-record.md`，并填充日期、macOS、机器、commit、App 路径和自动证据路径。

填写完成后运行：

```sh
scripts/validate-manual-acceptance-record.py
```

校验会确认 `Git commit` 等于当前仓库 HEAD，`自动证据` 指向退出码为 0 的报告，`App 路径` 指向真实存在的 `.app`。

## 构建信息

- 日期：
- macOS：
- 机器：
- Git commit：
- 构建命令：`scripts/build-local-app.sh`
- 自动证据：`dist/validation/automatic-evidence.md`
- App 路径：`dist/local/MaccyLite.app`
- 是否复制到 `/Applications`：是 / 否
- 验收人：
- 总结论：通过 / 有问题

## Result Matrix

| 范围 | 结果 | 证据 / 备注 |
| --- | --- | --- |
| 启动与权限 | 未验收 |  |
| 捕获短文本 | 未验收 |  |
| 捕获大文本 | 未验收 |  |
| 捕获 HTML | 未验收 |  |
| 捕获 RTF | 未验收 |  |
| 捕获多文件 URL | 未验收 |  |
| 捕获图片 | 未验收 |  |
| 运行时性能采样 | 未验收 |  |
| 搜索中文短词 | 未验收 |  |
| 搜索 URL / 文件名片段 | 未验收 |  |
| Pin / 删除 / 清空 | 未验收 |  |
| 未授权自动粘贴 | 未验收 |  |
| 已授权自动粘贴 | 未验收 |  |
| payload 恢复失败提示 | 未验收 |  |
| 每日导出默认关闭 | 未验收 |  |
| 手动导出 | 未验收 |  |
| 定时 / 启动补导出失败提示 | 未验收 |  |
| 打开导出目录 | 未验收 |  |
| `/Applications` 启动 | 未验收 |  |
| 长期运行观察 | 未验收 |  |

## 失败记录

| 编号 | 范围 | 复现步骤 | 实际结果 | 期望结果 | 处理结论 |
| --- | --- | --- | --- | --- | --- |
|  |  |  |  |  |  |

## 后续处理规则

- 核心捕获、搜索、粘贴、导出、大对象恢复失败：修复，并优先补 `ClipboardCore` 测试或非 GUI 静态守卫。
- 权限、签名、Gatekeeper、焦点类失败：记录系统提示文本、macOS 版本、App 路径和复现步骤。
- 文案/UI 问题：记录具体页面和可接受修改，不阻塞核心产品化，除非影响主要流程。
