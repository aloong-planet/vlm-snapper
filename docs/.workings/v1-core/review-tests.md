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

---

# VLMSnapper v1 — Ticket 08 test review

审查范围：历史查询/schema、删除协调器、保留期状态机、runner metrics、文件目录清理与管理中心渲染。

## 维度 1：覆盖是否完整

- 查询覆盖操作类型 + 原文/译文搜索，以及状态、Provider、模型、目标语言、日期和钉住的组合；schema v1 经 v2 路径迁到 v3，新版 schema 继续阻断。
- 删除覆盖活动/钉住跳过、匹配文件成功、普通文件错误保留、缺失/摘要不匹配只删内部记录、批量继续及精确汇总；文件测试覆盖空月份移除和根目录保留。
- 保留期覆盖缩短预览/确认、确认前零写入、延长只保存、启动只运行一次、86399 秒不运行与 86400 秒边界运行。
- UI 渲染覆盖 History、Settings、空搜索和清理失败四态，明暗各一张。真实确认 dialog 点击、菜单栏到窗口和 App 生命周期需要生产 executable，继续由 Ticket 09/10 补测。

## 维度 2：case 设计是否合理

- Core 测试只经公开 query/mutation/coordinator/session seam；probe 仅替代文件、偏好与清理系统边界，不读取私有状态。
- 删除顺序断言系统边界的 attempted paths 和最终 remaining IDs，因为这正是“失败项可重试、后项继续”的用户可观察行为。
- runner 时钟由注入序列驱动，不使用 sleep；期望 250/900 ms 是独立字面量，usage 直接来自模拟 Provider terminal metadata。
- 渲染使用真实 NSWindow、NSHostingView、PNG 编码与明确 8 文件计数，并另行逐图核对整窗布局。

## 维度 3：假通过检查

- 定向变异把普通文件删除错误改为继续删数据库，删除测试准确在 summary 与 remaining IDs 断言处红；精确还原后通过。
- 定向变异把 24 小时门禁从 `>= 86400` 改为 `> 86400`，调度测试准确在第二次 cleanup call 断言处红；精确还原后通过。
- 空月份目录断言在旧实现上读取到目录仍存在并红，修复后同时验证月份不存在、根目录存在。
- 最终完整运行以 Swift Testing 的 151/151、33 suites 汇总为准；一次过滤字符串导致 0 tests 的结果已明确作废并用类型过滤器取得真实 2/2。

## 结论

覆盖、case 设计和假通过三维均已核对；文件所有权、部分失败、精确 24 小时边界和当次渲染都有目标行为证据。未用离屏图冒充真实生产 App 生命周期测试。

---

# VLMSnapper v1 — Ticket 09 test review

审查范围：应用语言、登录项、单实例、诊断、更新生命周期、Sparkle 用户驱动与 Ticket 09 渲染。

## 维度 1：覆盖是否完整

- 语言覆盖完整系统偏好列表、手动策略与区域独立、`system` 原值持久化，并直接验证中英文词典切换。
- 单实例覆盖 secondary 零初始化、primary 一次初始化/激活和真实 POSIX lease 排他/释放；登录项覆盖默认启用后的审批重读和禁用偏好跨启动保持。
- 诊断覆盖 allowlist 拒绝、所有权范围清理、完整截止日、导出 compressor 和系统 gzip 解压；更新覆盖固定 21600 秒、禁止自动下载、按钮不改状态、失败后手动重试和信息型更新零下载。
- Sparkle adapter 覆盖 reply 单次消费、信息型更新拒绝下载和回调严格顺序。UI 实际生成 2 语言 × 2 appearance × 4 更新态 × 2 表面共 32 张 PNG，并人工检查中英文明暗长文案。
- 缺口：跨真实进程激活、SMAppService 审批 UI、签名 appcast 下载/安装与退出协调必须在 Ticket 10 的签名 App 上验证。

## 维度 2：case 设计是否合理

- Core 测试经公开 coordinator/state seam，系统边界仅替换锁、消息、登录 service、Updater driver 和 compressor；真实 POSIX/zlib 路径另有宿主测试，不只测 probe。
- 时间由固定 Date 注入；无 sleep。截止日、21600 秒、字节累计和一次性 reply 使用独立字面量断言。
- 渲染使用真实 NSWindow/NSHostingView、目标 appearance、真实本地化词典和 PNG 编码；直接字符串测试防止“图存在但仍是错语言”的假绿。

## 维度 3：假通过检查

