# 2026-09-30 单一版本号代码审查

范围：无票 spec 增量 `v1-core::REQ-004`；参考 `850f64d` + 当前未提交修改。仅审本轮版本参数、清单、校验与 CI 接线，不把原有双语/历史改动当作本轮修改。保留以下历史原始报告。

| 层 | 本轮核对与结论 |
| --- | --- |
| ① 底层前提 | 实测当前依赖 Sparkle 2.9.6 默认比较器，三段数字递增、同版本相等、0.1.1 小于旧 51；生产 updater 的 delegate 为 nil，没有自定义比较器。不能承诺旧整数自动升级。 |
| ② 可运行性 | 全部 build/verify/release 调用点与两个 workflow 已移除独立参数；实际 arm64 App 两字段均为 0.1.1。ReleaseManifest 保留 Codable 的 buildVersion 字段以读取旧数据，但构造时派生同值，发布校验拒绝旧不一致值；不做历史序列化字段删除。 |
| ③ 安全正确性 | 版本先校验再构建/凭据操作，workflow 输入经环境变量传参；签名、公证、HTTPS、EdDSA、架构门禁原样保留。发现 enclosure 版本属性可优先于 item 元素：新增真实反例先红，修正为同时查元素/属性并拒绝重复和不一致，防止错误更新版本逃逸到整版发布。 |
| ④ 一致性 | 三架构共享同一版本，CI 使用合法的 0.0.0 非发布样本，不引入 CI run number 作为另一版本。LiveProviderGate 自身的工具 Bundle 编号不属于发行 App，未改。spec、features、CONTEXT 口径同步；无界面或字典新增。 |

故障逃逸：非法输入/版本冲突必须终止本次构建或整版产物发布，不允许产生另一版本；appcast 失败在原子公开输出之前。审查未遗留本轮代码缺陷或待重构项。正式三架构公证与公开更新链路未运行，不由本地门禁代证。

证据：`/tmp/vlmsnapper-version-final-targeted.log`、`/tmp/vlmsnapper-single-version.sSHyyl/{build,signing,verification,invalid-build,invalid-display}.log`；安装状态以同 feature `final-regression.md` 本轮条目为准。

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

# VLMSnapper v1 — Retina frozen capture code review (2026-09-03)

审查范围：只修复 ScreenCaptureKit 冻结帧按逻辑 point 分辨率捕获、随后在 Retina overlay 中被放大的问题；不改变选区界面、图片格式、Provider 或历史行为。

## 【① 底层前提】

- 当前 SDK 声明 `SCContentFilter.contentRect` 使用 screen points、`pointPixelScale` 用于 point 到 pixel 的换算，且两项从 macOS 14 可用；项目最低版本正是 macOS 14。
- 先前真实屏幕诊断得到 logical `1512 × 982`、scale `2.0`、ScreenCaptureKit raster `3024 × 1964`。旧实现使用 `CGDisplayPixelsWide/High` 得到 logical 尺寸，与实际模糊的 2 倍放大相符。
- `NSImage(cgImage:size:)` 继续使用 logical point 尺寸，overlay 在 Retina backing surface 上显示完整物理像素；半透明遮罩只降低亮度和对比度，不参与缩放或模糊滤镜。

## 【② 可运行性】

- 每块显示器先建立 filter，再把 `contentRect × pointPixelScale` 四舍五入为输出尺寸；无效、非有限、零像素或超出 `Int` 的尺寸只使该屏捕获失败。
- filter 尺寸与当前 CoreGraphics logical bounds 不一致时，该屏以 geometry changed 失败；其他显示器仍由现有批处理继续。
- 捕获返回的 `CGImage` 必须与请求 raster 完全同宽高，尺寸不一致不会进入 overlay 或裁剪。
- 鼠标松开时重新从当前 `NSScreen.screens` 按 display ID 取 backing scale，再通过同一换算函数建立当前 geometry；分辨率或 scale 变化继续由既有 equality gate 拒绝。
- 现有 `applyCurrentDisplayGeometries(_:)` 没有生产调用者，只能在 mouse-up 检出变化。这是改动面外的既有即时失效缺口，已独立记录为 `issues/01-live-display-reconfiguration.md`，不混入清晰度修复。

## 【③ 安全正确性】

- 尺寸换算在浮点转整数前检查 finite、正值、舍入后至少 1 pixel 且严格小于 `Int.max`；真实溢出测试证明旧边界会 trap，修复后返回 nil。
- 本轮不读取或持久化用户内容，不改变屏幕录制权限、文件路径、PNG 所有权或网络边界。
- 显示配置变化的故障面为自伤：只移除或拒绝对应显示器；没有清空其他成功显示器或把错误冻结帧上传给 Provider。

## 【④ 一致性】

- 实现恢复 spec、feature catalog 与 ADR-0010 已有的物理像素、原始 PNG 和不缩放不增强约束；feature/spec 补充 Retina 可见行为，ADR 决策无需改变。
- `CaptureDisplayGeometry` interface 保持不变；新增 raster 类型与换算函数只在 Core 模块内部形成测试 seam，没有引入第二套公开 geometry。
- 全部四个 `currentCaptureDisplayGeometry` 定义/调用点已枚举并迁移到显式 scale，仓库内不再有 `CGDisplayPixelsWide/High` 的 Swift 调用。
- 按项目能力声明，i18n 已启用；本轮没有新增 UI 文案或本地化 key，不需要修改两语种字典。界面结构与视觉样式未变，不需要新原型。

## 结论

四层审查未发现本次修复的剩余阻断项。真实 ScreenCaptureKit 输出仍需签名安装版在 Retina 显示器上验收，单元测试不冒充该系统集成证据。

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
# VLMSnapper v1 — Ticket 12 status item interaction code review

审查范围：状态项左右键分流、原生 Quit 菜单、popover 关闭后截图接线、主面板入口和应用终止接线。

## 【① 底层前提】

- 当前 macOS SDK 的受支持入口是 `NSStatusItem.button` 与按钮的 `sendAction(on:)`；旧 `NSStatusItem.sendActionOn` 已弃用。
- `NSMenu.popUpContextMenu` 接收触发事件和状态项按钮即可展示原生菜单；不需要 Carbon、自绘窗口或第二个状态项。
- 真实截图入口已经存在于 `VLMSnapperApplicationModel.capture()`，全局快捷键和菜单栏按钮只应汇合到该入口。

## 【② 可运行性】

- 状态按钮现在接收左键和右键抬起：右键进入单项原生菜单，其他激活保持原有 popover toggle 行为。
- 主面板的 Capture Screen 先复用 `MenuCaptureRouter`。Provider/权限恢复仍在原 popover 展示；ready 分支通过 `popoverDidClose` 信号再调用已有 capture callback。
- 环境中没有生产 popover coordinator 时，preview、UI harness 和离屏渲染直接执行 callback，不会因测试宿主缺 AppKit controller 而失效。

## 【③ 安全正确性】

- 第一版环境动作草稿依赖 `@unchecked Sendable`。审查中把它替换为直接注入 `@MainActor` dismissal coordinator，去掉不必要的并发安全豁免。
- Quit item 只调用 `NSApp.terminate(nil)`；`applicationShouldTerminate` 仍是唯一调用 `prepareForTermination()` 的协调入口。主面板旧 callback 和模型 `requestQuit()` 已删除，避免同一路径准备两次。
- 右键路径不主动关闭 popover，不会在退出被取消前先销毁 Provider/权限 sheet 状态。截图路径只在 ready 分支关闭，且 pending callback 执行一次后立即清空。

## 【④ 回归与范围】

- Check for Updates、最近记录、History、Settings 与状态点保持原接线；只移除主面板 Quit 行和因此产生的未用图标。
- 没有修改 ScreenCaptureKit、冻结帧、选区、PNG、Provider、历史、Sparkle 或终止确认规则。
- 明暗模式真实 SwiftUI 离屏渲染已检查：主面板布局完整，Quit 行消失，Capture 与更新入口仍可见。

## 结论

审查发现并修正一处不必要的 unchecked concurrency seam，未发现剩余 race、双重退出准备、资源泄漏或第二套截图流程。实现与确认原型的入口分工一致。

---

# 2026-08-31 — Ticket 11/12 integration review

## 【① 底层前提】

- 当前 Installed App 的标准 Apple Event Quit 返回 `User canceled (-128)`，且 PID 保持不变；这排除了“退出后被登录项重新拉起”。
- `main` 已包含右键 Quit 到 `NSApp.terminate(nil)` 的接线，但未包含 Ticket 11 的 sheet window policy；PR #6 未合并是当前安装包仍失败的直接原因。

## 【② 可运行性】

- 合入最新 `main` 后，Ticket 11 的代码与 Ticket 12 的状态项代码没有冲突；冲突仅发生在两票共同追加的施工记录、spec 与 feature catalog。
- 三个 production `.sheet` host 仍只呈现 Provider setup、permission recovery 和 storage/privacy 三类内容，三类 root 都应用同一幂等 window policy。
- 右键 Quit 继续只进入 application delegate 的统一退出协调；本次合并没有引入第二次 preflight、提前关闭 sheet 或改变未保存结果确认。

## 【③ 安全正确性】

- 允许终止的策略仍局限于 VLMSnapper 自有 sheet，不影响 `NSAlert`、`NSSavePanel` 或 Sparkle 管理的窗口。
- 合并未改变 Provider 凭据、截图、历史或更新数据路径；故障面局限于退出请求是否能到达既有 coordinator。

## 【④ 一致性】

- 冲突解决保留 Ticket 11 的 sheet 退出语义和 Ticket 12 的左/右键入口语义；现行 spec 与 feature catalog 同时描述两者。
- 严格构建、完整测试、脚本语法与三架构 development DMG 门禁均通过。未发现需要另开的重构项。

---

# VLMSnapper v1 — Ticket 13 Edit menu and prototype parity code review

审查范围：原生 application/Edit menu、菜单栏左键面板、onboarding/provider/permission/privacy、截图操作栏、结果工作台、管理中心以及真实应用状态接线。

## 【① 底层前提】

- API Key 输入使用标准 SwiftUI `SecureField`，Command-V 的缺口来自应用没有 `NSApp.mainMenu`，不需要字段专用键盘处理。
- AppKit responder 项全部保持 `target == nil`；Find 使用 `performTextFinderAction:` 与 `NSTextFinder.Action` tag，菜单启用与动作对象由当前 first responder 决定。
- HTML 原型继续是已经确认的产品契约；生产保留原生 AppKit/SwiftUI 控件、字体栅格和辅助功能语义，不复制浏览器 harness 或 fixture 数据。

## 【② 可运行性】

- 应用在语言配置完成后安装 Application/File/Edit/Window/Help 菜单；Edit 的完整层级、selector、快捷键和双语标题均由独立测试承兑。
- 左键面板从真实 Provider readiness、持久化历史、截图路径和 Sparkle 状态生成品牌状态、三条最近记录、更新提示与双列入口；未配置时不会伪报 Provider 可用。
- 十个生产表面统一采用确认几何并通过同一 production view 离屏渲染；Provider、permission、privacy sheet 仍保留统一退出策略，截图按钮仍复用已有 capture route。

## 【③ 审查发现与修复】

1. `ProviderSetupSnapshot` 只描述当前选中的 Provider，最初直接拿它渲染所有行会把其他已配置 Provider 错报为未配置。修复新增只读 presentation seam，并把完整持久化 configuration map 接到 onboarding、菜单栏配置 sheet 和管理中心；非当前 Provider 现在保留真实模型与可用状态。
2. 最近记录最初直接取 Markdown 第一行，`# Designing Calm Software` 会在菜单中带出标题标记。修复只清理首行 heading marker 和空白；空标题仍回退到操作名称/失败标题。
3. 已确认 companion prototype 不包含独立手动更新行。生产面板只在更新状态需要注意时展示 inline notice；手动检查保持在 General Settings，避免同一动作出现两个不一致入口。

## 【④ 安全与回归】

- 没有修改截图冻结、PNG、Provider 请求、重试/超时、Keychain、历史删除或 Sparkle 下载语义；新增数据只读取已有配置和历史快照。
- 缺失或无法读取截图时 recent row 使用占位图；没有把文件错误提升为面板失败。
- 代码、注释和测试名保持英语；产品文案来自 234 键双语字典。扫描到的中文只存在于本地化行为断言和中文结果 fixture。

## 结论

审查发现的两处用户可见状态错误均已补成回归测试并修复。未发现剩余 race、资源泄漏、凭据暴露或第二套业务流程；实现与所有确认原型的生产数据边界一致。

---

# 2026-09-01 — Ticket 14 confirmed UI regression code review

审查范围：菜单栏 Capture 恢复路径、Provider API Key 输入状态、共享表面语义色、管理中心侧栏与历史详情卡片。

## 【① 底层前提】

- `VLMSnapperApplicationModel.capture()` 已经是 readiness 的真实生产入口：权限或 Provider 未就绪时调用 onboarding，ready 时才启动截图。`showOnboarding()` 对已有和新建窗口都执行 `makeKeyAndOrderFront` 与应用激活。
- 当前 Aqua 实测把 `underPageBackgroundColor` 渲染为相对亮度 `0.303`，与原型的浅色 `surface-subtle` 不同；该深灰在无 modal 的离屏生产渲染中同样出现，排除了遮罩导致变灰。
- API Key 的生产 binding 写入普通 application-model 属性，不发 SwiftUI observation；字段编辑器能显示新值不代表同一 view 的 sibling button 会重算。

