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

---

# VLMSnapper v1 — Ticket 02 code review

审查范围：受管理截图文件系统、SQLite 历史与数据库保留式重置。

## 【① 底层前提】

- 通过真实 APFS 临时目录实测 `Data.write`、同秒文件冲突、符号链接路径和替换文件行为，不以 Foundation 文档推断代替运行结果。
- 通过系统 SQLite 3 实测 WAL 重开、schema 元数据、损坏字节、`quick_check`、恢复文件及 `-wal`/`-shm` 边车文件。
- 原始 PNG fixture 至少一例使用真实可解码 1×1 PNG，SHA-256 期望值是独立固定摘要；其余只验证 opaque bytes 的用例不声称覆盖 PNG 编码。

## 【② 可运行性】

- 修复上层逃逸 bug：旧版初始化先切 WAL 再检查 schema，会改写本应只读阻断的新版库；现改为任何写入前完成版本、完整性和必需列预检。
- 修复同层逃逸 bug：版本为 1 但 `operations` 缺列时原实现会成功打开，后续所有历史操作才失败；现于启动时阻断且保持数据库字节不变。
- 修复同层逃逸 bug：普通终态 API 曾允许写出没有结果的成功记录或没有原因的失败记录；现成功与失败必须携带对应 payload。
- 启动恢复只把 preparing、uploading、streaming 改为 interrupted，已成功记录保持不变；取消与结果保存失败分别持久化。
- 保留式重置先移动主库及 WAL/SHM，再创建并验证空库；同秒 recovery 文件使用 `-2` 后缀且不覆盖旧副本。

## 【③ 安全正确性】

- 修复上层逃逸 bug：只检查根目录自身会沿祖先符号链接写到外部目录；现根、祖先、月份目录和最终文件四类静态链接均拒绝。
- 加载与删除前同时验证目录边界、文件命名、常规文件类型和 SHA-256；缺失、替换或链接文件均不能显示、上传或删除替代内容。
- 新版、损坏或结构不完整数据库在任何应用写入前阻断；重置只有显式调用恢复服务才会发生，服务不提供静默重建路径。
- 残余限制：同一用户的其他进程若在检查与系统调用之间做纳秒级路径替换，Foundation 路径 API 无法提供 inode 条件删除；在清理票接入并发删除前，应评估基于目录描述符的 POSIX seam。静态替换与所有符号链接形态已经覆盖。

## 【④ 一致性】

- 路径、命名、30 秒时间精度、原始 PNG 字节、schema 阻断和恢复副本均与 spec、ADR-0006、ADR-0008 一致。
- 源码、注释、测试名和持久化枚举均使用英文；本票没有界面变更，不新增视觉原型或用户可见功能目录项。
- 重构清单：`FileSystemScreenshotStore` 的 load/discard 所有权验证和 `SQLiteHistoryStore` 的状态更新存在重复代码，属于自伤型维护成本；建议后续在相邻票需要扩展这些 seam 时合并，不为本票单独扩大改动。

## 结论

4 个实际 bug 已补红测并修复；事实层修正后重扫安全与一致性层，无剩余发布阻断项。保留 1 个跨进程 TOCTOU 加固点和 2 个自伤型重复代码重构项，均不改变本票已承兑的静态所有权行为。