- 第一次沙箱内测试因 `.build`/clang cache 只读产生 `Executed 0 tests`；该结果明确作废，随后在可写宿主取得真实 Swift Testing 汇总。
- 语言测试最初抓到 `String(localized:)` 缓存导致切回中文仍返回英文；改为显式词典后才绿。
- 回调顺序测试直接记录 Core 事件序列；若恢复并行 Task，顺序不再由实现保证。gzip 测试不仅断言 magic bytes，还由系统工具解压并比对 `hello\n`。
- 完整门禁以 Swift Testing 172/172 汇总为准；XCTest 兼容层的 0 tests 行不作为证据。

## 结论

覆盖、case 设计与假通过三维均已核对；锁、隐私、截止日、一次性下载、回调顺序、双语和真实渲染都有目标行为证据，签名系统缺口未被库测试掩盖。

---

# VLMSnapper v1 — Ticket 10 test review

审查范围：生产组合新增 Core 行为、当前 UI 渲染、开发打包与正式发布门禁。

## 维度 1：覆盖是否完整

- 新增 manifest 覆盖三架构完整性、重复/缺失成员、身份/版本/公钥/feed 一致性与 slice；坐标 mapper 覆盖多显示器 AppKit/CG 坐标转换。
- 目标语言覆盖优先顺序、完整标准集合、去重和排除繁体/未知手输；快捷键偏好覆盖跨实例保存和不完整值回退。
- workspace 新增未保存完成结果显式 discard 转移；capture coordinator 覆盖权限、部分屏失败、全部失败和 discovery 权限错误。
- UI 生成 Ticket 09 的 32 张设置/菜单图与 Ticket 10 的 4 张 toolbar 图，并逐图检查中英文、明暗、快捷键尺寸和紧凑操作栏。
- 缺口明确保留：真实 TCC、多物理显示器首帧、系统热键冲突、SMAppService、签名 Keychain、Sparkle 安装和三个 live Provider 契约只能由正式签名环境承兑。

## 维度 2：case 设计是否合理

- Core 测试经公开 manifest/catalog/store/session/coordinator seam，不断言私有 SwiftUI 结构；文件、时钟与系统边界使用可控依赖。
- UI 测试使用生产 View、真实 NSHostingView、appearance、本地化词典与 PNG 编码；文件数量和最小字节门禁之外另有人工作品检查。
- release 脚本分别验证输入 fail-closed、bundle 元数据、目标 slice、DMG checksum/只读挂载和 codesign；formal 流程不因本机缺证书而降级。

## 维度 3：假通过检查

- `TargetLanguageCatalog` 与 `UserDefaultsGlobalShortcutStore` 均经历真实红灯：测试先因类型不存在而编译失败，最小实现后转绿。
- 未保存结果测试在旧实现没有 `discardUnsavedResults` 时编译红，新增状态转移后验证 snapshot 清空。
- 最终以 Swift Testing 的 184/184、45 suites 汇总为准；XCTest 兼容层的 `Executed 0 tests` 明确不作证据。
- 形式发布脚本在缺失凭据时退出 78 且不创建输出；三份 ad-hoc DMG 只证明开发 packaging，不被计入签名、公证或发布通过。

## 结论

覆盖、case 设计与假通过三维已核对；新增公开行为、当前 UI 和三架构开发 packaging 均有真实证据。未执行的签名/公证/Provider 系统门禁继续保持红色，不以 skipped 或开发包冒充通过。

---

# VLMSnapper v1 — Ticket 10 live Provider gate test review

审查范围：6 个 Core gate tests、CLI blocked smoke test、GitHub workflow 失败传播与 Gemini live probe。

## 维度 1：覆盖是否完整

- 覆盖完全缺配置、空白 key/model、环境变量成对装配、完整翻译成功、Provider 归一化失败、无 completed 的不完整流。
- 成功用例同时断言只发一个请求、固定原始 PNG、目标语言、模型、凭据传递、usage 和 request ID 摘要；失败报告编码明确排除 key、PNG/结果 marker 和 Retry-After 原值。
- CLI 无凭据路径验证真实 JSON 文件与非零退出；实际 Gemini 请求验证生产 request factory、URLSession SSE、decoder、10 秒门限与 allowlist 报告的完整链路。
- OpenAI、DeepSeek live 凭据以及三个 Provider 同次全绿仍是明确外部缺口；没有用 skipped 计作通过。

## 维度 2：case 设计是否合理

