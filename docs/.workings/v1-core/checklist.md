# VLMSnapper v1 实现核销清单

本清单把 `docs/specs/v1-core.md` 的行为分配给实现票。每票完成时必须补充 gate、测试名和可复查证据。

## Spec requirement ownership

来源：`docs/specs/v1-core.md`。下表机械枚举 12 个 User Stories 和 46 条「失败模式与边界」；User Story 使用 spec 的原始标题，失败模式保留原文。历史要求继续由既有票承兑，本轮 Provider 增量由 Tickets 19–23 承兑。

| # | 需求（spec 原文） | 承兑票 | 该票的验收标准 |
|---|---|---|---|
| US-01 | 启动与单实例 | 09、11、12、13 | 既有票的单实例、窗口生命周期、状态项交互和原生菜单验收；对应 evidence 章节提供 gate/test/evidence |
| US-02 | 首次引导与权限 | 07、14、15、19、23 | Ticket 19 的 onboarding 单次返回与内联 Provider 入口；Ticket 23 的组合流程测试 — test |
| US-03 | 截图入口、全局快捷键与屏幕冻结 | 05、12、14、18、22、23 | Ticket 22 的对称活动门禁与被阻止截图路由；Ticket 23 的生产组合测试 — test |
| US-04 | 选区操作栏 | 06、13 | 既有票的操作栏行为、几何与生产渲染验收；对应 evidence 章节提供 gate/test/evidence |
| US-05 | 提取文字与截图翻译 | 01、04、06、17、22 | 既有单请求/流式契约加 Ticket 22 的模型请求互斥标准 — test |
| US-06 | 流式返回与结果窗口 | 04、06、17、18、22 | 既有结果窗口/重跑验收加 Ticket 22 的 Try Again 门禁标准 — test |
| US-07 | Provider 配置与模型发现 | 03、04、14、15、16、19、20、21、22、23 | Tickets 19–22 分别承兑内联表面、原生编辑、Keychain 对账和跨工作流互斥；Ticket 23 组合收口 — gate/test/evidence |
| US-08 | 错误、限流与取消 | 04、06、08、09、15、21 | 既有错误归一化验收加 Ticket 21 的安全存储错误区分 — test |
| US-09 | 原始 PNG、历史与持久化顺序 | 01、02、06 | 既有持久化门禁、历史所有权及最终落库验收；对应 evidence 章节提供 gate/test/evidence |
| US-10 | 历史浏览与清理 | 02、08、18、22 | 既有历史验收加 Ticket 22 的阻止 Try Again 时历史不变标准 — test |
| US-11 | 本地化、隐私与诊断 | 02、07、08、09、16、20、21 | Ticket 20 本地化编辑状态与 Ticket 21 秘密流审查，连同既有隐私/诊断门禁 — gate/evidence |
| US-12 | 更新与分发 | 09、10、16、21 | 既有发布门禁加 Ticket 21 的签名 Data Protection Keychain 回归标准 — gate |
| FM-01 | 用户通过快捷键或主面板按钮触发截图，但没有可用 Provider/模型：不请求屏幕权限、不冻结屏幕；把首次引导窗口带到最前并提供前往设置中心 Provider 页面的入口。 | 14、15、19 | Ticket 19 onboarding 到内联 Provider 入口标准 — test |
| FM-02 | 用户通过快捷键或主面板按钮触发截图，但权限未授予或已撤销：不捕获，显示原因和系统设置入口；授权后要求重启；把首次引导窗口带到最前并展示权限恢复入口。 | 07、14、15 | 既有 readiness/permission routing acceptance — test/evidence |
| FM-03 | 部分显示器冻结失败：失败屏不可选，其他屏继续；全部失败则退出且无历史。冻结失败、当前进程无法从同一内容快照解析，或新遮罩无法覆盖任何显示器时，保留此前已打开的结果工作区或选区，不留下半退让状态。 | 05、18 | 既有冻结协调和工作区退让 acceptance — test |
| FM-04 | 用户拖出过小或跨越失效显示器的选区：保持选择模式，不生成 PNG。 | 05 | Ticket 05 selection validation acceptance — test |
| FM-05 | 用户在模型操作前取消：释放内存截图，无文件、无历史、无网络。 | 05、06 | Tickets 05/06 cancel-before-operation acceptance — test |
| FM-06 | 用户点击操作，但 PNG 无法保存：无网络，内存保留并允许重试保存；关闭后丢弃。 | 01、06 | Tickets 01/06 persistence-before-provider acceptance — test |
| FM-07 | PNG 成功而准备记录失败：无网络；仅删除所有权和哈希均可证明的本次文件，否则保留孤儿。 | 01、02 | Tickets 01/02 rollback ownership acceptance — test |
| FM-08 | 请求体预检超限：不联网、不改图，保存失败记录并建议缩小选区。 | 06、10 | Existing operation preflight and release contract acceptance — test/gate |
| FM-09 | Provider 调用出现网络、超时、限流、鉴权、安全或协议错误：立即停止，不自动重试；丢弃残缺流并保存归一化失败。 | 04、06、08、17 | Existing adapter, result, persistence, and DeepSeek activity acceptance — test |
| FM-10 | Provider 明确模型不支持图片：失败并清除当前模型，标记不兼容；普通 400 不触发该变化。 | 03、04 | Existing explicit vision-incompatibility acceptance — test |
| FM-11 | 模型不存在：只刷新列表一次；确认消失则清除并终止，刷新失败保留旧缓存但本次仍失败。 | 03、04 | Existing one-refresh and cache-preservation acceptance — test |
| FM-12 | 用户在请求中关闭结果窗口或主动取消：停止请求并保存已取消；不保留残缺文字。 | 06 | Ticket 06 cancellation acceptance — test |
| FM-13 | 应用崩溃或断电后重启：遗留非终态变为意外中断，不自动恢复请求。 | 02 | Ticket 02 startup recovery acceptance — test |
| FM-14 | Provider 完成但最终结果落库失败：结果只驻留内存且可复制，只允许重试数据库保存；关闭前确认。 | 02、06 | Existing result-save recovery acceptance — test |
| FM-15 | 用户移动、删除或替换受管理 PNG：保留文本和元数据，不显示、不上传、不删除不匹配文件。 | 02、08 | Existing managed-screenshot ownership acceptance — test |
| FM-16 | 自动清理或批量删除部分失败：继续其余记录并汇总结果；不把失败项误报为已删除。 | 08 | Ticket 08 partial-cleanup acceptance — test |
| FM-17 | 历史数据库损坏或版本过新：阻止新模型操作和写入，不静默新建；保留恢复路径。 | 02、06 | Existing database fail-closed acceptance — test |
| FM-18 | 更新准备安装时存在活动请求：先正常取消并持久化取消状态，再退出安装。 | 09、10 | Existing update termination coordination acceptance — test/gate |
| FM-19 | 应用附着面板打开时退出：仍进入统一退出协调；若未保存结果确认被取消，应用继续运行且原面板保持打开。 | 11 | Ticket 11 sheet termination acceptance — test/evidence |
| FM-20 | 用户验证有效 API Key，但当前已签名应用没有 Data Protection Keychain 授权或本地 Keychain 写入失败：验证流程终止，不保存 Provider 配置，显示本地安全存储错误及可操作建议，不改写为网络或 Provider 错误。 | 16、21 | Ticket 21 Keychain/metadata failure standard and signed CRUD gate — test/gate |
| FM-21 | 发布者启动正式构建，但 provisioning profile 缺失、过期、损坏，或与应用身份、签名证书、Keychain allowlist 不匹配：在任何可发布产物签名或上传前终止，不留下可被误当成正式发布的降级产物。 | 10、16 | Existing release profile fail-closed acceptance — gate |
| FM-22 | provisioning profile 验证通过，但 profile 授权与最终 App 签名实际声明不一致，或 Universal 产物的 Data Protection Keychain CRUD 失败：整个三架构版本失败，不进入公证、分发或 appcast 发布。 | 10、16、21 | Ticket 16 release gate retained by Ticket 21 signed-Keychain criterion — gate |
| FM-23 | 用户在结果工作区已进入成功、失败或取消终态且结果已安全保存后触发截图：先冻结排除 VLMSnapper 自身的当前屏幕；只有新选区遮罩成功覆盖可用显示器后，才退下结果窗口并提交工作区替换。任何前置步骤失败都恢复旧工作区继续可用，旧结果同时保留在历史记录中。 | 18 | Ticket 18 result-workspace capture acceptance — test |
| FM-24 | 用户在结果工作区仍有活动请求或未保存结果时触发截图：不替换工作区、不冻结屏幕，把当前结果窗口带到前台；同一工作区的退让请求只消费一次，不能与 Try Again 并发启动。 | 18、22 | Ticket 18 workspace guard plus Ticket 22 symmetric activity gate — test |
| FM-25 | 用户在菜单栏面板、管理中心或已有选区中触发截图且当前允许开始新截图：这些来源界面在冻结期间保持可用，但由 ScreenCaptureKit 排除在冻结帧外；新遮罩成功显示后才退下明确记录的来源界面。重复截图必须先显示新遮罩再释放旧遮罩和冻结帧，不能出现桌面闪烁或失败后丢失旧选区。 | 05、18 | Existing capture exclusion and atomic replacement acceptance — test/evidence |
| FM-26 | 用户单击管理中心历史记录：只切换详情；用户双击整条记录：管理中心退到后台并打开该记录的结果工作区，已保存结果立即显示且不产生网络请求或新历史记录。只有用户随后明确点击 Try Again 时，才按历史操作重跑规则创建新记录。 | 18 | Ticket 18 history-open and rerun acceptance — test |
| FM-27 | 用户从首次引导进入 Provider 设置后只验证 Key、尚未选择模型：停留在当前 Provider 卡片，不返回引导；选择有效模型后自动返回引导并显示完成状态。用户提前关闭设置中心时，直接返回引导并保留实际配置进度。 | 19、23 | Ticket 19 onboarding return criterion; Ticket 23 complete onboarding-to-Provider flow — test |
| FM-28 | 用户在已配置 Provider 输入新 Key 并点击验证：先持久记录旧凭据作废，再接受替换并移除旧 Key、旧模型缓存及该 Provider 的当前模型；验证、模型列表获取或后续安全存储失败不恢复旧配置。若作废记录无法持久化，则拒绝本次替换、不发请求、保留原配置并提示安全存储错误；存储恢复后重开可读取原配置。作废已经持久化但旧条目删除失败时，重开只允许清除明确已作废的旧条目，不能把它当作遗留凭据恢复。 | 21 | Ticket 21 changed-key invalidation and no-rollback criterion — test |
| FM-29 | 用户验证新 Key 后，Provider 返回的完整模型列表仍含旧模型：保留旧模型选择；列表不含旧模型：进入待选择模型。两种情况都不因该 Provider 可用而抢占另一个全局当前 Provider。 | 21 | Ticket 21 model-preservation/current-Provider criterion — test |
| FM-30 | 用户移除非当前 Provider：只清除该 Provider；用户移除全局当前 Provider：同时清空全局当前选择，不自动切换到其他可用 Provider，下一次截图按缺少当前 Provider 的流程进入引导。 | 19 | Ticket 19 Provider removal/current-selection criterion — test |
| FM-31 | 用户在模型请求进行中进入 Provider 页面：所有卡片仍可查看，但 API Key、验证、清空、模型选择、刷新、设为当前和移除配置全部只读；请求进入终态后恢复。 | 22 | Ticket 22 read-only-during-model/capture criterion — test |
| FM-32 | 用户打开 Provider 卡片但 Keychain 载入尚未完成：字段不接受键盘、粘贴、清空、显隐或验证操作；载入完成后一次性呈现该 Provider 的真实字段与状态。用户在此期间切换卡片时，迟到的载入结果被忽略，不改变新卡片。 | 20、21 | Ticket 20 coherent editor state plus Ticket 21 load-generation isolation — test |
| FM-33 | Provider 配置当前可编辑时，用户通过键盘或 `Command-V` 输入非空有效 Key：占位文案立即消失，清空和验证立即可用，字段与状态同时进入“待验证”；任一项仍显示空值状态都视为失败。移除已有配置必须走“移除配置”，不能把空输入当作新凭据。 | 20 | Ticket 20 native input and coherent presentation criteria — test |
| FM-34 | 用户在 Key 编辑过程中清空字段：字段回到空态，清空与验证禁用；尚未点击验证时不删除 Keychain 中的旧凭据，关闭并重新打开管理中心后恢复已保存配置。 | 20 | Ticket 20 coherent state and unsubmitted-draft lifecycle criteria — test |
| FM-35 | 用户切换到另一张 Provider 卡片：未提交草稿被丢弃，新卡片只加载自己的凭据状态；不额外确认。之前 Provider 的迟到 Keychain 结果不得改变新卡片的文本、状态或按钮可用性；已经提交的验证继续执行并仍只更新其原始 Provider。 | 20、21 | Ticket 20 immutable Provider submission plus Ticket 21 load-generation criterion — test |
| FM-36 | 用户点击验证或按 Return 后立即切换卡片：本次请求使用提交瞬间捕获的 Provider 与精确 Key；原卡片字段在验证终结前只读，结果只归属该 Provider。用户返回原卡片时看到正在验证或已经到达的终态，不会产生第二次验证。 | 20 | Ticket 20 immutable submission and Return/click exactly-once criteria — test |
| FM-37 | 用户在安全输入与明文显示之间切换：文本、插入点、选区和焦点保持；切换本身不改变“待验证”判断，不触发验证或写入安全存储。 | 20 | Ticket 20 real AppKit visibility-preservation criterion — test |
| FM-38 | 管理中心因应用状态更新而重新呈现 Provider 页面：当前窗口会话中的字段文本、状态、占位文案以及清空/验证可用性仍来自同一编辑状态，不能出现文本已显示但操作仍按空值禁用的分裂状态。 | 20 | Ticket 20 single-source editor presentation criterion — test |
| FM-39 | 已配置 Provider 的字段精确值与已载入凭据完全相同时：不显示待验证操作，按 Return 不发起验证，也不删除现有凭据；只有精确值实际发生非空变化后才能提交替换。 | 20 | Ticket 20 unchanged-key suppression criterion — test |
| FM-40 | 用户在 Keychain 载入或尚未提交的编辑状态关闭管理中心：取消载入并清除窗口会话草稿，已保存凭据不变。用户在正在验证时关闭：验证继续执行；重新打开后显示同一验证或其终态。失败时保留提交 Key 供修正，成功时只在安全存储写入成功后清除内存候选。 | 20、21、23 | Ticket 20 draft lifecycle, Ticket 21 validation continuity, and Ticket 23 combined flow — test |
| FM-41 | 应用在验证进行中正常退出、崩溃或被强制终止：取消仍可取消的请求并丢弃只存在内存中的候选 Key；已经接受替换并持久记录作废的旧配置不恢复。下次启动时不重新提交已经丢失的候选 Key；若新 Key 已经写入 Keychain，则按安全存储真相进入模型配置恢复，否则显示未配置。若退出前尚未接受替换，则保留原配置；迟到的凭据读取返回后不得再发验证请求。 | 21 | Ticket 21 termination, candidate-secret, and reconciliation criteria — test/evidence |
| FM-42 | 用户键盘输入 Key：空格、制表符和其他非换行字符按原样保留。用户粘贴 Key：只移除该次粘贴内容末尾至多一个 `CRLF`、`LF` 或 `CR`，再插入当前选区；其他字符不修剪、不规范化。结果为空、仍含换行或超过应用明确的 4096 UTF-8 字节安全上限时，保持编辑状态并显示本地输入错误，不删除旧配置、不联网，也不截断内容后尝试验证。 | 20 | Ticket 20 exact paste and local-validation criteria — test |
| FM-43 | 一个 Provider 正在验证时，用户切换到另一张卡片并输入新 Key：草稿正常保留在当前窗口会话，但验证操作保持禁用并显示现有只读提示条；前一项进入任一终态后，若草稿仍合法且非空，验证操作自动恢复。重复点击或按 Return 不产生第二个验证请求。 | 22 | Ticket 22 one-credential-job and cross-Provider draft criterion — test |
| FM-44 | Provider 凭据作业已经开始后，用户触发截图快捷键或菜单栏截图入口：不冻结屏幕、不创建选区，把管理中心的 Provider 页面及当前作业带到前台；截图操作栏不会出现“配置处理中”状态。已有结果工作区的 Try Again 同样禁用，不启动模型请求、不新增或修改历史记录。反向地，截图冻结、选区或模型请求已经活动时提交 Provider 验证或开始恢复均被拒绝，原有截图或请求不受影响；双方进入终态后恢复相应入口。 | 22、23 | Ticket 22 production routing and symmetric-gate criteria; Ticket 23 combined integration — test/evidence |
| FM-45 | 用户打开 Provider 卡片读取凭据：Keychain 返回条目不存在时显示未配置；返回权限、entitlement、访问控制或其他读取错误时显示本地安全存储错误并保持字段只读，不得伪装成未配置。用户收起再展开时发起新的读取，旧读取结果不能覆盖新代次。 | 21 | Ticket 21 missing-versus-read-failure and load-generation criteria — test |
| FM-46 | 新 Key 已成功写入 Keychain，但应用在发布模型缓存或 Provider 状态之前失败、崩溃或终止：下次启动或打开卡片时发现“有 Key、无一致配置”，自动进入恢复并重新获取完整模型列表；恢复作业开始后阻止新的截图、Provider 验证和模型请求，若截图冻结、选区或模型请求已经活动则等待其终结再开始。恢复成功前 Provider 不可用。反向发现“有配置、无 Key”时清除残留配置和全局当前指向。 | 21、22、23 | Ticket 21 deterministic reconciliation, Ticket 22 recovery exclusivity, and Ticket 23 combined restart flow — test |