## 【② 可运行性】

- 三种菜单 Capture readiness route 现在都先经 popover dismissal coordinator，再进入 application-model Capture；菜单 popover 不再持有 Provider/permission sheet，所以 720 pt Provider 面板不再锚定状态项屏幕边缘。
- Provider view 的本地 draft 驱动 SecureField 与 Validate enablement；点击 Validate 时先同步到现有 binding，再调用现有 async callback。Provider 切换和成功进入模型阶段会清除 draft。
- 历史 detail 保留原有 pin/delete、截图、原文/译文、metrics 和滚动路径，只增加原型确认的外层 secondary surface 与 bordered detail card。
- 最新中英文明暗 production renders 已重建；浅色侧栏、Provider sidebar、hint/metrics 与历史详情层级均恢复，暗色仍保持对比。

## 【③ 安全正确性】

- API Key draft 只存在于 Provider sheet 的内存状态；没有日志、磁盘或新持久化路径。成功验证仍由现有 session 写入 Keychain，失败不会触发额外请求或自动重试。
- 点击 Validate 的 binding 更新发生在创建 async Task 之前，现有 `validateProvider()` 读取到本次 draft 后才清空 application-model 临时值。
- Capture 修复没有跳过权限/Provider 检查；它只是把检查收回已有 application-model 单一入口。
- modal 移除只覆盖 menu popover 中已被新恢复路径取代的两类 sheet；onboarding 和 Management Center 的 app-owned sheet 与退出协调策略保持不变。

## 【④ 一致性】

- 审查发现菜单 handler 变更后仍残留整套不可达 popover sheet 参数和 Provider callbacks。该类级重复 recovery path 已从 `MenuBarContainerView`、application-model composition 与 render fixture 中删除，避免未来误接回边缘 sheet。
- 初版主题修复把 secondary surface 直接等同于 window surface，会丢掉原型的浅层级。复查系统语义色后改为 adaptive `unemphasizedSelectedContentBackgroundColor` 的轻透明层；浅/暗均通过当前产物渲染，而不是硬编码 RGB。
- `ProviderSetupInputState` 不需要成为 UI module 的公开 API；审查已缩回 internal test seam。
- 未新增图标或用户文案；现有 SF Symbols 图标模块与双语字典不变。未发现本次改动面外新增字符图标。

## 结论

审查发现并修正三处实现层问题：不可达的第二套 popover recovery、过度扁平的主题修复，以及不必要的公开输入状态。未发现剩余 race、资源泄漏、凭据落盘或业务语义扩张。
# Ticket 15 — Production regression follow-up code review

## 【① 底层前提】

- **发现并坐实**：安装版的 Provider 请求不是网络不可达。统一日志显示 DNS、TCP、TLS 和 HTTP/2 均成功，最终状态为 401；因此修复只调整 typed error 的 presentation 映射，不触碰请求端点、Authorization header 或网络权限。
- **发现并坐实**：`NSWindow.minSize` 约束外框，而已确认的 `920×620` 是 SwiftUI 内容区尺寸。独立 AppKit probe 得到 `frame=920×620 / content=920×588`，与用户截图上 32pt 的纵向裁切一致。
- **核对通过**：现行 Xcode SDK 明确说明应用 activation 不保证立即完成；引导路径因此不能只依赖 activation 顺序。实现额外使用一次 `orderFrontRegardless()` 保证用户显式恢复动作后的可见性，但没有改变 window level。
- **同类枚举**：结果窗口不在 status-item popover close transaction 中，因此没有本票的置前 race。审查同时发现其既有 `820×520` frame minimum 与 `1020×620` SwiftUI content minimum 不一致；用户本次没有报告结果窗口缩放故障，且它不属于历史管理中心验收，因此不在本票顺手修改，作为独立后续观察保留。

## 【② 可运行性】

- **窗口状态路径**：新建引导、复用已关闭引导、Provider 未就绪、权限未就绪均汇入同一 presentation helper；ready Capture 不进入该 helper。popover pending action 在取出后立即清空，所以重复 `popoverDidClose` 不会重复执行。
- **异步生命周期**：post-close Task 只持有一个短生命周期 action，没有循环、timer 或 retained continuation；hidden-panel 路径仍同步执行，避免给快捷键或非 popover 调用增加延迟。
- **Provider 状态路径**：只有真实 `ProviderModelListError.authenticationRejected` 映射为 invalid credential；503 等其他 model-list 错误仍为 unavailable。候选 key 的持久化仍发生在完整模型列表成功之后，失败不改变旧配置。
- **窗口几何路径**：默认 content rect 保持 `1200×720`，交互式最小外框由 AppKit 根据 `contentMinSize=920×620` 自动换算；SwiftUI 根视图的同值 minimum 不再大于可用内容区。
- **故障逃逸面**：三个原问题均为单次用户操作的自伤，不污染其他 Provider、历史记录或请求；修复没有新增同层或上层逃逸。

## 【③ 安全正确性】

- API Key 未进入日志、测试输出、诊断文件或新增文档；测试使用固定假值。
- 401 分类不展示 Provider 原始响应正文，只复用现有本地化 invalid-credential 文案。
- 没有新增网络请求、重试、Keychain 写入、权限请求、路径处理或持久化输入。
- `orderFrontRegardless()` 只在用户显式触发且 readiness 阻断时调用，不创建持续置顶窗口或扩大系统权限。

## 【④ 一致性】

- 实现继续遵守 one Capture workflow、panel-close-before-action、single Provider request、failure without auto-retry 和 confirmed prototype hierarchy。
- 新代码与注释均为英文，产品文字继续来自现有本地化字典；没有字符图标或硬编码 UI 文案。
- 坏味道核对：没有新增重复 switch、数据泥团、通用抽象或霰弹式修改。private onboarding helper 消除新建/复用两条路径的重复 presentation 顺序，具有直接行为增值，不是中间人。

## Review findings resolved

1. 测试 review 前的异步用例使用无截止 `AsyncStream`，若 action 永不执行会使测试挂死。已改为最多 10 次 main-actor yield 的有界等待，失败会产生明确断言而不是卡住测试进程。
2. Provider 分类测试最初只覆盖 401。已增加 503 反例，防止未来把所有模型列表错误都误标为凭据错误。
3. Ticket 13 只渲染默认管理尺寸。已增加 `920×620` 最小内容区的中英文/明暗四张 production render，并目视确认 Header、列表底栏和详情卡完整。

## Refactor disposition

- 无需另开重构。其他普通窗口的 activation 顺序属于既有代码且无同类实测故障；为保持窄范围，本票不改。

---

# VLMSnapper v1 — Ticket 16 code review

审查范围：Developer ID provisioning profile 验证、动态 entitlement 派生、三架构签名门禁、Data Protection Keychain 烟测以及 Provider 安全存储错误呈现。

## 【① 底层前提】

- 下载到本机的真实 Developer ID distribution profile 已由系统 `security cms` 解码；实际 UUID、到期时间、`OSX` 平台、全设备分发标志、App ID Prefix、Team ID、Bundle ID、Keychain allowlist 与 Developer ID Application 证书均由实现按真实结构读取，不以合成 fixture 代替外部事实。
- 当前登录钥匙串中的 `Developer ID Application: Longfei Zhou (RHQ28XS7D9)` 证书与 profile 内证书 DER 实际匹配；arm64、x64、Universal 三种临时 App 均由该身份真实签名并通过校验。
- Xcode 26 在 Apple Silicon 主机显式传入 arm64 triple 时会命中预编译 Foundation/优化器故障；构建脚本只在“本机即 arm64”时使用宿主目标，x64 与 Intel 主机上的 arm64 仍使用显式 triple。两条分支均以实际 release build 验证，不把旧 scratch 产物当本轮结果。

## 【② 可运行性】

- profile 缺失、CMS 解码失败、过期、渠道不符、Bundle/Prefix/Team 不符、Keychain group 未授权或签名证书不在 profile 内时，准备步骤在任何正式签名前终止；故障逃逸面为整次发布，属于预期 fail-closed，不留下可发布降级产物。
- 嵌套 Sparkle 代码逐项先签，外层 App 最后签；三架构均复验嵌入 profile 摘要、UUID、外层实际 entitlement、证书 authority、Team ID、runtime 与 secure timestamp。
- Universal 最终签名进程使用唯一 service 执行随机假凭据的增、读、改、删，成功与失败路径均尽力删除；真实运行已通过。Keychain 写入失败只使当前 Provider 配置失败并保留输入，不污染其他 Provider 或误报远端服务故障。
- review 清理了新文件内从未构造或匹配的 `signingCertificateUnavailable` 枚举分支。全库引用检索及 `git log -S` 均无其他实例；它没有持久化值或跨端消费者。

## 【③ 安全正确性】

- 仓库、Git index 与 artifact 清单都不包含 profile 输入、解码 plist、派生 entitlement 或 API Key；CI 仅从 protected secret 写入 runner 临时文件，权限由 `umask 077` 限制，并在 `always()` 清理步骤删除。
- App ID Prefix 不在生产代码、脚本或 CI 中硬编码；精确 application identifier、Team ID 与单一 Keychain access group 全部从已验证 profile 动态派生，再与最终签名实际值逐项比较。
- 签名准备拒绝覆盖既有输出；release staging 使用独立临时目录。准备过程的检查与写入之间仍有理论 TOCTOU，但调用目标均位于本次发布私有临时目录，不存在同层或上层故障逃逸面，故不扩张为通用文件事务重构。
- 日志和错误不包含 API Key。真实 Keychain 烟测的随机假凭据只存在于唯一临时 Keychain 条目，失败时执行 best-effort 清理。

## 【④ 一致性】

- 实现符合 ADR-0001 的 Keychain 保存、ADR-0005 的稳定 `com.loong.vlmsnapper` 身份、ADR-0007 的 Developer ID 直接分发和 ADR-0004 的三架构原子门禁。
- Provider 安全存储失败沿用现有 `local_storage` 用户错误类别；没有新增页面、控件、颜色、间距或状态结构，因此按已记录的原型例外无需新视觉原型。
- 新源码、注释、测试名与命令错误均为英文；用户文案通过 zh-Hans/en 字典成对进入。未发现需要另开任务的重构项。

## 结论

review 发现并删除 1 个本次引入的 orphan enum case；事实层重扫后，三架构签名、Keychain 生命周期、安全边界与既有 ADR 均无剩余阻断项。

---

# VLMSnapper v1 — Direct Pictures storage code review (2026-09-02)

审查范围：将系统 Pictures 目录 API 在沙盒中返回的代理路径解析为直接用户 Pictures 路径，并继续使用既有截图存储安全边界。

## 【① 底层前提】

- 已用签名、嵌入 provisioning profile 且启用 App Sandbox 的当前分支 App 实测：系统 API 返回的代理经解析后，实际保存路径为 `/Users/loong_zhou/Pictures/VLMSnapper/2026-09/...png`，不是 Container 内的 `Data/Pictures` 路径。
- 回归 fixture 复现了真实路径形态：Container 下的 `Pictures` 是指向用户 Pictures 的符号链接；测试不是仅按 spec 想象数据结构。
- 全库生产引用检索确认截图存储只在 `VLMSnapperApplicationModel` 构造一次，根目录只由 `ApplicationDirectories.screenshotRoot()` 提供；没有第二个未修复的同类入口。

## 【② 可运行性】

- `ManagedScreenshotRoot.directURL(for:)` 先解析系统提供的 Pictures 目录，再标准化并追加 `VLMSnapper`；返回 URL 不再依赖 Container 代理，因此 `FileSystemScreenshotStore` 可以按原规则创建根目录和月份目录。
- 失败面保持自伤：系统目录查询或目录创建失败只终止当前截图保存，既有流程不会上传或创建成功历史；没有污染其他历史记录或 Provider 配置。
- 真实签名沙盒验收执行了保存与删除，证明本次构建产物实际获得 Pictures entitlement 且直接路径可写；完整 SwiftPM 构建与 230 tests / 62 suites 同时通过。

## 【③ 安全正确性】

- 只在可信的系统目录 API 边界解析一次代理路径。解析后的 `VLMSnapper` 根目录仍由 `FileSystemScreenshotStore` 检查根目录、父目录、年月目录和图片文件不得是符号链接；既有 10 个存储安全测试全部通过。
- 解析结果是直接绝对 URL，后续保存不再穿过 Container 代理，代理在保存期间变化也不会改变已选定目标。应用仍不扫描 `VLMSnapper` 之外的 Pictures 内容。
- 本轮未放宽 `FileSystemScreenshotStore` 的通用符号链接策略，也未引入硬编码用户主目录、环境变量或自定义保存位置。

## 【④ 一致性】

- 实现恢复 ADR-0006 的既有结论：通过系统目录 API 获取 Pictures，用户可见与持久化路径为 `~/Pictures/VLMSnapper/`，不把 Container 代理路径当作保存位置。
- spec 中“固定保存到 `~/Pictures/VLMSnapper/YYYY-MM/`”和“不跟随符号链接提供隐式自定义位置”继续成立；系统 API 代理在存储边界前被消解，应用自建根目录及其后代仍拒绝符号链接。
- 新类型名称表达单一职责，没有重复条件、发散职责、未用参数或跨文件霰弹式修改；无需另开重构任务。