- Core 测试只经公开 runner/streaming seam；fixture streamer 替代唯一系统网络边界，不读取私有状态。请求次数和传入 operation 是“一次显式执行只请求一次”的外部行为。
- 期望报告使用独立字面量；SHA-256 期望由已知输入的独立摘要给出，不调用生产 redactor 重算。环境 fixture 同时放入完整对、缺 model 对与两家不同 Provider。
- live probe 使用内存生成的固定无敏感图，不保存响应正文；真实运行结果只按 allowlist 报告核对。

## 维度 3：假通过检查

- 缺类型、成功流未实现与空白配置三个 TDD 纵切都先在目标断言处红，再以最小实现转绿；最初 SDK/cache 权限失败不是行为红灯，已明确作废。
- 定向变异让 request ID 原样返回；成功用例准确在 `sha256:455590bece67` 断言处红，随后只还原该变异并重新验证。
- 实际 Gemini 多次出现 passed、malformed output 和 first-text timeout，证明 live gate 不会把“能联网”或某一次成功当作稳定契约通过。
- 完整门禁以 Swift Testing 的 190/190、46 suites 汇总为准；XCTest 兼容层的 `Executed 0 tests` 继续不作为证据。

## 结论

覆盖、case 设计与假通过三维均已核对；缺配置零网络、单请求、完成契约、错误脱敏和进程退出均有有效信号。OpenAI/DeepSeek 与三家同批 live 通过仍保持红色外部门禁。

---

# VLMSnapper v1 — Appcast staging path test review

审查范围：发布 appcast 输出目录回归测试、脚本语法和完整 Swift 门禁。

## 维度 1：覆盖是否完整

- 测试在独立调用目录运行假 `generate_appcast`，同时要求目标 XML 存在于 `appcasts/arm64` 且调用目录不存在同名泄漏文件。
- 正式 release 接线仍由脚本语法检查和代码审查覆盖；签名、公证、enclosure 与 EdDSA 的真实路径继续由本机正式运行承兑。

## 维度 2：case 设计是否合理

- seam 只替换唯一外部边界 Sparkle CLI，不模拟签名、公证或网络；假工具遵守真实 `-o` 参数解析，并在收到的路径写入最小 XML。
- 测试改变进程 current directory，避免“测试恰好从 staging 运行”掩盖相对路径缺陷；临时目录使用唯一 UUID 并在结束后清理。

## 维度 3：假通过检查

- 第一次运行因测试夹具未赋执行位而失败，未计作有效红灯。修正夹具后，旧相对路径在“目标缺失”和“工作目录泄漏”两个目标断言处真实红。
- 只把输出改为规范化 staging 绝对路径后，目标用例 1/1 通过；随后严格 build 与完整 Swift Testing 191/191、47 suites 通过。XCTest 兼容层的 0 tests 未作证据。
- `bash -n Scripts/*.sh` 与 `git diff --check` 通过，排除了新增脚本语法和补丁空白问题。

## 结论

测试能杀死已知相对路径实现，并同时保护目标存在与无仓库泄漏两个外部行为；未用“命令退出 0”替代文件位置断言。

## 2026-08-28 follow-up: versioned download prefix

- 同一个 CLI seam 额外记录 Sparkle 实际收到的 `--download-url-prefix`；输入 `.../releases/v1.0.0` 时必须得到 `.../releases/v1.0.0/`。
- 旧 helper 在该目标断言处真实红，返回值精确缺少最后 `/`；一行规范化修复后目标用例 1/1 转绿。
- 测试不依赖当前仓库路径或真实 Sparkle 私钥，只验证决定 enclosure URL 解析的外部 CLI 契约。

---

# VLMSnapper v1 — Screen-capture purpose metadata test review

## 维度 1：覆盖是否完整

- 源元数据测试同时覆盖英文 fallback、`en` 和 `zh-Hans`，并断言用户确认的完整字面值。
- 真实 arm64 App 组装加正式包校验覆盖文件进入最终 bundle 的接线。真实 macOS 权限弹窗仍需重建 Developer ID 包、安装并在用户授权后重置 VLMSnapper 的 TCC 状态；本轮不用非签名临时包冒充该系统验收。

## 维度 2：case 设计是否合理

- 测试站在 Distribution 元数据这一公开交付 seam，不 cast 私有成员、不手工构造不可达状态，也不重用生产常量计算期望值。
- `try?` 只把缺文件与无效 plist 同样归为“未提供预期值”，三条独立断言仍指向缺失的 locale，不存在静默 skip。

## 维度 3：有没有假通过

