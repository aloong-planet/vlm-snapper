# 27 — Test the total deadline and the default timeouts

**Status:** ready-for-agent

**Blocked by:** 26 (its manual timeout clock double is the cheapest way to drive these cases)

## 需求来源与分类

[v1-core spec](../../../specs/v1-core.md) §6：“首个有效文字事件超时与事件间停滞超时均为连续 10 秒无有效活动；单次请求总超时为 90 秒……DeepSeek 返回非空 `reasoning_content` 时，只刷新当前无活动计时”。
这是测试基础设施票，不改变产品行为，不为它虚构产品 REQ。来源：票 26 实现后复核的发现 4（`../ticket-26-review-tests.md`）；用户于 2026-10-29 决定建票（“file it as a ticket”）。

## Problem and scope

两条 §6 不变量没有任何测试驱动：

- 文字、推理等活动只刷新首字/停滞计时，**不得**重新开始或取消 90 秒总时限。现有 `totalDeadlineTerminatesOperation` 在没有任何活动时运行，删掉或改动 `receivedActivity` 对总计时的处理不会让任何测试变红；票 17 审查记录里“total timer 未被活动路径取消”的结论没有驱动它的用例。
- 默认值 10 s（首字）、10 s（停滞）、90 s（总时限）没有断言；改动 `ProviderStreamTimeouts` 的默认值时所有测试仍绿。

范围：只加测试（必要时复用票 26 的手动时钟替身），不改产品代码；若测试揭示产品偏离 §6，另行处理。

## Acceptance

- 流持续产生活动（推理与文字）时，总时限按开始时布置的那一个计时到期，活动不重新布置、不取消它；把活动路径改为重置总计时的变异必须让测试失败。
- 默认超时值分别断言为 10 s、10 s、90 s，并说明它们对应 §6 的哪一句；任一默认值改动必须让测试失败。
- 断言来源为 spec 原文数值，不从实现常量导入。

## 流程验收

- **Evidence** 代码审查：本票代码审查完成，结论、发现及处置可复查 — `ticket-27-review-code.md`（实施时建立）
- **Evidence** 测试审查：设计审查与实现后复核均已完成 — `ticket-27-review-tests.md`（实施时建立）
- **Evidence** 文档同步：交付前按“核销前的范围复核”核对现行状态与实际结果一致，清单无待处理项 — `ticket-27-doc-sync.md`（实施时建立）

## Comments
