# VLMSnapper v1 — Ticket 01 test review

审查范围：`ExtractionCoordinatorTests` 的 6 个公开行为用例。

## 维度 1：覆盖是否完整

- 成功：保存和上传都接收同一份原始 PNG；准备记录保留相同截图、operation ID、Provider 和模型；Provider 恰好调用一次。
- 截图保存失败：归一化为截图持久化错误，Provider 零请求。
- 准备记录失败：安全回滚原截图，Provider 零请求。
- 回滚失败：报告孤儿路径，Provider 零请求。
- 准备记录身份不一致：分别覆盖截图 SHA-256 不一致与模型选择不一致，均回滚且不请求 Provider。
- 本票明确不承兑真实文件系统、SQLite、HTTP 流式、Provider 错误、取消与最终结果落库，这些缺口分别由 Ticket 02、04、06 补测。
- PNG 在本 seam 中是完全不解析的 opaque bytes，因此 fixture 的 PNG 内部结构不会进入任何分支；真实 PNG 编码形态应在 Ticket 05 的截图编码集成测试中验证。

## 维度 2：case 设计是否合理

- 所有状态都从公开 `startExtraction` 入口到达，没有 cast 私有状态或绕过协调器。
- 只使用系统边界假件：截图存储、历史存储、Provider；没有 mock 项目内部模块。
- Provider 请求计数属于“不得联网/恰好一次”的外部边界可观察量，调用次数本身就是规格，予以保留。
- 期望值使用独立字面量或预先构造的领域值，没有复用生产常量或按实现算法重算。

## 维度 3：假通过检查

- 红绿记录：成功路径最初因 `notImplemented` 在公开 seam 红；截图保存、准备记录、回滚失败与准备记录身份不匹配分别在对应断言处红过。
- 变异 1：把传给截图存储的字节改为空 `Data()`；已确认变异到达生产调用点，用例在 `SuccessfulScreenshotStore` 的 0 bytes vs 5 bytes 断言处红。
- 变异 2：移除准备记录的 `ProviderSelection` 比较；已确认 guard 只剩截图比较，用例在“应拒绝不匹配选择”和 Provider 零请求断言处红。
- 变异 3：插入第二次 Provider 调用；已确认源码存在两个调用点，用例在 `requestCount == 1` 断言处红。
- 三次变异均使用事先保存的正式源文件精确还原，并以 `cmp` 逐字节确认；最终完整测试 6/6 通过。
- 曾出现一次测试夹具编译错误（actor 缺少显式初始化器），它没有进入产品行为路径，因此未当作红测证据。

## 结论

本票承兑范围内覆盖完整，case 可达且针对系统边界，三项高风险断言通过独立变异检验；未发现剩余假通过。

---

# VLMSnapper v1 — Ticket 02 test review

审查范围：`FileSystemScreenshotStoreTests` 与 `SQLiteHistoryStoreTests`。

## 维度 1：覆盖是否完整

- 文件系统 10 例覆盖：真实 PNG 字节/时间命名/独立摘要、同秒 `-2` 防覆盖、根链接、祖先链接、月份链接、文件链接、正常加载、正常删除、缺失文件和摘要不匹配替换文件。
- SQLite 12 例覆盖：准备态、uploading、成功原文/译文、归一化失败原因、取消、结果保存失败、三种非终态启动恢复、新版 schema 只读阻断、损坏库阻断、v1 缺列阻断、恢复主库及 WAL/SHM、重置后空库和同秒 recovery 防覆盖。
- spec 失败模式 7、13、14、15、17 中属于本票的持久化与所有权部分已有公开接口测试；真实 Provider、UI 关闭确认、自动清理并发和最终落库重试编排分别由 Ticket 04、06、08 继续覆盖。
- 不可稳定单测的缺口是跨进程在校验与文件系统调用之间替换路径；补测条件是引入目录描述符/POSIX 文件操作 seam，已记录在代码审查。

## 维度 2：case 设计是否合理

- 测试全部从公开 store/resetter 接口进入，不访问 actor 私有状态，不 mock 项目内部模块。
- SQLite 结果全部通过关闭并重开数据库后由公开 `operation(id:)` 读回；新版/损坏库另外比较打开前后原始数据库字节，未用“抛任意错误”替代只读保证。
- 文件内容和 recovery 边车文件直接从真实文件系统读取属于被测系统边界的用户可观察结果；没有断言内部调用次数或 SQL 文本。
- 真实 PNG 摘要是独立固定值；状态期望使用独立字面值或领域值，不复用生产 SQL/常量重算。

## 维度 3：假通过检查