## 结论

四层审查未发现剩余阻断项。本次改动只修正截图根目录入口，不放宽截图文件所有权与符号链接安全不变量。

---

# VLMSnapper v1 — Localization test isolation code review (2026-09-02)

审查范围：修复多个 Swift Testing suite 并发修改全局本地化 bundle 时产生的跨 suite 竞态；不修改生产本地化实现或用户界面。

## 【① 底层前提】

- `VLMSnapperLocalization.configure` 写入进程级 `LocalizationBundleStore.shared`。其内部锁只保护一次读写，不会把测试中的“切换语言、渲染、断言、恢复语言”组合成原子区段。
- 六个测试文件中的 10 个测试函数共包含 16 次语言切换；suite 自身的 `.serialized` 只约束同一 suite，不能阻止其他 suite 同时改写全局语言。
- 本轮用一个 test-target-only `NSLock` 作为共同协调点。生产 target、应用启动、语言选择和资源字典均未接触。

## 【② 可运行性】

- 每个会切换全局语言的测试在函数入口 `acquire()`，并立即用 `defer` 配对 `release()`；断言抛错或提前退出仍会解锁。
- `release()` 在解锁前统一恢复默认简体中文；已有恢复 `defer` 可重复执行，原先会遗留 English 的测试也不再把状态暴露给后续测试。
- 协调器回归测试让两个并发队列竞争同一入口：第一个持锁时第二个不得进入，释放后第二个必须完成并观察到默认简体中文。等待首个持锁者的 15 秒仅容纳其他 production render 测试的合法持锁时间；真正的互斥断言仍是 100 毫秒。

## 【③ 安全正确性】

- 锁只存在于 `VLMSnapperUITests`，不会扩大生产同步面、网络请求、文件保存或 UI 主线程阻塞。
- 所有 `acquire` 都有同函数、紧邻的 `defer release`，没有嵌套获取、跨异步 suspension 持锁或条件分支漏释放。
- 变异验证临时移除 `lock.lock()/unlock()` 后，协调器测试准确红于第二个区段提前进入；恢复两行锁操作后同一测试转绿。

## 【④ 一致性】

- ADR-0003 的两语种资源边界与生产运行时切换方式均未改变；本轮只让既有测试尊重该全局状态边界。
- 代码、注释和测试名均为英文；没有新增用户文案，因此无需修改 zh-Hans/en 字典、spec、feature catalog 或确认原型。
- 默认格式化工具曾产生六个文件的大面积机械 diff，review 中已全部移除；最终既有文件仅增加 20 行配对协调调用。

## 结论

四层审查未发现剩余阻断项。修复位于测试基础设施，覆盖了当前全部 16 个显式语言切换点，同时保持生产行为不变。

---

# VLMSnapper v1 — DeepSeek reasoning activity timeout review (2026-09-02)

审查范围：只修复 DeepSeek 实验视觉模型在持续返回私有推理分片时被 10 秒首字计时误杀的问题；不修改请求格式、公开事件协议、结果界面、自动重试或其他 Provider 行为。

## 【① 底层前提】

- 真实流式样本证明首个 SSE 在 317 ms 内到达、非空 `reasoning_content` 在 1,144 ms 内开始，而公开 `content` 最晚到 16,676 ms 才出现；旧实现只在公开文字事件上重置计时，因此把“Provider 正在处理”误判为“连接无活动”。
- `DeepSeekChatStreamDecoder` 是唯一理解该私有字段的层；统一 Provider 事件仍只包含 source、translation、metadata 和 completed，不能把推理内容提升为公开协议。
- 首字/停滞计时与 90 秒总计时由同一 actor 串行管理；本轮只重建当前无活动 timer，不触碰 total timer。

## 【② 可运行性】

- DeepSeek decoder 每个 payload 先清空活动位，只在所选 choice 的非空 `reasoning_content` 上置位；空字符串、普通缓冲 content、metadata 和 DONE 都不会冒充私有活动。
- executor 先把 decoder 结果折叠为公开事件与私有活动布尔值，再通知 timeout coordinator；公开事件仍按原顺序 yield，OpenAI/Gemini decoder 不产生私有活动。
- coordinator 在首个公开文字出现前收到私有活动时重启 first-text timer；收到公开文字后切换并持续重启 stalled timer。完成、失败和取消仍同时取消两个 timer。

## 【③ 安全正确性】

- 推理字符串只在 decoder 内做非空判断，没有进入 `ProviderStreamEvent`、accumulator、持久化、诊断或日志；全库引用检查未发现其他生产消费者。
- API Key、截图内容和模型输出没有写入测试报告。真实 10 次测试只保留耗时、运行序号和归一化状态，临时 CLI 测试入口已撤销。
- 失败策略没有放宽：连续 10 秒无有效活动仍失败，90 秒总时限仍不可延长，不自动重试、不切模型，也不接受残缺结构化结果。

## 【④ 一致性】

- spec、feature catalog、ADR-0011 与 `CONTEXT.md` 已同步同一边界：DeepSeek 私有活动可刷新无活动计时但不可显示或保存，OpenAI/Gemini 不变。
- 本轮没有用户界面结构、样式或文案变化，既有确认原型无需修改；按项目能力声明，i18n 已启用，但本轮没有新增本地化键或字典变更。
- 生产代码、注释和测试名均为英文；施工与审查记录继续保留在既有 v1-core working 目录。

## 结论

四层审查未发现剩余阻断项。实现将 Provider 私有活动限制在 DeepSeek decoder 到 timeout coordinator 的单向布尔信号中，没有扩大公开契约或安全暴露面。

---

# VLMSnapper v1 — Result window, rerun history, and menu interaction review (2026-09-02)

审查范围：结果工作区窗口层级与刷新、当前结果重跑的历史身份，以及菜单面板可点击/hover 区域；不改变 Provider 请求、历史操作重跑、截图捕获或已确认布局。

## 【① 底层前提】

- 代码实证表明旧窗口同时使用 `.floating`，并在约 50 ms 的流式快照刷新中反复执行 `makeKeyAndOrderFront` 与 `NSApp.activate`；两者共同造成窗口持续抢前台，不能只修其中一处。
- `prepareOperation` 每次都生成 UUID 并 INSERT；旧 runner 在每次 Try Again 都调用它，重复历史并非查询或刷新假象。
- SwiftUI 截图按钮的蓝色背景位于 `Button` 外部，而 label 未占满可见宽度；真实 AppKit 边缘点击测试在旧形态下没有触发 action。

## 【② 可运行性】

- 结果窗口首次展示与内容刷新拆成两条路径；只有首次打开和用户再次显式请求已有工作区时置前，流式/终态/保存刷新只替换内容，不改变窗口可见性或层级。
- runner 为同一工作区的 Extract 与 Translate 各保留一个历史身份。首次执行正常 prepare；当前结果重跑向 Provider 传入最新选择，但只有成功持久化时原子更新原 ID。失败或取消不会破坏此前成功结果。
- 保存失败仍保留待保存结果；Retry Save 按首次保存或替换语义走对应持久化路径，不会再次请求 Provider。
- 菜单 Capture、最近记录和底部两个入口共享同一全宽按钮组件；可见背景、content shape 与 action 命中边界一致，三种角色各有 hover 反馈。

## 【③ 安全正确性】

- 历史替换只按既有 UUID 更新，保留截图路径、SHA-256、创建时间和 pin 状态；SQL 使用参数绑定，未扩大文件删除、路径或凭据边界。
- 失败重跑的故障面保持自伤：当前工作区显示最新失败，但数据库中的此前成功结果不被清空；另一个操作槽和其他历史记录不受影响。
- 窗口修复不使用新的系统权限、全局事件监听或激活绕过；菜单测试只在 test host 内发送 AppKit 窗口事件。

## 【④ 一致性】

- `CONTEXT.md` 已明确区分“当前结果重跑”和“历史操作重跑”；spec/features 与实现统一为前者复用记录、后者未来创建新记录。
- companion-shell 原型已经把结果窗口画在后台，并为截图、最近记录和底部入口定义整行 hover；生产渲染保持原布局，仅恢复已确认交互。
- i18n 按项目能力声明已启用；本轮没有新增或修改用户文案，双语字典无需变化。图标继续使用集中式 SF Symbols。
- 新增的按钮组件消除了三类入口的重复命中/hover 实现；SQLite 的两个终态 SQL 绑定布局不同，局部 outcome 分解重复保持就地可审计，不另建抽象。

## 结论

四层审查未发现剩余阻断项。三个报告问题均在各自最窄边界修复，未改变历史操作重跑、Provider 或截图文件安全语义。

---

# VLMSnapper v1 — Capture from result workspace review (2026-09-03)

审查范围：结果工作区打开时的截图入口、工作区退让准入与冻结前窗口隐藏；不改变截图画面、结果布局、Provider 请求或历史存储格式。

## 【① 底层前提】

- 已在当前已安装版本中通过真实全局快捷键复现：结果工作区显示 `Done` 时按 `⌥⇧S`，窗口继续留在前台且没有出现选区。生产代码对应路径只判断工作区是否存在，随后无条件置前并返回，根因与用户症状一致。
- AppKit 当前构建测试使用真实 `NSWindow`，验证 `orderOut` 后 `isVisible == false`，并验证冻结入口不会在隐藏动作的同一同步调用栈内提前执行。它证明本轮窗口状态与调度顺序，不冒充尚未安装的新签名 App 验收。
- 工作区的活动任务、启动中状态和未保存结果都由同一个 actor 持有；截图准入在该 actor 内一次完成，没有从多个异步快照推断状态。

## 【② 可运行性】

- 工作区无活动任务且无未保存结果时，截图准入只成功一次；工作区立即停止接纳 Try Again，应用清除当前 live session，先隐藏结果窗口，再进入既有截图就绪检查和屏幕冻结流程。
- 成功、失败与取消终态均可经公开路径进入同一安全分支；活动或启动中的请求返回“展示当前工作区”，未保存结果也返回同一保护结果，不会被新截图替换。
- 重复快捷键与 Try Again 的竞态由 actor 内的一次性准入位约束：第一个截图请求消费退让，后续旧会话请求不再启动模型；应用侧的身份检查丢弃已经过期的异步回调。
- 清除 live session 不删除历史或 PNG；如果后续权限、Provider 就绪检查或显示器冻结失败，影响只限本次新截图，已经保存的旧结果仍可从历史记录查看。故障不逃逸到其他历史、Provider 配置或存储。

## 【③ 安全正确性】

- 本轮不改变 ScreenCaptureKit 权限、内容过滤、PNG 字节、Provider 上传、Keychain 或文件路径。窗口先隐藏，避免 VLMSnapper 自己的结果内容进入触发时冻结帧。
- 活动请求和未保存结果不能绕过保护分支；用户内容不会因截图切换而被静默丢弃，也没有新增日志、诊断字段或敏感内容落盘。
- 所有异步状态写入继续在主 actor 或工作区 actor 上执行；没有新增未受控 Task 所有权、跨线程 AppKit 调用或 TOCTOU 快照判断。

## 【④ 一致性】

- spec 与 feature catalog 已补入同一现行行为：安全终态先隐藏再截图，活动请求和未保存结果保持置前保护；ADR-0010 的“冻结帧不含 VLMSnapper 自有界面”继续成立。
- 已确认的结果工作区普通窗口层级和冻结选区原型覆盖最终两个可见状态；本轮只修复二者间路由，不新增页面、控件、布局、样式或文案，因此没有修改原型。
- 按项目能力声明，i18n 已启用；本轮没有新增用户文案，两份本地化字典无需修改。图标和主题锚点也未改动。
- 新枚举和方法名称描述截图准入及隐藏顺序，没有重复条件级联、未用参数、跨模块霰弹修改或需要另开任务的重构项。

## 结论

四层审查未发现剩余阻断项。修复位于工作区 actor、应用入口和结果窗口控制器三个既有边界，覆盖了根因、并发保护与窗口可见性，不扩张 Provider、历史或截图像素职责。

---

# VLMSnapper v1 — Management Center capture and history-open review (2026-09-03)

审查范围：管理中心触发截图时的窗口退让，以及双击历史记录恢复结果工作区；不改变 Provider 协议、历史存储格式、截图像素或结果视觉布局。

## 【① 底层前提】

- 管理中心截图继续进入既有 readiness、权限与 ScreenCaptureKit 冻结路径；新增控制器 seam 只负责先 `orderOut` 并等待一个主 actor 调度点，不复制捕获逻辑。
- 历史恢复以 `StoredOperation` 和受管理 PNG 校验结果为唯一输入。保存的结果、操作类型、Provider/model 和目标语言用于展示；当前 Provider 配置只在用户后来明确重跑时使用。
- 单击选择和双击打开分别通过两个回调表达，避免把 SwiftUI `List` 的 selection 副作用误当作打开行为。

## 【② 可运行性】

