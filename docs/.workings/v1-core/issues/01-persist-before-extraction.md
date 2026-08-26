# 01 — Persist before extraction

Status: completed

Blocked by: none

## Goal

建立可测试的 Swift 核心模块，并完成第一条纵向行为：用户显式开始文字提取后，原始 PNG 和准备记录都成功持久化，才允许向当前 Provider/模型发出一次请求。

## Scope

- 创建 macOS 14+ Swift Package 核心模块与测试 target。
- 通过公开应用工作流接口注入截图存储、历史存储和 Provider 边界。
- 保存原始 PNG 字节并取得路径与 SHA-256 描述。
- 创建准备请求记录后才调用 Provider。
- PNG 保存或准备记录失败时立即返回归一化本地错误，不调用 Provider。
- 一次用户执行最多调用一个 Provider；本票不实现自动重试。

## Acceptance

- 测试证明成功提取只能从已经保存截图并已经创建准备记录的公开状态到达。
- 测试证明 PNG 保存失败时 Provider 零请求。
- 测试证明准备记录失败时 Provider 零请求，并请求回滚本票新建且摘要匹配的文件。
- 测试证明成功路径上传的 `Data` 与输入原始 PNG 字节相同。
- `swift test` 全绿；新增 Swift 源码通过严格并发检查。

## Out of scope

- 真实文件系统与 SQLite 实现。
- 真实 Provider HTTP 协议与流式解析。
- 截图 UI、结果 UI 和本地化文案。
- 最终结果持久化、取消、超时和重试保存。

## Comments

- 该票先确立 spec 的应用工作流 seam；后续票只能扩展公开状态，不得绕过持久化门禁。
- 2026-08-26：实现与双重审查完成。实际门禁使用 `/Applications/Xcode.app` 的 toolchain；系统默认 Command Line Tools 与其 SDK build 不匹配，不能作为有效测试环境。
