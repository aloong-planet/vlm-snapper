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

# VLMSnapper v1 — Retina frozen capture test review (2026-09-03)

## 维度 1：覆盖是否完整

| 边界/回归点 | Test / evidence | 结论 |
| --- | --- | --- |
| 1× display 不被无条件放大 | `preservesOneTimesDimensions` | `1920 × 1080 @1x` 保持原尺寸 |
| Retina filter geometry 使用物理像素 | `convertsRetinaGeometryToPhysicalPixels` | 真实诊断形态 `1512 × 982 @2x` 得到 `3024 × 1964` |
| fractional raster 舍入 | `roundsFractionalPhysicalDimensions` | 两个 `.5` 边界独立断言为相邻整数 pixel |
| 小于半 pixel 的无效尺寸 | `rejectsRoundedZeroDimension` | 不产生 0 宽 raster |
| 浮点到 Int 溢出 | `rejectsIntegerOverflow` | 不 trap，返回 nil |
| point 到 pixel 选区映射 | 既有 `CaptureCoordinateMapperTests` | Retina 2× 映射与上下轴翻转继续通过 |
| 原始 PNG 不缩放裁剪 | 既有 `SRGBPNGCropperTests` | pixel rect 直接裁切且输出尺寸精确 |
| 真实 ScreenCaptureKit 返回 raster | 签名安装版验收缺口 | 需要屏幕录制权限和 WindowServer；发布前在 Retina 真机检查冻结预览及 PNG dimensions |

## 维度 2：case 设计是否合理

- 新用例使用 Core 模块内部 raster seam，不构造 `SCContentFilter` 私有状态、不 mock 自有模块，也不依赖某台机器的活动显示器。
- Retina fixture 来自本机真实诊断形态，而非仅由 spec 想象；期望 `3024 × 1964` 是独立字面量，没有复用生产算法重算。
- 1×、fractional、零像素和溢出均使用互不别名的输入与期望；测试函数同步执行，没有未 await callback 或空集合断言。
- 测试名称只声称验证 filter geometry 换算；它不声称纯函数绿灯证明系统截图输出。生产代码另以实际 `CGImage` dimensions 做运行期 gate。

## 维度 3：有没有假通过

- 首个 Retina 用例在生产路径已接入但仍忽略 `pointPixelScale` 时，准确红为 `1512 × 982 != 3024 × 1964`；加入 scale 后转绿，失败原因正是本次旧行为。
- 溢出用例在旧上界判断下实际以 Swift `Double` 转 `Int` trap 退出；把 gate 改为对舍入值执行严格上界检查后转绿。
- 变异到达由 SwiftPM 重新编译 `ScreenCaptureKitFrozenDisplayCapturer.swift` 和失败位置确认；没有使用陈旧 App 产物、skip 或条件 return。
- 纯单测不能证明 WindowServer 实际输出，缺口已在维度 1 明示；不以 helper 测试冒充签名 App 端到端验收。

## Review result

测试覆盖旧 1× 错误、正常 1×、舍入及转换安全边界，且两个目标故障均有真实红绿证据。系统截图与 Retina 视觉清晰度保留为明确的安装版验收项。

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

---

# VLMSnapper v1 — Localization test isolation test review (2026-09-02)

## 维度 1：覆盖是否完整

| 边界/回归点 | Test / evidence | 结论 |
| --- | --- | --- |
| 两个本地化测试区段不能重叠且不能泄漏语言 | `LocalizationTestCoordinatorTests.localizationTestSectionsCannotOverlap` | 直接并发竞争共同协调器，覆盖持锁、阻塞、释放后继续和默认简体中文恢复 |
| 当前全部显式语言切换点 | 六个文件、10 个测试函数、16 次 `VLMSnapperLocalization.configure` | 每个函数入口都有共同 `acquire` 与配对 `defer release` |
| 原受影响 suite 的行为回归 | 7 suites / 17 focused tests | 应用菜单、菜单栏、Ticket 09/10/12/13 渲染与交互全部通过 |
| 正常并发完整门禁 | `--parallel --num-workers 8` | 最小 diff 版本连续三轮 231 tests / 63 suites 全绿，不再用单 worker 隐藏竞态 |

## 维度 2：case 设计是否合理

- 回归测试使用协调器的公开 test-target seam，不读取私有锁状态或按生产实现重算期望。
- 第一个队列明确发出“已进入”信号并等待释放；第二个队列的“提前进入”是本次故障的直接反例。释放后两条队列都必须在有界时间内完成，最终字符串还必须恢复为简体中文，避免死锁或状态泄漏型假绿。
- 首次进入允许等待 15 秒，是因为完整并发运行中其他 production render 测试可能合法持锁约 5–9 秒；拿到锁后的关键反例仍限定为 100 毫秒，没有通过放宽目标断言掩盖互斥失效。
- 既有测试只增加配对协调调用，原输入、渲染、用户文案和期望均未改变。

## 维度 3：有没有假通过

- TDD 第一阶段先因 `LocalizationTestCoordinator` 不存在产生编译红；加入空实现后，行为测试准确红于第二个区段提前进入。
- 最终 API 形态再次做 mutation test：移除 `lock.lock()/unlock()`，测试在 5 毫秒内精确红于 `.success != .timedOut`；恢复两行锁操作后转绿。
- 最小 diff 版本 focused 17/17 通过，随后三次正常 8-worker 完整运行均为 231/231；没有缓存旧二进制、skip 或单 worker 降级。
- 调整前的一次完整并发运行曾在无关的 `SQLiteHistoryStoreTests.uploadingExtractionSurvivesReopeningDatabase` 抛 `databaseFailure`。该用例单独连续 10 次全绿，后续最小 diff 三轮完整运行也全绿；当前证据不足以归因或证明不存在独立偶发问题，本 PR 不改 SQLite。建议另开诊断任务做可观测错误码与并发压力复现，不把本次绿色结果冒充该信号已修复。

## Review result

测试覆盖目标竞态、全部现有调用点和正常多 worker 门禁，且 mutation 会准确打红。未发现本次修复的假通过；SQLite 偶发信号明确隔离并保留为独立诊断候选。

---

# VLMSnapper v1 — Result window, rerun history, and menu interaction test review (2026-09-02)

## 维度 1：覆盖是否完整

| 边界/回归点 | Test / evidence | 结论 |
| --- | --- | --- |
| 普通窗口层级 | `normalWindowAndNonPresentingRefresh` | 直接断言真实 `NSWindow.level == .normal` |
| 内容刷新不得重新显示隐藏窗口 | 同一用例先保持新窗口隐藏，再调用 production `update` | `isVisible` 仍为 false；不会用内容刷新冒充展示 |
| 当前结果重跑复用历史身份 | `rerunReplacesExistingHistoryRecord` | 两次同槽运行只 prepare 一次、字典只保留一个 UUID，最终内容为第二次结果 |
| 失败重跑保留旧成功结果 | `failedRerunPreservesPreviousPersistedResult` | 第二次 Provider 失败后仍为同一 ID 和首次成功内容 |
| 替换保存失败后手动重试 | `retryingReplacementSaveReusesHistoryIdentity` | unsaved replacement 可再次持久化到原 ID，不重新请求 Provider |
| SQLite 原子替换 | `replacingResultPreservesIdentityAndPinState` | 经公开 history 查询读回同 ID、新内容、新模型、新耗时及原 pin 状态 |
| 菜单完整可见区域点击 | `completeRowIsClickable` | 真实 `NSWindow + NSHostingView` 在 240 pt 按钮的 x=235 边缘点击 exactly once |
| 三种菜单角色 hover | `everyRoleHasHoverResponse` | Capture、row、footer 的 hover 与 idle 背景状态均不同 |
| 生产界面回归 | `Ticket13RenderingTests` | 44 张中英文/明暗生产表面实际渲染；菜单非 hover 布局人工核对通过 |

真实跨应用退后台和真实鼠标 hover 仍需安装版 WindowServer 验收；单元层不以合成事件冒充这两项系统集成结论。

## 维度 2：case 设计是否合理

- runner 用例从公开 `run` 接口驱动两个完整 Provider 流，并通过 history boundary 的 UUID/当前结果观察效果；没有直写 runner 状态或只断言内部调用顺序。
- SQLite 用例通过公开 prepare/finish/replace/history 接口读回，期望内容使用独立字面量，不复算 SQL 或读取数据库私有字段。
- 菜单点击走 `NSWindow.sendEvent` 的正常命中与 responder 路径，断言 action 的用户可见效果；它证明组件几何，不声称覆盖真实物理鼠标或状态栏窗口。
- 窗口用例构造真实 controller/window；应用层全部调用点另以全量检索核对，只有首次打开传 `bringToFront: true`，五个流式/终态刷新点使用非展示路径。

## 维度 3：有没有假通过

- 历史用例在修复前实际红于 prepare 两次和两个 UUID，成因正是目标重复记录。
- 窗口用例初始编译红只证明缺少 refresh seam，因此另将 `.normal` 变异回 `.floating`；测试精确红于 level 3 对 level 0 的断言，随后只还原该行。
- 菜单命中用例将 label 的 `maxWidth: .infinity` 移除后，右侧边缘 actionCount 精确保持 0；恢复该 modifier 后转绿。
- hover 用例把 row/footer 的 hover opacity 固定为 0 后精确产生两条失败；恢复分支后转绿。
- 完整运行实际执行 246 tests / 65 suites；没有 skip、零断言循环、陈旧构建或失败后放宽断言。

## Review result

测试能对三个旧故障形态分别打红，并覆盖成功、失败、保存替换和 UI 几何。安装版仍需用户验证真实跨应用排序与物理鼠标 hover，缺口已明确，不用单元绿灯替代。

---

# VLMSnapper v1 — DeepSeek reasoning activity timeout test review (2026-09-02)

## 维度 1：覆盖是否完整

| 边界/回归点 | Test / evidence | 结论 |
| --- | --- | --- |
| 两段推理活动跨过 250 ms 首字期限后仍能完成 | `deepSeekReasoningKeepsFirstTextDeadlineAlive` | 公开文字在约 300 ms 才到达，若推理活动未重置计时则必然失败，修复后成功 |
| 推理内容不进入公开结果 | 同一 executor 用例的完整事件数组 | 只得到 `sourceDelta("Hello")`、metadata、completed，没有推理增量 |
| 只有非空推理字段算私有活动 | `onlyNonemptyReasoningIsPrivateProviderActivity` | 覆盖非空推理、普通缓冲 content 与空推理三个相邻形态 |
| 首字、停滞、总时限及 OpenAI 行为 | `ProviderAdapterExecutorTests` 既有 timeout 用例 | 共享 coordinator 回归保持通过；total timer 未被活动路径取消 |
| 真实模型波动 | 同一原图、生产 executor、顺序 10 次 | 10/10 通过，0 次 `first_text_timeout`；两次总耗时超过 10 秒仍完成 |