- 管理中心触发截图时，窗口先隐藏，再调用既有截图入口；Provider 或权限尚未就绪时，后续既有逻辑仍会把首次引导带到前台。
- 双击历史记录异步加载记录和受管理截图，随后在主 actor 上验证最新 generation；较慢的旧双击结果不会覆盖较新的选择。
- 已存在结果工作区时，actor 内的原子 replacement reservation 同时阻止并发 Try Again 和第二次替换；活动请求或未保存结果保持原工作区在前台。
- 有效 PNG 允许用户明确 Try Again，并由新的历史会话创建新记录；PNG 缺失或所有权校验失败时只恢复保存文本，所有启动入口均禁用且应用层再次 guard。

## 【③ 安全正确性】

- 历史打开本身不构造 Provider runner，不调用 Provider，也不写历史。只有用户明确重跑且截图通过现有受管理文件校验后，图片才可能进入既有上传路径。
- 不可信或缺失 PNG 不以空图片上传：界面禁用 Extract、Translate、Try Again 和 Retry Save，应用入口也拒绝启动。
- 历史 `resultPersistenceFailed` 恢复为不可直接重试的失败展示，避免把没有待保存 payload 的只读历史会话误送入保存路径。
- 本轮没有扩大 Keychain、文件删除、日志或诊断边界，也没有把 Provider 原始错误或用户内容新增落盘。

## 【④ 一致性】

- 已确认管理中心原型、spec Failure Modes 25–26、`CONTEXT.md` 不变量、feature catalog 和实现统一为：单击选择、双击打开、打开不请求、截图前退让。
- 结果工作区继续沿用已确认布局；历史恢复只切换既有状态和按钮可用性，没有新增页面、文案、图标或颜色。
- 按项目能力声明，i18n 已启用；本轮没有新增或修改用户文案，两份本地化字典无需变化。
- 代码变化限定在应用协调器、会话恢复、两个窗口控制器和既有 SwiftUI 入口；没有顺手重构 Provider、存储或截图模块。

## 结论

四层审查未发现剩余阻断项。审查中识别并修复了结果工作区替换与 Try Again 的竞态、无控制器时的展示回退，以及历史保存失败状态不能安全 Retry Save 三个问题。

---

# VLMSnapper v1 — Inline Provider settings review (2026-09-04)

审查范围：设置中心内联 Provider 配置、首次引导跳转与自动返回、凭据直接替换、当前 Provider 切换/移除，以及活动请求期间的只读边界。

## 【① 底层前提】

- API Key、模型缓存、每 Provider 当前模型和全局当前 Provider 继续由应用级 `ProviderConfigurationCoordinator` 持有；SwiftUI 只持有展开项、Key 显隐和待验证编辑态，不复制持久状态。
- 首次引导只传递一次性的返回来源。Provider 配置仍在同一个管理中心窗口完成，模型选择与窗口关闭通过可消费一次的返回上下文收口，没有第二套 Provider 配置状态机。
- 新 Key 提交遵循 ADR-0012：旧 Key 与配置先失去资格，再获取模型和写入新凭据；失败不回滚。旧模型只在新列表仍包含它时保留。

## 【② 可运行性】

- 管理中心按显式目标、当前 Provider、DeepSeek 的顺序确定初始展开项；同一时刻只展开一张卡片，切换卡片只改变查看目标。
- Key 有非空改动时才显示并启用验证；未改动的已配置 Key 不会因 Return 被再次提交。验证成功后模型选择原位出现，显式选择模型才触发从首次引导来源自动返回。
- 活动模型请求通过协调器冻结 Provider 配置写入；卡片仍可展开和切换查看，Key、验证、刷新、模型、设为当前和移除操作保持只读，终态后恢复。
- 快速切换 Provider 时，异步 Keychain 读取前后都核对当前选择，较慢的旧读取不能覆盖新卡片的 Key。

## 【③ 安全正确性】

- API Key 仍只持久化到 Apple Keychain；本轮没有把 Key 写入 metadata、历史、日志、诊断、原型 fixture 或仓库。显示/隐藏只改变当前进程内输入控件呈现。
- 替换当前 Provider 时先清除全局当前选择；只有新配置最终可用且旧模型仍有效时才恢复。失败保持未配置，不会让请求继续引用已删除凭据。
- 移除当前 Provider 同时清空全局当前选择，且不自动切换其他 Provider。非当前 Provider 的验证和模型选择不会抢占既有当前 Provider。
- 并发配置变更与活动请求继续由 actor 内互斥状态拒绝；没有依赖多个异步 UI 快照推断锁状态。

## 【④ 一致性】

- 已确认管理中心与首次引导原型、v1 spec Failure Modes 27–31、feature catalog、`CONTEXT.md` 和 ADR-0012 对同一流程给出一致描述。
- 按项目能力声明，i18n 已启用；新增可见文案全部通过 `VLMSnapperStrings` 读取，英文与简体中文资源各 251 个键且集合一致。Swift 源码新增行未发现中文硬编码。
- 生产路由不再构造 `ProviderSetupView`；“所有生产界面渲染”测试也已移除旧独立页面。该类型仍被历史 Ticket 07 测试、终止 sheet 回归与 UI harness 引用，本轮按既有 dead-code 规则保留，不扩大为跨文件清理任务。

## 审查中发现并修复

| 问题 | 影响 | 修复 |
| --- | --- | --- |
| 只读状态同时阻止卡片切换 | 活动请求时无法查看其他 Provider，违背只读而非不可浏览的约定 | 只限制配置 mutation，允许 `selectProvider` 更新查看目标 |
| 已配置且未编辑的 Key 仍可由 Return 验证 | 隐藏的重复提交路径会无意替换凭据 | `canValidate` 同时要求验证操作可见，未编辑状态不能提交 |
| 卡片状态把“凭据已验证、待选模型”当作未配置 | 卡片徽标与 Key 状态混淆，用户无法判断下一步 | 拆分卡片状态与凭据状态，分别表达“待选模型”和“已配置” |

## 结论

四层审查未发现剩余阻断项。改动覆盖完整用户序列，同时保持 Provider 持久状态、页面状态和首次引导来源三类职责分离；没有新增未经原型确认的界面或越界重构。

---

# VLMSnapper v1 — Retired Provider component removal review (2026-09-04)

## 【① 底层前提】

- 对当前源码树执行全量符号与参数检索后，`ProviderSetupView` 只由 UI harness、Ticket 07 渲染和 sheet 终止回归引用；生产 App 已无构造路径。该结论不依赖抽样。
- SwiftPM 的 `VLMSnapperUI` target 按整个 `UI` 目录收集源码，没有需要同步删除的显式文件清单。
- `git log -S'ProviderSetupView' --all` 证明它是历史界面类型；没有数据库字段、settings 值、IPC 字符串或其他持久化兼容值与该类型绑定。

## 【② 可运行性】

- 管理中心仍需的 Provider 详情映射已迁入 `ProviderSettingsPresentation.swift` 并改名为 `ProviderSettingsDetailPresentation`，两个生产调用点与现行测试同步更新。
- 删除旧 View 后，harness 不再接受 `--provider`，Ticket 07 不再生成旧页面，sheet 终止回归只枚举仍存在的权限与隐私 sheet。
- 旧 `ProviderSetupMetrics`、五个专用字符串 accessor 和两语种资源键一并删除；完整编译能枚举所有 Swift 静态引用并已通过。

## 【③ 安全正确性】

- 本轮不改 Keychain、Provider 请求、模型配置、窗口路由或用户数据。被删除对象只包含不可达 UI、开发预览入口和相应测试 fixture。
- 现行内联页面的 Key 显隐、清空、验证资格、模型选择、当前 Provider 与移除确认均未删除；敏感信息边界不变。
- 删除不涉及动态反射或字符串构造的类型发现路径；当前树对旧类型、旧 metrics、旧输入状态和 `--provider` 的全量检索均为空。

## 【④ 一致性】

- 源文件、测试名、测试 suite、harness 参数、几何常量和本地化键全部从“Provider setup”旧组件语义收敛到现行“Provider settings”语义。
- 既有 spec、feature catalog、原型 manifest 和权威 README 已只描述管理中心内联流程；本轮删除不可达组件没有改变用户可见行为。
- 审查发现 Ticket 07 渲染目录未在运行前清空，旧 Provider PNG 会污染文件数量断言。已补上目录清理并由原始失败后重跑通过验证。

## 结论

四层审查未发现剩余阻断项。旧独立 Provider 组件及其专属依赖已完整删除，现行管理中心内联实现与覆盖未受损。

---

# VLMSnapper v1 — Ticket 19 inline Provider geometry review (2026-09-05)

## 【① 底层前提】

- 850 pt 内容上限、54 pt 卡片头、29 pt Provider 标记和 32 pt 凭据字段均可在已确认的管理中心原型中复现，不以实现常量或旧测试作为设计依据。
- `a97bd73` 的现行内联行为测试与严格构建虽为绿，但当时没有这四个几何约束；本轮把它识别为证据缺口，没有将旧绿误报为视觉验收。
- 全量固定字符串检索实际覆盖 `Sources`、`VLMSnapper`、`Tests`、`docs` 和 `Package.swift`；旧 UI 类型、harness 参数、专属 accessor 均为零结果，保留的 `ProviderSetupSession` 是现行领域会话而非退役页面。

## 【② 可运行性】

- Provider 页与 General Settings 分成两个同级内容分支；Provider 使用独立 `ScrollView`，因此 850 pt 内容可以居中而不再受 grouped `Form` 的系统 inset 和行背景支配。
- 模型列表为空时只展示凭据列；列表可用后，`ViewThatFits` 先尝试 400 + 14 + 400 pt 的双列布局，卡片正文可用宽度不足时确定性回退为 14 pt 间距的纵向布局。
- 正常与最小窗口的中英文、明暗生产渲染均已检查：正常宽度为双列，最小宽度为纵向堆叠，标题、徽标、输入和卡片边界无裁切或越界。
- 故障逃逸面：本轮只改变布局。尺寸回归最多自伤当前 Provider 页，不会污染其他 Provider 状态、请求或持久化；没有错误路径跨条目或上层逃逸。

## 【③ 安全正确性】

- 本轮不改变 API Key 值、验证提交、Keychain、模型列表或当前 Provider 语义；拆分出的字段方法继续使用原有 binding 和 action。
- 安全/明文字段、清空和验证按钮仍受同一只读状态约束；没有新增 secret 日志、持久化或跨 Provider 访问。
- 固定 400 pt 列宽只在父容器确认可容纳时生效；较窄容器走纵向分支，不存在通过裁切隐藏溢出的假安全路径。

## 【④ 一致性】

- 新尺寸集中在 `ManagementCenterMetrics`，并由生产 View 和独立 literal assertions 共同使用；测试期望没有从生产常量反算。
- Provider 页保持现有主题、圆角、边框、状态徽标和本地化入口，只修复原型已确认的信息层级与响应式几何，没有引入新的视觉方向。
- 坏味道复查未命中需要处理的新增项。字段方法拆分减少原函数长度，职责仍局限于同一 Provider 卡片，没有新增 speculative abstraction 或跨文件霰弹修改。

## 结论

四层审查未发现剩余阻断项。Ticket 19 的行为、退役表面和确认几何现在都有独立证据；Ticket 20 的原生 AppKit 凭据编辑器仍保持为后续票，没有被本轮顺带实现。

## 2026-09-05 — API Key validation regression review

### 【① 底层前提】

发现：普通配置中嵌套闭包 Binding 不足以使生产窗口的派生控件读取当前值。已用真实窗口、空/预填正对照和旧读值路径变异坐实。第一次仅提升 `@Binding` 的方案又被清空反向测试推翻，最终使用窗口 State 驱动所有字段控件。

### 【② 可运行性】

复查输入、粘贴、清空、Return、外部加载、清除和窗口 rootView 更新，公开交互测试全部通过。外部同步只改显示值，不触发网络或标记编辑。故障逃逸面为当前 Provider 卡片自伤；测试观察的提交内容与用户输入一致。同类实例全量检索 `Binding<`：同配置内另一条 pendingModelID 写入会调用模型选择并刷新配置；ResultWorkspaceView 和 CaptureOperationToolbar 的输入本身为动态属性。此次修复覆盖 API Key 所有读取点，未调整模型选择流程。

### 【③ 安全正确性】

只读判断、Keychain、网络提交和替换旧 Key 的时机未改。测试使用虚拟凭据和私有临时 pasteboard，不读取或输出真实密钥。临时调试输出已移除。既有异步加载/提交生命周期属于后续票，本轮不声称其已验收。

### 【④ 一致性】

字段、占位、清空和 Validate 共用窗口当前值；外部加载通过 onChange 同步。没有更改视觉层级、主题、图标、本地化文案或 API。测试的 AppKit 编辑路径与生产字段一致，不引入仅测试使用的产品抽象。spec/features 补充即时启用和清空禁用要求。范围外图标未做全仓穷举；本轮触及的字段图标仍复用既有 SF Symbols 锚点。

## Ticket 20 — 2026-09-06 whole-ticket review

Admission: Ticket 20 criteria are mapped to named cases in checklist.md before this review. Scope is the native credential field, standard Paste adapter, observable editor, submission/load identity, production dispatch and the native acceptance runner. Review is self-review, not an independent agent review.

### 【① 底层前提】