- 红绿成因与目标一致：同秒冲突、根/祖先链接、启动恢复、新版库先写后验、v1 缺列、结果 payload 和保留式重置均在对应公开行为断言处红过；测试环境或夹具创建失败没有算作行为红证据。
- 变异 1：在 SHA 一致后删除路径中把摘要比较改成恒真；替换文件测试在“不得删除替代文件”和文件仍存在断言处红。
- 变异 2：在隔离包中跳过既有数据库预检；新版 schema 测试在“必须阻断”和数据库字节不变断言处红。
- 变异 3：在隔离包中从启动恢复 SQL 漏掉 streaming；测试在恢复数量和 streaming 状态断言处红。
- 正式仓库中的 SHA 变异通过最小补丁还原；后两项只在 `/private/tmp` 隔离副本执行。正式源文件随后由完整测试重新编译，不依赖陈旧构建产物。

## 结论

覆盖、case 设计与假通过三维均已核对。3 项高风险保护通过定向变异；剩余缺口有明确触发条件和后续 seam，不以不稳定竞态测试伪造绿色结果。

---

# VLMSnapper v1 — Ticket 03 test review

审查范围：Provider 配置 16 例、官方模型目录 5 例（覆盖 6 个 Provider/分页结果）、元数据文件 3 例和 Keychain 1 例。

## 维度 1：覆盖是否完整

- Key 验证覆盖完整列表成功、列表失败零写入、Keychain 写失败保留旧状态，以及新凭据已持久化后的启动协调。
- 模型目录覆盖 Gemini 两页成功、后页失败拒绝部分结果、重复 token、401；OpenAI 和 DeepSeek 使用官方真实响应形态，DeepSeek fixture 含实验视觉模型精确 ID。
- 状态机覆盖 24 小时边界、刷新成功/失败、消失模型、首个/后续 Provider、不可用当前 Provider 不自动回退、活动请求冻结、视觉成功/明确不兼容/普通错误和单次刷新门禁。
- 元数据覆盖重开、无秘密内容、祖先符号链接和损坏数据不覆盖；Keychain 覆盖真实增删改查。
- 缺口：签名 App 的 Data Protection Keychain 由 Ticket 10 验收；模型不可用错误到单次刷新门禁的请求级接线由 Ticket 04 验收。

## 维度 2：case 设计是否合理

- HTTP fixture 来自官方文档和调研中的真实响应形态，不与实现模型同源；API Key 只通过请求头断言，且 Gemini URL 明确断言不含 Key。
- 所有配置状态经公开协调器 API 到达；假件只替代 Keychain、元数据和 HTTP 系统边界，不访问 actor 私有状态。
- 文件测试使用真实文件系统，Keychain 测试使用随机 service 并串行运行；失败时清理同一随机条目。

## 维度 3：假通过检查

- 符号链接祖先测试在旧实现上同时于“应报 unsafePath”和“目标目录不得创建”处红；当前 Provider 不抢占测试在旧自动选择条件上红。
- 配置/请求竞态测试最初的缺 API 红不算行为证据；随后定向移除 mutation guard，确认同一测试在允许重叠的断言处红，再精确恢复保护并全量重编译。
- 完整分页测试断言两条真实请求及合并结果；后页失败测试断言具体 503 映射，无法以返回第一页部分结果假绿。
- 完整门禁最终由 Swift Testing 汇总确认 53/53 通过，不使用 XCTest 的“Executed 0 tests”兼容行作为证据。

## 结论

覆盖、case 设计与假通过三维均已核对；高风险竞态、路径逃逸和当前 Provider 不变量都有目标行为红灯证据。两个真实环境/跨票缺口已写明补测条件。

---

# VLMSnapper v1 — Ticket 04 test review

审查范围：请求构造、SSE、三个 wire decoder、结构化增量解析、统一执行器、超时和 HTTP 错误归一化。

## 维度 1：覆盖是否完整

- 三个 Provider 使用同一参数化录制契约，均断言原文、译文、元数据、完成的严格顺序和恰好一个 HTTP 请求。
- 请求体分别覆盖官方端点/鉴权、原始 PNG、流式开关和结构约束；Gemini 额外覆盖完整序列化体上限。
- 协议边界覆盖 SSE UTF-8 字节拆分、注释、CRLF/空帧、Unicode escape/代理对/组合字符、重排键、残缺 JSON、Provider 截断终态、Gemini STOP 后元数据和 DeepSeek 缺失 `[DONE]`。
- 执行覆盖 transport 失败不重试、首字/停滞/总超时、429 冷却截断和 Provider-specific 错误类别。真实网络、账户余额和签名取消只能在 Ticket 10 集成环境补测。

## 维度 2：case 设计是否合理