## 维度 2：case 设计是否合理

- executor 回归使用真实 DeepSeek SSE JSON 与生产 decoder/timeout actor，仅替换传输边界和时间长度；它没有直接调用 `receivedActivity`，因此能覆盖字段解码、私有信号传播和 timer 重置整条链路。
- 250 ms first-text 与 150 ms + 150 ms 分片间隔构成清晰反例：任何单段间隔都未超时，但若推理活动不被识别，总等待必然越过旧 deadline；100 ms 余量降低高负载 CI 的调度型假红风险。
- decoder scope 用例先断言推理没有公开事件，再用尚未形成公开事件的普通 `{` content 验证它不获得私有特权，最后验证空推理不算活动。
- 真实测试使用用户授权的同一原始 PNG 和实际 `deepseek-v4-flash-vision-exp`，顺序执行以避免并发限流；报告不包含 API Key 或识别文本。

## 维度 3：有没有假通过

- 第一条回归最初以 60 ms deadline 和 40 ms 分片间隔在实现前实际运行，并于 68 ms 精确红为 `firstTextTimeout`；实现后转绿，最终测试再放大为 250/150 ms 以增加调度余量，证明不是只调整期望。
- 收紧范围时新增 decoder 用例，当前补丁先精确红于普通缓冲 content 被误标为活动；删除该越界置位后同一用例转绿，证明测试能区分推理与普通 content。
- 完整 8-worker 测试实际执行 239 tests / 63 suites 并一次通过；warnings-as-errors 严格构建通过，没有 skip、串行降级或失败后重跑。
- 真实 10 次生产链耗时为 6,396–19,827 ms，中位 8,945 ms、平均 10,140.1 ms；结果保留了两次超过 10 秒的慢样本，没有筛除波动以制造全绿。

## Review result

单元层能对旧 bug 和越界修复分别打红，完整套件守住共享行为，真实生产链覆盖实际模型波动。未发现恒真断言、未到达代码、陈旧构建或绕过应用 timeout 的假通过。

---

# VLMSnapper v1 — Capture from result workspace test review (2026-09-03)

## 维度 1：覆盖是否完整

- 工作区 seam 覆盖已保存成功、失败、取消三种终态，活动请求、未保存结果、重复截图准入和退让后 Try Again 六类边界；所有状态都经公开操作路径构造，没有直写 actor 内部字段。
- 窗口 seam 使用真实 AppKit `NSWindow`，同时断言隐藏后的可见性、动作同步时尚未执行，以及后续主 actor 调度中只执行一次。
- 应用入口的已安装旧版由真实全局快捷键复现过原始症状；本次 SwiftPM 测试不发送 Provider 请求，也不替代下一次本地安装后的完整快捷键验收。补测条件是把本 PR 合并并更新签名 App 后，在已保存结果工作区再次按 `⌥⇧S`。
- spec Failure Modes 23–24 的活动、未保存、三类安全终态和重复触发均有对应测试；没有新的外部数据 fixture。

## 维度 2：case 设计是否合理

- 测试只调用 `OperationWorkspaceSession` 和 `ResultWorkspaceWindowController` 的公开 seam；不 mock 项目内部模块、不 cast 私有状态、不读取数据库或窗口内部实现作旁路断言。
- 终态用例分别让 runner 成功、失败和在公开 close 路径取消；活动用例使用受控系统边界 runner 保持请求进行中，未保存用例使用公开持久化失败事件。
- 窗口测试断言的是用户关心的可观测状态 `isVisible` 和截图动作发生顺序；exactly-once 次数本身就是重复截图准入契约，不是内部协作者顺序耦合。
- 所有异步断言均被 await；等待循环有最终精确断言，不存在 callback 未执行或空集合导致的静默绿。

## 维度 3：有没有假通过

- 最初的工作区回归在实现前准确红于旧 `.presentWorkspace` 行为；窗口回归在隐藏和延迟尚未实现时分别红于 `isVisible == true` 和同步 `captureCount == 1`。
- 负向变异分别移除活动请求保护、移除未保存结果保护、移除一次性消费，以及把安全终态改回“展示工作区”。对应测试逐一精确红于 `.beginCapture` / `.presentWorkspace` / `.alreadyPrepared` 的目标断言，恢复后 17 项工作区测试重新全绿。
- 变异直接落在生产 `prepareForCapture` 的已枚举唯一实现中，SwiftPM 每次重新编译该文件；错误位置均落在新增测试断言，不是陈旧构建或其他 suite 偶发失败。
- 完整 8-worker 测试实际执行 259 tests / 66 suites 并通过。严格 warnings-as-errors 构建已通过，无 skip、串行降级、输入别名期望或 production constant 同义反复。

## Review result

新增测试能分别打红根因、保护边界和调度顺序。唯一保留缺口是新签名安装版的真实快捷键端到端验收，已明确补测条件，没有用合成事件或旧构建冒充。

---

# VLMSnapper v1 — Management Center capture and history-open test review (2026-09-03)

## 维度 1：覆盖是否完整

| 边界/回归点 | Test / evidence | 结论 |
| --- | --- | --- |
| 已保存翻译恢复 | `restoresSavedTranslationWithoutStartingWork` | 操作槽、原文、译文、metadata 和成功状态均从历史快照恢复 |
| 失败提取恢复 | `restoresFailedExtractionWithoutStartingWork` | 保存的失败原因和提取操作被保留，不伪造成功内容 |
| 工作区替换竞态 | `historyReplacementReservationOnlySucceedsOnce` | actor 内 reservation 只允许一次，旧工作区不再接纳并发操作 |
| 截图前管理中心退让 | `managementCenterHidesBeforeDeferredCaptureAction` | 真实 `NSWindow` 先不可见，同步调用栈不执行截图动作，下一调度点只执行一次 |
| 单击与双击职责分离 | `managementCenterSelectionAndOpenCallbacksRemainSeparate` | selection 与 open callback 独立触发，没有隐式 Provider 工作 |
| 全量回归 | `swift test` | 264 tests / 67 suites 通过；warnings-as-errors 构建通过 |

## 维度 2：case 设计是否合理

- 恢复测试只通过公开 `OperationWorkspaceSnapshot(restoring:)` 输入持久化模型，不直写会话私有状态，也不 mock 项目内部模块。
- replacement 测试连续调用公开 actor seam，第二次必须失败；它直接覆盖用户双击和旧窗口 Try Again 的竞争边界。
- 窗口测试使用真实 AppKit `NSWindow`，同时检查隐藏状态、同步时序和 exactly-once，不以控制器内部字段替代用户可见结果。
- 回调测试证明两种手势的业务职责可分离；真实 SwiftUI `List` 的鼠标双击投递与缺图禁用外观仍保留为安装版人工验收项。

## 维度 3：有没有假通过

- 初始有效红由缺失的历史恢复 initializer、管理中心退让方法和打开回调产生；修复前测试不能编译，补齐最小公开 seam 后转绿。
- 把翻译恢复错误改成提取恢复时，四项快照断言失败；恢复正确映射后转绿。
- 移除 reservation 的状态消费时，第二次准入断言失败；恢复原子消费后转绿。
- 把截图 action 提前到窗口隐藏之前时，时序测试失败；恢复隐藏后调度后转绿。
- 吞掉打开回调时，独立回调测试失败；恢复传递后转绿。所有变异均用补丁恢复，并重新运行完整套件。
- 最终一次受限环境内运行在 SwiftPM manifest 的嵌套 `sandbox-exec` 阶段失败，尚未编译产品代码；按同一命令在获准的系统沙箱外重跑后 264 tests / 67 suites 通过，因此没有把基础设施失败写成产品红灯，也没有拿旧结果代替重跑。

## Review result

测试能打红恢复映射、并发准入、窗口顺序和回调分离四类核心错误。安装版真实双击与缺图视觉状态没有被单元测试冒充，已作为合并安装后的明确验收项保留。

---

# VLMSnapper v1 — Inline Provider settings test review (2026-09-04)

## 维度 1：覆盖是否完整

| 边界/回归点 | Test / evidence | 结论 |
| --- | --- | --- |
| Key 直接替换且失败不回滚 | `credentialWriteFailureDoesNotRestorePreviousConfiguration`、`listFailureDoesNotRestorePreviousProviderConfiguration` | 旧凭据、配置和当前选择不会在新 Key 失败后复活 |
| 旧模型保留与当前 Provider 恢复 | `replacementPreservesAvailableModelAndCurrentProvider` | 仅在新列表仍包含旧模型且新配置可用时恢复 |
| 当前 Provider 移除 | coordinator removal tests | 清除配置和全局当前选择，不自动回退 |
| 活动请求只读 | `readOnlyStateBlocksConfigurationMutations` 及 freeze tests | 卡片可浏览，验证、刷新和模型 mutation 均不执行 |
| Key 行内状态 | `inlineCredentialStates`、`validationAndFailureOverrideStatus` | 验证可见性、Return 可用性、验证中和失败状态分离 |
| 卡片状态 | `providerCardDistinguishesPendingModel` | 待选模型、可用与未配置不会混淆 |
| 首次引导返回 | `onboardingReturnIsConsumedExactlyOnce`、窗口关闭回调测试 | 模型完成或提前关闭只消费一次来源 |
| 生产界面渲染 | `confirmedSurfacesRender` | 管理中心 Provider 页面在双语言、明暗外观和最小尺寸下渲染；旧独立面板不再列为生产界面 |
| 全量回归 | `swift test` | 273 tests / 68 suites 通过；warnings-as-errors 构建通过 |

真实签名 App 的 Keychain 读写、管理中心与首次引导的窗口层级切换，以及鼠标对折叠卡片和确认菜单的投递仍属于安装版人工验收；SwiftPM 测试没有把内存存储或直接调用闭包冒充这些系统集成结果。

## 维度 2：case 设计是否合理

- coordinator 测试通过公开 API 和可控的凭据/metadata/model-list 边界构造成功与失败，不读取 actor 私有字段。
- UI 状态测试输入明确的配置与会话快照，只断言用户可观察的状态映射和动作资格；没有复制 SwiftUI 条件常量来形成同义反复。
- 返回来源使用独立值类型验证 exactly-once，再由真实 `NSWindow.close()` 验证控制器回调；应用代理的窗口编排保留安装版验收，不用伪窗口扩大结论。
- 渲染测试实际生成管理中心 Provider 页面，不再用已退出生产路由的 `ProviderSetupView` 提供虚假的实现证据。

## 维度 3：有没有假通过

