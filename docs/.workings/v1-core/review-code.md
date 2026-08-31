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

---

# VLMSnapper v1 — Ticket 05 code review

审查范围：ScreenCaptureKit 多显示器冻结、显示器本地物理像素选区、sRGB PNG 裁切、快捷键协调器及 Carbon C shim。

## 【① 底层前提】

- 冻结帧由快捷键上层触发后立即调用的 capture seam 产生，鼠标松开只裁切已有 `CGImage`，不再访问实时屏幕。
- Carbon 只封装系统仍提供的全局热键注册/事件处理 C API；C shim 独占不安全指针与 callback 生命周期，Swift 只接收 registration ID，并在 MainActor 交付行为。
- 真实快捷键回调、系统冲突、TCC 与多屏热插拔需要签名 App 和实际显示器，继续作为 Ticket 10 集成门禁，不用 SwiftPM 生命周期 smoke 冒充。

## 【② 可运行性】

- 显示器并行独立捕获，权限拒绝走全局恢复；断开、几何变化和普通捕获失败只禁用对应显示器。成功帧按 display ID 排序，选区不接纳后来出现的显示器。
- 修复 actor 重入竞态：异步裁切期间取消不会被裁切完成复活；选中显示器失效时保留其他冻结屏并回到 selecting；取消优先于随后到达的底层裁切失败。
- 修复快捷键生命周期：协调器销毁会注销仍活动的注册，避免 backend 继续持有失去所有者的全局热键；替换仍保持“新注册成功后再撤旧注册”的原子顺序。

## 【③ 安全正确性】

- 物理像素矩形先用无加法溢出的边界公式校验，再裁切、重绘为 8-bit sRGB 并编码 PNG；极端 `Int.max` 坐标返回明确错误而不触发进程 trap。
- 显示器在系统捕获前后各读取一次逻辑边界、物理像素与旋转；任一变化或返回图像尺寸不匹配均拒绝该帧。
- `CGImage` 只通过不可变 retained reference 跨并发边界；完成或取消后选区 actor 清空所有冻结帧，仅返回最终 PNG `Data`。

## 【④ 一致性】

- 默认 `⌥⇧S`、至少一个主修饰键、保留键拒绝、冲突保留旧注册、2 × 2 下限、单屏失效和原始 sRGB PNG 均与 spec 及 ADR-0010 一致。
- 源码、注释和测试名均为英文。本票仍没有可独立操作的 App/UI，`docs/features/` 留到 Ticket 10 初始化，不提前宣称用户可用。
- 操作栏、单活动任务、重复快捷键语义与结果窗口属于 Ticket 06，不在本票核心 seam 中假接线。

## 结论

审查发现并先红后绿修复 4 个状态/边界 bug 和 1 个快捷键生命周期 bug；严格 Swift/C 构建及完整 105 例测试通过。真实 macOS 集成门禁明确保留，无剩余 Ticket 05 代码阻断项。

---

# VLMSnapper v1 — Ticket 06 code review

审查范围：操作工作区 actor、持久化 runner、历史 schema v2、操作栏与结果窗口原生 UI。

## 【① 底层前提】

- SwiftUI 只负责快照展示与显式 intent；请求次数、截图所有权和终态持久化由 actor/runner seam 约束，不能由按钮禁用状态代替。
- AppKit panel/window 已通过真实 harness 渲染核对明暗外观与 4 px 操作栏位置；签名 App 的点击、键盘、辅助功能和 TCC 行为仍属于 Ticket 10 集成门禁。
- 历史 schema v1 只有提取记录，因此迁移时将旧行确定性标记为 extract，不推断不存在的翻译目标。

## 【② 可运行性】

