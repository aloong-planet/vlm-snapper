## Agent skills

### Issue tracker

本仓库使用本地文件管理票。见 `docs/agents/issue-tracker.md`。

### 文档布局

本仓库采用单上下文文档布局。见 `docs/agents/docs-layout.md`。

### 项目能力

- **i18n：已启用。** UI 语言集为简体中文（源语言）和英语；产品 UI 不承诺 RTL 镜像。字典统一放在 `VLMSnapper/Resources/Localization/`（实现阶段创建）。运行时值、日志字段和持久化枚举使用语言无关的英文标识。

### 工作语言

- 源代码、代码注释和内置模型提示词统一使用英文。
- 产品 UI 文案必须来自本地化字典，不以仓库工作语言代替产品语言。
- 项目设计、需求和 ADR 文档可使用中文。