- 只读浏览测试在旧 guard 下准确红于仍选中 OpenAI；移除查看层 guard 后只读 mutation 断言继续为绿。
- 已配置 Key 的 Return 资格断言在旧 `canValidate` 下准确红；要求验证操作可见后转绿。
- 待选模型卡片测试在最初骨架统一返回未配置时准确红；拆分卡片状态后转绿。
- 两次过滤器运行匹配 0 tests：一次使用 suite 展示名，一次使用不存在的 `readOnlyStateStillAllowsProviderNavigation`。两次均作废并未计入通过；随后使用实际函数名精确重跑，各执行 1 test 并通过。
- 最终完整命令退出码为 0，日志明确报告 273 tests / 68 suites；严格 warnings-as-errors 构建退出码为 0。没有 skip、0-test 结果、陈旧构建或截图目测替代最终门禁。

## Review result

新增测试能分别打红凭据替换、状态映射、只读浏览和首次引导返回的主要错误。剩余系统集成缺口已明确限定为合并安装后的人工验收，不影响本地自动化门禁的真实性。

---

# VLMSnapper v1 — Retired Provider component removal test review (2026-09-04)

## 维度 1：覆盖是否完整

- 删除的两项测试只驱动已删除的 `ProviderSetupInputState`：粘贴后启用验证、切换 Provider 清空旧 draft。现行 `ProviderInlineCredentialPresentation`、卡片状态、初始展开与引导返回测试全部保留。
- Ticket 07 从旧页面截图清单中移除 Provider，预期文件数从 10 降至 8；Ticket 13 继续渲染双语言、明暗外观及最小尺寸的现行管理中心 Provider 页面。
- sheet 终止回归从三个样本改为两个，继续覆盖仍以 sheet 呈现的权限恢复和存储隐私；Provider 设置现在是普通管理中心窗口，不属于该测试的枚举集合。
- 完整回归实际执行 271 tests / 68 suites 并通过；warnings-as-errors 构建通过。

## 维度 2：case 设计是否合理

- 保留的 Provider tests 均面向现行 presentation 与 coordinator/session 公开 seam，不引用被删除类型或通过旧页面 fixture 间接证明新页面。
- Ticket 07 在每次运行前删除并重建自己的临时输出目录，文件数量现在只反映本次渲染，不受历史 PNG 影响。
- 源码全量引用检索与编译分别覆盖字符串/符号残留和类型链接残留，两者用途不同，没有用单一 grep 冒充构建验证。

## 维度 3：有没有假通过

- 第一次删除后 Ticket 07 准确失败于 `renderedFiles.count == 8`，实际为 10。检查输出目录确认多出的正是上轮遗留 Provider PNG；修复测试隔离后限定名测试执行 1 test 并通过。
- 一次用人类可读测试标题过滤得到 0 tests，该结果已作废；随后使用 `Ticket07RenderingTests.confirmedSurfacesRender`，实际执行 1 test。
- 完整测试日志明确报告 271 tests / 68 suites、退出码 0；没有把 0-test 过滤、旧截图产物或单纯编译成功计作行为通过。

## Review result

测试删除范围与组件删除范围一致，现行 Provider 行为覆盖没有被削弱。渲染测试的历史产物污染已转化为可重复的目录隔离防线。

---

# VLMSnapper v1 — Ticket 19 inline Provider geometry test review (2026-09-05)

## 维度 1：覆盖是否完整

- Ticket 19 的配置、验证后只揭示模型、当前 Provider 保持、移除、首次引导定向进入与 exactly-once 返回均由现有 presentation、coordinator、session 和 onboarding 用例覆盖。
- 新增四条 literal assertions 覆盖原型确认的内容宽度、卡片头高度、Provider 标记和凭据字段高度；Ticket 13 生产渲染同时覆盖正常/最小窗口、中英文和明暗外观，并验证双列/纵向切换结果。
- 旧独立页面的负向要求由跨生产源码、harness、测试、本地化、原型和 manifest 的全量固定字符串检索承兑；Swift 全编译补充类型链接层验证。
- 真实签名安装后的输入焦点、Command-V 和 Keychain 行为不属于本票，分别由 Tickets 20–21 承兑；本轮没有用渲染或纯 SwiftUI 测试冒充这些宿主行为。

## 维度 2：case 设计是否合理

- 四条新增断言使用原型 literal 作为独立 oracle，不 import 或重算生产值；每条明确对应一个设计约束。
- 断言落在既有公开 `ManagementCenterMetrics` seam，不 cast 私有成员、不 mock 项目模块、不旁路生产布局常量。
- 渲染用例调用生产 `ManagementCenterView`，并实际生成 44 张图；检查的四张 Provider 图来自本轮清空后的输出目录，不是 HTML fixture 或陈旧截图。
- 现有行为测试均从公开 coordinator/session/presentation 路径驱动目标状态；没有以空集合循环、条件提前 return 或零测试过滤计入通过。

## 维度 3：有没有假通过

- 最初新增常量前的红是 missing-member 编译失败，只证明接线尚不存在，不能证明几何断言会捕获错误值；该红没有被作为最终有效性证据。
- 随后把四个正式值分别改为 849、53、28、31，并先用源码检索确认变异到达 `ManagementCenterMetrics`。限定测试在四条对应断言行分别报告实际值与期望值不等，证明每条都能捕获 1 pt 漂移。
- 变异仅通过反向 patch 恢复四个值；恢复后同一限定测试执行 1 test / 1 suite 并通过。最终严格构建和完整测试另行执行，日志报告 271 tests / 68 suites、退出码 0。
- 原型脚本门禁先枚举 9 个非 vendor HTML，再实际解析其中 9 个 inline scripts；本地化检查先确认两份字典各有 246 个键，再比较排序后的完整键集合，避免空集合假绿。

## Review result

本轮新增的四条几何断言经过针对目标失效形态的变异验证，能真实阻止确认值漂移。行为、渲染、语法、本地化和清理证明各自检查不同风险，没有用单一绿灯替代其他验收面。

## 2026-09-05 — API Key validation regression test review

### 维度 1：覆盖

本轮新增一个参数化生产窗口场景，枚举初始空/非空 × 键入/粘贴四组，逐组检查当前内容提交、清空后阻止提交、再次输入后 Return、窗口刷新和外部加载/清除。覆盖本次状态传播回归。真实账号、物理键盘 Command-V、后续 Ticket 20 的原生字段行为不在本测试覆盖内，文件头和复盘明确边界。

### 维度 2：设计

使用公开 ManagementCenterWindowController、真实 AppKit field editor 和窗口鼠标事件，没有调用私有实现或直接调用 onValidate 凑成功。回调只作为网络/存储前的公开提交边界，断言独立虚拟文本字面量。命中坐标以已确认最小窗口布局为基准，有预填正对照并已核对实际截图；以后布局变化需同步该 UI 测试，不将它解释为任意布局测试。

### 维度 3：假通过

最初编译环境和无障碍对象定位失败只视为测试工具未就绪，不计红绿证据。真正的红是底层收到 test-key 后，真实点击却没有提交；预填正对照能提交。仅改 @Binding 后的清空测试又检出空文本误提交。最终将 hasAPIKey 暂改回配置 Binding，重编译后空值起始和清空反向断言按预测失败；只撤回这一变异后，严格构建和完整 272 tests / 69 suites 通过，退出码 0。原型静态渲染不再作为输入行为证据。

## Ticket 20 — 2026-09-06 whole-ticket test review

### 维度 1：覆盖

Inventory: ProviderAPIKeyInputTests (1 declaration); ProviderAPIKeyFieldTests (3, including parameterized paste and secure/plain routes); ProviderCredentialEditorTests (8 declarations with lifecycle parameters); ProviderCredentialInteractionTests (5 with empty/prefilled × input-source cases); new ProviderSetupSessionTests cases (3, one success/failure parameter); coordinator unsafe-input regression; local-hint presentation case; changed ApplicationMenu fallback case; existing rendering fixture rewiring; executable native menu runner.

The checklist maps US-07/US-11 and FM-32–40/42 to these cases. UTF-8 boundary uses 1024 four-byte symbols (4096 bytes) and one extra byte, not a character-count approximation. Clipboard cases include CRLF, separate CR/LF, repeated newline, spaces, tab, decomposed Unicode and embedded newline. State cases cover A/B/A, closed reads, pending/terminal close/reopen, exact reversion and immutable original-provider completion.

User-reported live failures (visible entered text with disabled Validate, prefilled-versus-empty difference and selection replacement) supplied the native fixture shapes; dummy secret values preserve those shapes. No external account response parsing was changed, and synthetic model listing is only a controlled delay/error boundary, not real Provider compatibility evidence.

Gap: tests use actual AppKit windows/editors but programmatic events/actions. Physical keyboard/mouse, installed signed application, real Keychain permission and network acceptance remain distinct. The runner's ten passes prove repeatability at the described native boundary, not those missing layers. File-header comments state the supplementary acceptance conditions.

### 维度 2：case 设计

- Found an over-isolated new session seam: tests substituted our own configuration coordinator. Replaced those three new tests with the real ProviderConfigurationCoordinator; only model listing and external persistence use controlled substitutes. Existing unrelated session probes are not represented as integration evidence for this ticket.
- Editor tests use public transitions and immutable tickets, not private dictionaries or casts. Native tests inspect real public AppKit fields and assert submitted payloads, selection, visible clear/Validate behavior and loaded text.
- Submission counts are externally visible dispatch obligations (exactly once), not assertions on private implementation calls. The ordinary NSTextView fallback spy checks responder forwarding only; it does not certify full ordinary-editor rendering.
- Fixed-coordinate native hits are limited to the confirmed minimum layout and have positive controls with the same hit target. Broader layout acceptance is not claimed. Run-loop settling is a test synchronization aid, not a production sleep-based fix.
- Scope contains no new dynamic/static private-member access or production mocks. The new test helper controls the external model completion through continuations so ordering is explicit.

### 维度 3：假通过

- Deliberate red causes are indexed in the tasklist. Compiler/setup failures and the earlier popup run with exit 0 but no completed test report were rejected, not counted as red/green.
- Strengthened real-coordinator test mutation: remove same-Provider admission suppression, rebuild current source, run pendingValidationSuppressesDuplicates. Both cases fail at ProviderSetupSessionTests.swift:44 (lost validating phase). Compilation log confirms the changed session source was rebuilt. Restore only the guard, then strict/full/native gates pass.
- Native Paste no-op mutation previously reached the insertion assertion and failed; missing marker (/usr/bin/true) and timeout negative controls separately fail the runner. Its normal invocation always rebuilds source. Ten loops of a stale prebuilt binary are not the default gate.
- The new shorter-value selection assertion was green immediately because AppKit already handles it; no fake product fix was made to manufacture a red.
- No conditional success-return silently skips the added native cases. Required fields, editor, events and indices use #require; async session tasks are awaited; external callbacks have explicit payload-count assertions.
- Final verified gate: 293 tests / 72 suites, 15.460 seconds; strict build and native 10/10 (0.893–1.477 seconds), plus identical 248-key localization sets and git diff --check. These are scoped evidence, not full feature or signed-app acceptance.

## Ticket 21 — 2026-09-07

### 1. Coverage