- 修复 actor 重入竞态：请求等待全局 lease 时切换结果标签，旧实现会重新读取标签并偷换请求类型；现在首次点击即冻结 operation kind，等待后不再读取展示选择。
- 修复截图所有权泄漏：新截图保存后、历史准备接管前收到取消，旧实现保留了无历史所有者的文件与缓存；现在取消与普通准备失败使用同一安全回滚路径。
- 修复取消状态错记：HTTP/executor 会把 Swift 取消归一化为 `ProviderAdapterError.cancelled`，旧 runner 会持久化 failed；现在两种取消信号都写入 canceled 并向会话抛 `CancellationError`。
- 修复窄屏布局：当包含长模型名的操作栏宽于可见屏幕时，旧 x 公式会把左端移出屏幕；现在至少固定可操作的 leading edge 在可见区域。

## 【③ 安全正确性】

- Provider 请求只在截图保存、typed operation 准备及准备结果身份核对后开始；不一致记录、准备失败和新截图取消都不会访问 Provider。
- 最终结果落库失败只保留内存结果并提供 Retry Save；未保存结果阻断任何后续模型请求，关闭需要确认，保存重试不触发 Provider。
- Provider/model/operation/target 在请求前冻结；失败不自动重试、不换模型、不重放，partial delta 不进入 committed result。

## 【④ 一致性】

- 操作栏 4/3/25/6 px 常量、顶部分段切换、左右双区结果和明暗语义色与已确认原型一致；无标注、画线或画框能力。
- 28 个 zh-Hans/en 键成对存在；产品源码、注释与提示词保持英文，用户文案只通过本地化目录进入。
- `docs/features/` 仍未初始化：Ticket 06 已有可渲染组件但尚无 Ticket 07 App 入口，不提前宣称最终用户可独立使用。

## 结论

审查发现并先红后绿修复 4 个实际竞态、所有权、状态与布局问题；严格构建和完整 127 例测试通过。无剩余 Ticket 06 代码阻断项，签名 App 系统交互保留为 Ticket 10 发布门禁。

---

# VLMSnapper v1 — Ticket 07 code review

审查范围：首次引导与附着面板、权限恢复 actor、Provider 配置 presentation actor、菜单栏入口与离屏渲染 harness。

## 【① 底层前提】

- Core Graphics 的公开预检只返回可访问/不可访问，无法可靠区分从未请求、用户拒绝和后来撤销。实现只用本安装的“曾请求”布尔记录区分首次请求与统一恢复状态，不向用户伪报不可观察的细分类别。
- 权限请求、Provider 网络和 Keychain 不由 SwiftUI body 触发；视图只发显式 intent。系统请求只有 `performPrimaryAction` 的首次分支可调用。
- 直接桌面截图被当前锁屏拦截，未当作视觉证据；随后通过真实 `NSHostingView`/AppKit 离屏窗口渲染 5 个入口表面、明暗各一份并人工逐图检查。

## 【② 可运行性】

- 修复上层入口顺序错误风险：菜单截图固定先检查可用 Provider/当前模型，再检查权限；否则全新安装会在模型尚未配置时提前触发 TCC 流程。定向反转顺序后测试准确红。
- 修复同层权限竞态：系统授权框尚未返回时重复点击，旧实现会并发进入恢复分支并打开系统设置；现在 actor 合并重叠 intent，第二次返回 no-op。该用例在旧行为上准确红。
- 修复同层 Provider 重入：模型选择挂起时切换侧栏，旧完成结果可能写回新 Provider 的 presentation；generation guard 保留新选择，定向挂起测试在旧实现上红。
- 修复上层 Provider 不变量破坏：presentation 层曾在每次选模型后强制设置全局当前 Provider，会让后来配置抢占已记忆选择；现只调用既有 `selectModel`，由核心协调器在“当前为空”时自动采用首个可用 Provider。
- 修复上层只读缺口：活动模型请求期间，Provider presentation 曾仍可发出验证、刷新、模型和 Provider 切换；现统一 `isReadOnly` 同时阻断 actor mutation 与控件交互。移除验证 guard 的定向变异在系统边界记录处红。

## 【③ 安全正确性】

