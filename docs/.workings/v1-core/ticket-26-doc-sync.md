# 文档同步清单

票：[26 — Make the DeepSeek reasoning timeout test deterministic](issues/26-deterministic-reasoning-timeout-test.md)。

本票只改测试与施工记录，不改变产品行为：`docs/features/`、spec、ADR、CONTEXT 没有哪句话因此成谎或缺句（核对见下方范围复核），不列行。

| 同步事项及触发时点 | 涉及文档 | 状态与说明 |
|---|---|---|
| 交付时回写票状态与证据摘要（开 PR 时） | [issues/26](issues/26-deterministic-reasoning-timeout-test.md) | 待处理：开 PR 后写入 Comments（复现、修复、门禁、复核结论与 PR 链接） |
| 票 17 指向本票（测试机制变化，事件） | [issues/17](issues/17-deepseek-reasoning-stream-activity.md) | 已完成：Comments 追加 2026-10-28 条目 |
| 复核发现 1、2 的更正（测试注释、票 26 验收第 1 条、`ticket-26-review-code.md`、本票测试审查记录 T1 行） | [issues/26](issues/26-deterministic-reasoning-timeout-test.md)、[ticket-26-review-code.md](ticket-26-review-code.md)、[ticket-26-review-tests.md](ticket-26-review-tests.md) | 已完成：`96f7e7f` |
| 复核发现 4 的后续：用户决定建票时在票 17 的 Comments 追加指向 | [issues/17](issues/17-deepseek-reasoning-stream-activity.md) | 待处理：等待用户决定建票或放弃；放弃则移除本行并写明原因 |
| 票关闭（随本 PR 合并） | [issues/26](issues/26-deterministic-reasoning-timeout-test.md) | 待处理：合并前在本 PR 内写为“随本 PR 合并完成”的状态 |

## 核销前的范围复核（2026-10-28）

范围：本票改动（`8c00b2d..HEAD`）、`docs/.workings/v1-core/`（票、清单、本票记录）、spec §6 与 Seam 2 的超时测试表述。
spec §6 “DeepSeek 返回非空 `reasoning_content` 时，只刷新当前无活动计时”与 Seam 2 “三个超时”的测试要求，经新测试仍被驱动（断言未削弱，另加对重新计时的断言），陈述保持为真；双语检索（`grep -rn -i -E 'reasoning' docs/.workings/v1-core docs/specs` 与 `grep -rn -E '推理' docs/.workings/v1-core docs/specs`，除本票文件外全部命中逐一判定）：
- 票 17 的原始记录（`issues/17-…`、`review-code.md:802–820`、`review-tests.md:733–755`、`final-regression.md:759–792`）：2026-09-02 当时的审查与回归；`review-tests.md:739`、`:748` 描述旧测试靠 150 ms + 150 ms 真实时间与 250 ms 期限判定——当时为真，原始记录不改写；已在票 17 的 Comments 追加 2026-10-28 一条指向本票。
- `checklist.md:481` 票 17 状态行：仍为真，不改。
- `requirements-alignment.md:105`、`:107`（推理/thinking 模式与高级参数）：与本票无关，仍为真。
- spec `:94`（推理档位）与 `:100`（§6 推理活动只刷新无活动计时）：仍为真；`:100` 仍由本测试驱动。
