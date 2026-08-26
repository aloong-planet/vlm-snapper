# VLMSnapper v1 — Ticket 01 code review

审查范围：Swift Package 核心模块与 `ExtractionCoordinator` 第一纵切。

## 【① 底层前提】

- 已实测 `/Applications/Xcode.app` 的 Swift toolchain 能为 macOS 14 构建并运行 Swift Testing；系统当前默认 Command Line Tools 的编译器与 SDK build 不匹配，因此验证命令显式指定 Xcode，不据默认 toolchain 下结论。
- 本票依赖的截图存储、历史存储和 Provider 都是系统边界协议；真实文件系统、SQLite 和 HTTP 行为没有在本票中假定为已验证，分别留给后续票。
- 首次红测中 Swift Testing 报告失败但命令层一度返回 0；最终门禁同时核对进程退出码与 Swift Testing 汇总，不能只信 XCTest 的“Executed 0 tests”兼容输出。

## 【② 可运行性】

- 发现并修复同层逃逸 bug：历史边界若返回另一张截图或另一组 Provider/模型，旧实现会带着错误历史身份上传原始 PNG。现在 Provider 调用前同时核对 `ManagedScreenshot` 和 `ProviderSelection`；不匹配时走安全回滚，测试覆盖截图摘要与模型选择两种不匹配。
- 截图保存失败是当前操作自伤：归一化后立即终止，Provider 零请求。
- 准备记录失败是当前操作自伤：先请求 `discardIfOwned`；成功时返回历史准备错误，失败时返回带孤儿路径的独立错误；两条路径均为 Provider 零请求。
- 成功路径一次调用 Provider，并把保存、准备记录和上传串成单一 actor 隔离流程。

## 【③ 安全正确性】

- Provider 只能收到与已保存截图和当前选择一致的 `PreparedExtraction`。
- 回滚职责位于 `ScreenshotPersisting.discardIfOwned` 边界，真实实现必须按路径与 SHA-256 验证所有权；协调器不会提供任意路径删除接口。
- 本票没有 API Key、日志或真实网络代码，不产生凭据暴露面。

## 【④ 一致性】

- macOS 14、Swift 6、英文源码/标识符与仓库约定一致。
- 行为符合 ADR-0006 的“先 PNG、再准备记录、后上传”和原始字节不变要求。
- 没有用户界面改动，因此本票无需新增视觉原型。
- 未发现需要立即执行或另开任务的重构项；真实路径类型、SHA-256 计算和数据库事务属于 Ticket 02 已承兑范围，不在本票投机实现。

## 结论

发现的 1 个一致性 bug 已通过先红后绿修复；重扫安全与一致性层后无剩余阻断项。