The closeout gate must parse `US-01` through `US-12` and `FM-01` through `FM-46`, require exactly 58 unique rows, and reject blank ownership or acceptance cells.

| 票 | 承兑范围 | 状态 |
| --- | --- | --- |
| 01 | 原始 PNG → 准备记录 → 单次 Provider 提取请求的持久化门禁；失败不联网 | 已完成 |
| 02 | 历史数据库、结果终态、失败恢复、受管理截图所有权与最终落库重试 | 已完成 |
| 03 | Provider 配置、Keychain、完整模型列表、刷新与视觉兼容状态 | 已完成 |
| 04 | OpenAI、Gemini、DeepSeek 图片流式适配器与归一化错误 | 已完成 |
| 05 | 多显示器冻结、选区裁切、全局快捷键与原始 PNG | 已完成 |
| 06 | 操作栏、核心结果窗口、单活动任务、取消和重新执行 | 已完成 |
| 07 | 菜单栏、首次引导、权限恢复与 Provider 配置 UI | 已完成 |
| 08 | 管理中心、搜索筛选、钉住、保留期与清理 | 已完成 |
| 09 | 单实例、诊断、本地化、登录项与 Sparkle 更新 | 已完成 |
| 10 | 三架构直接分发、签名/公证/appcast 门禁与全功能收口 | 进行中（正式门禁阻塞） |
| 11 | app-owned sheet 打开时的菜单退出、Command-Q 与系统 Quit 进入统一退出协调 | 已完成 |
| 12 | 状态项左/右键分流、右键退出与面板按钮真实截图衔接 | 已完成 |
| 13 | 完整 Edit 菜单、文本编辑 responder chain 与所有确认原型的生产界面一致性 | 已完成 |
| 14 | 未就绪截图回到前台引导、Provider 输入与居中恢复、管理侧栏和历史详情原型回归 | 已完成 |
| 15 | 菜单截图恢复置前、Provider 鉴权失败原因和管理窗口最小内容区回归 | 已实现，待安装版验收 |
| 17 | DeepSeek 推理流活动重置 10 秒无活动计时，且不展示推理内容 | 已完成 |
| 19 | 设置中心内联 Provider 管理、首次引导自动返回、旧独立表面退役与确认响应式几何 | 已完成（PR #23 已合并） |
| 20 | 原生 API Key 编辑、精确粘贴、光标/选区保持与提交身份隔离 | 本票核销完成，ready-for-review；未合并 |
| 21 | Keychain 真相对账、凭据替换、失败恢复与启动修复 | in-progress; prerequisite 20 merged in PR #24; acceptance pending |
| 22 | Provider 凭据作业与截图、选区、模型请求及重跑互斥 | blocked by 21 |
| 23 | 内联 Provider 配置全 feature 验收与文档回归收口 | blocked by 19–22 |

