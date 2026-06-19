# 上游 Maccy Issue / PR 学习记录

本文记录从 `p0deje/Maccy` 上游 issue 和 PR 中筛出来的有效经验。目标不是跟随上游功能，而是服务 MaccyLite 的定位：轻量、稳定、不卡顿、适合个人长期剪贴板记录和每日导出。

## 判断标准

- 优先跟：性能、内存、搜索、大对象预览、自动粘贴稳定性、多屏弹窗位置、数据一致性。
- 谨慎跟：Pins 管理、快捷键细节、导出增强。只有真实使用痛点出现后再做。
- 不跟：Workspace、Todo、OCR、URL 清洗、同步、多语言扩展、复杂分组。这些会把工具推向 All-in-one。

## 已吸收并落地

### 大历史性能

参考：
- [#1372](https://github.com/p0deje/Maccy/issues/1372)
- [#1391](https://github.com/p0deje/Maccy/pull/1391)
- [#1373](https://github.com/p0deje/Maccy/pull/1373)

上游问题是打开面板时加载和准备过多历史对象，历史量大后面板出现延迟。MaccyLite 已经采用更直接的方案：列表查询只拿轻量字段，限制首屏数量，右侧预览按选中项加载，搜索有 debounce 和候选集限制。

后续只在真实卡顿复现时继续做分页滚动，不提前引入复杂状态机。

### 大对象预览和内存

参考：
- [#1365](https://github.com/p0deje/Maccy/issues/1365)
- [#1378](https://github.com/p0deje/Maccy/pull/1378)
- [#1416](https://github.com/p0deje/Maccy/pull/1416)

上游反复出现的问题是大图片、大文本、缩略图和预览面板触发主线程卡顿。MaccyLite 的原则是：

- 列表不解码大图。
- 图片和文件只在选中后预览。
- 文本预览不做用户可感知的“逐段加载”。
- 大 payload 内部可以资产文件化，但粘贴语义必须还原原内容。

这条线继续作为性能优化主线。

### 搜索输入保护

参考：
- [#1394](https://github.com/p0deje/Maccy/pull/1394)

上游指出用户可能误把大段剪贴板内容粘进搜索框，导致正则或 fuzzy 搜索卡死。MaccyLite 已吸收为搜索入口硬上限：搜索 query 最多处理 1000 个字符。

### 自动粘贴权限

参考：
- [#1210](https://github.com/p0deje/Maccy/issues/1210)
- [#1381](https://github.com/p0deje/Maccy/issues/1381)

自动粘贴失败通常不是业务逻辑问题，而是 macOS 辅助功能权限问题。MaccyLite 已经把 Enter 默认改成直接粘贴，并在权限缺失时显示明确提示。

### 多屏和边缘弹窗

参考：
- [#1421](https://github.com/p0deje/Maccy/issues/1421)
- [#1364](https://github.com/p0deje/Maccy/pull/1364)

上游有多屏边缘位置弹到相邻屏的问题。MaccyLite 目前默认居中，风险较低，但仍已对弹窗 origin 做 visibleFrame clamp，避免从当前屏幕可见区域溢出。

### 去重和数据一致性

参考：
- [#1368](https://github.com/p0deje/Maccy/issues/1368)
- [#1369](https://github.com/p0deje/Maccy/pull/1369)
- [#1387](https://github.com/p0deje/Maccy/pull/1387)
- [#1257](https://github.com/p0deje/Maccy/issues/1257)

上游 SwiftData 路径容易在重复项合并时留下 orphan content。MaccyLite 已经改成 DB 层 canonical payload fingerprint 去重：按可粘贴内容合并，并保留最新 payload。因为我们不背旧库迁移，不做 DB compaction 兼容逻辑。

## 暂不跟

### Workspace / Group / Tabs

参考：
- [#1408](https://github.com/p0deje/Maccy/issues/1408)
- [#1417](https://github.com/p0deje/Maccy/pull/1417)
- [#1221](https://github.com/p0deje/Maccy/pull/1221)

这类功能会明显增加信息架构和状态复杂度。对 MaccyLite 当前目标来说，搜索、Pin、每日导出已经足够。

### OCR / 图片文字提取

参考：
- [#1152](https://github.com/p0deje/Maccy/pull/1152)
- [#1229](https://github.com/p0deje/Maccy/issues/1229)

已明确不做。图片只做预览和粘贴还原。

### URL 清洗 / 自动处理内容

参考：
- [#1413](https://github.com/p0deje/Maccy/pull/1413)
- [#1366](https://github.com/p0deje/Maccy/issues/1366)

这会改变用户复制内容的语义。MaccyLite 的原则是记录和还原，不默认改写内容。

### 多选、批量粘贴、Todo

参考：
- [#1401](https://github.com/p0deje/Maccy/pull/1401)
- [#1402](https://github.com/p0deje/Maccy/issues/1402)
- [#1377](https://github.com/p0deje/Maccy/issues/1377)

这些功能可能有用，但不属于当前核心路径。只有个人使用中明确需要，才以独立小功能评估。

## 后续观察清单

- 搜索 query 上限是否影响真实搜索。
- 大图片和文件连续复制后的内存占用。
- 辅助功能权限被系统重置时的提示是否足够明确。
- 多显示器下 `center`、`statusItem`、`cursor` 三种弹窗位置是否稳定。
- Pin 项在去重和清理历史时是否保持稳定。
- 高频复制时 CPU 是否仍稳定，特别是富文本和文件 URL。