- 首次有效红灯精确在三个 `NSScreenCaptureUsageDescription` 值断言处失败；之前的文件读取异常已明确作废，没有当成 TDD 证据。
- 包校验器经过变异：从当次 App 暂时移走 `zh-Hans` 文件后，精确以 `Missing localized Info.plist strings` 终止；只还原该文件后同一校验重新通过。
- 完整门禁以 Swift Testing 的 192 tests / 48 suites 为准；XCTest 兼容层的 `Executed 0 tests` 仍不作证据。

## 结论

覆盖、case 设计与假通过三维已核对。源元数据和最终 App 接线均有可杀死已知缺陷的独立信号；系统 TCC 弹窗保留为重建正式包后的用户授权验收。

---

# VLMSnapper v1 — Quit with app-owned sheet test review

## 维度 1：覆盖是否完整

- 一个真实 AppKit 集成 case 同时呈现 Provider setup、permission recovery 和 storage/privacy 三个 SwiftUI sheet，并逐个断言 attached `NSWindow` 不再阻止应用退出。
- 现有生产 `.sheet` call site 已全量枚举为 onboarding、menu-bar container 和 management center；它们呈现的内容集合与测试中的三个 root 一致。
- 既有 shutdown coordinator 测试继续覆盖活动请求取消/持久化和未保存结果允许/取消；本票没有复制这些断言。独立 bundle-id 的 Developer ID probe 负责普通系统 Quit smoke，不用单元测试冒充进程退出。

## 维度 2：case 设计是否合理

- 测试 seam 是实际 `NSHostingController`、`NSWindow.beginSheet` 产生的 attached sheet，不直接调用私有 bridge，也不手工设置目标属性。
- 断言对象正是 Unified Log 指向的 AppKit window policy，不以“modifier 存在”或“进程启动成功”替代目标行为。
- 三个 sheet 同时呈现，避免连续释放 SwiftUI sheet 时测试框架自身的异步 teardown signal 11；父窗口仅在测试进程内受控保留。

## 维度 3：有没有假通过

- 最初按 suite 显示名使用 `swift test --filter` 时实际运行 0 tests；该结果已明确作废。通过 `swift test list` 获得真实标识后，所有定向结论均要求 Swift Testing 汇总显示 1 test / 1 suite。
- 临时移除 storage/privacy root 的 modifier，并用 `rg` 独立确认目标调用不存在；精确目标测试随后在 `preventsApplicationTerminationWhenModal -> true` 的窗口断言处红。
- 只恢复该 modifier 后，同一精确测试以 1 test / 1 suite 转绿，证明新增 gate 能杀死本次已知回归。

## 结论

测试直接测量导致 Installed App 退出失败的窗口属性，并经过可定位的红绿变异。0-test 输出未计作证据；Developer ID probe 的系统 Quit 返回成功且目标 PID 消失，完成了真实进程层验收。
# VLMSnapper v1 — Ticket 12 status item interaction test review

## 维度 1：覆盖是否完整

- 事件路由覆盖右键抬起、左键抬起和无当前鼠标事件；右键菜单覆盖单 item、无分隔线、英中本地化与实际 target/action 调用。
- dismissal coordinator 覆盖 visible 延后、hidden 立即执行、无 pending close 与重复 close 幂等。
- capture action handler 同批覆盖 Provider 配置、权限恢复与 ready capture 三条互斥路径，明确只有 ready 使用“关闭后截图”。
- Ticket 07 明暗渲染覆盖主面板移除 Quit 后的生产 View；完整测试同时回归全局快捷键、capture router、操作状态与协调终止。

## 维度 2：case 设计是否合理

- 鼠标事件和 capture route 测试站在确定性行为 seam，不通过阻塞的真实 `NSMenu` tracking 或脆弱的 SwiftUI 私有层级完成断言。
- 原生菜单测试真实构造 `MenuBarPanelController` 和 `NSMenuItem`，用 AppKit action dispatch 证明注入 closure 被调用，不只检查 selector 名称。
- popover 时序以 `isPanelShown`、`requestClose` 和 `panelDidClose` 三个系统边界替身控制，断言 callback 相对关闭通知的顺序，而不是等待任意时间。
- UI 渲染只承兑视觉结果；“按钮是否截图”由 capture route + dismissal seam + 生产 `callbacks.onCapture -> capture()` 接线共同承兑，避免把截图像素逻辑复制到 UI 测试。

## 维度 3：有没有假通过

