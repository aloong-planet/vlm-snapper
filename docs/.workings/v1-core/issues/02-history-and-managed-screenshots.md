# 02 — History and managed screenshots

Status: blocked

Blocked by: 01

## Goal

实现 SQLite 历史、操作终态、结果落库恢复和受管理截图的路径与 SHA-256 所有权。

## Acceptance

- 原子 PNG 写入、同秒冲突命名、符号链接拒绝、目录边界和回滚行为可集成验证。
- 成功、失败、已取消、意外中断和结果保存失败可持久化与恢复。
- 文件缺失或摘要不匹配时禁止显示、上传和删除替代文件。
- 数据库损坏或版本过新时阻断写入，重置前保留恢复文件。

## Comments