- API Key 仅存在于 SecureField binding，验证成功、取消或完成时清空；持久写入仍完全委托现有 Keychain 协调器。菜单、历史预览、错误与本地化文案不包含密钥或响应正文。
- 权限请求历史只写一个非秘密布尔值；首次 intent 在调用系统 API 前持久标记，拒绝/撤销后不会重复弹系统框。
- 统一恢复面板提供取消、系统设置或重启 intent；实际打开设置/终止重启由应用组合回调注入，未在视图层增加任意 URL 或进程控制路径。

## 【④ 一致性】

- 引导 Direction A、Provider Direction B、菜单 Direction C 和权限 Direction A 均由真实 SwiftUI 组件实现；Provider 顺序、8 px 面板圆角、24 pt 固定标识和模型验证提示在渲染检查后与原型同步。
- 83 个 zh-Hans/en 键成对存在；源码、注释、测试和提示词保持英文，产品 UI 无直接硬编码文案。
- 重构清单：引导与菜单容器各有一段 Provider sheet 回调接线，属于自伤型重复代码；Ticket 09 组合生产 App 时可抽成共享 presenter。当前两处都复用同一个 `ProviderSetupView` 和同一 core session，行为没有分叉，故本票不扩大范围重构。

## 结论

审查发现并修复 5 个入口顺序、异步竞态、Provider 不变量和只读状态问题；事实层修正后重扫安全与一致性层，无剩余 Ticket 07 阻断项。签名 TCC、真实 System Settings/重启和状态栏点击仍按 Ticket 10 集成门禁保留。

---

# VLMSnapper v1 — Ticket 08 code review

审查范围：历史 schema v3、查询与 metrics、删除/保留期协调器、管理中心窗口和离屏渲染。

## 【① 底层前提】

- v1/v2 没有持久化创建时间，不能安全推断旧记录真实年龄；迁移统一使用迁移时刻，避免升级后第一次清理意外删除全部旧历史。
- 缺失文件和摘要/路径不匹配只证明原图不可用，不等同于应用可删除路径上的当前文件；内部记录可删除，但替代文件始终不触碰。
- SwiftUI 渲染测试使用当次构建的真实 AppKit hosting/window 产出；兼容 XCTest 的 `Executed 0 tests` 未作为通过证据。

## 【② 可运行性】

- 修复清理遗漏：删除某月最后一张受管理 PNG 后，旧实现留下空 `YYYY-MM` 目录；现在仅在目录完全为空时移除，VLMSnapper 根目录保留。
- 修复管理中心状态接线：已钉住入口现在真正过滤，History 与 Pinned 不会同时选中；Provider 与通用设置使用各自页面状态。
- 修复窗口刷新：已显示的管理中心收到新记录、图片、失败数量或保留期后会重建当前 destination 内容，不再只更新未被视图读取的属性。
- 批量删除的单项文件错误是自伤边界，不再向同层逃逸；失败项保留，后续候选继续执行，汇总 deleted/failed/skipped。
- 历史单条删除按 ID 查询，不再为批量中的每条记录加载全库正文，避免 O(n²) 热路径。

## 【③ 安全正确性】

- 唯一删除路径先执行现有路径、符号链接、规则文件名和 SHA-256 所有权门禁，再删除数据库记录；缺失或替换只删内部记录。
- 活动记录在协调器和数据库删除语句两层拒绝；自动清理永不授权钉住记录，清空历史只有显式选择才能包括钉住项。
- Provider usage 只保存终态 metadata 的真实值；缺失显示不可用，不估算费用。首字与总耗时由 runner 单次执行时钟产生，用户重试不会聚合。
- 搜索与筛选全部在本地数据库/内存记录上完成，不把历史内容发送给 Provider。

## 【④ 一致性】

- 类型筛选左对齐、搜索右对齐、列表/详情从工具栏下开始，与已确认 management-center 原型一致；历史和设置复用同一个窗口 controller。
- 永久删除/清空使用系统确认界面，无 Trash、无撤销；清空明确区分保留钉住和包括钉住。
- 新增本地化键成对存在；耗时、Token 三项和保留天数使用本地化格式，源码/注释/测试保持英文。
- `docs/features/` 仍不初始化：仓库尚无生产 App executable，按“出现即可用”不提前声明最终用户可运行；Ticket 10 负责全功能目录收口。