## Ticket 01 evidence

- Gate: `swift build` 与完整 `swift test`；二者必须使用匹配的 Xcode toolchain，测试输出还必须包含 Swift Testing 的 6/6 passed 汇总。
- Tests: `persistedExtractionReachesSelectedProvider`、`screenshotPersistenceFailureNeverReachesProvider`、`historyPreparationFailureRollsBackScreenshot`、`failedRollbackReportsOrphanPath`、`mismatchedPreparedRecordIsRejected`、`mismatchedPreparedSelectionIsRejected`。
- Evidence: `Sources/VLMSnapperCore/ExtractionCoordinator.swift` 的公开工作流 seam；`Tests/VLMSnapperCoreTests/ExtractionCoordinatorTests.swift` 的系统边界假件和行为断言；`review-code.md` 与 `review-tests.md` 的审查和变异证据。

## Ticket 02 evidence

- Gate: `swift build -Xswiftc -warnings-as-errors`、完整 `swift test`、`git diff --check`、源码与测试 CJK 扫描；Swift 命令使用匹配的完整 Xcode toolchain。
- Tests: `FileSystemScreenshotStoreTests` 10 例与 `SQLiteHistoryStoreTests` 12 例，覆盖原始字节、命名、防覆盖、所有静态符号链接形态、路径/SHA 所有权、终态 payload、启动恢复、schema/损坏阻断和保留式重置。
- Evidence: `FileSystemScreenshotStore.swift`、`SQLiteHistoryStore.swift`、`HistoryDatabaseResetter.swift`；`review-code.md` 与 `review-tests.md` 的分层审查和三项变异证据；`final-regression.md` 的三阶段文档一致性表。

