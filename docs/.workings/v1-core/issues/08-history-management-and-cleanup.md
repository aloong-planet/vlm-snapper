# 08 — History management and cleanup

Status: completed

Blocked by: none (02 and 06 completed)

## Goal

实现统一管理中心、历史检索筛选、钉住、保留期和安全清理。

## Acceptance

- 标题栏类型筛选左对齐，搜索保留，详情和菜单栏入口定位正确。
- 7/30/60/90/180 天与默认 30 天符合 spec，钉住记录不自动清理。
- 永久删除不进废纸篓且无撤销；摘要不匹配文件永不删除。
- 批量部分失败继续并准确汇总。

## Comments

- 2026-09-13 requirements reconciliation: the original acceptance above covered type/search, but not all filter dimensions promised by the spec. Preserve this ticket's historical completion for its actual scope; it does not establish full history filtering. Current units are v1-core::US-001/AC-01, v1-core::US-001/AC-02, v1-core::US-001/AC-03, v1-core::US-001/AC-04, v1-core::US-001/AC-05, v1-core::US-001/AC-06, v1-core::US-001/AC-07, v1-core::US-001/AC-08 and v1-core::US-001/AC-09 in [v1-core spec](../../../specs/v1-core.md), reference 0febbb48fcd9acccdefc67dc9015ebf92605511c plus uncommitted updates. #23 tracks the missing native path; the [proposed vertical slice](../remaining-ticket-proposal.md) awaits approval. No new implementation or acceptance is claimed.