All owned requirement rows are enumerated in the Ticket 21 checklist inventory, with physical/browsing gaps retained. Added/changed case inventory:

| Cases | Boundary and failure sensitivity |
|---|---|
| genericCredentialWriteFailureIsSecureStorage; metadataPublicationFailureIsSecureStorage; credentialWriteFailureDoesNotRestorePreviousConfiguration | Injected credential/metadata failures through the real coordinator/session; category and not-usable outcome. Wrong network classification produced a genuine red. |
| retirementWriteFailurePreservesOriginalConfiguration; failedDeletionCannotRecoverRetiredCredential | Public configuration/selection first, then storage fault. No-auth boundary rejects any forbidden external call. Old-key mutation reached both parameter cases and failed; restored run passed. |
| canceledValidationDoesNotPersistCandidate; cancellationBeforeReplacementAdmission | Suspended external listing/read, task cancellation, release, awaited result, public credential/state inspection. Late-read request was genuinely reproduced before its guard. |
| postKeychainPublicationFailureRecovers; reconciliationCommitsMetadataForDurableNewCredential | Durable new key with failed publication or legacy journal, then a different fresh model list. Literal model IDs/time prevent cached-list tautology. |
| reconciliationClearsConfigurationWithoutCredential; reconciliationRecoversStoredKeyWithoutConfiguration | Public save followed by external item/cache loss; public reconciliation proves missing cleanup versus orphan recovery. |
| configuringAnotherProviderDoesNotReplaceRememberedCurrentProvider | Both providers configured and selected through public operations; replaced the formerly fabricated current pointer. |
| lateReadFailureIsIgnored; closingEditorInvalidatesCredentialRead; recoveryPublishesBusyState; keychainReadFailureIsNotMissingCredential | Close/A-B-A and uncancellable read, positive read-error control, recovery pending/terminal and successful explicit reopen. Generic and Apple error variants included. |
| reopenedLoadWaitsForCanceledRead; closingCancelsLoad; terminationDiscardsCandidates | Public editor lifetime. Uncancellable continuation replaces misleading cancellation-aware stream. Detached recovery is the positive counterexample to load cancellation. Both pending and failed candidates tested on termination. |
| storageReadOnlyActions; unchangedCredentialAfterFailure | Recovery/read-error have no unusable action, editable failed write can retry, unchanged loaded key cannot resubmit. Actual red for eligibility, positive failed-write control retained. |
| confirmedSurfacesRender; clearedFailedCandidateRenders | Production render creation; manual inspection of recovery/read-error variants and before/after cleared-write-error view. PNG byte count is not an assertion of visibility or native interaction. |

Existing real-coordinator continuity tests remain in the full suite. Installed process death/physical input and blocked prototype interaction are explicitly not simulated. Their supplement requires a user-driven installed-app session and an allowed browser preview. Ticket 22/23 combined flow remains unaccepted.

### 2. Case design and fixture provenance

- New coordinator/session tests use actual product modules and injected external storage/model-list boundaries. Memory stores make faults deterministic; they do not claim OS permission/entitlement realism. The separately signed random-service CRUD gate supplies actual Data Protection Keychain evidence.
- Legacy journal fixture represents the persisted pre-change schema; fresh-list expectations are independent literals. Model API fixtures retain object/data/id and Gemini next-page shapes in the existing adapter suite; this turn did not independently establish their capture provenance or run a live account catalog request. Recovery tests consume the existing typed complete-list contract, not a new HTTP parser. Do not call their fixture success live Provider validation.
- The three existing setup boundary doubles gained the protocol method only to preserve their original isolated tests; they are not used to accept new reconciliation behavior. Inspection of the test storage's durable metadata is a deliberate persistence-boundary assertion where the public readiness view masks an unreadable provider; public reopen/ready assertions additionally prove recovery.
- No private casts or direct writes to product private state were added. External call counts are justified only for the user-visible no-resubmission/no-retired-authentication contract. Callback tests have positive completion/payload assertions; rendering uses required hosts and artifacts.

### 3. False-green review

- Genuine reds and exact-restoration logs are indexed in the tasklist: delayed reopen, stale read error, storage classification, recovery action hiding, cancellation-before-admission and isolated retired-authentication mutation. Compilation/sandbox setup failures are excluded from red evidence.
- New unchanged-key case fails specifically at the overly permissive canValidate result. The production wiring fault was observed in the pre-fix render; the model test alone would not catch a future view-side reintroduction. This manual visual check remains required and is not disguised as automated coverage.
- Checked the new case inventory for empty-loop assertions, unawaited tasks, same-object expected values and silent environment returns. New outcomes use literals/categories; resumed tasks are awaited and positive controls show the targeted paths execute. Native smoke requires current-source rebuild, process success and one exact completion marker; 10 successes measure repeatability, not physical input or account access.
- Final v4: 312 tests / 72 suites, 15.447 seconds; strict build; native 10/10 (0.858–1.325 seconds); signed Universal/profile/Keychain CRUD; identical 251-key dictionaries; diff check. Browser validation remains unavailable, not green.

## Ticket 22 — 2026-09-07

### 1. Coverage inventory

| New test | Behavior / failure boundary |
|---|---|
| exclusiveActivityReleaseRequiresTheOwnerToken | Foreign/stale release cannot unlock a successor; correct release permits admission. |
| workflowOwnerBlocksAllConfigurationChanges | Capture/model owners block all five mutation families; saved key/state unchanged. |
| providerValidationAndCaptureAreMutuallyExclusive | Capture rejects validation before writes; only owner transitions atomically. |
| reconciliationWaitsForModelRequestToFinish | Orphan credential waits, then recovers after model owner release. |
| reconciliationWaitsForCaptureToFinish | Capture wait succeeds after release or cancels without publishing. |
| canceledRecoveryDoesNotWaitForOwner | Cancellation finishes while capture still holds; bounded rescue prevents hanging silently. |
| captureRoutesActiveProviderJob | Shortcut/menu target active Provider with no capture effect; terminal positive control executes. |
| blockedTryAgainPreservesHistory | Real workspace/runner/SQLite; no blocked request/snapshot/history mutation; terminal rerun replaces Result 1 with Result 2 under same ID. |
| captureHandoffFailureReleasesOwner | Failed replacement retains capture; transition stays exclusive; operation failure releases; stale handoff has no effect. |
| captureActivityLocksSession | Real actor activity reaches session; no blocked validation/list/model effects, then succeeds. |
| crossProviderSubmissionIsExclusive | Externally suspended first list, success/failure terminals; other draft editable but duplicate submissions produce no request. |
| activeCredentialJobControlsEditingAndValidationSeparately | Valid/empty/newline drafts; only valid changed draft re-enables. |
| otherProviderJobBlocksNativeSubmission | AppKit field editing; blocked click/Return do not submit; terminal click submits preserved draft once. |
| activeJobFocusNavigatesExistingWindow | Existing History window shows target's disabled field within content bounds after focus request. |

Existing request-freeze tests now use owner tokens. Unsaved-workspace preparation and render/localization suites remain regression gates. Native input is programmatic AppKit, not physical shortcut delivery. Signed-app capture/foregrounding/account acceptance is excluded in test headers and remains combined acceptance. No old standalone Provider-sheet harness was restored.

### 2. Case and fixture design

- Exclusivity uses real coordinator/session/editor. Only external credential/metadata storage and model-list delay are controlled. Rerun uses real temporary SQLite, screenshot storage, runner and workspace; reads via public history, not SQL/private state. Counts observe external Provider/native effects because zero/one request is the requirement, not internal call order.
- Expected snapshots/records are immutable values with independent Result 1/Result 2, count and ID assertions, not mutable aliases. The PNG header fixture is opaque persistence input, not image-decoding evidence. No new external response parser is introduced; normalized sourceDelta/metadata/completed is the established boundary, whose protocol-shape coverage remains in recorded adapter fixtures.
- Unsaved-result foregrounding is native wiring without injectable window construction in this test target. The session outcome test does not prove OS focus. No private cast or duplicate test router hides that gap.

### 3. False-green audit

- Genuine owner red failed foreign/stale release; recovery red rejected instead of waiting; integration red failed observed activity/routing. Toolchain/build failures are excluded.
- Explicit restoration mutation added only && false to production canValidate (stricter never-enabled control). Rebuilt source reached ProviderSettingsPresentation.swift. Presentation test failed at line 21 for valid terminal draft; native test failed at line 358 with zero instead of one submission. Log /private/tmp/ticket22-ui-restoration-mutation.log, exit 1. Removed only that token and rebuilt: /private/tmp/ticket22-review-green.log, three tests passed, including unsaved preparation. This proves terminal restoration sensitivity, not every routing mutation.
- Initial unguarded capture stub was rejected before application and not retried elsewhere. Capture/rerun gate-removal mutation is not claimed. Blocked/admitted controls establish effect observables; owner/recovery reds guard admission independently. This limitation is recorded instead of manufacturing a bypass or red-first claim.
- Enumerated new cases for zero-assertion loops, silent skips, missing awaits, stale paths and same-algorithm expected values: none introduced. Parameters are explicit; suspended tasks resume and are awaited. Recovery's 50 ms observation alone is not scheduling proof; rejection red, terminal effect and cancellation-owner assertion are separate checks. Geometry checks target visibility, not pixel identity or physical foregrounding.

## 2026-09-07 — Ticket 23 checklist gate increment only

This review covers the six new CLI tests, not the still-missing combined application cases or the final feature-wide review.

### 1. Coverage

| Case | Actual boundary driven | Result / limitation |
|---|---|---|
| missing_requirement_fails_even_with_ownership_heading | Remove FM-46 from real document | Nonzero, names FM-46 |
| duplicate_requirement_is_not_hidden_by_unique_count | Insert a second US-01 inside ownership | Nonzero duplicate diagnostic |
| unknown_requirement_cannot_expand_the_contract_silently | Insert FM-47 inside ownership | Nonzero unexpected diagnostic |
| complete_repository_checklist_passes_with_historical_evidence | Entire current checklist with other historical tables | Zero, explicit 58-row report |
| blank_or_malformed_ownership_rows_fail | Blank owner/criterion, missing/extra column | All four variants fail, name US-01 |
| missing_or_duplicate_section_is_not_accepted | Rename ownership heading / append another heading | Both fail at section validation |

The fixture shape is the actual repository document, not a toy table generated with the implementation's algorithm. Source/spec semantic correspondence, named criterion truth, application interactions and full release acceptance remain outside this structural gate.

### 2. Case design

All tests use the public CLI in subprocesses with isolated files; none imports the parser or mocks an internal component. Expectations use independent requirement identifiers and exit behavior. No original checklist mutation. The success control prevents an always-failing gate from passing the negative suite. Named negative cases inspect the relevant error, not merely any process failure.

### 3. False-green checks

