# 文档布局

本仓库采用单上下文结构。

## 结论类文档

| 位置 | 内容 |
|---|---|
| `CONTEXT.md` | 产品领域术语及应避免的同义词 |
| `docs/adr/` | 架构决策、备选项及取舍原因 |
| `docs/specs/<slug>.md` | 功能需求、边界和明确不做的内容 |
| `docs/features/<slug>.md` | 当前版本的用户可见行为 |
| `docs/prototypes/` | 界面与状态模型原型 |
| `docs/postmortems/` | 事故与问题的因果分析 |
| `docs/ops/` | 签名、打包、发布等运维手册 |

`docs/specs/` 与 `docs/features/` 使用相同的 slug。

## 过程类文档

`docs/.workings/<slug>/` 保存施工票、`review-code.md` 和
`review-tests.md`。

过程类文档在合并后保留，但不能作为当前行为的可靠依据。与结论类
文档冲突时，以结论类文档为准。

## 开始工作前

先读取：

- 仓库根目录的 `CONTEXT.md`
- `docs/adr/` 中与当前工作相关的 ADR

文件尚不存在时静默继续，由对应 skill 在首次需要时创建。

## 统一术语

issue、方案、假设和测试名称必须使用 `CONTEXT.md` 中定义的术语。
需要的新概念应交由领域建模流程裁定。

## ADR 冲突

新方案与现有 ADR 冲突时，必须明确指出所冲突的 ADR 及重新讨论的原因，
不得静默覆盖。