## Ticket 03 evidence

- Gate: `swift build -Xswiftc -warnings-as-errors`、完整 `swift test` 53/53、`git diff --check`、15 个源码与测试文件的 CJK 扫描；Swift 命令使用匹配的完整 Xcode toolchain。
- Tests: Provider 配置 16 例、官方目录 5 例、元数据 3 例和 Keychain 1 例，覆盖完整分页、失败零写入、崩溃协调、缓存替换/保留、首个与已记忆 Provider、冻结竞态、视觉证据、路径防护和真实 Keychain 生命周期。
- Evidence: `ProviderConfiguration.swift`、`ProviderModelCatalog.swift`、`AppleKeychainProviderCredentialStore.swift`、`FileProviderMetadataStore.swift`；`review-code.md` 与 `review-tests.md` 的分层审查、行为红灯和变异证据；`final-regression.md` 的三阶段文档一致性表。

## Ticket 04 evidence

- Gate: `swift build -Xswiftc -warnings-as-errors`、完整 `swift test` 83/83、`git diff --check`、本票源码与测试 CJK 扫描；Swift 命令使用匹配的完整 Xcode toolchain。
- Tests: 三 Provider 共享录制契约、三个官方请求体、SSE 任意字节边界、结构化 JSON 增量与 Unicode 边界、首字/停滞/总超时、单请求无重试、HTTP 错误和截断/不完整终态。
- Evidence: `ProviderRequestFactory.swift`、`ProviderAdapterExecutor.swift`、三个独立 stream decoder、`OrderedStructuredOutputParser.swift`、`ProviderStreamTimeout.swift`；`review-code.md` 与 `review-tests.md` 的审查和三项变异证据。真实账户与签名 Provider 限制仍按 Ticket 10 发布门禁保留，不冒充已验证。

## Ticket 05 evidence

- Gate: 严格 `swift build -Xswiftc -warnings-as-errors -Xcc -Wall -Xcc -Wextra -Xcc -Werror`、完整 `swift test` 105/105、`git diff --check`、本票 Swift/C 源码与测试 CJK 扫描；Swift 命令使用匹配的完整 Xcode toolchain，Keychain 全套测试在允许访问登录 Keychain 的宿主执行。
- Tests: 冻结协调 4 例、选区状态机 7 例、PNG 裁切 4 例、快捷键协调 6 例及 Carbon registrar 生命周期 1 例，覆盖权限/全部失败/部分失败、2 × 2、几何失效、裁切期间取消与竞态、坐标溢出、sRGB 像素内容、原子替换和销毁注销。
- Evidence: `CaptureFreezeCoordinator.swift`、`CaptureSelectionSession.swift`、`ScreenCaptureKitFrozenDisplayCapturer.swift`、`SRGBPNGCropper.swift`、`GlobalShortcutCoordinator.swift`、`CarbonGlobalShortcutBackend.swift` 与窄 C shim；`review-code.md`、`review-tests.md` 的分层审查和红灯/变异证据。真实多显示器、TCC、快捷键冲突和签名 App 回调仍按 Ticket 10 集成门禁保留。

## Ticket 06 evidence