- The native secure editor must not be replaced. The earlier ordinary NSTextView substitution crashed while AppKit configured secure storage; no such substitution remains. Existing Paste actions are adapted only for the active Provider field, with public menu-tracking notification. Native context-menu tracking and selection replacement passed 10 fresh processes.
- Swift String equality is canonically equivalent, not byte equality. Credential dirty checks and field updates use UTF-8 equality; NFC/NFD is covered by baselineUsesExactBytes.
- The suspected shorter-value/visibility selection issue did not reproduce: AppKit clamps to the new end. The added real-field assertion passed without changing production code. No speculative clamp or causal claim was added.
- The previous 97-minute desktop automation stall is not diagnosed by this work. The bounded runner limits its own child and requires an explicit completion marker; it is not a claim that CUA is fixed.

### 【② 可运行性】

Lifecycle paths enumerated: loaded → edited/reverted/cleared; unloaded → loading → loaded; load → switch A/B/A or close; draft → submit → success/failure; pending → switch/return/close/reopen; closed failure → reopen/edit/remove; secure ↔ plain. Editor tests and real-window tests cover these public transitions.

The implementation slices found and fixed actual errors: reverted loaded values could resubmit; post-success Return could duplicate; provider-only read checks admitted stale A/B/A results; global pending state blocked another card's draft and let the first result overwrite it; returning to a pending Provider lost pending/terminal presentation; failures finishing while closed lost their candidate. Their deliberate red/green logs are indexed in the tasklist. After these fact-layer corrections, the safety and consistency layers were rechecked.

Failure escape surfaces: invalid input is local to its candidate and cannot delete a saved credential; network/storage validation failure is scoped to the submitted Provider; stale read/completion is ignored rather than polluting another card; UI-harness timeout fails the batch and kills only its spawned child. Startup Keychain errors currently collapse to missing in existing application reads: this is an acknowledged Ticket 21 requirement (FM-45), not fixed or certified by Ticket 20. Cross-Provider/capture admission remains Ticket 22 (FM-43/44), not inferred from same-Provider suppression.

### 【③ 安全正确性】

- Validate/Return share a synchronous claim with an immutable Provider/value. Actor-level duplicate suppression survives card changes; unique load tokens reject closed/obsolete visits. New session tests run the real configuration coordinator with only external model/storage boundaries controlled.
- Old baseline is dropped before replacement dispatch. Failed candidates are memory-only and released on edit/removal; window close does not cancel submitted work. Successful completion uses the coordinator result after storage publication. Process-exit/crash recovery is explicitly owned by Ticket 21.
- Empty/newline/over-4096-byte input is rejected in both presentation and coordinator before destructive replacement. Opaque whitespace and Unicode remain intact; no key format heuristics.
- All native test values are dummy data, pasteboards are private, no user key is read or logged. Production no-op mutations were restored exactly, not by resetting tracked files.

### 【④ 一致性】

All four ProviderSettingsConfiguration constructor consumers were enumerated: application model, native interaction tests, rendering tests and smoke harness. They now supply the same observable editor interface; no stale external apiKey binding remains in that surface. Native field, status, placeholder and actions derive from one editor. The fixed input owns no alternate Keychain store or network client.

The Paste exception intentionally replaces the former blanket statement that no field-specific adaptation exists; spec/features are updated together. Public native symbols, theme and approved geometry remain unchanged. Removal does not falsely clear the local editor when the coordinator rejects deletion. Keychain error wording/recovery is still 21.

Bad-smell review: the load/submission value types are narrow immutable identities, not speculative generality; per-Provider job/candidate maps are required by switch/close behavior. Shared native paste routing avoids separate keyboard/context implementations. No additional refactor or unrelated dead-code removal is proposed.

## Ticket 21 — 2026-09-07

Reviewed current coordinator/session, application lifecycle, editor/presentation and localization diffs after the scoped checklist reconciliation. This is code review, not installed-app or browser acceptance.

### ① Bottom-level premises

- Found and fixed: cancellation of an AsyncStream was not evidence of an uncancellable Keychain read finishing; the continuation-based public editor case reproduced the ordering fault. Only the canceled predecessor is awaited, not every credential job.
- Found and fixed: generic storage errors had been treated like Provider outages. The actual coordinator/session now classifies credential and metadata boundary errors without preserving raw descriptions. Apple `errSecItemNotFound` alone means absence; inspected the actual Security adapter, not a comment.
- Found and fixed: no-draft-change and read-only are not the same fact. The final production render showed the cleared write-error form losing Validate. Only one production presentation constructor supplies live editor state; the other is the no-settings fallback. Full Swift-root constructor search found no additional production instance of this conflation. The eligibility test genuinely failed before the two-line fix; before/after PNGs were visually inspected.

### ② Runtime and failure propagation

- Traced entry/exit for load, close, switch, A/B/A, submitted validation, detached recovery, explicit reopen, cancellation and application termination. Generation plus editor identity prevent stale read publication; recovery/validation belong to the app and reattach without resubmission. Physical Quit/crash acceptance remains a documented gap in the session test header.
- Retirement-save failure rejects before request and preserves durable original state. Failed retired-key deletion cannot become orphan-key authentication. Post-key publication failure retains a recoverable new generation; orphan recovery fetches a fresh full list rather than trusting journal models.
- Failure escape classification: per-provider credential errors mask only that provider's readiness and current reference; startup catches each provider's failure and continues the enumeration. A failure reading the shared metadata store prevents trustworthy aggregate readiness, so presentation fails closed without erasing durable metadata. The explicit all-provider reconciliation API propagates failure; production startup deliberately uses per-provider calls. Cross-workflow scheduling is Ticket 22, not silently accepted by these state tests.
- Final current-source strict/full/native and signed CRUD gates passed (v4 logs in tasklist). Rendering is the native view, not the HTML prototype.

### ③ Security correctness

- Rechecked after facts above: opaque-key local checks precede retirement; durable retirement precedes external authentication; known retired generation is delete-only, unrelated generation fails closed. Cancellation checks after delayed reads and before listing prevent late authentication.
- Secret-flow inventory: 117 matches / 13,027 bytes, hidden/ignored production Swift included. Followed metadata Codable types, atomic metadata encoder, Keychain encoder and application diagnostic construction. Metadata has generation/configuration, not candidate text. API keys reach their designated request headers and Keychain; new errors contain sanitized categories/status only. The diagnostic whitelist alone is not a secret detector; actual call-site values were checked. No secret values were read from the user's environment or logged during this review.
- Authorized isolated mutation reached both retired-key cleanup branches and failed at the injected no-network lister; exact restoration and rebuild passed. No rollback secret persisted; memory String zeroization is not claimed.

### ④ Consistency and bad smells

- Restored empty-validation behavior without changing approved geometry, icons, theme or edit semantics. Recovery/read-error wording is paired in both dictionaries. Existing context invariants and ADR-0012's accepted admission addendum remain consistent.
- The provider-indexed pending/failure maps and load identities have distinct lifetimes; they are required state, not speculative abstraction. Storage wrappers centralize error sanitization. Presentation switches distinguish card, credential and model-detail roles; no unrelated refactor or dead-code deletion is proposed.
- The previously reported prototype DS/OA/G letter marks remain assigned to Ticket 23's visual closeout; no unapproved icon change. Browser-preview policy remains a delivery gap, not a reason to invent a passed UI gate.

## Ticket 22 — 2026-09-07

Scope: owner-token activity admission, event-driven reconciliation waiting, shared production capture/rerun entry, cross-Provider exclusion and native active-job focus. All seven criteria were mapped to tests and evidence before this separate review. This is not Ticket 23 whole-feature review.

### ① Bottom-layer assumptions

- Fixed integration finding: an async protocol default returning no activity shadowed the actor's synchronous query at awaited call sites. The gate rejected work but UI/routing observed idle (same-layer escape into other cards and routing). Nine activity/routing assertions failed; removing only the default made the same 51 tests pass. Enumerated all protocol conformers in Sources, Tests and VLMSnapper: one production coordinator and three legacy test doubles. The production witness is mandatory; the three explicit nil test witnesses are not used for exclusivity cases. captureActivityLocksSession uses the real actor.
- Result-window update replaces content only; present activates the window. Activity observation uses update and cannot unhide retired sources or repeatedly activate streaming results.
- Read-only presentation is advisory. Coordinator admission remains before storage/model effects; a gray button alone is not exclusion.

### ② Runtime and lifecycle

- Fixed review finding: the rewritten native capture adapter discarded presentWorkspace without fronting an unsaved result. Restored its make-key/activate effect after workspace-identity validation, retaining no capture and release of the new lease. Instance-level omission, same-layer loss of recovery navigation. The shared model-active refusal already invokes its fronting effect. unsavedResultKeepsWorkspaceForCapture verifies the session preparation outcome; installed-app unsaved-window fronting remains a manual wiring gap, not a newly proved red/green test.
- Entry/exit audit: new capture acquires before readiness/native effects; failure releases; replacement failure retains the original owner; cancel closes selection before release; stale generations cannot commit an overlay or cancel its successor; selection-to-model transition keeps its lease. Model closures release on success/error, and cancellation of a superseded child run is awaited before outer release. Failure-alert retries release failed new ownership before showing the alert, without releasing a surviving selection.
- Recovery waits before credential read/list/publication. Cancellation resumes its waiter with CancellationError; release resumes registered waiters; reentry checks occupation again. Batched recovery publishes the current Provider. Observer termination removes its continuation. Test-only 30/50 ms probes and cancellation rescue are not production waiting; existing result-render polling is unrelated and retained.
- Credential errors keep their original Provider attribution; denied capture/rerun cannot mutate sibling history or workspace. Foreign/stale release is a no-op. Existing request-owned compatibility updates remain inside the running request, not user configuration controls.

### ③ Security and correctness

- Tested all five user mutation families under capture and model ownership: replacement, refresh, model selection, current selection, removal. Coordinator admission serializes them across awaits. ADR-0012 replacement/retirement semantics are unchanged.
- Cross-card editing does not permit submission. UI/session reject duplicates; coordinator rechecks stale callbacks. Fronting only responds to an explicit capture action, not an observer update.
- No real account requests, key logging, raw Provider payloads, broad deletion, signing or installed-app changes. History tests use isolated temporary SQLite and public history access.

### ④ Consistency and smell check

- FM-44's recovery-rejected sentence contradicted FM-46 and the ticket. Corrected spec/checklist to waiting and extended read-only statements to capture/selection; synchronized CONTEXT/features.
- Owner IDs and capture generations protect distinct boundaries: activity ownership and native replacement completion. CaptureEntryPoint enumerates two production entrances with identical policy. ApplicationWorkflow is used by production, not a test-only duplicate.
- No further refactor/dead-code cleanup proposed. Existing prototype icon followups remain with Ticket 23. Only paired localized lock wording changes, no geometry/theme/icon redesign.

## 2026-09-07 — Ticket 23 checklist gate increment only

This is a scoped review of the new command, its CLI tests, CI step and merge/status receipts. It is not the ticket's final review: combined application acceptance and full-feature reconciliation remain open.

### ① Bottom-level assumptions

The actual checklist contains both ownership and historical evidence tables. The initial whole-document ID scan wrongly counted the latter as duplicates (aggregate gate failure from unrelated rows). Fixed by requiring one named ownership section; the complete repository document is the positive control. Expected identifiers are the ticket's explicit 12+46 contract, not an inferred count of current input. Existing phase/status notes are preserved, with a new merge receipt.

### ② Runtime behavior

Six CLI cases pass, including missing/duplicate/unknown IDs, blank/malformed cells, absent/duplicate section and the real valid document. IO/encoding errors return nonzero. Every rejection fails the aggregate command intentionally; no mutation of the checklist occurs. Temporary fixtures are isolated and subprocesses have a ten-second bound. Duplicate ownership cannot disappear through conversion to a set.

### ③ Safety/correctness

No shell interpolation, network, credentials, app launch or installation. The executable takes an explicit input path and only reads it. GitHub Actions runs tests and the actual ownership command before build, under its fail-fast shell. The command accepts the repository's simple four-cell Markdown dialect; it is not a general Markdown parser or a semantic acceptance checker.

### ④ Consistency

Only this ticket's demanded gate and status receipts changed; no production or UI change. Standard-library Python matches the repository's existing script tooling. No new general framework or preexisting dead-code cleanup. Current source reveals a separate application-construction seam gap; proposal and affected paths are recorded in the Ticket 23 tasklist for user agreement, not silently refactored.

## 2026-09-07 — Application Model injection increment only

### ① Bottom-level assumptions

Direct executable-target import is now exercised by compiled application tests, not inferred from a package declaration. The Model retains real editor/session/coordinator, parser, files and SQLite. Only external adapters are supplied by tests. Live construction remains on the production initialization path after primary-instance ownership. A passing Model callback test is not evidence of native input, delegate window routing or OS termination delivery.

### ② Runtime and lifecycle