## 结论

审查发现并修复空月份目录、侧栏状态、窗口刷新和批量查询资源问题；事实层修正后重扫安全与一致性层，无剩余 Ticket 08 核心阻断项。生产组合、真实菜单栏跳转与签名产物仍是 Ticket 09/10 集成门禁。

---

# VLMSnapper v1 — Ticket 09 code review

审查范围：单实例租约与激活、脱敏诊断、本地化、登录项、Sparkle 产品用户驱动，以及菜单/通用设置更新表面。

## 【① 底层前提】

- 锁文件本身不代表所有权；只有进程持有的内核 advisory lease 才是主实例证据，崩溃后由内核释放。
- Sparkle 的下载按钮只消费一次公开 choice reply；按钮点击不是下载成功证据，下载中和已下载状态只接受 Sparkle 回调。
- 当前 Package 仍没有签名生产 App。SMAppService、跨进程唤醒、真实 appcast、退出安装和公证产物不能由库测试冒充，继续是 Ticket 10 门禁。

## 【② 可运行性】

- 修复 Swift 对 Darwin `flock` 名称歧义：窄 C seam 持有真实同步锁，新增测试验证第二所有者失败且 lease 释放后恢复。
- 修复 Sparkle 回调潜在乱序：独立 Task 改为串行 delivery chain；测试按 available → started → expected bytes → bytes → ready 逐项断言。
- 修复诊断截止日提前删除：七天 cutoff 改为 UTC 日界线，完整保留截止当天；gzip 由系统 `/usr/bin/gzip -dc` 验证可解压原文。
- 修复语言 bundle 切换缓存：显式加载目标 `Localizable.strings` 词典，避免同 key 在进程内沿用旧语言；设置变化暴露 restart-required 和一键重启 intent。

## 【③ 安全正确性】

- 诊断入口只接受 typed allowlist；无自由消息、正文、路径、截图、密钥、请求/响应或认证头字段。动态 token 不符合字符/长度规则即整字段省略。
- gzip C seam 对 `uInt` 输入/输出上界显式拒绝，所有分配路径释放；导出只聚合受管理日文件。
- 信息型更新带 HTTPS intent，不显示 Download，也不能进入 Core 下载路径。Provider/Sparkle 原始错误不持久化或直接展示。
- 登录项注册后重新读取系统状态；`requiresApproval` 不伪装成启用成功，并保留打开系统设置 intent。

## 【④ 一致性】

- 菜单提醒和 General Settings 共享同一 `UpdateLifecycleState`；状态栏注意点只对 available/downloading/ready 显示。
- 确认原型中的无自动下载、六小时自动检查开关、下载/查看/退出安装、语言、登录项、保留期和诊断入口均已进入双语 SwiftUI。
- review 期间恢复了 AGENTS 原有 issue tracker 与 docs layout 入口，i18n 能力声明只追加不覆盖。
- `docs/features/` 继续不初始化：仓库尚无生产 App executable，按“出现即可用”不提前宣称最终用户可运行；Ticket 10 负责全功能目录收口。

## 结论

审查发现并修复回调乱序、诊断截止日、语言缓存和 AGENTS 覆盖四类真实问题。库与 UI 层无剩余 Ticket 09 阻断项；签名系统交互明确留在 Ticket 10。

---

# VLMSnapper v1 — Ticket 10 code review

审查范围：生产 App 组合、截图 host、目标语言与快捷键、退出/清理/诊断接线、三架构构建及正式发布流水线。

## 【① 底层前提】