- Gate: 严格 `swift build -Xswiftc -warnings-as-errors -Xcc -Wall -Xcc -Wextra -Xcc -Werror`、完整 `swift test` 127/127、`git diff --check`、源码/测试 CJK 扫描、本地化键一致性与 UI 硬编码文案扫描；Swift 命令使用匹配的完整 Xcode toolchain，Keychain 全套测试在允许访问登录 Keychain 的宿主执行。
- Tests: 操作会话 9 例、持久化 runner 7 例、操作栏定位 3 例、Provider 错误码 1 例及 SQLite 类型/迁移 2 例，覆盖显式单请求、全局排他、等待期间冻结操作、关闭取消、旧成功保留、截图复用/回滚、Provider 取消归一化、最终保存重试、4 px 间距与窄屏长操作栏。
- Evidence: `OperationWorkspaceSession.swift`、`PersistedOperationWorkspaceRunner.swift`、`ProviderPreparedOperationStreamer.swift`、schema v2 的 `SQLiteHistoryStore.swift` 以及 `VLMSnapper/UI/` 原生组件；light/dark harness 实际渲染已核对确认原型。签名 App 的窗口交互、辅助功能遍历、TCC 与真实 Provider 仍按 Ticket 10 集成门禁保留。

## Ticket 07 evidence

- Gate: 严格 `swift build -Xswiftc -warnings-as-errors -Xcc -Wall -Xcc -Wextra -Xcc -Werror`、完整宿主 `swift test` 143/143、10 张 AppKit/SwiftUI 明暗离屏渲染、`git diff --check`、源码/测试 CJK 扫描、83 个本地化键一致性与 UI 硬编码文案扫描。
- Tests: 引导/菜单路由 4 例、权限恢复 6 例、Provider presentation 5 例和真实 UI 渲染 1 例，覆盖必要条件门禁、Later 恒可用、Provider 优先路由、显式一次 TCC、拒绝/撤销恢复、成功后重启、重叠点击、模型原地展开、无自动选择、异步切换隔离、活动请求只读与五个入口表面明暗渲染。
- Evidence: `OnboardingSession.swift`、`ScreenCapturePermissionCoordinator.swift`、`ProviderSetupSession.swift`、`UserDefaultsPermissionRequestHistoryStore.swift` 与 `VLMSnapper/UI/` 的 onboarding/menu/provider/privacy/permission 组件和状态栏 controller；`review-code.md`、`review-tests.md` 的分层审查与三项行为/变异红灯；`final-regression.md` 的三阶段一致性表。签名 TCC、真实状态栏点击、System Settings 与一键重启仍按 Ticket 10 集成门禁保留。

## Ticket 08 evidence

- Gate: 严格 `swift build -Xswiftc -warnings-as-errors -Xcc -Wall -Xcc -Wextra -Xcc -Werror`、完整宿主 `swift test` 151/151、8 张管理中心明暗离屏渲染、`git diff --check`、源码/测试 CJK 扫描和双语本地化键一致性。
- Tests: 历史查询/钉住/metrics 2 例、删除协调 2 例、保留期/24 小时调度 2 例、runner metrics 1 例、空月份目录 1 例和管理中心渲染 1 例，覆盖类型与本地搜索组合、完整筛选、Provider usage、活动/钉住跳过、缺失/替代文件、部分失败继续、缩短确认、延长不清理、启动一次与 24 小时边界、空态和后台清理失败提示。
- Evidence: `HistoryManagement.swift`、`HistoryRetention.swift`、schema v3 的 `SQLiteHistoryStore.swift`、`FileSystemScreenshotStore.swift`、`PersistedOperationWorkspaceRunner.swift` 以及 `ManagementCenterView`/window controller；`review-code.md`、`review-tests.md` 的分层审查和两项目标行为变异证据；`final-regression.md` 的三阶段一致性表。生产 App 组合与真实菜单栏到窗口接线仍按 Ticket 09/10 门禁保留。

## Ticket 09 evidence

- Gate: Sparkle 2.9.6 exact dependency、严格 Swift/C warnings-as-errors build、完整宿主 `swift test` 172/172、32 张中英文/明暗/更新状态离屏渲染、系统 gzip 解压验证与 `git diff --check`。
- Tests: 语言 3 例、登录项 2 例、单实例 3 例、诊断 4 例、更新生命周期 4 例、Sparkle 用户驱动 3 例和 UI 2 例，覆盖完整偏好列表、默认登录启用/审批、真实排他锁恢复、allowlist/截止日/gzip、六小时且不自动下载、reply 单次消费、回调顺序及共享菜单/设置状态。
- Evidence: `ApplicationLanguage.swift`、`LoginItemCoordinator.swift`、`PrimaryInstanceCoordinator.swift`、`DiagnosticLogStore.swift`、`UpdateLifecycle.swift`、独立 Sparkle target 与原生 UI adapters；`review-code.md`、`review-tests.md` 和 `final-regression.md` 的 Ticket 09 章节。签名进程唤醒、真实 SMAppService/appcast/安装和退出协调仍由 Ticket 10 验收。

## Ticket 10 evidence

- Development gate: strict Swift/C warnings-as-errors build, full Swift Testing 184/184 in 45 suites, 32 Ticket 09 and 4 Ticket 10 bilingual light/dark renders, localization-key parity, shell/YAML syntax checks, and separate Universal/Apple Silicon/Intel ad-hoc DMG verification.
- Implemented surfaces: production accessory executable, application composition, frozen overlay, searchable target-language picker, persistent custom shortcut, menu/history/settings/onboarding/result routing, hourly cleanup wake with a 24-hour core gate, sanitized diagnostic export, and coordinated termination for Quit, Command-Q, language restart, and Sparkle installation.
- Release pipeline: exact three-member manifest, separate architecture feeds, fail-closed credentials and HTTPS validation, nested hardened-runtime signing, app and DMG notarization/stapling/Gatekeeper checks, EdDSA verification, and atomic six-file staging.
- Formal gate remains blocked: no local Developer ID identity or notarization evidence, no public HTTPS feed/download host, and no protected live OpenAI/Gemini/DeepSeek credentials. Development DMGs are not release evidence; Ticket 10 stays in progress.

## Ticket 11 evidence