Observed reds are logged in the Ticket 23 tasklist. During the duplicate increment, the test initially passed for the wrong reason: unrelated historical rows also triggered duplicates. This signal was rejected, the parser scope was corrected, and the full-document positive control was added. The corrected unknown-ID red fails precisely on returncode 0; malformed-cell reds likewise prove false acceptance before the check. Section cases passed initially because section validation already existed; no red-first claim is made for those supplementary regressions. Six cases now pass through current source, without build caching, async callbacks, silent skips or zero-iteration input sets. These results are not native interaction evidence.

## 2026-09-07 — Application Model injection increment only

### 1. Coverage

Complete new-case inventory:

| Test | Driven boundary and observable failure |
|---|---|
| injectedUpdateEventsReachTheApplicationPresentation | Injected driver emits availability through captured production handler; both Model and settings must update; automatic download remains disabled. |
| failedValidationKeepsCandidateAndAllowsManualRetry | Real HTTP parser/coordinator sees status 401 and 500; candidate remains editable, no credential stored, manual retry sends a second request and reaches pending-model. |
| permissionAndRetentionUseOnlyTheIsolatedPreferences | Preflight false plus requested-history true produces unavailable; actual retention callback writes the isolated suite and a fresh Model restores 60 days. |
| terminationPreparationDoesNotUnregisterBeforeExitIsCommitted | Real start registers; preparation retains; final stop unregisters once and repeated stop leaves zero registrations. |
| validatesSelectsAndRestoresProviderThroughApplicationCallbacks | Real editor submission and Model callbacks discover/select/persist/notify; duplicate refused; reconstructed Model recovers the selected model and credential without another HTTP request. |

Five functions, six parameterized cases. Test header excludes native input/window routing. Delegate onboarding return, capture/rerun exclusion, suspended-request teardown and signed-app physical focus remain pending Ticket 23 work, not coverage supplied by these cases.

### 2. Case and fixture design