- ad-hoc 签名只能验证 bundle 与装载形态，不能替代 Developer ID、Apple notarization、stapling 或 Gatekeeper；三份开发 DMG 明确不作为正式发布证据。
- Sparkle 的最终 EdDSA 必须覆盖公证并 stapling 后的 DMG；三个架构使用同一产品身份和公钥，但各自读取独立 appcast。
- ScreenCaptureKit 冻结结果可能乱序返回；触发代次而非 Task 完成顺序决定哪一次截图有权展示。

## 【② 可运行性】

- 修复快速重复快捷键竞态：旧冻结任务返回时只释放自己的 session，不能覆盖新一代 overlay；选区/操作栏重触发重新冻结，活动模型 workspace 只前置结果窗。
- 修复最近记录入口只打开历史页但不选中记录；现在解析 UUID、载入记录与受管理截图并定位详情。
- 修复生产进程只在启动执行一次清理；现在应用生命周期每小时唤醒，Core scheduler 仍严格限制 24 小时最多一次。
- 修复启动快捷键冲突导致整 App 退出；冲突只在设置中呈现，应用其余入口保持可用，成功替换先注册新键再释放旧键。
- 修复全部显示器失败后无解释退出；现在关闭 capture surfaces 并显示本地化 Retry/Cancel，权限失败继续走 TCC recovery。

## 【③ 安全正确性】

- 修复未保存结果保护只覆盖菜单 Quit/立即安装的问题；`applicationShouldTerminate` 统一拦截 Command-Q、Sparkle 自主终止等路径，语言重启也先走同一 coordinator。
- 修复“确认丢弃”没有实际状态转移；明确清除未保存完成结果后才关闭 workspace，取消确认时保持窗口与数据。
- 诊断仍是 typed allowlist 和七天本地保留；导出失败不再静默，显示不包含内部路径或原始错误的本地化说明。
- 发布脚本只在所有架构、签名、公证、staple、Gatekeeper、feed 与 EdDSA 验证完成后，把六个文件同文件系统原子移动到输出目录；CI 临时私钥、p12 与 keychain 在 always step 清除。

## 【④ 一致性】

- 操作栏 4 px 距离、25 px 控件、6 px 圆角和单行结构保持确认原型；中英文/明暗共 4 张当前 toolbar render 已逐图核对。
- 通用设置加入固定尺寸原生快捷键 recorder；Ticket 09 的 32 张当前 render 复核无错位或长英文截断。
- `docs/features/v1-core.md` 只描述开发应用中的已实现行为，并在顶部和发布章节声明尚不具备正式公开发布资格。
- 代码、注释、测试、提示词、commit/PR 文案保持英文；用户界面仅通过成对 zh-Hans/en 字典输出。

## 结论

实现层自审修复截图乱序、最近记录定位、清理周期、快捷键启动、全屏失败反馈、未保存丢弃和统一退出七类问题。开发应用与发布流水线形态无已知代码阻断项；正式完成仍被 Developer ID、公证、公共 HTTPS 和真实 Provider 门禁阻塞。

---

# VLMSnapper v1 — Ticket 10 live Provider gate code review

审查范围：live-contract Core runner、脱敏报告 CLI、固定无敏感 PNG 与正式 GitHub workflow 接线。

## 【① 底层前提】

- GitHub 仓库当前没有任何 Actions Secret 或 Variable；本机没有有效 Developer ID 签名身份，只有本地 Gemini 凭据。因此工作流存在不等于正式门禁已通过。
- 真实 Gemini 响应并不稳定：相同固定输入实测同时出现通过、结构化输出错误和 10 秒首字超时。录制 fixture 只能证明 decoder 对已知形态的兼容性，不能替代 live gate。
- timing 原先使用 wall clock，系统时间调整会污染报告；审查中改为 monotonic uptime，避免倒退或跳时。

## 【② 可运行性】