- Gate: strict Swift/C warnings-as-errors build、完整 Swift Testing 193/193（49 suites）、目标 AppKit test 1/1、三架构 development App/DMG 组装与校验、脚本语法、prototype JS 语法和 `git diff --check`。
- Tests: 真实 `NSHostingController`/`NSWindow` 同时呈现 Provider setup、permission recovery、storage/privacy 三个 sheet，并逐个断言 attached window 不再阻止 termination。移除其中一个 modifier 的定向变异准确在 `true` 窗口属性处红，恢复后同一 case 重新转绿。
- Evidence: `ApplicationTerminationSheet.swift`、三个 sheet root、`ApplicationTerminationSheetTests.swift`、logic prototype、Ticket design/review。独立 bundle-id 的 Developer ID probe 在 Provider sheet 打开时接收标准 Apple Event Quit 后 PID 正常退出；没有覆盖或终止当前安装的旧版 App。

## Ticket 13 evidence

- Gate: 严格 Swift/C warnings-as-errors build、完整 Swift Testing 209/209（54 suites）、40 张精确命名的中英文/明暗生产界面渲染、本地化 234/234 键一致、prototype shared-block 检查、UI 硬编码扫描与 `git diff --check`。
- Tests: `ApplicationMenuTests` 4 例、`MenuBarPresentationTests` 3 例、`ConfirmedSurfaceContractTests` 3 例和 `Ticket13RenderingTests` 1 例，覆盖完整 Edit 层级、标准 selector/快捷键/responder Paste、真实历史与 Provider 状态、独立原型几何，以及十个生产表面在双语双主题下的 40 个精确产物。
- Evidence: `VLMSnapperApplicationMenu.swift`、`MenuBarPanelView.swift`、`ProviderSetupView.swift`、`ScreenCapturePermissionRecoveryView.swift`、`ResultWorkspaceView.swift`、`ManagementCenterView.swift` 与对应 production wiring；`review-code.md`、`review-tests.md` 的批判式审查和三项变异证据；`final-regression.md` 的三阶段一致性核销。

## Ticket 14 evidence

- Gate: 严格 Swift/C warnings-as-errors build、完整 Swift Testing 213/213（56 suites）、40 张双语/明暗生产界面渲染、234/234 本地化键一致、prototype JavaScript 检查、UI 硬编码扫描、本票源码与测试 CJK 扫描、shell syntax 与 `git diff --check`。
- Tests: `Ticket12MenuBarInteractionTests` 的三个未就绪/就绪路由都先关闭面板、`ProviderSetupInputStateTests` 2 例验证粘贴立即启用和切换 Provider 清理草稿、`ThemeSurfaceRenderingTests` 2 例验证 Aqua/Dark Aqua 自适应次级表面；三处定向变异均准确红灯并在恢复后转绿。
- Evidence: `MenuBarContainerView.swift` 移除状态项 popover 内的重复 sheet host、`ProviderSetupView.swift` 使用可观察的本地输入状态、`VLMSnapperTheme.swift` 恢复原型层级的自适应浅色表面、`ManagementCenterView.swift` 恢复带边框的历史详情卡；Ticket design/review、code/test review、production renders 与 `final-regression.md` 完成闭环。

## Ticket 15 evidence

- Gate: 严格 Swift/C warnings-as-errors build、完整 Swift Testing 216/216（57 suites）、44 张双语/明暗生产界面渲染、234/234 本地化键一致、prototype JavaScript、shell syntax、UI literal/CJK 与 `git diff --check` 全部通过；Developer ID arm64 build 6 已验证并安装，等待真实 WindowServer 用户验收后核销本票。
- Tests: `ProviderSetupSessionTests` 的 401 正例和 503 反例区分无效凭据与服务不可用；`ManagementCenterWindowContractTests` 用真实 AppKit window 证明 `920×620` 约束完整内容区；`Ticket12MenuBarInteractionTests` 证明 pending Capture 不在 popover close callback 内同步执行，而在下一主线程周期 exactly once 运行；Ticket 13 render 追加四张最小管理窗口产物。
- Evidence: 安装版统一日志确认 OpenAI 请求完成 DNS/TLS/HTTP2 后返回 401；独立 AppKit probe 证明 `920×620` 外框只有 `920×588` 内容区；三条 TDD 红绿、503 过宽映射变异、code/test review、spec/features 与 `final-regression.md` 完成闭环。跨应用 WindowServer 置前仍由本票签名安装版手动 acceptance 承兑，不以 SwiftPM 单测冒充。

## Ticket 18 — Result window, rerun history, and menu interactions

- [x] Result workspace presents once, refreshes in place, and otherwise behaves as a normal backgroundable window.
- [x] Try Again reuses the current screenshot-operation history identity and replaces the successful result.
- [x] Menu capture, recent-record, History, and Settings actions use full visible hit targets and hover states.
- [x] Targeted red/green tests, full verification, code review, test review, and documentation consistency are complete.

## Ticket 18 evidence

- Gate: strict Swift/C warnings-as-errors build, full Swift Testing 246/246 in 65 suites, 44 bilingual light/dark production renders, `git diff --check`, and three targeted behavior mutations.
- Tests: real AppKit window level and hidden refresh, runner history identity/replacement and failed-rerun preservation, SQLite identity/pin/metadata replacement, full-width AppKit edge click, and all menu roles' hover response.
- Evidence: `ResultWorkspaceWindowController.swift`, application presentation wiring, `PersistedOperationWorkspaceRunner.swift`, `SQLiteHistoryStore.swift`, the shared menu action component, Ticket 18 design/reviews, and the three-stage final regression. Physical pointer hover and cross-application ordering remain installed-App acceptance checks.

## Ticket 19 evidence

- Gate: warnings-as-errors 严格构建、271 tests / 68 suites、246/246 本地化键集合、9 个 prototype HTML/9 个 inline scripts、生产渲染与 `git diff --check` 全部通过。
- Tests: `ProviderSettingsPresentationTests`、`OnboardingSessionTests`、`ProviderConfigurationCoordinatorTests`、`ProviderSetupSessionTests` 的 Ticket 19 行为用例，以及 `ConfirmedSurfaceContractTests.workspaceGeometry` 和 `Ticket13RenderingTests.confirmedSurfacesRender`。
- Evidence: 正常与最小管理中心生产渲染验证双列/纵排；退役 UI 符号与 `--provider` 在生产源码、harness、测试、本地化、原型和 manifest 中全量检索为零；四个确认几何值均通过 1 pt 受控变异验证。

## Ticket 20 evidence — 2026-09-06

This is Ticket 20's scoped acceptance, not acceptance of Keychain reconciliation (21), cross-workflow exclusion (22), or full feature closeout (23).