No mocked internal coordinator or alternate router. HTTP, credentials and system adapters are test replacements; parser/files/SQLite are production. HTTP fixture shape comes from the official DeepSeek list-models response example (https://api-docs.deepseek.com/api/list-models/), with synthetic identifiers; this is a documented wire-shape sample, not a successful live-account request. All other new fixtures implement external adapter behavior rather than inventing external file formats. Request/registration counts observe external effects required by duplicate/lifecycle semantics, not internal ordering. Defaults readback is an additional adapter check; reconstruction through the Model supplies the persistent-behavior assertion.

### 3. False-green checks

Audited every listed case for silent skips, unawaited assertions, empty loops, stale production paths and expectations recomputed with implementation algorithms. None is used to claim native acceptance. Update payload comparisons check propagation into separately owned presentation state, not mutation of an aliased expected object. A five-second bounded poll awaits the same terminal fields subsequently asserted; an earlier editor-only wait read presentation too soon and was rejected as a false red.

The completion test's deliberate production-callback removal reached rebuilt code (independent runtime mutation marker), then failed its completion deadline; only that edit was restored and full tests passed. The corrected lifecycle test failed specifically at premature unregister, then passed after final-stop separation. Initial toolchain/concurrency compilation failures and the superseded preparation-unregister expectation are not product-bug evidence. Supplementary preference, HTTP and updater cases are regression checks, not claimed independently mutation-validated for every assertion. Final full suite: 331 tests/73 suites, exit 0; strict build also passed. No all-native or all-Ticket-23 completion claim follows.

## 2026-09-07 — Delegate/native increment only

### 1. Coverage

Complete additional-case inventory (earlier five Model functions unchanged in purpose):

| Case | Actual path / remaining boundary |
|---|---|
| nativeOnboardingValidatesSelectsAndReturns | Real delegate startup, rendered Provider button via AppKit mouse events, secure editor insert/Return, one HTTP request, unselected-model stay, close/reopen through delegate, native popup menu action, both window visibility states, fresh Model restore. Does not prove Paste, Validate mouse click, in-flight close, late completion, ordinary settings non-return or OS foregrounding. |
| applicationStartupOwnsRealWindowsAndReleasesPrimaryLock | Two real temporary-lock contenders, no secondary Model factory/extra registration, final release and new primary. Does not invoke an actual process exit or failure launch. |
| credentialValidationAndFreezingExcludeEachOtherThroughApplicationWiring | External HTTP paused, real registered shortcut routes to Provider without capture; resumed configuration enables capture; paused freezer disables submission and preserves candidate/no new HTTP/empty history; permission-denied terminal enables resubmission. Does not prove selection/model/rerun/recovery waiting or preservation of nonempty history. |

The wire fixture is the previously documented official DeepSeek model-list shape. New messaging, permission and suspended-capture fixtures are external effects, not business-module mocks or invented wire formats. All three cases retain actual application state ownership. Full Ticket 23 coverage remains incomplete and its acceptance boxes remain open.

### 2. Design

No private setters/casts or copied delegate callbacks. Native NSView downcasts select public AppKit controls; the popup's actual menu action drives its binding. The onboarding click point was verified against the newly rendered fixture at `/private/tmp/ticket23-onboarding-native.png`, and English is explicitly selected in the isolated suite. This coordinate is layout-coupled, so future layout changes must reverify the hit point; missing routing fails the bounded wait rather than passing on a click alone. This exception avoids falsely claiming unavailable in-process accessibility children were found.

AppKit pumping has a 10 ms event-processing bound and runs only while checking real readiness, under an outer five-second deadline; production receives no sleep. Suspension completion is explicit. Process-level main menu/localization state requires running the application suite separately from other suites, now encoded in CI's complementary commands. Model fixture cleanup releases suspended adapters even after an assertion/throw; capture release remains latched for late arrival.

### 3. False-green audit

New native failure-sensitivity mutation omitted only the delegate's final `showOnboarding()`. Rebuilt runtime printed its distinct marker, and the final return wait failed with deadline/exit 1; the preceding close-return path had already passed. Restoration touched only that line. Initial zero geometry, absent accessibility children, wrong popup action ownership, nested Testing macro error and a Swift compiler assertion on `#require(handler)()` are invalid red signals, explicitly excluded. The latter was corrected by separating unwrap and invocation; no production change addressed it.

All eight test functions were checked for unconditional expectations, await completion, no silent skips, and active production paths. The complementary CI filters preserve all suites. Exclusion uses observable positive controls and explicit suspended work, not fixed waiting to infer zero effects; it is supplementary regression coverage, not claimed independently gate-removal-mutation-proved. Empty history is only asserted as no creation, never as preservation of an existing result. The two new startup/native cases are not substitutes for signed/installed acceptance or completion of Ticket 23.
## 2026-09-08 — Native menu/closed-window increment test review

- 【维度 1：覆盖】Enumerated two additions: (1) actual key-window ownership, Edit/Paste action, CRLF-normalized native input/caret, mouse Validate, one exact authenticated external request; (2) validation starts, Settings closes before HTTP release, onboarding first lacks then renders pending-model status while Settings remains hidden, reopening restores editable submitted text without a duplicate request. Existing close/reopen-before-response remains complementary. Failure/cancellation, physical Cmd+V/foregrounding, bilingual visual parity and full-ticket acceptance remain open; the header says so. Model-list fixture retains the previously verified official wire shape, only identifiers/key text are synthetic.
- 【维度 2：设计】Production delegate, editor, sessions, coordinator, menus and views execute unchanged. The isolated pasteboard is an external input seam, not an internal mock. HTTP suspension establishes close-before-response causally. Render OCR reads only the actual fixture view, not an invented status label. `Choose a model` proves the model-list outcome, not all downstream editor cleanup; the reopened editable field is separately awaited/asserted. Existing external request counts express no duplicates. Test-runner activation is explicitly not physical-focus acceptance. Shared helpers throw neutral errors, and XCTest failures are explicitly recorded rather than relying on Swift Testing assertions outside a Swift Testing test.
- 【维度 3：假通过】Paste mutation rebuilt/reached `MUTATION-ticket23-real-paste-disconnected`, then failed waiting for the exact field text (`ticket23-paste-mutation-neutral.log`, exit 1). Closed-editor completion mutation rebuilt/reached `MUTATION-ticket23-closed-completion-dropped`, then failed waiting for editability on reopen (`ticket23-closed-mutation-caught.log`, exit 1). Earlier InvalidTransition/crash/incomplete-footer runs are invalid evidence, not target failures. Both mutations restored with exact patches. CI's positive report checks require one XCTest case, so Swift Testing's separate zero-tests footer cannot count as success. The all-App group initially failed at capture toolbar delivery; logging made that test pass, revealing timing sensitivity rather than proving a production fix. Event pumping between test drag events is verified separately; no fixed production delay or relaxed toolbar assertion was introduced.

# Ticket 23 scoped test review — 2026-09-08 capture/rerun/recovery composition

## Subsequent scoped review: pending-validation close/reopen

- 【维度 1：覆盖】One added case, `nativeValidateSurvivesCloseAndReopenWhileResponseIsPending`: real delegate onboarding route; native editor value/caret; mouse Validate; exact one authenticated model-list request; close and return; reopen before HTTP release with original candidate read-only and no duplicate request; response completion restores editable value/model list; a fresh Model restores saved key and pending-model readiness. Main-menu Paste, completion while remaining closed, failure/retry variants, physical focus and visual review remain explicit gaps. Existing fixture model-list JSON retains the previously verified official response shape; no new wire schema invented.
- 【维度 2：设计】All business components and native controls remain production instances. Suspended HTTP gives a deterministic causal boundary, not a sleep-based race. Native field and popup are public AppKit controls; no private object graph access. Validate geometry is relative to the real field, with its effect proved by the actual request. The case uses direct text insertion, not clipboard input, and its name/header do not claim otherwise. Cleanup releases external pending operations in both successful and throwing paths. External request counts enforce the no-duplicate requirement, not internal call order.
- 【维度 3：假通过】An early experiment reopened after observing credential storage, before the application completion callback; a closed-editor mutation never printed its marker, proving that experiment did not establish the claimed ordering. It is not red-capability evidence. A later accessibility wait failed even without mutation and was also discarded. The final case's mutation removes submitted candidates only on actual `ProviderCredentialEditor.close()`: rebuilt runtime printed `MUTATION-ticket23-close-drops-submitted-candidate`, then failed exactly at the reopened candidate/read-only wait (line 53, `/private/tmp/ticket23-close-candidate-mutation.log`, exit 1). Mutation restored precisely. A separate global event-loop experiment exited 0 with no completed test summary; never counted as a pass. Final acceptance requires both successful command exit and an explicit Swift Testing completion summary. No silent skip or deprecated accessibility probe remains.

- 【维度 1：覆盖】Enumerated current increment: native selection rejects edits; active image request rejects edits; successful result creates history; credential validation blocks result rerun; terminal validation permits rerun; successful rerun updates the same history identity/text; a second Provider's credential-without-metadata recovery waits for the active model; recovery then blocks freeze/rerun; recovery terminates without stealing the current Provider. Existing freezing case remains complementary. Not covered here: all cancellation/failure permutations, native menu Paste/Validate-button/late-completion cases, real focus/shortcut delivery, signed identity or full bilingual/light-dark rendering. Header and spec retain these boundaries.
- 【维度 2：设计】Uses production application model/real workflow, editor, sessions, parser, cropper, PNG store and SQLite. Only external credential/HTTP/SCK/system adapters are replaced. Request counts are external network/capture effects whose cardinality is part of the contract, not counts of internal calls. History is read through Model's presented records with value snapshots and independent literals `First result`/`Replacement result`; equality against the preserved snapshot additionally checks IDs/status/metrics. Setup's orphan credential models an external persisted-key/publication-interruption condition, then recovery is entered through the production card binding. No private-state casting or duplicate routing.
- 【维度 3：假通过】The new case already passed against existing production behavior; no production fix was manufactured. Initial compiler/lookup/coordinate failures do not establish red capability. Deliberately disconnected rerun was rebuilt, reached its unique marker and failed the second-request wait. Deliberately omitted waiter wakeup was rebuilt, reached its marker with a real waiter and failed the recovery-request wait. Both exact mutations restored; full complementary suites then passed. Native rerun is driven at a measured point and validated by an actual second request and replacement text, not just button existence. History replacement waits for the asserted text, not merely a different record. Immediate blocked-effect checks are repeated after credential terminal completion. These tests do not prove OS-generated physical event delivery or an accessibility-enabled property.

Verification: `/private/tmp/ticket23-composition-strict.log`; `/private/tmp/ticket23-composition-nonapp.log` (326); `/private/tmp/ticket23-composition-app.log` (9). All chained gates exited 0. Six Python CLI cases and the 58-row ownership gate passed. Full Ticket 23 closeout is still incomplete.

## 2026-09-08 — Refresh A scoped test review

### 1. Coverage inventory

| Case | Observed contract |
|---|---|
| refreshPreservesConfiguredContent | Ready phase, cached list/selection and lock during suspended refresh; duplicate refresh/replacement does not send extra HTTP work |
| concurrentRefreshKeepsBusyOwner | 32 concurrent public activations converge to one external refresh; busy owner remains until that response is released |
| refreshSurvivesCardSwitchAndNetworkFailure | Other-card editable/read-only distinction; return during pending work; ready terminal on success/503; credential preserved; no auto retry; explicit retry clears feedback |
| refreshedModelRemoval | Finish while another card is open; returning sees the new complete list and cleared selection; explicit choice restores readiness |
| modelRefreshPublishesProgressAndFailureWithoutChangingCredentialState | Production application callback and observer wiring publish busy, 503 and manual retry through the real HTTP decoder |
| modelRefreshSurfacesRender | 24 production-view renders: zh-Hans/en, light/dark, 920/1200 widths, idle/busy/failed |

Existing coordinator refresh cache/error tests, session locks and all application test partitions were rerun. Physical installed-app Refresh clicking and every OS window/foreground interaction remain outside this increment. Render-file creation alone is not layout acceptance: current PNGs were opened and visually compared; no pixel-perfect or automatic geometry gate is claimed.

### 2. Case design

Session tests retain the real coordinator; only external model-list and storage boundaries are controlled. External request counts check the user-visible no-duplicate/no-auto-retry contract, not internal method order. Application HTTP fixture follows the recorded DeepSeek models-list shape and retains production parsing. Render fixtures represent reachable configured states; corrected the initial inconsistent current-Provider fixture before final review. No real key/clipboard or private-state cast is used.

### 3. False-green audit

The first baseline red reports phase validating instead of ready. The second reports cached model/selection loss and stale validating completion after switching back (10 assertions across success/failure). Both are intended behavioral failures, followed by passing real-coordinator tests. Removed-model and application-observer cases extend regression coverage without claiming another baseline red. Compilation typos and the initial SDK/cache failure are setup failures, not regression evidence. Render PNG byte-count checks only establish render production; visual review is the separate evidence. Tests await the actual snapshot states and all four Swift command partitions exited 0 with nonzero completion counts.

Final evidence: strict build; 331 non-App tests; 11 App tests; each isolated native XCTest reported Executed 1 test, with 0 failures; six Python cases; 58 ownership entries; shell syntax and git diff --check. Logs are listed in provider-refresh-tasklist.md. The final concurrent-activation case passed against the existing admission path; it is additional coverage, not a new reproduced bug or evidence that every scheduling permutation was tested.

## 2026-09-08 — Visual alignment VA-01–04 test review

### 1. Coverage

| Changed verification | What it covers / limit |
|---|---|
| `ProviderVisualGeometryTests.modelControlGeometry` | Production ManagementCenter window, short model title, actual native width/height at 920×620. Not color or desktop occlusion. |
| `ProviderVisualGeometryTests.selectionAndRefresh` | Selected item, refreshed menu IDs, placeholder, read-only refusal and re-enabled callback. Fixture now pairs model metadata and selecting/ready phase with its actual selection instead of inventing a ready-with-no-selection state. Direct native action is explicitly not a physical click. |
| Application onboarding locator | OCR locates the rendered Provider Settings button before existing native event routing and downstream assertions. Replaces two stale hardcoded click positions; it does not call the routing callback directly. |
| Existing render and dimension tests | Fresh bilingual light/dark production views; static dimensions only guard configuration and are not visual proof. All 20 affected surface images opened separately. Five Refresh state images sampled, not all permutations. |
| Existing application partitions | 333 non-App tests; 11 App tests; closed-window native XCTest passes. Main-menu XCTest failed once before key-window acquisition and passed unchanged on independent rerun; no stability claim. |

Current change does not alter external payload parsing. Model fixture values are synthetic identifiers and existing HTTP fixtures retain the recorded models-list shape. Onboarding visual fixtures cover incomplete setup; readiness logic is covered separately, but every ready/restart combination has not received new manual pixel review. Physical hover, installed-app keyboard/activation and browser pixel comparison remain explicit Ticket 23 work.

### 2. Case design

No private member cast, self-module mock, internal state mutation, or source-string assertion was added. Actual public window controls and observable selection callbacks are exercised. Localization is serialized through the existing coordinator. The native geometry test measures the control, not its outer row. XCTest count assertions prevent an empty Swift Testing run from masquerading as native coverage. OCR lookup requires the exact rendered action label and then the actual window transition; missing recognition fails rather than silently skipping.

### 3. False-green audit

The intended baseline geometry red reports 24 vs 32 points and 143 vs >450 points; the earlier sandbox cache error is not counted as red. A deliberate `button.isEnabled = true` mutation was compiled and caused selection/read-only assertions to fail at lines 77/80/89 in that revision; only that mutation was reverted. The final fixture consistency edit does not relax those assertions. Color/spacing changes use the declared pure-style TDD exemption and inspected renders, not a claim that constants or PNG existence prove parity. No assertions were relaxed after the key-window timeout: its first failure and unchanged passing rerun are both retained. Overall first-attempt gateway success is not claimed.

## 2026-09-08 — Native lifetime correction test review

Final gate correction: exit 0 was insufficient for the App partition; two logs ended after a started case without a suite completion. Both were rejected, not counted as 11 passes. Temporary exit tracing plus a no-nested-RunLoop control identified the new cleanup interaction, then tracing was removed. CI's added named/nonempty completion checks reject both incomplete archived logs, while the native completion check rejects the forced-retention failure. Final alternating App/native repetitions are recorded separately from the earlier native-only rounds.

### 1. Coverage

Enumerated three native methods: main-menu Paste/Validate, closed-window response/reopen, thrown-operation cleanup. The third runs both ordinary failure and cancellation after native input/Validate while the HTTP fixture is paused. The latter cancels only its child operation Task, not the XCTest runner. Each obtains a non-null native input container before observing weak release. The third asserts release before error propagation and preserves the content identity of a window created before the fixture. Both fixture constructors and all four success/error stop branches use the shared cleanup. Existing 11 App tests cover the model-only owner as well. Remaining gaps are listed in the test header: physical input, real accounts, OS occlusion and historical key-window/toolbar timeout causes. Synthetic credentials and existing recorded response shapes remain; this change does not add a payload parser.

### 2. Case design

Actual public AppKit controls and application composition remain active. Only external adapters are replaced. Weak adapter identity is intentionally coupled to test-lifecycle ownership, not an assertion about internal business-call counts. View identity is the property under test (do not replace an unrelated window's content), so identity comparison is not an aliased mutable-value expectation. Non-null capture precedes each weak-release assertion. Empty lifetime collections are allowed for startup paths that never construct a model; all three native cases independently reach real views before cleanup. Assertions and cleanup Tasks are awaited; no conditional environment return or disabled case was introduced.

### 3. False-green audit

- The rebuilt baseline and the uninstrumented no-detachment control aborted with the target deinitializer stack. Setup/cache permission errors are not counted as regression reds.
- A temporary strong `WeakShortcutLease.value` rebuilt the actual App test module and made ordinary cleanup fail at `waitForShortcutRelease` after its five-second bound. This also exposed loss of the original error, which is now preserved in `FixtureError.cleanup`.
- Repeating that strong-retention fault on the cancelled-operation path reported both `CancellationError` and release deadline, confirming cancellation does not skip the new cleanup Task. Logs: `/private/tmp/vlmsnapper-lifetime-retention-errors.log` and `/private/tmp/vlmsnapper-lifetime-cancel-retention-fault.log`. Only the strong keyword mutation and temporary loop selection were reverted. Normal cancellation tests had passed before the fix; they alone were not evidence of bounded cleanup under delayed release.
- The earlier 10/10 round result predates the final cancellation/error-reporting changes and is not substituted for the final rerun. Named XCTest counts plus process exit are required; the coexisting Swift Testing `0 tests` footer is not native acceptance. No retry is permitted within the ten-round command.
- A successful run is finite evidence on this runtime, not proof that all future scheduling or production destruction contexts are safe.

## 2026-09-09 — Live display reconfiguration (scoped follow-up)

### 1. Coverage inventory

| Case | Boundary and evidence | Limit |
|---|---|---|
| `displayChangesCancelSelectionBeforeMouseUp` | Five inputs: sleep, disconnect, pixel-scale/resolution, rotation, position; native overlay visibility changes before mouse-up, content is detached and capture occupancy releases | Injected OS boundary; not hardware sleep/hot-plug |
| Same parameterized case: unchanged + new ID snapshot | Existing overlay stays visible and no new panel appears | One real screen; does not prove two-screen focus transfer |
| `displayChangeBetweenFreezeValidationAndObserverRegistrationIsNotLost` | Complete snapshot followed by empty snapshot cancels without input; red before re-read | Deterministic geometry read sequence, not timing stress |
| `replacementAndEscapeRetireDisplaySubscriptions` | Two captures replace/retire old native surfaces; subsequent config event delivered once; Escape and active-selection termination stop observation | Native event dispatch, not physical keyboard |
| `nativeCaptureAndRerunPreserveHistoryWhileProviderValidationIsExclusive` | Real crop → toolbar; subsequent sleep/config events do not remove completed crop; existing request/history/rerun path still passes | Existing physical-focus gap retained |
| Existing `invalidatesOnlyChangedDisplay`, `allDisplaysDisconnected`, `selectedDisplayChangeDuringCrop` | Core per-display availability, cancelled drag and suspended-crop race guards | Not a two-monitor native application acceptance |

Pending-freeze termination is only code-reviewed here. Test-file header and issue 01 explicitly retain hardware notification delivery and multi-screen survivor/focus acceptance. No silent environment skip was added.

### 2. Design and fixture review

All setup goes through the real editor submission/model selection and registered shortcut callback. Only external HTTP/credential/capture/notification/geometry boundaries are isolated; internal sessions, native controller and workflow coordinator are real. Geometry shape comes from a real NSScreen/CGDisplay snapshot; synthetic pixels and fixture keys avoid user data. No private casts/state edits were added. The display-read count assertions observe an external subscription boundary (duplicate delivery/stop), not internal collaborator call order; the primary assertions remain native visibility, content retirement, activity and absent provider/history effects. The monitor is constructed in both live and isolated dependency factories, with no partial live fallback.

An observed test failure initially read `.activity == nil` before the capture publication arrived. The test now establishes `.capture` before cancelling; it does not lengthen a deadline or relax the terminal assertion. This test synchronization mistake is not reported as a production bug.

### 3. False-green audit

- Original missing-sleep wiring failed at the intended pre-mouse-up deadline (exit 1). The registration-gap test independently failed because the lease/overlay remained active before the second-read fix.
- Config-forwarding mutation rebuilt the App module and printed `DISPLAY-CONFIG-MUTATION reached`; four geometry/disconnect cases failed directly at `!overlay.isVisible`, not only a setup deadline. Only the callback mutation was undone and the full 14-test App suite then completed successfully.
- Enumerated assertions: no empty-loop substitute for visibility, no expected geometry recomputed from implementation, no API-key/network use, no un-awaited callback assertion, no silent skip. Negative observer/read assertions include a prior delivered event as a positive control. Core per-display tests remain supplemental, not a substitute for missing physical composition evidence.
- Final strict build, 333 non-App tests and 14 App tests pass with explicit completion. Native XCTest reports 3 tests / 1 failure at key-window acquisition before Paste, exit 1. The Swift Testing `0 tests` footer is rejected as native acceptance; no automatic retry and no overall-green claim. Failure is recorded in #24 without attributing it to the new display monitor (that test does not start a capture).

## 2026-09-09 — Provider identity marks (scoped follow-up)

### 1. Coverage
Pure display mapping, TDD exemption; no new behavior test or gate introduced.
Existing modelRefreshSurfacesRender covers 2 languages × 2 appearances × 2 widths
× 3 refresh states (24 images), including all three Provider identities. All were
regenerated; four inspected images span both languages/appearances/widths and all
three states. Images reside under the system temporary
vlmsnapper-provider-refresh-renders directory. No external fixture needed for
static identity text. Live browser and installed-App checks require unlocking.

### 2. Case design
Rendering uses the production ManagementCenterView with isolated fake credentials,
not a copied mark demo. The refreshed build compiled ManagementCenterView and the
central icon/theme modules. Mark changes do not alter fixture setup or assertions.
No new casts, mocks of private state, or assertion bypasses introduced.

### 3. False-green audit
The PNG-size assertion cannot detect the wrong mark, color or radius. Visual
evidence is the inspected new images, not the rendering test's green status.
No new automated parity claim or mutation-test claim. Strict build passed and
333 non-App tests passed; App tests failed 1 of 14 at the existing toolbar wait.
No retries or longer deadlines; original failure retained for Ticket 24.
Known key-window tests were not run on a locked desktop; full gateway incomplete.

## 2026-09-09 — Ticket 23 continuation: history-filter evidence audit

Scope: the history-query evidence cited for US-10, Ticket08 rendering assertions,
and the 58-row ownership gate. This is **not** the final all-test-suite review.

- 覆盖：enumerated all HistoryQuery dimensions and compared them with the native
  filter predicate. Kind/search/pinned have a UI path; status/Provider/model/
  target-language/date do not. A store-level test cannot cover that missing path.
  Required follow-up is a prototype-approved control-to-list test plus mixed
  records and date boundaries. Physical display and #24 wait evidence stay open.
- Case 设计：`pinningAndMetricsSurviveCompleteFilter` uses the public store API
  with a temporary database, which is appropriate for persistence. It has just
  one record matching every condition; it does not independently demonstrate
  rejection by each optional predicate. `historyQueryCombinesTypeAndSearch`
  supplies two records and targets its narrower type/search behavior. Neither
  constructs a native filter selection. No private-state setup is needed for
  the recommended production-boundary test.
- 假通过：Ticket08's eight-image count/PNG-size assertions are render smoke checks,
  not filter existence, hit testing or list-result assertions. The ownership
  parser explicitly checks structural coverage only; all six parser tests and
  58 rows passed in this continuation. No target mutation was performed here,
  so the single-record test is marked insufficient evidence, not claimed to
  have passed or failed a mutation check.

No weakened assertion, synthetic event substitute or retry-until-green used.
See `23-history-filter-audit.md` for the missing workflow and disposition.
The independent final test-review task remains unchecked.

Fresh result for this audit: 17 SQLiteHistoryStoreTests passed with explicit
Swift Testing completion and exit 0 using CI's full Xcode DEVELOPER_DIR. The first
default-toolchain attempt failed to import Testing before execution; both logs
are named in `23-history-filter-audit.md`. This environment correction is not an
unchanged failing-test retry or evidence that the missing UI controls work.

## 2026-09-14 — #25 历史 UI 同步测试审查

四个新增 case 全量枚举：historicalProviderFiltersList、queryWindowLifetime、combinedQueryAndSelection、historyRenders。复用 ProviderCredentialInteractionTests.windowCloseDiscardsDraft。数据为既有 HistoryRecord/StoredOperation 结构的脱敏合成值，混合提取/翻译与四个终态；不是外部模型协议或真实账户契约证据。

- 【覆盖】Provider 本地选项及真实菜单 action → 列表数量/详情、隐藏保留与关闭重置、8 个中英明暗/920与1200宽原生渲染有当次证据。组合 case 在焦点/选择/导航边界未完成，未覆盖到的 Pinned 交集、搜索零匹配/译文、设置往返不抵扣；图片乱序、数据变化、键盘焦点/hover、历史打开重跑组合仍由 #25 补齐。文件头明确缺口与补测条件。
- 【case 设计】不注入私有 SwiftUI 状态；通过生产窗口、NSTableView 可见行数、原生菜单 action 和字段编辑器观察。菜单 action 是程序化控件测试，不等于物理点击。鼠标组合中的坐标/事件可靠性未坐实，不能据此把产品手势改到凑绿。异步试验没有完整测试结束报告，已撤回；最终保持同步用例，避免持有共享本地化锁跨 await。
- 【假通过】最初辅助功能只遍历空容器，已补子视图遍历，并以实际行数 2→1 作正反例；错误的 NSPopUpButton target/action 触发方式改为真实菜单项 action。Provider 缺失与关闭后旧筛选保留分别产生目标红，再有恢复绿。宽度断言测原生表格滚动区，不以 PNG 存在代替布局；其变异有效性尚未核实，视觉结论来自实际查看截图。组合测试失败不跳过，不弱化断言。只有 XCTest 的零测试摘要不算通过，必须读 Swift Testing 完整结束报告。

清单门禁测试也发现真实假信号：新映射表使原先“替换第一个表格分隔行”的两个变异插入错误章节，门禁当然返回成功。改为定位 Spec requirement ownership 并断言锚点存在；再次运行 6 项全部通过。门禁本身仍仅核旧 US/FM 58 行，不能证明新稳定 ID 的 19 项映射或验收完成，新映射由本次逐行人工核对并在 checklist 留证。

证据保留：/tmp/vlmsnapper-history-red-controls.log、history-red-lifetime.log、history-session-regression.log；测试夹具失败及试验见 /tmp/vlmsnapper-history-key-window.log、history-activation-events.log、history-gesture-check.log、history-async-interaction.log、history-row-hit-target.log。退出 0 但缺少最终测试摘要的试验不计绿。当前全量结果和每项缺口以 checklist 本轮验证历史为准。

## 2026-09-14 记录栏视觉对齐测试审查

- 【覆盖】逐项检查 historicalProviderFiltersList、queryWindowLifetime、combinedQueryAndSelection、historyRenders，以及 HistoryWindowNativeTests 现有三个窗口用例。最终实际执行通过前两项、historyRenders（中英×明暗×920/1200，8 图）和 testSingleClickSelectsAnotherHistoryRecord。其余窗口用例本轮仅适配检索，不宣称重跑通过；combinedQueryAndSelection 本轮无完成结果。真实 hover、键盘/VoiceOver、常驻滚动条及离屏行滚动仍是显式缺口。全部终态有 fixture，但像素自动断言只守行数及选中宽度，不能声称自动校验每种字体和颜色。
- 【设计】不再断言私有 SwiftUI 类型或要求 NSTableView：在生产 NSHostingView 上捕获实际绘制，再由元信息蓝色定位可见行、检查选中填充和点击效果。fixture 全部可见是此 helper 的明确前提，不作通用列表枚举器；只用于本文件与原生窗口测试的固定样本。颜色/249pt 期望来自已确认原型，不导入生产颜色常量作同义反复。鼠标事件仍是 in-process NSEvent，不冒充物理鼠标交付。fixture 保留真实记录的原文/译文/状态/Provider/日期结构，字段值脱敏，无外部请求。
- 【假绿】先要求实际行数为 4 再测宽；无空集合静默通过。内容宽度 259→260 的变异使渲染宽 249→250，8 个断言在 HistoryInteractionTests 的宽度条件失败，且当时 PNG 宽度独立可见。仅撤回变异，最终退出 0。最初的零行来自抓取子 ScrollView 空图及 ICC 二次转换的测试测量错误，未当作生产缺陷；helper 改为 hosting root → PNG → sRGB 后检出真实行。组合测试无完成结果不算绿。

最终日志：/private/tmp/vlmsnapper-history-style-verified.log（XCTest 1 + Swift Testing 3，退出 0）。
变异日志：/private/tmp/vlmsnapper-history-style-mutation.log（8 个预期宽度失败）。

## 2026-09-14 记录栏视觉对齐测试审查

- 【覆盖】核对 HistoryInteractionTests 四项及 HistoryWindowNativeTests 三项。最终执行通过 historicalProviderFiltersList、queryWindowLifetime、historyRenders（中英×明暗×920/1200共8图）、testSingleClickSelectsAnotherHistoryRecord。其他两个窗口测试仅适配行检索，不宣称本轮通过。combinedQueryAndSelection 无完成结果。物理hover、键盘/VoiceOver、常驻滚动条、离屏滚动仍待验收。
- 【设计】读取生产hosting root实际渲染，不依赖NSTableView/SwiftUI私有类。按类型蓝色定位可见行，按独立的原型色值判选中，固定fixture都在视口内；此helper不是通用AX或虚拟列表枚举器。样本保留历史记录的原文/译文/状态/Provider/日期结构，字段用隔离值。NSEvent测试不冒充真实鼠标。
- 【假绿】先断言4行，再测实际选中色横向宽。259→260列宽变异使行249→250，8项在预期宽度断言失败；当时PNG也显示宽度变化。只patch撤回变异，最终退出0。先前零行是子ScrollView缓存空图与ICC二次转换的测量错误，不是生产缺陷。自动像素断言不覆盖全部字体/状态色；渲染图人工检查与自动门禁分开记账。

最终日志：/private/tmp/vlmsnapper-history-style-verified.log（XCTest 1 + Swift Testing 3，退出0）。
变异日志：/private/tmp/vlmsnapper-history-style-mutation.log（8个预期宽度失败）。

## 2026-09-15 历史详情重试测试审查

- 【覆盖】枚举提取/翻译、当前模型与原目标语言、重复点击、配置刷新互斥、截断响应、原图替换、完成落库失败、只重试本地保存及源记录删除保护，均由真实应用回调→HTTP→临时 SQLite 驱动。原生首次详情加载、8组中英明暗/尺寸渲染单独验证；完成结果另经生产详情渲染 OCR 核对。物理鼠标/tooltip、关闭重开进行中窗口、退出未保存确认、自动清理时序仍未完成实机验收，不以源代码代替。
- 【设计】只替换系统边界 adapter，不替换编辑器、配置协调器、workflow、runner、session 或 DB。HTTP fixture 参照现有记录型 DeepSeek chat SSE；翻译内容固定 source→translation 顺序，避免 Dictionary 无序使 fixture 自己违反流式契约。实际 SQLite trigger 使成功写入失败，DROP 后经正式 Retry Save 回调恢复；SQL 仅用于制造存储故障，结果断言经应用历史接口读取。HTTP 请求次数为外部副作用契约，并非内部方法调用次数。
- 【假绿】初始红测卡在未发出图片请求，不是编译错误；删除保护红测在最终历史数 3≠4 上发现源记录被删除。早先依赖任意 publish 的即刻存在性检查不足以证明删除完成，已把源记录保留断言移到保存完成刷新之后。等待改成真实 allowsStart，终态断言改成实际 slot，不能仅等上游 phase 或超时。SwiftUI 虚拟按钮未出现在 NSView AX 枚举里，已撤掉不适用的文本存在性断言，不将其空结果归因于按钮不存在；按钮外观由原生截图核对，点击路径仍需安装版验收。

初始加载变异与最终回归日志见 25-history-retry-verification.md。全套运行未完成，不计作全绿；专门用例通过不能覆盖该缺口。

## 2026-09-16 AX 输入同步测试审查

- 【覆盖】完整枚举本次四个新增方法：`accessibilityEditsReachBinding`、`accessibilityRejectsUnavailableFields`、`accessibilityClearingAndReload`、`accessibilityEditsWithSystemEditor`，各有密码/明文两个参数；原有 pasteNormalizationIsNarrow、visibilityPreservesSelection、standardPasteRoutes 均继续执行。外部四场景：密码、明文、跨 Provider 忙碌、丢弃结果反例。禁用值/隐藏字段测试不等于完全隐藏窗口后台可控性；物理键鼠和真实账户未覆盖。
- 【设计】标准 AppKit setter 与既有 binding 回调是原生组件 seam；不 mock 自有 editor、不直接提交。外部场景采用生产 ManagementCenterView 和真实 ProviderCredentialEditor，只有网络/安全存储终点替换为精确假值回调。不得将测试回调标题当作真实模型验证。只读字段由公开原生 isEditable 状态构造，隐藏引用由正常显隐转换获取。
- 【假绿】setter 测试先红于精确 UTF-8 结果而非编译；外部原始 step3 红已由实际同场景绿闭环。丢弃结果先断言进入该分支再期待成功，实际在最后一步失败，证明断言能拒绝动作成功但业务失败。期望字节是独立字面量，断言均在调用后执行，无条件跳过。保护移除变异被安全策略拒绝，未验证其变异敏感性；不混作通过。

全量真实红：旧坐标测试 5 条失败保留，不以定向绿覆盖。详情、日志、版本和边界见 [验证记录](ax-input-sync-verification.md)。

## 2026-09-16 Provider 旧坐标用例替换审查

- 【覆盖】按源文件全量枚举 7 个方法：关闭重开、回到基线、非法 Return、菜单 Paste、4 参数编辑/粘贴/重发布、跨 Provider 锁定 Return、活动页导航。全部保留责任，3 个涉及坐标流程的方法改为诚实名称与键盘路径；按钮责任迁至 AX 14 个正向场景。8 组合覆盖 920/1200pt × 空/预填 × 密码/明文，以及清空重填、快照重发、成功后禁用；另有基本提交、两尺寸作业解锁、LF/CR/4097 字节边界。原真实样本形态来源是用户输入后 Validate 不可点击及前轮坐标复现，数值全部替换为非秘密字符串。没有复制一套 Provider 状态机作为被测实现。
- 【设计】公开 production view / credential editor seam 不变；AppKit 输入/菜单/Return 与 AX 语义按钮动作互补，不把 AXSetValue 冒充粘贴或 AXPress 冒充真实鼠标。原非法坐标断言可能点空白假绿，现由同一按钮 enabled→disabled→enabled 加真实提交正对照取代。测试只控制外部公开 snapshot 与提交回调，不调用按钮内部业务函数来冒充点击。其他测试的真实命中区域断言不删除。
- 【假绿】新增 drop-result 先看见回调已到达但效果被丢弃，再在 step_6 的成功结果断言 wait_timeout，前 5 步与清理必须成功；正常路径同样精确值通过。7 个报告门禁测试拒绝缺步骤、错误阶段、错误原因、非预期绿、退出码矛盾、清理失败；python -O 实测仍拒绝反例。每个正常 AX case 都要走生产 Validate 并观察精确值回调，不以“操作返回成功”代替结果。原生键盘测试的提交断言在操作后执行，保留精确数组与零提交要求，没有减少参数或放宽断言。

边界：AX 测试不证明真实账户、硬件键鼠、完全隐藏窗口或焦点超时根因；固定 Runner 的权限缺失明确失败。完整本地门禁包含该组，托管 CI 只跑无桌面依赖的报告门禁，不冒称覆盖 AX 实机。

## 2026-09-16 菜单最近记录五条

- 【覆盖】新增一个参数化用例，0、2、5、6 条历史，经 SQLite 公开写入接口及生产 model.menuView 渲染，OCR 验证每个可见标题、最新五条截断和底部入口；model 保留全部记录。原有浅/深色、中/英文渲染样本补足五条。没有改点击、持久化或网络行为，不声称本例重测这些路径。
- 【设计】临时 fixture 采用当前真实历史的持久化结构，含原文、操作、时间、终态、丢失截图占位。期望标题集独立列明，不按生产 prefix 算法计算，不调用私有列表或替换菜单实现。
- 【假绿】修改生产前，6 条样本准确红于第四、第五条不可见，0/2 正常；修改后隔离运行通过。混跑语言渲染 suite 曾因全局语言被切换而红于英文 Settings 文案，不是菜单数量错误；遵循现有完整回归脚本把 App suite 与语言渲染 suite 分进程执行，没有弱化断言。
- 【验证边界】浏览器策略拒绝本地 HTML 自动预览，未绕过；原型仅做源码数量/样式核对，不算浏览器视觉通过。原生 PNG 已实际查看五行与底部，生产渲染 OCR 使用自适应窗口高度而非扩大截图伪装可见性。相关日志在 `/private/tmp/vlmsnapper-recent-five-*.log`。

## 2026-09-16 历史重试身份修复接续

### 维度一：覆盖

枚举本轮用例：historyRetryUpdatesOriginalRecord（提取/翻译）、historyRetrySurvivesWindowChangesAndRejectsLateDeletion、HistoryRetryIdentityTests 全部六个测试函数及其参数、原 runner/session 的当前结果重跑与原图归属回归、HistoryWindowNativeTests 的首开尺寸/双击。逐 AC 映射追加于 checklist 的“接续核销”。恢复测试使用真实 SQLite 与生产 model、session、runner；App HTTP fixture 遵循已有 Provider SSE/模型列表解析形态，不以 mock 自有 runner 代替。Core 测试的短 PNG 字节只验证存储身份，App 测试另用有效 PNG；不据此声称模型视觉理解能力通过。真实硬件、账户、断电与安装版物理交互仍单列。

### 维度二：设计

从公开 prepare/finish 接口种入记录，按公开 history/operation 查询读回；请求计数是外部 HTTP 边界，不是私有函数调用次数。两个 ID 验证目标归属；10 天前记录进入 7 天保留期删除分支，且最终清理真实删除，避免负例因未过期恒绿。SQLite trigger 只用于注入外部存储故障；临时 SQL 备份只供已经红了的 fixture 收尾，不是产品备份，不替代公开查询验收。生产回调代表接线测试，不冒充真实鼠标操作。

### 维度三：假绿/红归因

- 身份测试红在条数 2/3/4 与原 ID 旧内容；不是依赖编译错误。连续重试及应用重建读回避免只测内存。
- retention 测试红在实际行数 0≠2；正文测试使用仅正文出现的第二段文字，避免命中列表/标题而误报可读。
- 首开窗口 red 为旧 1200×812 frame 不等于 screen.visibleFrame；双击 red 为打开回调收到 ID，而非空标题等无关断言。
- 一次生命周期测试误把未取消的原生 retention sheet 当作窗口关闭失败；补齐真实取消后再关闭，不修改产品关闭逻辑迎合错误操作序列。
- CLT 构建缺 Testing module 不计业务红；使用 Xcode 后验证。先前 AX 首次 launch 失败保留；本轮完整 gate 一次退出 0，15 AX 场景含预期失败反例通过。
- 移除旧“关闭独立历史结果返回”的测试和孤立 callback 转发测试，因为用户已取消该入口；保留双击不打开、右侧重试及关闭/重开持久化的替代验证，不是删失败测试求绿。

正式门禁：`/private/tmp/history-retry-full-closeout.log`；340 非 App Swift Testing、17 App Swift Testing、XCTest、两个独立原生用例、15 AX 场景均通过。测试头已更新物理交互缺口；未声称全 feature 人工验收通过。