- runner 以 `ProviderID.allCases` 的确定顺序逐个执行；缺 key/model 时零网络并记录 blocked，配置完整时每家只调用一次截图翻译流。
- 只有 source、translation、metadata、completed 全部通过统一 accumulator 才记 passed；Provider 错误、不完整 EOF 或事件顺序错误分别记 request/validation failure。
- CLI 无凭据 smoke test 实际写出三条 blocked 报告并返回 1；完整 Swift build 与 190 tests / 46 suites 通过。正式工作流失败后仍上传报告，后续发布构建因前置失败不会运行。

## 【③ 安全正确性】

- 报告结构没有 API key、认证头、PNG、原文、译文或原始响应槽位；Provider request ID 先做 SHA-256 截断摘要，usage 只接受终态 metadata。
- CLI 异常只输出固定错误句，不插值底层 error；报告原子写入指定路径，正文同时输出到 CI 日志时仍只有 allowlist 字段。
- 固定测试图仅在内存生成，内容只有产品名，不写入 artifact；产品 10 秒/90 秒 timeout 和“失败不自动重试”规则原样生效，没有为门禁变绿而放宽。

## 【④ 一致性】

- 三家 Provider 共用同一 live seam 和同一翻译操作，adapter 差异仍由现有 request factory/decoder 隔离，没有复制第二套网络协议。
- GitHub 凭据使用 Secrets，非敏感模型 ID 使用 Variables；名称已同步进 Ticket 10 design，代码与注释保持英文。
- 本轮不改变最终用户可见产品行为；`docs/features/v1-core.md` 无需新增内部 CI/凭据实现说明，正式发布未就绪声明仍真实。

## 结论

审查修复 timing 的 wall-clock 假设；未发现会泄漏用户内容/凭据、自动重试或绕过失败传播的实现问题。代码门禁已补齐，但真实发布仍因外部凭据、签名、公证、公共 HTTPS 与 live Provider 不稳定而阻塞。

---

# VLMSnapper v1 — Appcast staging path code review

审查范围：`release-macos.sh` 的 Sparkle feed 生成接线、独立 appcast seam 与原子发布边界。

## 【① 底层前提】

- Sparkle `generate_appcast -o` 的相对路径按调用进程当前目录解析，不按最后一个扫描目录解析；正式 arm64 运行已复现该事实。
- 每架构 appcast 必须在自己的临时 staging 目录生成。仓库工作目录出现 XML 既会让随后的 enclosure 校验找不到文件，也会留下未纳入清理 trap 的孤儿。

## 【② 可运行性】

- 新的 `generate-release-appcast.sh` 先将已存在的架构目录规范化为绝对路径，再把完整 XML 路径交给 Sparkle。
- 正式脚本仍按 final DMG → appcast → enclosure/EdDSA 校验顺序运行；辅助 seam 没有复制签名、验证或发布逻辑。

## 【③ 安全正确性】

- 私钥文件只作为参数透传给本机 Sparkle 工具，不读取、不记录、不复制；测试使用无内容的占位路径。
- 修复不改变 fail-closed 和六文件原子移动。任何架构生成或校验失败时，最终输出目录仍不存在。

## 【④ 一致性】

- 设计已补充“绝对输出路径且工作目录不得收到 appcast”的明确不变量。
- `docs/features/v1-core.md` 已经声明 per-architecture appcast 和 atomic six-file staging；本次只恢复该既有行为，不新增用户可见功能。

## 结论

正式运行暴露的路径解析 bug 已隔离修复。审查未发现新资源泄漏、凭据暴露、发布顺序变化或原子性回归。

## 2026-08-28 follow-up: download prefix directory semantics

- 第二次正式 arm64 运行证明绝对输出路径已经生效，但 enclosure URL 丢失 `v0.1.0`；Sparkle 按标准 URL 相对解析替换了无尾斜杠 prefix 的最后组件。
- helper 现在先去除用户输入的可选尾斜杠，再追加一个 `/`。这既避免双斜杠，也保证版本组件是目录；release 脚本的 expected URL 仍保持规范化无尾斜杠后自行拼接文件名。
- 修复只改变传给 Sparkle 的 URL 形态，不改变下载主机、版本、文件名、签名内容、原子发布或凭据边界。

