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

---

# VLMSnapper v1 — Ticket 03 code review

审查范围：Provider 配置领域状态、官方模型目录、Apple Keychain 和非秘密元数据文件。

## 【① 底层前提】

- OpenAI、Gemini、DeepSeek 的模型列表请求形态以 2026-08-25 的官方文档和真实响应结构为基准；Gemini 完整分页、OpenAI/DeepSeek 单列表均由独立 HTTP fixture 驱动。
- 真实登录 Keychain 已实测增删改查；SwiftPM 未签名测试宿主无法访问 Data Protection Keychain，因此生产默认路径留到 Ticket 10 的签名 App 验证，不把测试降级参数误报为生产验证。
- DeepSeek 实验视觉模型不硬编码、不注入；只有账户列表实际返回精确 ID 时才进入候选。

## 【② 可运行性】

- 修复上层逃逸竞态：配置操作在外部异步边界挂起时，旧实现允许活动请求取得冻结并与 Key/模型变更重叠。现以互斥状态阻止请求冻结与配置变更交叠，定向变异移除保护后测试准确变红。
- 完整刷新成功才替换缓存并重置兼容性；当前模型消失时清除选择，刷新失败保留旧缓存与选择。
- 修复同层状态错误：新增或恢复另一个 Provider 曾会抢占已记忆但暂时失效的当前 Provider；现在只有全局当前 Provider 为空时才自动选中首个可用 Provider。
- Key 替换使用可恢复的 generation journal；崩溃发生在 Keychain 写入前后时，启动协调分别回滚或提交元数据。

## 【③ 安全正确性】

- API Key 只在完整模型列表成功后写入不可同步的 app 专属 Keychain 条目；普通元数据文件不包含 Key、请求或响应正文，文件权限为 `0600`。
- 修复上层路径逃逸：元数据目录的既有祖先为符号链接时，旧实现会穿透写入目标目录；现在创建前拒绝解析路径不一致，回归测试同时断言目标目录没有副作用。
- 只有明确的图片输入不支持证据会标记不兼容并清除选择；普通错误不改变状态。成功图片请求只验证实际使用的模型。

## 【④ 一致性】

- 官方端点、24 小时缓存、禁止手输、首个 Provider 选择、不自动回退、视觉状态和活动请求冻结与 spec、ADR-0001、ADR-0011 一致。
- 源码、注释和测试名均为英文；本票没有可独立操作的产品 UI，不提前写入 `docs/features/`。
- 重构清单：模型 ID 去空/去重逻辑在 Key 验证与刷新中重复，属于自伤型维护成本；清除 Provider 尚无删除 journal，元数据落盘失败时会留下“无 Key 的旧缓存”并可通过再次清除恢复。两项建议在 Ticket 07 接配置 UI 时结合真实恢复交互处理，不扩大本票。

## 结论

3 个实际 bug 已先红后绿修复；事实层修正后重扫安全与一致性层，无剩余 Ticket 03 阻断项。签名 Data Protection Keychain 与模型不可用后的请求级接线分别由 Ticket 10、Ticket 04 验收。

---

# VLMSnapper v1 — Ticket 04 code review

审查范围：OpenAI Responses、Gemini `streamGenerateContent`、DeepSeek Chat Completions 图片请求、SSE 解码、增量结构解析、统一事件/错误和超时执行器。

## 【① 底层前提】

- 三家协议以 2026-08-26 官方文档调研为基准，canonical 报告位于 `~/research/vlmsnapper-provider-adapters/`；没有把 OpenAI-compatible 当作共享 wire contract。
- DeepSeek 当前公开文档虽列出实验视觉模型，但其他官方页面仍有冲突；本票只完成隔离适配和录制契约，不声称真实账户、定价、请求上限或发布可用性已验证。
- 请求使用同一份原始 PNG；Gemini 对完整序列化 JSON 体执行严格小于 20,000,000 bytes 的门禁。OpenAI/DeepSeek 的签名版本化产品限制继续保留为发布 Pending。

## 【② 可运行性】

- 三个独立请求构造器接到一个执行 seam；每次用户操作只调用一次 transport，失败、超时和取消均终止当前流，不重放请求、不换模型。
- 首字和停滞超时各 10 秒，总超时 90 秒；时钟可注入，首字计时覆盖 HTTP 等待，收到每个有效文字增量后重置停滞计时。
- 修复同层 Unicode bug：按 Swift `Character` 前缀比较会把后到的组合音标误判为已有文本被改写；现按 UTF-8 前缀计算增量，同时保留合法 grapheme 延展。
- 修复同层 Gemini bug：STOP 后合法的 usage-only chunk 曾被拒绝，且 usage 字段部分缺失会使完整输出失败；现允许 STOP 后只更新元数据，并仅在三项 token 都存在时生成 usage。

## 【③ 安全正确性】

- SSE 只接受完整 UTF-8 frame；三个 Provider 都要求各自成功终态，截断、缺失 `[DONE]`、结构不完整、键顺序错误或成功终态缺失均不产生正式完成结果。
- HTTP 错误正文最多读取 64 KiB，只提取归一化证据，不向上暴露正文；额度、图片模态、图片过大、鉴权、模型、内容安全和服务错误分开映射。
- 429 只返回冷却提示，`Retry-After` 秒数截断到 60–300 秒；执行器没有自动计时重发路径。持久化冷却由后续操作编排接入。

## 【④ 一致性】

- 提取与翻译均是截图直送同一多模态模型的一次请求；翻译严格输出 `sourceDelta → translationDelta → metadata → completed`，符合 spec 和 ADR-0011。
- 源码、注释、测试名和英文提示词均为英文。本票没有用户可操作入口，`docs/features/` 仍由 Ticket 10 初始化，不提前宣称产品功能已可用。
- 残余发布门禁：真实 OpenAI、Gemini、DeepSeek 账户契约、签名 App 的取消行为及 Provider 限制必须在 Ticket 10 验证；失败时对应 Provider 不标记发布就绪。

## 结论

审查发现并修复 2 个真实增量/元数据 bug；重扫请求次数、终态、超时、取消和错误正文边界后，无剩余 Ticket 04 代码阻断项。真实在线契约明确保持 Pending。