- 初始有效红灯分别因事件 router、Quit init/menu、dismissal coordinator 和 capture handler 不存在而编译失败；实现各自最小纵切后转绿。最初错误 toolchain/cache 运行被明确作废，没有计作行为红灯。
- 受控变异把 `.rightMouseUp` 错路由到主面板，目标测试精确在 `.contextMenu` 断言失败；还原后重新转绿。
- 第二个受控变异把 ready capture 错路由到权限恢复，目标测试得到 `provider, permission, permission` 并精确拒绝，证明测试能发现按钮未截图的核心回归。
- 最终以 Swift Testing 的 197/197、49 suites 为证据；XCTest 兼容层 `Executed 0 tests` 不作证据。严格 Swift/C warnings-as-errors build、双语 strings 校验、源码/测试 CJK 扫描、prototype script parse 与 `git diff --check` 均通过。

## 结论

测试覆盖、case 边界与假通过检查完整。系统级人工剩余项只是安装 App 后实际左右键触感与真实 ScreenCaptureKit/TCC 路径，不影响当前确定性回归证据，也不会被冒充为已完成的签名宿主验收。

---

# 2026-08-31 — Ticket 11/12 integration test review

## 维度 1：覆盖是否完整

- 目标 AppKit test 以真实 attached sheet 覆盖三类 app-owned sheet 的 termination policy，1 test / 1 suite 通过。
- Ticket 12 tests 覆盖右键 action 到注入 Quit callback、左键 panel route 与 ready capture dismissal；完整组合回归为 198 tests / 50 suites。
- 当前 Installed App 的标准 Quit 失败作为旧构建红灯；当前合并产物尚未替换 `/Applications`，因此不把旧 PID 继续存活误报为新代码失败。

## 维度 2：case 设计是否合理

- sheet 测试读取真实 `NSWindow.preventsApplicationTerminationWhenModal`，menu 测试通过 AppKit action dispatch 驱动公开 callback，两条 seam 分别承兑阻断点与入口接线。
- 组合正确性由 production wiring 和完整回归共同承兑；没有通过私有状态、延时猜测或强制结束旧进程制造假成功。

## 维度 3：有没有假通过

- 首次未指定 `DEVELOPER_DIR` 的测试因 Command Line Tools 缺少 `Testing` 模块而在编译阶段失败，未计作行为红灯；改用 CI 同款 `/Applications/Xcode.app` toolchain 后目标测试与全量测试真实执行。
- Swift Testing 明确汇总 198 tests / 50 suites；XCTest compatibility layer 的 `Executed 0 tests` 未计作证据。
- 严格 Swift/C warnings-as-errors build、脚本语法和 arm64/x64/universal DMG 组装与 `hdiutil verify` 全部通过。

---

# VLMSnapper v1 — Ticket 13 Edit menu and prototype parity test review

## 维度 1：覆盖是否完整

- Application menu 测试覆盖完整 Edit 层级、子菜单顺序、标准 selector、快捷键、Find tag、nil target、真实 `NSTextView` responder Paste，以及简体中文菜单。
- Presentation/contract 测试覆盖真实历史标题/操作/相对时间/终态/截图路径、Provider badge、非当前 Provider 的持久化配置状态，以及 menu/onboarding/provider/permission/result/management 的独立确认几何。
- production render 直接实例化十个生产 view，在简体中文/英语和 light/dark 下生成 40 张精确命名 PNG；人工抽查了所有关键表面的层级、截断、圆角、对齐和主题表现。

## 维度 2：case 设计是否合理

- responder 测试调用真实 `NSTextView.tryToPerform`，不是只断言菜单里出现了 “Paste”；selector/target 断言与行为断言相互独立。
- 几何期望在测试中写确认字面值，不用生产 view 自己的 layout 结果计算期望。Provider row 测试构造“当前 DeepSeek 未配置、非当前 OpenAI 已配置”的可达状态，正面覆盖原实现的误报路径。
- render 测试每次先移除固定临时输出目录，再精确比较全部预期文件名；旧截图或遗漏渲染不能再仅靠总数 40 假通过。PNG 字节门槛只证明产物非空，视觉结论仍来自实际查看。

## 维度 3：有没有假通过

- 把 Paste selector 从 `paste:` 变异为 `copy:` 后，目标测试精确在 selector 断言处红；恢复后完整门禁转绿。
- 把菜单栏确认宽度从 370 变异为 369 后，几何测试精确拒绝；恢复后转绿。
- 把非当前 Provider 的 `isConfigured` 强制为 false 后，Provider row 状态测试精确红；恢复真实 `configuration.isUsable` 后转绿。
- 最终 Swift Testing 汇总为 209 tests / 54 suites；XCTest compatibility layer 的 `Executed 0 tests` 不作证据。严格 Swift/C warnings-as-errors build、234/234 双语键、prototype shared blocks、UI literal scan 与 `git diff --check` 均通过。