---

# VLMSnapper v1 — Screen-capture purpose metadata code review

审查范围：分发 `Info.plist`、`InfoPlist.strings`、App 组装与最终包校验。

## 【① 底层前提】

- 已用当次重新组装的 arm64 App 实测：主 `Info.plist` 能读到英文 fallback，`en.lproj` 与 `zh-Hans.lproj` 能分别读到确认文案。
- `InfoPlist.strings` 由 macOS bundle 本地化机制消费，不是 App 内 SwiftUI 字典的替代入口；两者的语言集仍为 `zh-Hans` 和 `en`。

## 【② 可运行性】

- 本地化文件在签名前复制到 App 顶层 `Contents/Resources/<locale>.lproj/`，所以签名覆盖完整最终字节。
- 正式 App 校验同时核对 fallback 与两份本地化值；丢失任一文件都在架构检查之前终止。该错误仅影响当前产物，不会污染其他架构产物。

## 【③ 安全正确性】

- 新增内容只是用途说明，不包含凭据、用户数据、路径或动态输入。
- 修复不修改 TCC 数据库，不重置 VLMSnapper 权限，也不删除 Transfer 的历史条目；这些系统状态操作仍需用户单独授权。

## 【④ 一致性】

- 主 fallback、英文本地化和简体中文本地化与用户确认的文案逐字一致；代码、注释与测试名保持英文。
- 复制清单显式枚举项目支持的两个 locale，没有引入第三种 UI 语言或 RTL 承诺。

## 结论

未发现新的 race、资源泄漏、状态错乱或凭据风险。该修复窄化在分发元数据与打包门禁，不改动权限请求状态机。

---

# VLMSnapper v1 — Quit with app-owned sheet code review

审查范围：`ApplicationTerminationSheet.swift`、三个 app-owned sheet root、真实 AppKit 集成测试及统一退出文档。

## 【① 底层前提】

- 当前 macOS SDK 明确提供 `NSWindow.preventsApplicationTerminationWhenModal` 控制 modal window 是否阻止应用退出；Installed App 的 Unified Log 已在应用 delegate 之前报出 `App termination blocked by modal sheet`。
- 修复把策略写在 backing view 已进入真实 sheet window 的 `viewDidMoveToWindow`，不会依赖 SwiftUI 创建窗口之前的无效时机。

## 【② 可运行性】

- Provider setup、permission recovery 和 storage/privacy 三个实际内容 view 都应用同一 modifier；生产目录现有三个 `.sheet` host 均只呈现这三类内容。
- modifier 只设置现有 sheet window 的单个幂等属性，不持有 presentation binding，不关闭窗口，也不创建第二个退出入口。
- 真实 `NSWindow` 测试等待 attached sheet 出现后读取窗口属性；测试父窗口的受控进程期保留避免 SwiftUI 异步 teardown 在测试返回后释放 AppKit 状态。

## 【③ 安全正确性】

- 退出决定仍由既有 application delegate 与 shutdown coordinator 作出；活动请求取消、持久化和未保存结果确认没有被绕过。
- 用户取消未保存结果确认时，修复没有预先关闭或改写 sheet 状态，因此原面板可继续保持。
- 策略没有全局应用到 `NSAlert`、`NSSavePanel` 或 Sparkle window，未弱化不属于本票的 modal 行为。

## 【④ 一致性】

- spec、feature catalog、logic prototype、Ticket design 与实现都描述“sheet 不再抢先取消退出，统一协调仍是唯一决定者”。
- 没有新增用户文案、语言键、图标、尺寸、颜色或布局像素；无需新增视觉快照。
- review 修正了 design 中“每次 SwiftUI update 都重新应用”的过强措辞，使其与实际的 window-attachment policy 一致。

## 结论

未发现新的 race、展示状态丢失或退出绕过。修复范围仅覆盖 VLMSnapper-owned SwiftUI sheets；未来新增 `.sheet` 时必须继续纳入同一 class-level 审计。
