# 04 — Provider adapters

Status: completed

Blocked by: 01, 03

## Goal

实现 OpenAI、Gemini、DeepSeek 官方图片请求适配器和统一流式事件/错误契约。

## Acceptance

- 三个适配器通过同一组录制响应契约测试。
- 翻译事件严格按原文、译文、元数据、完成输出。
- 首字、停滞和总超时可注入时钟验证；截断与不完整结构不会保存残缺结果。
- 每次执行只有一个 HTTP 请求，无自动重试或回退。
- DeepSeek 发布状态仍受真实密钥 Pending 门禁约束。

## Comments

- Canonical protocol research: `/Users/loong_zhou/research/vlmsnapper-provider-adapters/ticket-04-provider-adapter-contracts-2026-08-26.md`.
- Each user action sends exactly one model request. Provider SDK retry defaults are not adopted.
- OpenAI uses Responses, Gemini uses `streamGenerateContent`, and DeepSeek uses Chat Completions; each has an independent wire decoder behind one normalized event contract.
- Recorded fixtures, byte-boundary SSE tests, injectable timeout tests, and no-retry request-count tests pass. Live-account contract checks and signed provider limits remain release gates; no live API request was made in this ticket.