- 录制 fixtures 按三家官方事件形态独立编写，不复用生产 decoder 或请求 encoder 生成期望；共享断言只针对统一公开事件契约。
- timeout clock 与 HTTP transport 是系统边界假件；测试不访问 actor 私有状态、不真实等待 10/90 秒。请求次数是“无自动重试”的产品可观察约束，因此直接断言。
- 解析测试从公开 `consume`/`finish` 进入；成功必须看到终态，失败必须断言具体归一化类别，不能用“抛任意错误”假代替。

## 维度 3：假通过检查

- 变异 1：成功路径临时插入第二次 `transport.stream`；`successfulOperationMakesOneRequest` 在 request count 断言处红。
- 变异 2：把 stall timeout 错误改成 first-text timeout；`stallDeadlineTerminatesAfterText` 在具体类别断言处红。
- 变异 3：允许 DeepSeek 只有 `finish_reason=stop` 而无 `[DONE]` 完成；`missingDoneIsIncomplete` 在“应抛错”断言处红。
- 三个变异目标还原后 SHA-256 与变异前逐字节一致；最终完整 Swift Testing 汇总 83/83 通过。

## 结论

覆盖、case 设计和假通过三维均已核对；请求次数、超时类别与成功终态三项高风险保护均被定向变异证实。在线账户契约仍是明确的发布补测条件。

---

# VLMSnapper v1 — Ticket 05 test review

审查范围：冻结协调 4 例、选区状态机 7 例、PNG 裁切 4 例、快捷键协调 6 例和 Carbon registrar 生命周期 1 例。

## 维度 1：覆盖是否完整

- 冻结覆盖权限预检、捕获期权限撤销、部分显示器失败与全部失败；选区覆盖触发时帧引用、2 × 2、几何变化、全断开，以及裁切挂起时取消/失效/失败的 actor 重入顺序。
- PNG 覆盖尺寸、8-bit sRGB、越界、极端坐标不溢出和两行不同像素的原位裁切；快捷键覆盖默认值、修饰键、保留键、冲突、原子替换与所有者销毁。
- 缺口：实际 ScreenCaptureKit 像素、TCC 提示、真实多显示器变更和 Carbon 热键投递/冲突只能由 Ticket 10 的签名 App 集成验收。

## 维度 2：case 设计是否合理

- 状态测试只通过 actor 公开 API 进入，不读取私有成员；可暂停 cropper 精确控制异步边界，不依赖 wall-clock sleep。
- PNG 测试使用真实 `CGImage`、真实 ImageIO 解码和 RGBA 像素断言；Carbon smoke 使用真实 registrar 建立/释放，但不抢占用户机器上的实际快捷键。
- 快捷键 probe 只替代 OS 注册边界，直接断言用户可观察的旧注册是否仍有效或已注销。

## 维度 3：假通过检查

- 三个 actor 竞态测试在旧实现上分别出现完成态复活、错误状态残留和错误类别泄漏，随后逐项绿化。
- 极端坐标测试在旧加法校验上使测试进程 signal 5，改为减法边界后稳定返回 `invalidPixelRect`。
- 定向把裁切 Y 坐标改为 `pixelRect.y + 1` 后，真实像素测试准确从红行变为蓝行并失败；还原后通过。
- 协调器销毁测试在旧实现上看到注销计数 0，增加 isolated deinit 后变为 1。最终 Swift Testing 汇总确认 105/105 通过。

## 结论

覆盖、case 设计与假通过三维均已核对；高风险重入、坐标、像素内容和热键生命周期均有明确红灯证据。真实系统交互缺口已分配 Ticket 10。

---

# VLMSnapper v1 — Ticket 06 test review

审查范围：`OperationWorkspaceSessionTests`、`PersistedOperationWorkspaceRunnerTests`、schema v2 SQLite 用例、错误码契约与操作栏定位。

## 维度 1：覆盖是否完整

- 会话覆盖标签切换零请求、显式单请求、全局排他、lease 等待期间关闭/切换、流中关闭、失败 rerun 保留旧成功、未保存结果关闭确认与后续请求阻断。
- runner 覆盖同图复用、截断终态、准备失败/取消回滚、身份不一致零 Provider、Provider 取消、最终保存失败与只保存重试。
- SQLite 覆盖 typed translation/target language 和 v1→v2 legacy extract 迁移；UI 几何覆盖常规下置、屏幕底部翻转和操作栏宽于屏幕。
- 不可由 SwiftPM 稳定覆盖的签名窗口点击、VoiceOver 遍历、真实 TCC 和在线 Provider 留给 Ticket 10，未用静态断言冒充。

## 维度 2：case 设计是否合理