## 结论

覆盖、case 设计和假通过三维均已核对。Edit 菜单行为、生产状态映射、确认几何和完整表面渲染都有能杀死对应回归的独立信号；真实安装 App 的鼠标/键盘手感仍属于合并后安装验收，不被离屏测试冒充。

---

# 2026-09-01 — Ticket 14 confirmed UI regression test review

## 维度 1：覆盖是否完整

- Menu capture case 同批驱动 `.configureProvider`、`.recoverPermission` 与 `.capture` 三个公开 route，逐项要求进入 panel-dismissal 后的 application callback；现有 dismissal tests 继续承兑 visible/hidden panel 时序和幂等关闭。
- Provider input state 覆盖用户粘贴后立即可验证、validating 期间禁用、点当前 Provider 保留 draft、切换到另一 Provider 清除旧 draft。
- Theme render case 在真实 `NSHostingView` 中把 secondary surface 合成到 window surface 后取中心像素，分别固定 Aqua 与 Dark Aqua；浅色亮度必须大于 `0.8`，暗色必须小于 `0.2`。
- History detail 的 card hierarchy 属纯视觉结构，SwiftUI 私有层级没有稳定公开 seam。测试不添加与实现共享的几何常量；由最新 production whole-window render 承兑 outer surface、bordered card、header divider、截图/文字/metrics 层级。
- 真实安装 App 的“点击 Capture 后 onboarding 成为系统最前窗”和实际 SecureField 粘贴手感仍需本地安装 smoke；离屏/纯状态测试不冒充系统窗口层验收。

## 维度 2：case 设计是否合理

- Menu test 站在生产 handler seam，三种 route 都来自公开枚举；断言用户动作最终是否进入 application callback，不断言内部 sheet state。
- Provider state 是为修复 plain binding 不观察而建立的 presentation seam；状态全部通过公开编辑/Provider 选择动作到达，没有 cast、私有字段改写或 application-model mock。
- Theme test 的阈值来自已确认原型的浅/暗表面关系，未 import 生产常量作期望；先绘制真实 window backing，避免半透明颜色在透明 bitmap 上产生无意义 RGB。
- Ticket 13 render 每次重建当前分支的 production views 并清空固定输出目录；本轮实际查看了管理历史、Provider settings、Provider setup 和暗色管理页。

## 维度 3：有没有假通过

- 菜单定向变异让 `.configureProvider` 不调用 dismissal callback；目标测试从三次事件变为两次，并精确红在缺少一次 `capture-after-dismissal`。
- Provider 定向变异让 `updateAPIKey` 丢弃输入；目标测试精确红在 draft 仍为空和 Validate readiness 为 false。
- Theme 定向变异恢复旧 `underPageBackgroundColor`；浅色实际合成亮度降为 `0.358`，目标测试精确拒绝。
- 三处变异分别用 `apply_patch` 只还原变异行；还原后 menu 1/1、Provider 2/2、theme 2/2 全部重新转绿。
- Ticket 13 PNG 生成测试仍只证明产物存在，不单独承担视觉正确性；本轮结论明确依赖实际查看的新渲染图，避免把旧的 byte-count 假绿继续当原型一致证据。

## 结论

本轮行为与主题回归都有可杀死已知错误的独立测试。纯历史布局保留诚实的视觉验收缺口，并已由当前产物整窗核对；下一道完整门禁和安装 smoke 仍需继续执行。
# Ticket 15 — Production regression follow-up test review

## 维度 1：覆盖完整性

| 用户操作/边界 | Test / evidence | 结论 |
| --- | --- | --- |
| 可见菜单面板关闭后才进入 readiness，并且不在 close callback 内同步执行 | `visiblePanelDefersActionUntilAfterCloseCallback` | 已覆盖异步 race；有界等待避免挂死 |
| hidden panel 的既有路径仍立即执行且 close callback 幂等 | `hiddenPanelPerformsActionImmediately` | 既有回归覆盖保持 |
| 401/403 typed rejection 显示 invalid credential | `rejectedAPIKeyIsReportedAsInvalidCredentials` | 通过公开 `validate(apiKey:)` 路径覆盖 |
| 非鉴权 model-list failure 不被误标为 invalid credential | `providerOutageIsNotReportedAsInvalidCredentials` | 503 反例覆盖 |
| 管理窗口最小值约束完整内容区 | `minimumAppliesToContentArea` | 覆盖独立 `920×620` literal 与 AppKit minimum frame 的实际 content layout |
| 最小内容区的完整视觉层级 | `confirmedSurfacesRender` 的四张 `management-minimum-*` | 已生成并目视核对双语明暗 |
| status-item 到 frontmost key window 的跨应用 activation | 签名安装版手动 acceptance | 自动化缺口已在 `Ticket12MenuBarInteractionTests.swift` 文件头说明；需要真实 WindowServer 与另一前台应用 |