| Owned requirement | Named test / gate | Evidence and boundary |
| --- | --- | --- |
| US-07; FM-33, FM-38 | ProviderCredentialInteractionTests.editingEnablesValidation (empty/prefilled × typing/paste) | Real ManagementCenterWindowController, AppKit editor, visible Clear/Validate hits and Return; refresh retains one observable value. |
| FM-34, FM-39 | ProviderCredentialInteractionTests.revertedCredentialCannotSubmit, windowCloseDiscardsDraft; ProviderCredentialEditorTests.baselineUsesExactBytes | Exact revert suppresses submission; close/reopen loads saved text, not the unsubmitted draft. Coordinator safety tests separately verify saved configuration remains unchanged. |
| FM-32, FM-35 | ProviderCredentialEditorTests.lateReadCannotPopulateNewVisit, closeInvalidatesReads, submittedKeySurvivesCardSwitch | Unique load identity rejects A/B/A and closed-window reads. Loading blocks edits. Actual Keychain error-versus-missing reconciliation is Ticket 21, not inferred from these injected values. |
| FM-36 | ProviderCredentialEditorTests.submissionIdentityAndCompletion; ProviderSetupSessionTests.submittedValidationUsesExplicitProvider, pendingValidationSuppressesDuplicates, returningAfterValidationFailure | Synchronous immutable claim feeds the real configuration coordinator; delayed external model listing checks original identity and return-to-original pending/terminal state. |
| FM-37 | ProviderAPIKeyFieldTests.visibilityPreservesSelection | Native secure/plain field keeps UTF-16 selection, exact UTF-8 content and focus; no editing or submit callback. Concurrent shorter reload is safely clamped by AppKit itself. |
| FM-40 (editor responsibility) | ProviderCredentialEditorTests.closingSubmittedDraft, closedFailureRetainsCandidate, failedCandidateCanBeDiscarded; ProviderCredentialInteractionTests.windowCloseDiscardsDraft | Pending submission survives closing; failure candidate survives reopening and is discarded after editing/removal. Termination and durable Keychain recovery remain Ticket 21/23. |
| FM-42 | ProviderAPIKeyFieldTests.pasteNormalizationIsNarrow, standardPasteRoutes; ProviderCredentialInteractionTests.pasteReplacesSelectionWithoutTrimming, unsafeDraftCannotValidate; ProviderAPIKeyInputTests.validationUsesTheDocumentedSafetyBoundary; ProviderConfigurationCoordinatorTests.unsafeInputPreservesSavedConfiguration | One trailing CRLF/LF/CR only, unchanged private clipboard, selection replacement; empty/newline/4097-byte rejection before coordinator mutation. |
| US-11 (local input wording) | ProviderSettingsPresentationTests.localAPIKeyErrorsHaveSpecificHints; bilingual key-set comparison | Both dictionaries contain 248 unique keys with identical sets. New text contains no credential value or provider-specific key format. |
| Native menu path | Scripts/verify-native-provider-editor.py | Current source rebuilt, 10 fresh processes passed in 0.893–1.477 seconds. Real AppKit menu tracking followed by programmatic action, not physical input automation. |
| Complete local gate | Strict Swift/C build → full swift test → rebuilt native runner → git diff --check, joined by && | Exit 0; 293 tests / 72 suites, 15.460 seconds. Logs: /private/tmp/ticket20-closeout-strict.log, ticket20-closeout-full.log, ticket20-closeout-native.jsonl. |

Mutation: removing same-Provider admission suppression and rebuilding makes the real-coordinator session test fail at the required validating phase in both success/failure cases. Exact guard restored; final full/native gates above ran after restoration. Log: /private/tmp/ticket20-coordinator-mutation.log. Earlier native Paste no-op, missing completion marker and timeout controls are recorded in 20-native-acceptance-review.md.

Coverage bookkeeping repaired: 12 user stories + 46 failure modes = 58 unique ownership rows. Ticket 20's former nonexistent test references have been replaced by actual declarations. Other ticket definitions copied from the approved draft preserve their unresolved dependencies; this does not mark them implemented.

## Ticket 21 evidence inventory — acceptance pending

This is a pre-review inventory, not a completed checklist. Names below refer to current test declarations; previous nonexistent names in the ticket have been corrected. The final v2 verification logs are recorded in `21-keychain-reconciliation-tasklist.md`.

| Owned rows | Current evidence | Limit or remaining gate |
|---|---|---|
| US-07, FM-28 | ProviderConfigurationCoordinatorTests.retirementWriteFailurePreservesOriginalConfiguration, credentialWriteFailureDoesNotRestorePreviousConfiguration, listFailureDoesNotRestorePreviousProviderConfiguration, failedDeletionCannotRecoverRetiredCredential | Retirement and cleanup cases pass. After specific user authorization, the forbidden-request mutation reached both deletion-permission branches and both failed at the injected boundary; exact restoration made both pass. Tests used only memory-store literals and an outer deny-network sandbox. |
| FM-29 | ProviderConfigurationCoordinatorTests.replacementPreservesAvailableModelAndCurrentProvider, configuringAnotherProviderDoesNotReplaceRememberedCurrentProvider | Both Providers are configured through public operations in the remembered-current case. No live Provider request is claimed. |
| US-08, FM-20 | ProviderConfigurationCoordinatorTests.genericCredentialWriteFailureIsSecureStorage, metadataPublicationFailureIsSecureStorage; ProviderSetupSessionTests.keychainReadFailureIsNotMissingCredential | Injected OS/filesystem faults drive the actual coordinator and session. |
| FM-32, FM-35 | ProviderSetupSessionTests.lateReadFailureIsIgnored, submittedValidationUsesExplicitProvider; ProviderCredentialEditorTests.reopenedLoadWaitsForCanceledRead | Delayed uncancellable reads and A/B/A identities are covered at public seams, not through installed-window input. |
| FM-40 | ProviderSetupSessionTests.pendingValidationSuppressesDuplicates, recoveryPublishesBusyState; ProviderCredentialEditorTests.closingSubmittedDraft, closedFailureRetainsCandidate | Application/window wiring remains a physical interaction gap; programmatic native Paste does not accept this workflow. |
| FM-41 | ProviderConfigurationCoordinatorTests.canceledValidationDoesNotPersistCandidate, postKeychainPublicationFailureRecovers; ProviderSetupSessionTests.cancellationBeforeReplacementAdmission; ProviderCredentialEditorTests.terminationDiscardsCandidates | Task cancellation and restart from injected durable state are covered; actual Quit/crash/force-termination of the installed app is not simulated. |
| FM-45 | ProviderSetupSessionTests.keychainReadFailureIsNotMissingCredential, lateReadFailureIsIgnored; ProviderSettingsPresentationTests.storageReadOnlyActions | Missing/read-error distinction and reopen are tested; all eight recovery/read-error production renders inspected. Browser controls remain unverified. |
| FM-46 (reconciliation only) | ProviderConfigurationCoordinatorTests.reconciliationRecoversStoredKeyWithoutConfiguration, reconciliationCommitsMetadataForDurableNewCredential, reconciliationClearsConfigurationWithoutCredential, postKeychainPublicationFailureRecovers | Cross-workflow exclusion belongs to Ticket 22; combined restart flow belongs to Ticket 23. Neither is accepted here. |
| US-11 | Both localization dictionaries have 251 matching keys; candidate termination tests; production secret-flow index covers 117 matching lines across the three production source roots | Formal security/code review remains pending. Metadata stores generation/configuration values, not candidate text; diagnostic construction does not receive API Key values. No zeroization claim. |
| US-12, FM-22 | Final v2 Universal Developer ID/profile verification and Data Protection Keychain CRUD returned exit 0 | Separate signed test bundle; no installation, notarization, appcast publication or release performed. |