- actor 测试从公开 select/start/close/snapshot API 进入；可暂停 gate 精确控制首次 suspension，不依赖 sleep 或私有状态。
- runner 假件只替代文件、SQLite 和 Provider 系统边界；直接断言截图保存/删除、typed operation、终态和 Provider stream 次数这些用户可观察约束。
- UI 定位以明确 CoreGraphics 坐标和已确认 4 px 常量断言；实际 harness 截图另行核对视觉层级，不用像素快照替代状态测试。

## 维度 3：假通过检查

- “等待 lease 切换标签”在旧实现上准确发出 translate，并同时使 extract/translate 状态断言变红；冻结参数后绿化。
- “历史准备取消回滚截图”在旧取消 catch 上同时于 discard count 和下一次 save count 处红；统一所有权回滚后绿化。
- “Provider cancellation 持久化 canceled”在旧实现上抛 `OperationWorkspaceRunFailure(code: canceled)`、写 failed 且未写 canceled；修复后具体错误与终态断言均绿。
- “宽操作栏保持 leading edge 可见”在旧公式上得到 x=-40 而期望 40；边界夹取修复后绿。最终独立全量运行汇总 127/127，而非采用一次缺少完成汇总的 0 退出假信号。

## 结论

覆盖、case 设计与假通过三维均已核对；4 个高风险用例都在目标行为断言处真实红过。完整测试具有 127/127 Swift Testing 汇总，无剩余已知假通过。

---

# VLMSnapper v1 — Ticket 07 test review

审查范围：`OnboardingSessionTests`、`ScreenCapturePermissionCoordinatorTests`、`ProviderSetupSessionTests` 与 `Ticket07RenderingTests`。

## 维度 1：覆盖是否完整

- 引导 4 例覆盖权限优先 blocker、Provider/model blocker、双条件启用、Later 恒可用，以及菜单 Capture 的 Provider → 权限 → 截图路由顺序。
- 权限 6 例覆盖展示时零请求、首次显式请求、请求前持久标记、拒绝/撤销后只开设置、成功后要求重启、已有权限和重叠点击合并。
- Provider presentation 5 例覆盖完整列表原地展开、不自动选模型、选择后完成、切换 Provider 清 transient、异步旧选择隔离，以及活动请求只读；核心 Ticket 03 测试继续覆盖 Keychain 原子替换、刷新删除消失模型与当前 Provider 不抢占。
- 渲染 1 例实际生成引导、Provider、权限、菜单和隐私 5 个表面，明暗各一份；逐图检查圆角、窄 Provider 标识、操作层级、长英文换行和扁平隐私分区。
- 缺口：真实状态栏点击、SwiftUI sheet 键盘/遮罩、TCC、System Settings 与一键重启需要签名 App；补测条件是 Ticket 09 完成生产组合、Ticket 10 生成签名产物。

## 维度 2：case 设计是否合理

- 核心测试只通过公开 snapshot/intent API 进入；可暂停系统授权和模型选择边界，不依赖 sleep、私有状态或 wall clock。
- Probe 只替代 TCC 请求历史与 Provider 配置系统边界。请求次数是“不得重复系统提示”的用户可观察约束；Provider mutation 记录是只读门禁的外部副作用，均属可接受边界断言。
- 渲染测试使用真实 AppKit window、真实 SwiftUI hosting、PNG 编码和像素尺寸，不用“能构造 View”冒充渲染；输出 PNG 大小门禁之外另有人工作品检查。
- 本票 state fixture 不是第三方 wire data；外部模型列表形态继续由 Ticket 03 的真实官方分页/列表 fixture 独立覆盖。

## 维度 3：假通过检查

- 权限重叠用例在旧实现上得到 `openSystemSettings` 而不是 `noAction`，准确于目标 intent 断言处红；模型切换挂起用例在旧实现上保留旧 Provider presentation，准确红。
- 变异 1：把菜单路由改为权限优先；测试在“模型缺失必须先配置 Provider”断言处得到 `recoverPermission` 并红，随后精确恢复。
- 变异 2：移除只读状态的验证 guard；测试观察到候选 Key 到达 Provider 边界并红，随后精确恢复。
- 渲染门禁同时断言 10 个明确文件、目标像素尺寸和非空 PNG；人工逐图发现 Provider 顺序与重复提示问题并推动修正，证明它不是只检查文件存在的假绿。
- 最终完整宿主测试以 Swift Testing 的 143/143 汇总为准；XCTest 兼容层的 Executed 0 tests 行未作为通过证据。

## 结论

覆盖、case 设计和假通过三维均已核对；入口顺序、重复 TCC、异步 Provider 隔离和只读门禁均有目标行为红灯证据。真实签名系统交互缺口已明确分配，不以离屏渲染替代。