## 维度 2：case 设计

- Provider 用例通过 `ProviderSetupConfiguring` 公开边界抛出生产 typed error，没有 cast、私有状态或项目内 mock。
- 管理窗口用例构造真实 `ManagementCenterWindowController` 和 `NSWindow`，独立期望值为用户确认的 `920×620`；没有复用 production constant 作为 expected。
- menu 用例通过既有 dismissal coordinator 公开路径进入可达状态，断言 close request、callback 内未执行和后续 exactly-once 结果。
- render 使用 production `ManagementCenterView`，不是 prototype fixture；其定位是视觉补充证据，不冒充窗口约束行为测试。
- 所有 async 断言都在 awaited 测试体内执行，没有 callback 内静默绿或空集合循环。

## 维度 3：假通过检查

- Provider auth 用例在实现前准确红于 `.unavailable == .invalidConfiguration`；成因就是目标错误分类。
- Management 用例在实现前准确红于 `contentMinSize=(920,588)` 及 content height 588；成因就是 frame/content 混用。
- Menu lifecycle 用例在实现前准确红于 callback 内 `events=["capture"]`；成因就是目标同步执行。
- 503 反例用于防止过宽映射；review 变异把任意 `ProviderModelListError` 视为 invalid credential 时，该用例必须红于 `.invalidConfiguration == .unavailable`，还原后重新转绿。
- 无恒真阈值、输入别名期望、复用 production constant、静默 skip 或陈旧构建产物；每次 focused run 都先触发 SwiftPM 重建受改目标。

## Review result

覆盖完整、case 站在现有公开 seam、三条核心回归均有准确红灯。唯一无法在 SwiftPM 单测内证明的是跨应用 WindowServer activation，已诚实保留为签名安装版 acceptance，不用合成断言冒充。

---

# VLMSnapper v1 — Ticket 16 test review

## 维度 1：覆盖是否完整

- profile 测试覆盖匹配成功、动态 entitlement、过期、错误 Bundle ID、未授权证书、未授权 Keychain group、非 Developer ID distribution profile，以及基础 entitlement 禁止预写三项受管理身份键。
- preparation/script 测试覆盖既有输出拒绝覆盖和正式发布缺少外部 profile 时的状态 78 fail-closed。真实下载 profile 另走系统 CMS 解码与签名工具，提供独立于 spec/合成 fixture 的外部结构样本。
- Provider 测试覆盖 Keychain 写失败映射到本地安全存储；既有配置协调器测试覆盖失败时回滚 pending journal、保留旧配置。烟测单元测试覆盖完整增读改删顺序与中途读取失败仍清理。
- SwiftPM 无签名宿主不能证明 Data Protection Keychain。该缺口由最终签名 Universal App 的真实 CRUD 进程验收填补；arm64、x64、Universal 三种 App 均另做静态 profile/签名一致性验收。
- 未执行完整公证上传、stapling 与公开 appcast 发布；这些仍由既有正式发布 workflow 承兑，本票只改变其签名前置 profile 与 Keychain 门禁，不把本地签名验收冒充正式发布完成。

## 维度 2：case 设计是否合理

- profile 用例从公开初始化与 `validatedSigningMetadata` seam 驱动；期望值是已知字面量，不复用生产常量或按实现算法重算。
- Keychain smoke fake 记录外部存储边界操作；顺序本身就是“增、读、改、读、删、确认删除”的验收契约，因此精确序列断言属于系统边界豁免，不是内部协作者耦合。
- release script 测试启动真实 shell 入口并断言退出状态与稳定错误，不读取私有函数。真实签名验收读取最终 bundle 的系统签名与 entitlement，不以源文件存在性替代生效验证。
- 所有临时目录和随机 service 都由用例独占并清理；无私有 cast、手工不可达状态、空集合循环断言或条件静默 return。

## 维度 3：有没有假通过