The `/implement` checklist gate remains open. Formal code review, test review and final feature cross-regression must not be marked complete from this inventory.

### Ticket 21 current-source reconciliation — 2026-09-07

The inventory above is now reconciled for code-level review: each owned row names its public test, signed gate or inspected secret-flow evidence. The documented physical-process/browser gaps remain explicit exceptions, not passing tests. Ticket 22/23 responsibilities are unchanged.

- Current strict/full/native chain exited 0: 312 tests / 72 suites, 15.447 seconds; native editor 10/10, 0.858–1.325 seconds. Logs: `/private/tmp/ticket21-final-v4-{strict,full,native}.log`.
- US-11 inspection: `/private/tmp/ticket21-review-secret-sinks-v4.log` contains 117 matches / 13,027 bytes from all three production Swift roots with hidden/ignored files included. Followed the actual credential, metadata and diagnostic encoders and application diagnostic call sites. Candidate values go to memory, the designated Provider request and Keychain, not metadata or diagnostic fields. This is source-flow review, not a universal runtime leak detector or a memory-zeroization claim.
- US-12/FM-22 final-source Universal bundle: `/private/tmp/vlmsnapper-ticket21-signing-final-v4/VLMSnapper.app`. Developer ID/profile verification and random-service Keychain CRUD exited 0; logs `/private/tmp/ticket21-final-v4-{universal,signing,keychain}.log`. Installed app was untouched.
- US-07 empty-state correction: `unchangedCredentialAfterFailure` failed before the eligibility correction and passed afterward; `clearedFailedCandidateRenders` produced the actual management view before/after. Before: validation row absent; after: visible disabled. Static PNG generation alone is not an automated visibility assertion.
- This code-level reconciliation permits the separate code/test reviews below. Browser preview acceptance is still unavailable; it is not inferred from this checklist. Do not mark the ticket delivered or open a PR on the strength of these local gates alone.

### Ticket 21 final acceptance — 2026-09-07

This table supersedes the pending delivery status above, not its historical observations. Each row is accepted at the ticket's declared test/gate/evidence boundary, not as installed-app or live-account certification.

| Owned rows | Redeemed criterion and current evidence | Verdict |
|---|---|---|
| US-07, FM-28 | `retirementWriteFailurePreservesOriginalConfiguration`, `credentialWriteFailureDoesNotRestorePreviousConfiguration`, `listFailureDoesNotRestorePreviousProviderConfiguration`, `failedDeletionCannotRecoverRetiredCredential`; actual no-network mutation red and exact-restoration green recorded above | Pass: admission/no rollback; no retired authentication |
| FM-29 | `replacementPreservesAvailableModelAndCurrentProvider`, `configuringAnotherProviderDoesNotReplaceRememberedCurrentProvider` | Pass: full-list model retention, no selection theft |
| US-08, FM-20 | `genericCredentialWriteFailureIsSecureStorage`, `metadataPublicationFailureIsSecureStorage`, `keychainReadFailureIsNotMissingCredential` | Pass: local storage errors are not Provider outages |
| FM-32, FM-35 | `lateReadFailureIsIgnored`, `submittedValidationUsesExplicitProvider`, `reopenedLoadWaitsForCanceledRead` | Pass: stale generation rejected at session/editor seams |
| FM-40 | `pendingValidationSuppressesDuplicates`, `recoveryPublishesBusyState`, `closingSubmittedDraft`, `closedFailureRetainsCandidate`; reviewed app-owned task wiring | Pass at declared tests; physical window sequence is not claimed |
| FM-41 | `canceledValidationDoesNotPersistCandidate`, `postKeychainPublicationFailureRecovers`, `cancellationBeforeReplacementAdmission`, `terminationDiscardsCandidates`; inspected accepted-Quit cancellation | Pass at cancellation/persistence seams; actual process death is not simulated |
| FM-45 | `keychainReadFailureIsNotMissingCredential`, `lateReadFailureIsIgnored`, `storageReadOnlyActions`; eight production renders; user accepted prototype checklist on 2026-09-07 | Pass: distinct absence/read error, read-only surface, explicit reopen |
| FM-46 reconciliation | `reconciliationRecoversStoredKeyWithoutConfiguration`, `reconciliationCommitsMetadataForDurableNewCredential`, `reconciliationClearsConfigurationWithoutCredential`, `postKeychainPublicationFailureRecovers` | Pass for Ticket 21 only; exclusion and combined restart remain Tickets 22/23 |
| US-11 | 251-key bilingual parity; termination cases; exhaustive production secret-flow inventory and followed encoders in separate code review | Pass for declared evidence; no runtime leak-detector/zeroization claim |
| US-12, FM-22 | Final-source v4 Universal Developer ID/profile verification and Data Protection Keychain CRUD, exit 0 | Pass for retained signed gate; no notarization/release/install |

Delivery refresh: strict build passed; full tests with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` passed 312 tests / 72 suites (16.015 seconds); rebuilt native Paste passed 10/10 (0.956–3.369 seconds); shell syntax, localization parity and diff checks passed. The default Command Line Tools setup failure was excluded from test evidence and prevented delivery until this rerun passed. Source has not changed since the v4 signed gate. Separate code/test reviews and the three-stage document regression are complete for this scope. User prototype acceptance does not accept the separate physical/lifecycle supplement or later tickets.
