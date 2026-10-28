# 26 — Make the DeepSeek reasoning timeout test deterministic

**Status:** in-progress

**Blocked by:** none

## 需求来源与分类

[v1-core spec](../../../specs/v1-core.md) §6（“首个有效文字事件超时与事件间停滞超时……DeepSeek 返回非空 `reasoning_content` 时，只刷新当前无活动计时”）与 Seam 2 Provider 适配器契约。
这是测试基础设施票，不改变产品行为，不为它虚构产品 REQ；它支撑上述既有条文的回归测试。用户于 2026-10-28 要求“file it as a ticket and fix it”。

## Problem and scope

`ProviderAdapterExecutorTests` 的 “DeepSeek reasoning activity keeps the first-text deadline alive” 用真实时钟：
假流在两段推理事件之间各睡 150 ms，首字与停滞截止为 250 ms。宿主繁忙时一次睡眠超出约 100 ms 余量，
首字计时到期，测试报 `.firstTextTimeout` 失败，与被测行为无关。

证据：PR #36 的 CI 运行 40711901881 第 1 次尝试在该测试失败（`ProviderAdapterExecutorTests.swift:106`，
Caught error: `.firstTextTimeout`），该分支未改动任何 Provider 代码；同一测试在本地两次全量门禁中通过。

范围：只改这一测试及其测试替身，使其不依赖真实时间；断言内容（推理活动刷新首字计时、最终事件序列）不变、不削弱。
不改产品代码，不改其他测试。

## Acceptance

- 测试改用注入的时钟决定截止何时到期，不再依赖真实睡眠时长；在宿主高负载下重复运行不再失败。
- 推理活动没有刷新首字计时（旧计时未取消或未重新计时）时，测试必须失败。
- 事件序列断言保持：`sourceDelta("Hello")`、metadata（`chat_reasoning`）、`completed`。

## 流程验收

- **Evidence** 代码审查：本票代码审查完成，结论、发现及处置可复查 — [ticket-26-review-code.md](../ticket-26-review-code.md)
- **Evidence** 测试审查：设计审查与实现后复核均已完成，结论、验证缺口及处置可复查 — [ticket-26-review-tests.md](../ticket-26-review-tests.md)
- **Evidence** 文档同步：交付前按“核销前的范围复核”核对现行状态与实际结果一致（本票状态、清单、相关记录），遗漏补入、过期说明就地更新；清单无待处理项，待触发项写明后续安排 — [ticket-26-doc-sync.md](../ticket-26-doc-sync.md)

## Comments