- profile 合成用例开发期分别红于缺少 parser、派生身份和受管理 entitlement；Provider 分类用例红于 `.unavailable != .secureStorage`；smoke 清理用例红于失败后没有 delete。
- 三架构验收均在本轮重新 build 后执行。Universal 真实 CRUD 输出来自最终 Developer ID 签名进程；未签名 SwiftPM 在 Codex 沙箱内返回 `-50` 的失败已判为环境假信号，并在沙箱外完整 Xcode 环境重跑为绿。
- 对签名一致性新门禁做了负向变异：只修改临时 metadata 副本中的 application identifier，确认被检对象确实包含错误值后，校验器以状态 1 精确失败在实际 entitlement 比较；原 App 与正式 metadata 未改动。
- 最终全量为 229 tests / 61 suites；Keychain 与 AppKit 必须在沙箱外运行，所有套件均实际执行，无 skip。`git diff --check` 与五个 shell 脚本语法检查同时通过。

## Review result

单元、脚本、真实 profile、三架构签名和最终签名进程 CRUD 形成互相独立的验证层；没有发现恒真断言、陈旧产物或用合成路径冒充系统行为的剩余缺口。

---

# VLMSnapper v1 — Direct Pictures storage test review (2026-09-02)

## 维度 1：覆盖是否完整

| 边界/回归点 | Test / evidence | 结论 |
| --- | --- | --- |
| 沙盒 Pictures 代理必须转换为直接用户 Pictures 根目录 | `sandboxPicturesProxyResolvesToDirectUserPicturesPath` | 覆盖真实代理形态、根目录字面值与最终受管理文件路径 |
| 直接根目录仍能保存原始 PNG | 同一测试通过 `FileSystemScreenshotStore.save(originalPNG:)` | 走公开存储 seam，不只断言路径字符串 |
| 应用自建根目录、祖先、年月目录或图片被符号链接替换 | `FileSystemScreenshotStoreTests` 既有 10 个用例 | focused 安全套件全绿，未因入口修复放宽通用防护 |
| 已签名沙盒 App 实际写入用户 Pictures | Developer ID 签名诊断运行 | 保存路径实测为 `/Users/loong_zhou/Pictures/VLMSnapper/2026-09/...png`，随后删除诊断文件 |
| 其余应用回归 | 完整 SwiftPM test run | 230 tests / 62 suites 全部执行并通过 |

## 维度 2：case 设计是否合理

- 新用例通过公开 `ManagedScreenshotRoot.directURL(for:)` 与 `FileSystemScreenshotStore.save(originalPNG:)` 验证行为，没有 cast 私有状态、mock 自有模块或断言内部调用顺序。
- fixture 使用真实系统形态：一个存在的 Container `Data/Pictures` 符号链接指向另一个存在的 Pictures 目录；状态可经文件系统公开操作构造且可复现。
- 期望根目录由独立字面量 `Pictures/VLMSnapper` 构造，不复用生产解析算法；最终文件还必须位于该根下且不得位于 Container 路径下。
- 临时目录由用例独占并在 `defer` 清理；异步保存被 `await`，断言不会落在未执行 callback 或空集合循环里。

## 维度 3：有没有假通过

- 开发红灯准确发生在生产类型尚不存在的编译错误；该红只证明缺少 seam，因此另做目标变异验证。
- 变异检验只删除生产实现的 `.resolvingSymlinksInPath()`，SwiftPM 明确重新编译该文件，测试精确红于 `Caught error: unsafePath`；这正是本次要防止的旧故障。
- 只用 `apply_patch` 恢复该一行后，同一 focused 测试重新构建并通过。变异到达、失败归因和还原三项均有直接输出证据。
- 签名沙盒验收使用本轮重新构建和重新签名的 App，并断言实际返回的保存路径；不是文件存在性、旧构建产物或手动调用内部函数。
- 变异还原后的默认完整运行曾有一次既有 `ApplicationMenuTests` 读到另一套件写入的简体中文全局语言状态；该套件单独运行 4/4 通过，完整套件限制为一个 worker 后 230/230 通过。它是改动面外的测试隔离问题，不把重跑绿冒充不存在；本轮完整门禁采用 `--parallel --num-workers 1` 消除跨 worker 共享状态干扰。

## Review result

覆盖包含模拟真实代理形态的永久回归测试、既有安全边界测试和一次真实签名沙盒验收。测试会在直接路径解析被移除时准确失败，未发现恒真断言或用合成路径冒充产品行为的剩余缺口。