Found and fixed an instance-level regression in this increment: unregistering during termination preparation affected the separate update-install attempt path (same-layer escape into a still-running app's shortcut). Enumerated all production preparation call sites: quit, update installation, and delegate termination. Preparation now preserves registration; final `stop()` releases registration and cancels scheduled cleanup. The corrected expectation failed against the interim implementation and passes after moving release. Repeated stop is covered. Actual OS callback delivery and teardown during suspended external work remain acceptance gaps under Ticket 23, not certified by this fixture.

Validation success, 401/500 failure, manual retry, model selection, completion notification and reconstruction run through real Model callbacks. Failures remain attributed to the submitted Provider; the single-Provider fixture does not certify cross-Provider exclusion. Update-event publication and permission/retention adapters have additional regression cases. On success and thrown test failure, fixture preparation/stop precede temporary-state removal.

### ③ Security/correctness

The dependency constructor requires all external adapters without partial live fallbacks. Fake implementations live only in the new test target; production's factory uses existing Keychain, HTTP, ScreenCaptureKit, login, Sparkle and shortcut adapters. No runtime environment switch or dynamic injection mechanism is added. The same credential store is shared by configuration and operation streaming. Tests use synthetic keys, UUID paths and isolated defaults suites; no installed app or real account is accessed. Streaming and screen capture are intentionally rejected by this setup fixture, not exercised successfully.

### ④ Consistency and smells

No target/source split, main.swift, schema, Keychain identity, entitlement or visual redesign. The dependency bundle groups external construction rather than replacing internal business modules; update/shortcut factories preserve lazy creation. No unrelated dead-code cleanup or new DI framework. Spec and tasklist distinguish approved construction from pending full native acceptance. The stale current-evidence paragraph was updated to describe the new target. No additional refactor proposed in this scope; remaining integration work stays in Ticket 23.

## 2026-09-07 — Delegate/native increment only

### ① Bottom-level assumptions

Two test assumptions were false in this runner: a visible window initially had a zero-sized hosting view, and the SwiftUI popup button had no action although its menu items did. Measured native geometry/render and inspected public controls before changing test input. Production layout and routing were not altered to satisfy those assumptions. The actual delegate now receives startup boundaries; its model factory is invoked after the real POSIX lock. A secondary-start test checks that the factory is not invoked again, not merely that the second model does not register a shortcut.

### ② Runtime/lifecycle

Enumerated affected paths: primary startup creates one model/menu, secondary returns to launch's termination branch, startup errors still terminate from the launch wrapper, ordinary termination prepares before final stop, update preparation remains distinct. Final stop closes owned windows after clearing onboarding return context, removes the status item/monitors, releases model and primary coordinator. Closing during cleanup therefore cannot reopen onboarding. Primary lock reacquisition and single registration are exercised; OS launch notification/actual process exit are not simulated as a success claim. Explicit fixtures restore the prior main menu and remove only UUID temp data/suite.

Validation/freezing suspension uses external adapters, not a second coordinator. Positive terminal controls demonstrate both adapters can be reached after exclusion. Failure escape is confined to the single fixture: suspended operations are released in cleanup; capture release is latched so a late entry cannot wait forever after cleanup. In-flight delegate shutdown remains a separately recorded Ticket 23 gap rather than a proved race-free path.

### ③ Security/correctness

Startup dependencies contain root, defaults, messaging and a lazy factory, with the production default using original implementations. No test switch, private API, TCC reset, real HTTP/Keychain read, installed application replacement or identity change. Native secure input uses a synthetic key. The lock is real but temporary, and messaging cannot activate the installed app. Window enumeration is scoped to the test process and identifies the onboarding hosting type; configuration is driven through the actual production view. Programmatic events are not physical-device delivery evidence.

### ④ Consistency

`main.swift`, UI geometry/colors/text, resources and signatures are unchanged. The only UI-controller addition is final status-item disposal; existing hide behavior removes monitors. Production launch still applies accessory policy before startup; direct tests exercise startup, not that OS launch callback. No new general router or DI framework. CI's complementary skip/filter invocations include every suite while separating process-global AppKit/localization mutations; neither half alone constitutes full verification. Spec and tasklist now identify the native path and freeze-only boundary accurately. Icon choice remains owned by Ticket 23; no new icon surface was introduced or broadly audited here.
## 2026-09-08 — Native menu/closed-window increment review

- 【① 底层前提】A native field being editable did not imply key-window ownership. The new menu case explicitly waits for the real `NSApp.keyWindow` and invokes the installed Edit item, not a replacement responder. `finishLaunching()` was not necessary in a counterfactual probe and is absent. XCTest methods are run in separate processes: combined native methods aborted, and prior Swift Testing activation experiments exited without completion. The runtime root cause is unresolved; explicit completed-test reports and process isolation are the gate, not a claim of a product fix.
- 【② 可运行性】Enumerated clipboard creation/live default/use/release; native activation success/rejection/throw restoration; fixture start/operation failure/success teardown; paused response release on success/failure. Shared fixture optional unwrapping now throws independently of the testing framework. Both `withModel` and `withApplication` previously could skip `stop()` when preparation returned false; both now stop before throwing (same-class cleanup escape fixed in both helpers). This only disposes isolated test resources, not production update-preparation semantics. Capture regression timing sensitivity remains tracked in #23 rather than hidden by its later pass.
- 【③ 安全正确性】Live startup supplies the unchanged general pasteboard; only tests supply a unique pasteboard and release it. No real key, HTTP, Keychain or desktop pixels are read. Vision recognizes only an in-process fixture onboarding render, without saving its image. No application callback is forged; native event pumping processes AppKit events. Temporary probes/mutations are removed precisely, with no production overlay/menu behavior diff.
- 【④ 一致性】No user-visible product behavior changed: startup simply forwards the existing menu-builder clipboard dependency. Accordingly no feature sentence becomes false and no user-visible feature sentence is missing from this increment; #23 still requires its separate full-feature closeout. CI covers existing non-App/App groups and each native XCTest method explicitly, with an outer timeout and nonempty completion check. Physical input, visual parity and untested failure/cancellation variants remain out of this increment's evidence. Small native-fixture helpers are shared rather than copying production routing. RTL mirroring is not enabled by the project capability declaration and is skipped.

# Ticket 23 scoped review — 2026-09-08 capture/rerun/recovery tests

## Subsequent scoped review: pending-validation close/reopen

- 【① 底层前提】The attempted Paste case had an editable real field and readable isolated clipboard but no `NSApp.keyWindow`; accessory policy and explicit activation did not establish it. A global event-dispatch experiment exited 0 without a test-completion record: rejected as false green. Accessibility terminal-label probes also failed against unmodified behavior. These experiments and unused clipboard injection were removed; no production cause is claimed.
- 【② 可运行性】The retained case pauses external model-list HTTP, inserts text through the native editor, clicks the rendered Validate action, closes via NSWindow, reopens through the actual onboarding action, observes the same candidate disabled, then releases HTTP and observes editable text/model choices. Delegate fixture cleanup now releases both suspended external adapters on success and throw before normal preparation/stop, preventing a fixture-owned waiter from escaping into another test. Normal and exceptional cleanup branches were both exercised by green and candidate-loss mutation runs.
- 【③ 安全正确性】Retained changes do not read the general clipboard or real credentials, dispatch arbitrary application events, change activation policy, or modify production Provider behavior. Only synthetic text and isolated temporary adapters are used. Production mutations were exactly removed; the editor file has no diff. No private state or fake responder is used.
- 【④ 一致性】The test was renamed to explicitly say reopen while response is pending. Waiting on credential persistence alone was too early to prove closed-window callback completion, so that claim remains Pending in the spec and tasklist. Actual main-menu Paste also remains Pending with its environment prerequisite. No user-visible behavior changed in this increment; feature-wide review still remains required for #23. According to project capability declaration, RTL UI mirroring is not enabled and that check is skipped.

This reviews only the current test increment, not full Ticket 23 completion.

- 【① 底层前提】Found and corrected a test-only assumption: rendered SwiftUI Run Again is not an `NSButton` in the observed native view tree; the only native button was Copy with an empty title. A fresh production render established the mouse hit point. Synthetic frames use observed screen geometry but contain only generated white pixels. HTTP fixture shape follows the existing recorded DeepSeek chat contract (delta content, finish_reason, usage, DONE), retaining production decoding. No claim of real-provider or accessibility acceptance.
- 【② 可运行性】Real shortcut → overlay → toolbar → request → saved history → rerun paths executed. Terminal completion wakes an actual waiting recovery. The HTTP fixture rejects unexpected or overlapping image requests; teardown releases suspended response/capture continuations, prepares/stops the Model, and hides only windows created within the fixture. Previously title-based lookup could fail this case itself (self-contained test failure); fixed before reviewing upper layers. Deadline errors now carry call-site file/line instead of an unlocatable timeout.
- 【③ 安全正确性】No real secrets, screen pixels, global shortcut registration, login service, system permission request, update network or installed-app mutation. Fake key enters only the isolated credential adapter; generated PNG and real SQLite remain in the unique temporary root. Public AppKit view/window operations do not access private application members. Temporary mutation/debug output was removed and both production files restored.
- 【④ 一致性】No product behavior or visual change in this increment; spec Testing Decisions now reports the increased but still partial coverage. Existing-current-history identity and non-current Provider not stealing selection are asserted. New fixture-only helpers are narrow; geometry coupling is intentionally limited to the English one-line fixture and does not count as bilingual layout acceptance. Full feature review remains open under #23. According to project capability declaration, RTL UI mirroring is not enabled, so that check is skipped.

## 2026-09-08 — Refresh A scoped implementation review

- 【① 底层前提】Confirmed through public-session red tests that model refresh reused the credential-validating phase; returning to that card additionally cleared its cached presentation. Native rendering confirmed a separate lock row and conditional footer actions were the geometry-sensitive consumers. Refresh now preserves configuration phase, exposes separate transient progress, and stores ordinary refresh feedback per Provider.
- 【② 可运行性】Reviewed start, duplicate, cross-card, return, success, removed-model and ordinary-failure/manual-retry paths. The real coordinator owns persistence and its lease; delayed completion applies only to its Provider and does not override a recorded credential-read failure. Existing storage/authentication error categories remain separate, not converted to the retained-cache network message. Failures are Provider-local, with other cards' drafts still editable and mutations globally blocked.
- 【③ 安全正确性】No credential format, Keychain permissions, HTTP endpoint, persistence schema or production injection default changed. Tests use fixture keys and isolated adapters. Refresh does not call the replacement-key path, so the destructive replacement policy is unchanged. Existing capture/model-request locks remain enabled; hiding the banner does not remove admission checks.
- 【④ 一致性】Refresh progress and ordinary failure are no longer credential status. Reused semantic colors, native spinner and existing disabled behavior; added matching source-language/English strings. Render review caught a fixture with an unconfigured current OpenAI and corrected it to a reachable configured state. No new dependency or reusable abstraction. Existing DS/OA/G prototype marks remain assigned to Ticket 23's visual consistency item rather than being copied into native UI. According to project capability declaration, RTL mirroring is not enabled and that check is skipped.

This is the Refresh follow-up only. Installed-app Refresh clicks, signing/packaging and the feature-wide Ticket 23 closeout are not claimed.

## 2026-09-08 — Visual alignment VA-01–04 scoped review

- 【① 底层前提】The existing native model picker measured 24 points high and 143 points wide with the short model fixture, despite an enclosing row frame. The new regression failed on those actual native bounds before replacement. Confirmed prototype geometry requires a 32-point stretching control and 128-point Refresh. Initial English onboarding rendering clipped the footer at the old 760×540 size; adopting the confirmed 900-point shell (604-point content, excluding its simulated title bar) and compact status badges makes the footer visible. These are observed render/geometry failures, not compiler failures.
- 【② 可运行性】Reviewed all changed view builders, the new native picker/coordinator, its selection binding and disabled state, two-field layout, shared button style, icon vector, bilingual strings and test locator. Refreshed model IDs replace native menu items; unavailable selection uses the existing placeholder; disabled actions do not submit. Existing application validation→model selection→return and closed-window completion pass. The isolated main-menu case initially timed out at `NSApp.keyWindow === management`, before Paste; unchanged independent rerun passes. This establishes intermittent focus acquisition, not its root cause or stable desktop acceptance. No focus workaround or timeout relaxation was introduced. Track that remaining acceptance in Ticket 23.
- 【③ 安全正确性】No Keychain, credential admission, HTTP, capture, database, or production dependency defaults changed. Fake keys and externally controlled HTTP are isolated in the existing test fixture. The new picker updates the existing public binding, not persistence directly. Removal still requires the existing confirmation and admission checks; the transparent style does not bypass them. No real API call, installation, signing-identity access, or release was performed by these tests.
- 【④ 一致性】Source contracts and 20 fresh affected surface renders (onboarding plus normal/minimum Provider and History, both languages/appearances) reviewed. Five additional Refresh state renders sampled; not a claim that all 24 were manually rechecked. Colors and interaction states live in the theme; new shared style has four call sites, all within these confirmed actions (`rg SetupActionButtonStyle VLMSnapper Tests`). The brand vector follows the confirmed shape. Existing SF Symbols remain, with prototype DS/OA/G choice outside scope and tracked by Ticket 23. A stale CONTEXT sentence saying models always appear below the key was reconciled to wide-side-by-side/narrow-stacked behavior. No new architecture decision or reusable framework is needed; the two-child Layout remains local to Provider fields. RTL mirroring is not enabled per project declaration and is skipped.

Evidence limit: native view renders exclude real title-bar/occlusion and physical hover. The blocked local HTML browser preview was not bypassed. These checks close the four implementation differences against the confirmed source contract, not the full feature's visual/interactive acceptance. No additional production bug was established by the scoped review.

## 2026-09-08 — Test-owned native lifetime correction

Final fact-layer correction: broader App verification exposed two exit-0 incomplete runs, despite the native-only ten rounds passing. A temporary exit stack points to Swift async-main drain. Removing only the new release wait's nested RunLoop restored the 11-test completion; final polling uses autoreleasepool + the existing async yield. This was an upper-level test-runner escape introduced by this increment and was corrected before delivery. CI also checks completion reports, rejecting those archived incomplete runs. Upper safety/consistency layers were rechecked: no production or installed-app mutation, no deadline relaxation, and the existing native event helpers remain unchanged.

- 【① 底层前提】The same-process XCTest baseline aborted after Paste passed. An autorelease pool around stop alone did not fix it. Snapshotting windows before stop, detaching their hosting content, and awaiting actual weak adapter release form the retained correction. A reduction without content detachment passed with deinit logging but aborted on the first uninstrumented repeat; that reduction was rejected. Earlier instrumentation observed all three real coordinators deinitializing with a current Swift Task. Final repeats must run without that production instrumentation; no claim that an async XCTest declaration alone controls later AppKit release.
- 【② 可运行性】Enumerated both fixture owners (`withModel`, `withApplication`) and both exit branches in each; all four call the same stop helper. Only windows absent at entry are detached, inside the serialized native-test environment. Normal Paste, closed/reopened settings, explicit thrown operation and cancelled operation with paused HTTP are exercised. New weak lifetime checks can fail rather than retain objects until process exit. Review found cleanup exceptions masking the original operation error (self-contained diagnostic loss); fixed by reporting both. Cleanup runs in an awaited independent MainActor Task so cancellation does not bypass its existing five-second bound. Strong-retention fault injection confirmed deadline failure for ordinary and cancelled exits, not a silent green or infinite wait. Historical runtime abort is an upper-level escape affecting the entire test process; this correction is test-only, not a production compatibility fix.
- 【③ 安全正确性】No production deinitializer/isolation, permission, credential store, real HTTP, installed binary or user window is modified. The new case types a synthetic key into isolated controls and pauses the fixture HTTP adapter. Pre-existing window content identity is checked after both error paths. View detachment occurs after production prepare/stop and after the operation's assertions, not as a shortcut to passing application behavior. The test-owned weak wrapper observes an external adapter lifetime; it does not expose or mutate private coordinator state.
- 【④ 一致性】No sleep, longer deadline, assertion weakening or retry-on-failure. Middle-Man exemption: the small forwarding adapter provides a unique lifetime identity per real coordinator while existing shortcut simulation remains shared within the fixture. Temporary strong retention and production deinit logging are removed. CI gains a same-process native suite in addition to existing isolated cases, requiring nonempty XCTest completion and process success. No feature/spec UI behavior changes in this increment: no feature sentence becomes false and none is missing. Full Ticket 23 closeout, historical focus deadlines and actual installed-app acceptance are not inferred from these results. i18n is enabled but no product strings changed; per project declaration RTL mirroring is not enabled, so that check is skipped.

## 2026-09-09 — Live display reconfiguration (scoped follow-up)

This review covers only CaptureDisplayMonitor, its required composition dependency, application selection wiring, per-display overlay retirement and their tests. It is not the unfinished full Ticket 23 review or a passed delivery gate.

- 【① 底层前提】Confirmed Apple documents `NSApplication.didChangeScreenParametersNotification` as a main-actor configuration notification with no geometry payload. `NSWorkspace.screensDidSleepNotification` must use the workspace notification center; production does so. Geometry is read from the active NSScreen set and excludes sleeping displays. Injected center tests establish application delivery/handling, not actual OS hardware notification timing; two-display unplug/scale/focus acceptance remains in issue 01. No assumption that a visible window is key: the full native gate exposed precisely that gap again in #24.
- 【② 可运行性】Found and repaired an instance-level registration gap: the first geometry read preceded an actor hop and observer registration. A queued external snapshot test was red before the second read; registration followed immediately by re-reading on MainActor now covers that interval without sleep. Traced all touched entry/exit paths: first freeze and replacement revalidate; failed replacement preserves the old monitor/session; successful replacement switches generation before cancelling the old actor; changed panels are retired synchronously; all-invalid cancels/releases; crop success, Escape, termination and final stop unsubscribe. Affected-display errors are self-contained; cancelling unaffected displays would be same-level escape and is avoided. Pending-freeze termination guards are inspected but do not have a new controlled integration test in this increment.
- 【③ 安全正确性】Both async invalidation and crop completion check session identity and generation before touching UI. Native hit targets and the presentation geometry map are removed before the actor hop; old geometry never re-adds an invalidated frame. Enumerated production `applyCurrentDisplayGeometries` callers across Sources/VLMSnapper: the post-freeze check and active-notification path are both accounted for. No new provider request, screenshot capture, credential read, diagnostic content, privilege, storage or retry path is introduced. Completion/termination behavior uses existing lease ownership rather than releasing unrelated work.
- 【④ 一致性】US-03/ADR-0010 remain the authority: per-display invalidation, no mid-session additions, no live recapture. UI admission is the already-required lifecycle, not a new panel/design; no style/copy/icon changes. Bad-smell review: two geometry maps serve distinct synchronous native-hit-target and asynchronous crop-resource boundaries; keeping ordered panels plus an ID index preserves existing key-panel ordering while supporting targeted removal. No speculative protocol or dynamic fallback to real test IO. No extra refactoring proposed. Project i18n is enabled; no copy changed. Per capability declaration RTL mirroring is not enabled and is skipped.

The first/second snapshot correction was rechecked against generation, replacement and cancellation guards after the fact-layer fix. Strict build and the App/non-App suites pass; the native key-window failure means the overall gateway is still red. No PR, install or full-ticket closure.

## 2026-09-09 — Provider identity marks (scoped follow-up)

- 【① 底层前提】Confirmed prototype has DS/OA/G. Its later provider-name span
  selector overrides the logo font size/color to 10px and tertiary gray; retained
  weight 800, 29px square and radius 8. Native implementation follows that cascade,
  not the earlier 11px/accent declaration. Browser unavailable: Mac locked.
- 【② 可运行性】Strict build exit 0; fresh production renders show all three marks.
  Static exhaustive ProviderID switch introduces no jobs, callbacks or lifecycle.
  Render inspection: zhHans-light-1200-idle, zhHans-dark-1200-idle,
  en-dark-920-busy, en-light-920-failed in the temporary Provider render directory.
- 【③ 安全正确性】Only static display identifiers; no credential access, network,
  persistence or new interactive control. Mark is accessibility-hidden while the
  adjacent localized full Provider name remains; existing card button unchanged.
- 【④ 一致性】Central icon module and theme own appearance. Explicit user approval
  for prototype monograms is a narrow exception, documented in spec and module.
  Existing generic SF Symbols remain. No refactoring items introduced. All three
  ProviderID cases checked through the exhaustive switch and rendered cards.
  No new class names; pre-edit source search found no ProviderIdentityMark.
  This pass did not exhaustively audit unrelated character-icon carriers.
- Regression boundary: 333 non-App tests pass. App suite 14 tests / 1 failure at
  capture-toolbar wait (ProviderApplicationTests.swift:321), exit 1, retained in
  /private/tmp/vlmsnapper-provider-marks-app.log. No rerun, no claim of full green.
  Live native focus suite not attempted on the locked desktop. Ticket 24 remains.

## 2026-09-09 — Ticket 23 continuation: scoped semantic audit

Scope: closeout documentation and the connected history-filter/display-notification
paths. This is **not** the final review of all accumulated dirty implementation files.

- 【① 底层前提】Found: prior ticket completion and 58 ownership rows did not
  establish the entire US-10 workflow. Five query dimensions have no native
  control path. Separately, the display ticket's opening description was stale:
  production now calls session invalidation and registers AppKit notifications.
  Corrected current bookkeeping; historical comments retained.
- 【② 可运行性】History query entry points in the application use the default
  query; the native view predicate implements kind/search/pinned only. The missing
  dimensions affect history discoverability, not proven data loss or mutation.
  All five optional dimensions were enumerated from HistoryQuery and checked
  against the SQL builder and native state/toolbar/predicate. Their shared UI
  omission needs a confirmed layout before implementation. Display hardware
  behavior remains unverified; injected callbacks are not physical acceptance.
- 【③ 安全正确性】No production behavior or secret-handling changes in this
  continuation. The audit does not access stored API keys, real screenshots or
  external Providers. No history migration/deletion proposed. Broader production
  security review remains pending rather than being inferred from this scope.
- 【④ 一致性】Corrected ownership/current-checkpoint drift and added the missing
  feature index. Spec requirements remain intact; the confirmed prototype does
  not yet cover the five additional controls. The discrepancy stays owned by #23
  pending user direction. No speculative abstraction or adjacent cleanup.

Detailed source evidence and recommended acceptance: `23-history-filter-audit.md`.
The independent final code-review task remains unchecked.

## 2026-09-14 — #25 历史 UI 同步审查

范围为当次历史工具栏、行元数据、选择协调、窗口会话和补齐的 Provider 布局/菜单组件；不冒充累积工作区或全 feature 审查。参考 0febbb48fcd9acccdefc67dc9015ebf92605511c + 未提交修改。

- 【① 底层前提】发现当前 Provider 视图引用的 ProviderFieldLayout / ProviderModelPicker 定义缺失，授权构建明确报错；补齐这两个依赖，不撤销已有 Provider UI。原型确认只作为设计依据，不当作 App 证据。严格构建还检出了菜单 Coordinator 缺少 MainActor 声明，已补齐并在 strict-build-fixed 日志中验证。
- 【② 可运行性】关闭后原 HostingController 保留查询，queryWindowLifetime 明确红过；改用 sessionID 重建 SwiftUI 状态，保留宿主视图身份，关闭后新会话、截图隐藏同会话两路径及 Provider 草稿关闭回归通过。选择原图异步回调存在跨记录污染风险（同层逃逸）：选择时清空旧图，加载成功/失败均核对当前 ID，视图同时检查图片身份。静态路径已修正，受控乱序实测仍缺，不将此条标为完整验收。单击/导航测试失败在处理真实 AppKit 激活事件后仍存在，暂未坐实是产品还是合成输入；试验性手势变更无有效通过证据，已只撤销这些试验，不改变生产焦点规则。
- 【③ 安全正确性】Provider 筛选只消费传入的本地历史，无网络、Keychain 或数据库写入；不读取用户真实截图/Key。菜单候选为缓存模型 ID；禁用状态传递给原生控件。图片旧结果身份保护适用于成功及失败两条回调。未改变文件所有权规则。残留竞态实测由 #25 继续持有。
- 【④ 一致性】完整枚举新文案三项，中英字典和调用一致，历史“提取”不改截图/结果页“提取文字”。类型/状态使用动态系统语义色，区域日期继续 .formatted。Provider 字段并排/堆叠复用同一布局，无新生产测试开关。类级会话影响复查 Provider 关闭/重开及截图隐藏两种使用者，专项四例通过。未顺带删除旧查询模型字段或重构既有手势。

未完成项有明确归宿：#25 保留鼠标组合、图片乱序和完整原生验收；#24 保留原有焦点/等待诊断。未开 PR、未将门禁失败解释为通过。

## 2026-09-14 记录栏视觉对齐自审

范围：ManagementCenterView 的历史列表/行呈现、Theme 的历史专用配色及其测试适配；不重审本分支其他既存改动。

- 【① 底层前提】发现并修正：List 的默认行布局并不等于声明的 row inset，实际原生 PNG 显示额外缩进；改为原生滚动列表。原型列宽包含 1pt 分隔线，内容应为 259pt，非 260pt。PNG 带显示器色彩描述，直接比较未转换 RGB 会误判颜色；已按 sRGB 核验。
- 【② 可运行性】最终构建及四项定向测试通过，包含 8 个实际原生渲染与鼠标事件选择。发现 HStack + Spacer 的两个 10pt spacing 会把最小日期间距扩大为 20pt，已改为单一 10pt 最小间隔并复测。选中背景优先于 hover；过滤、关闭重置和临时隐藏保留由生产窗口回归覆盖。实际 hover、键盘焦点和组合交互仍未完成验收，不能推断通过。
- 【③ 安全正确性】未改变 Provider 请求、凭据、图片路径、持久化或删除逻辑；测试只用隔离记录。列表 Button 仍仅更新选择，既有双击 callback 本轮保留。没有自动网络调用或更广的数据逃逸面。
- 【④ 一致性】原生 SwiftUI 实现视觉契约而非嵌入原型；同一个 historyContent 覆盖 History/Pinned/筛选结果，未复制多套样式。专用颜色避免系统强调色改变已确认视觉；既有主题其他调用不受影响。spec 的 AC-13/15/16 与 features 同步。没有新增需跨文件重构的抽象；无另行删除既有 dead code。

结论：本轮发现均已修复；交互验收缺口记录于 25-history-row-style.md，不将编译/渲染通过等同全量原生验收。

## 2026-09-14 记录栏视觉对齐自审

- 【① 底层前提】原生 List 的额外行缩进由实际 PNG 坐实，替换为原生 ScrollView/LazyVStack/Button；原型260列宽包含1pt分隔，内容259而非260。截图带显示器ICC，先转sRGB再比较，不能直接读原始RGB。
- 【② 可运行性】修正 HStack + Spacer 造成最小时间间隔20而非10的问题；最终构建、单击选择、Provider筛选、隐藏/关闭恢复、8组渲染通过。选中背景优先hover。组合交互无完成摘要，实际hover/键盘尚未验收，不推断通过。
- 【③ 安全正确性】没有改变请求、凭据、图片路径或持久化；测试用隔离记录。保留本轮前既有双击callback，不自动请求Provider。无跨记录数据副作用。
- 【④ 一致性】History/Pinned/筛选共用一份行呈现，无复制实现；历史专用明暗配色与系统强调色独立。spec AC-13/15/16、features已同步。不涉及架构或领域变更，无新增重构建议。

证据与未验证边界见25-history-row-style.md。视觉实现完成不代表全量原生交互验收。

## 2026-09-15 历史详情重试（本轮增量自审）

- 【① 底层前提】历史重跑创建新操作、当前工作区重跑复用身份是不同语义。本次复用生产 runner/session，但每次历史重试创建新 runner；原 PNG 经存储所有权及哈希重新验证。测试通过外部 HTTP、真实 SQLite 验证，并读取生产详情渲染证明成功文本实际可见。Provider phase.ready 比应用 readiness 先传播，测试改为等待实际按钮 allowsStart，不修改生产配置规则。
- 【② 可运行性】首次选中未触发图片加载会永久禁用重试，补 initial 回调；观察任务在 actor 返回后检查取消，避免终态被迟到进度覆盖。同步 isRunning 挡重复点击，应用级工作流挡配置冲突。发现未保存结果的源记录可被删除（同层逃逸：恢复入口消失）；已保护该记录，并对同类入口逐一检查：单条删除、清空历史、手动保留期清理和每小时自动清理。后两者暂缓；启动清理先于任何历史重试，不受本轮状态影响。
- 【③ 安全正确性】不读取真实 Key，不添加模拟启动入口。请求前保存新截图和数据库准备记录，原图替换测试无新增 HTTP。SQLite 触发器制造真实完成写失败，本地 Retry Save 恢复后 HTTP 总数不增；失败不自动请求、不覆盖旧记录。应用退出取消任务或确认未保存结果；该确认框的安装版交互未在本轮验收。
- 【④ 一致性】沿用顺时针 SF Symbol、既有中英 Retry/Retry Save 字典、主题色，三个标题按钮盒统一 30pt；失败时保留旧文字，成功时不把旧耗时冒充新结果。新入口不删除原双击功能或改变默认窗口大小。当前 spec AC-07–09、功能目录、CONTEXT、原型适用范围与映射已同步。未发现本轮必须执行的额外重构。

验证边界和全套测试未完成记录见 25-history-retry-verification.md。本自审不抵扣物理鼠标验收或全 feature 收口。

同层逃逸复审补充：仅保护源ID仍允许迟到的清空确认删除待保存的新操作，之后Retry Save无法恢复。已先让负测在保存成功断言上红，再改为请求中/待保存时暂停全部历史删除和清理（共用应用入口，UI保留禁用）；源ID和新操作ID均被保护。最终16项应用/初始详情回归退出0。

## 2026-09-16 AX 输入同步修复

- 【① 底层前提】标准 AX 写值不等于文本 delegate 通知。前轮外部观测与通知校准支持此归因；本轮不在 Runner 合成通知，而在两个原生字段标准 setter 连接生产 binding。新类仍保留 NSSecureTextField / NSTextField 身份。
- 【② 可运行性】类级问题：该输入组件包含密码/明文两实现，均已修复并分别通过外部 AX → Validate → 精确值回调。当前活跃、可编辑且非隐藏字段才接受写入；有系统编辑器时写入与后续编辑一致，切换显隐及程序载入不产生编辑。闭包弱引用 owner，无新异步任务/订阅或生命周期竞争。故障影响为本卡片输入自伤，没有跨 Provider 写入。
- 【③ 安全正确性】仅标准字符串写入，不改安全字段读接口、不记录值、不绕过 editor 的本地输入校验、提交互斥或 Keychain 边界。无真实 Key 或真实网络；只读/隐藏负测通过。拒绝的变异未执行；正式保护仍在。无自动提交或主动激活行为。
- 【④ 一致性】两段相同 setter 是 AppKit 两个基类所需的薄适配；检查与更新合并在 owner 一处，不引泛化框架。UI 几何、文字、图标均不改，沿用原型；图标模块既有明确批准的 Provider 字母标识不在此次范围，本次未对全项目图标做穷举。未发现需另开重构的本次新增问题。

本轮全量失败和安装边界见 [验证记录](ax-input-sync-verification.md)；不等于 #24 或全功能收口。

## 2026-09-16 Provider 旧坐标用例替换

- 【① 底层前提】旧测试的按钮坐标已经过单变量复现确认不再命中，尤其不能继续用同一空白位置的负向断言充当禁用验证。现行测试接入固定授权的外部 AX 客户端，fixture 从当前源码重建；不复用 PoC 产物。实际两尺寸、两初值、两显隐组合均通过。
- 【② 可运行性】真实 ManagementCenterView / CredentialEditor / 字段保留；fixture 仅替换公开网络/存储提交终点，快照更新维持同一 hosting controller。Runner 检查唯一 selector、前台不变和正常清理。丢弃结果分支先由独立标题确认到达，再在最终效果断言失败。测试 fixture 90 秒自退，调用器 180 秒超时；不强杀用户 App。
- 【③ 安全正确性】独立 bundle ID、仅固定非秘密测试值、不打开生产数据/Keychain/网络、不移除生产字段保护。报告门禁用显式异常而非可被 python -O 移除的 assert；非预期阶段/原因、漏步骤、子进程退出码不符或清理失败均阻断。正式 App 未增加任何测试开关。
- 【④ 一致性】全库枚举鼠标事件调用：ProviderCredentialInteractionTests 内四处同类定位（含负向）全部替换，清空坐标和截图副作用一并删除；其他 History/Application 交互及菜单整行命中测试保留，不能把它们误称为都已迁移。新 shell 语法门禁逐文件运行 bash -n，修正通配参数实际只检查首文件的问题。未发现需扩大生产改动面的重构。

本次没有改变产品行为；features 既有描述无新增缺口或失真，不重做视觉原型或安装生产 App。只更新 spec 的 Testing Decisions 和测试执行说明。全量结果单列于 ax-test-migration-verification.md；不关闭 #24 的其他焦点/toolbar 待查事项。

## 2026-09-16 菜单最近记录五条

- 【① 底层前提】当前生产链路在 model 和 view 两处截取三条，均改为五条；没有数据库条数限制变更。面板控制器实际按 hosting fittingSize 取高度，不使用固定三行高度。
- 【② 可运行性】临时 SQLite 经真实 model.menuView 渲染；0、2、超过五条分别验证，追加正好五条边界。保留缩略图、终态、回调与排序；第六条仅从菜单省略。无新增异步或错误路径。
- 【③ 安全正确性】不改变凭据、权限、网络和数据删除。测试只写自身临时数据库。安装按原身份覆盖，不碰用户数据。
- 【④ 一致性】保持 300pt、原行尺寸及五条同样式；两处既有限制同步修改，不为简单数量新增抽象。渲染样本补两条并扩高，避免固定测试画布把英文更新提示和箭头裁切。现行 spec/features/原型 README 同步；未发现需另开重构的本轮新增项。

## 2026-09-16 历史重试身份修复接续

- 【① 底层前提】旧“同 runner 第二次调用”不能代表从数据库恢复的历史入口。生产 App 回调测试先复现原行未改、条数增加，恢复显式 operation ID 后转绿。删除“历史重试应新建行”的旧假设；提示词版本持久化经用户否认后从验收移除，不新增 schema。首开尺寸和双击旧测试与已确认原型相反，已替换。
- 【② 可运行性】逐条核对恢复→原图预检→请求→完整结果→UPDATE、失败/取消、待保存→本地重试、目标丢失、切换/隐藏/关闭、删除和清理路径。发现迟到 retention 确认绕过忙碌保护并删除两行（同层逃逸），已加保护；失败后 committedResult 已保留却阻止正文渲染（自条目可见功能 bug），已恢复旧正文并保留成功指标展示。两者均有目标错误上的红→绿。枚举应用删除入口：单条删除、清空、手动清理、自动清理、缩短保留期确认，最后一项缺保护，已修复；其余入口保留既有保护。
- 【③ 安全正确性】持久化只替换既有 ID，目标消失不得 INSERT；保留创建时间/原图/语言/Pin，Pin 运行中变化不被旧快照覆盖。复核受管理路径、哈希和 PNG 内容，不因预览曾可用就直接上传。更新失败保留内存结果和原目标，不重发 HTTP。测试仅访问隔离目录、假凭据与受控 HTTP；安装不修改用户数据。没有引入提示词历史落盘或密钥日志。
- 【④ 一致性】从 spec/CONTEXT/features/原型 README 中清理双击打开独立结果、1200×780 默认窗口及提示词持久化的过时现行描述；施工历史保留并追加取代记录。双击只保留普通行选择；首次铺满 visibleFrame，非 macOS fullscreen，后续保留用户尺寸。类级目录 URL 比较 load/discard 两处已同步验证。未增加与本次无关的重构。

证据：`/private/tmp/history-retry-boundaries-current-red.log`、`history-retry-failed-body-red.log`、`history-retry-complete-targeted.log`、`history-retry-full-closeout.log`。完整门禁退出 0。程序化回调/渲染与真实安装版操作区分记录，不把人工验收标成完成。

## 2026-09-24 历史原文翻译

版本：`850f64d01641922f6b2ece6458a121081a823789` + 本轮未提交修改。范围：[v1-core::US-003](../../specs/v1-core.md) 和所触及共享规则；不是全 v1 收口。

- 【① 底层前提】逐 Provider 枚举 OpenAI/Gemini/DeepSeek 三个请求构造器：文字输入均无图片字段，图片路径维持原契约。Foundation 分句的前导空白曾产生空白片段，已用保留字符的切片及非空句范围修复，重复句、Markdown、多段、组合 Unicode 样本验证精确字节。原文身份在本地确定，未把模型回传的 source 当真值。真实模型文字契约尚未执行，不声称账户兼容。
- 【② 可运行性】检查 preparing→streaming→succeeded/failed/canceled/save-failed→retry-save；原执行结果在成功事务之前不改动。取消只停外层 Task 的假设被生产回调测试推翻，已同时关闭捕获的 session，避免继续占用全局活动（上层逃逸）；准备期取消曾显示普通失败，精确断言先红后绿。退出现有历史任务同样调用 session.close，枚举另一取消入口后未见同类遗漏。切换记录、保存失败、过滤改变使用原应用生命周期和 UI 选择协调；原生测试覆盖转换目标与其他选中项两种分支。
- 【③ 安全正确性】文字入口不读取截图，不绕开 Provider 凭据和活动门禁。转换前后核对原记录，保存使用既有 UPDATE，不恢复已删除目标；Pin 单独持久化，旧快照不覆盖它。只有完整顺序/身份/原文字节一致且译文非空才提交。重试仍经 loadIfOwned 与 PNG 解码，测试对实际 HTTP 体核对原图 base64；缺图无请求。未新增 schema、凭据落盘、原始响应或用户内容日志。
- 【④ 一致性】复用既有双栏、30pt 图标、主题、本地化与事务接口，不替换新截图流程。首次文字转换和后续图片重试在 spec/CONTEXT/ADR 补充说明中明确区分。隐私说明原只提截图，改为显式对应截图或原文；属于本轮必要事实校正。SF Symbols 沿用项目原生约定，Provider 的已确认字母标识不在本次更改范围；无新字符图标。未引入需要另开重构的改动。

测试途中 fixture 缺 DeepSeek SSE id 与原生测试错误枚举名属于测试搭建错误，修正 fixture/测试，不记作产品修复红。具体逐项证据与安装结果见本轮 checklist 和 final-regression 追加记录。

## 2026-09-24 流式元数据前缀误判修复

- 【① 底层前提】真实 JSON 可任意字段顺序；复现响应的 block 最后到达。保存的完整响应及 expected source 对读相等，但 chunk1174 发布 block=s。最小逐 scalar 样本同样红，修复后的原响应回放绿，排除本次复现的 JSON 语法/原文字节不同。
- 【② 可运行性】状态机的 start/fieldValue/fieldEnd/segmentEnd/done 未变；仅 text field 可以进入 decodePrefix。id/block/kind 在 acceptString 后才进入 fields，缺元数据的快照不发布；后续正确完整片段仍能发布。错误原会中止整个请求（上层逃逸），本轮当场修复。
- 【③ 安全正确性】不修补截断、不猜配、无额外网络请求；完整 JSON/重复 ID/类型/源文相等/数量的最终守卫均保留。真实测试使用合成文字与既有签名 Keychain 权限，保存前剔除 reasoning_content，无用户原文和 API Key。原失败响应未留存，不声称已核验用户那一包。
- 【④ 一致性】全库枚举 OpenAIResponsesStreamDecoder、GeminiStreamDecoder、DeepSeekChatStreamDecoder 均走同一 OrderedStructuredOutputParser/AlignedTranslationParser；三处均受修复，无独立同类元数据前缀实现。提取 parser 的前缀仅用于正文，无需修改。没有界面/模型切换/持久化策略变化，不引入新抽象或顺手重构。

归因复盘与规格测试边界已同步；安装版同记录重验仍待用户，不把样本 live 通过当所有账户保证。
