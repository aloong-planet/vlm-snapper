# VLMSnapper v1 — Documentation regression

## 2026-08-26 — Ticket 02

### 阶段一：逐句核真

| 声明面 | 对照端 | 结论 |
| --- | --- | --- |
| Ticket 02 acceptance | 文件系统、SQLite、重置实现与 22 个测试 | 四项承兑均有公开行为证据；状态改为 completed |
| `v1-core.md` 第 9 节与失败模式 7/13/14/15/17 | 本票实现 | 原始 PNG、先持久化、意外中断、结果 payload、所有权和数据库阻断一致 |
| ADR-0006 | 受管理截图实现 | 路径与 SHA-256 共同决定加载/删除资格，替换文件不被认领 |
| ADR-0008 | SQLite 初始化与 resetter | 新版/故障库不静默重建；显式重置先保留主库和 WAL/SHM |
| 原型 | 本票实现 | 本票没有用户界面变化，无需同步原型 |

### 阶段二：关系对读

| 关系 | 检索/核对 | 结论 |
| --- | --- | --- |
| Ticket ↔ checklist | Ticket 02 状态与 evidence 行 | 两处均为已完成，测试数与文件一致 |
| ADR ↔ spec | `rg "数据库.*(损坏|版本|重置)|SHA-256|符号链接" docs` | ADR-0006/0008 与 spec 没有反向表述 |
| 规则 ↔ 门禁 | 英文源码规则 ↔ CJK 扫描；持久化门禁 ↔ 完整 Swift 测试 | 门禁覆盖本票触碰的源码和测试；设计文档允许中文 |
| features ↔ 当前产品 | `docs/features/` 尚未初始化，Ticket 10 承担全功能收口 | 本票只提供不可独立操作的核心 seam，不提前声明用户可用功能 |

### 阶段三：事件核销

| 事件 | 核对 | 结论 |
| --- | --- | --- |
| 新增持久化状态/结果字段 | spec 的成功、失败、取消、意外中断、结果保存失败枚举 | 成员未改变，只实现既有枚举；无其他数量声明需更新 |
| 新增 recovery 文件行为 | ADR-0008 与 spec 恢复路径 | 命名细化不改变既有产品决策，旧副本不覆盖 |
| 新增符号链接覆盖形态 | spec“不跟随符号链接” | 是既有通则的完整实现，不产生新通则 |
| `Pending:` 注记 | `rg "Pending:" docs/.workings/v1-core docs/specs docs/adr` | 本票范围无到期 Pending 注记 |

### 收敛结论

三阶段队列已清空；本票没有需回写 spec、ADR、CONTEXT 或原型的实现偏离。代码与测试审查记录保留跨进程 TOCTOU 补测条件，不把它误报为已覆盖。

---

## 2026-08-26 — Ticket 03

### 阶段一：逐句核真

| 声明面 | 对照端 | 结论 |
| --- | --- | --- |
| Ticket 03 acceptance | Provider 状态、目录、Keychain、元数据实现与 25 个 Ticket 测试 | 完整列表后写 Key、不可手输、刷新替换/保留、24 小时、冻结、视觉证据和一次刷新原语均有公开行为证据；状态改为 completed |
| `v1-core.md` Provider 配置与失败模式 10/11 | 本票实现 | 普通 400 不误判、明确图片不支持清除模型、模型消失与刷新失败语义一致；请求级错误接线仍按 Ticket 04 边界保留 |
| ADR-0001 | Keychain 与元数据存储 | 三个 Provider 独立、禁用同步、普通配置无 API Key；签名 Data Protection 路径未被降级测试冒充 |
| ADR-0011 | DeepSeek 模型列表 | 精确实验 ID 只接受账户实际返回，不注入、不预选 |
| 原型 | 本票实现 | 本票只实现核心 seam，Provider 配置 UI 仍由 Ticket 07 按已确认原型接入 |

### 阶段二：关系对读

| 关系 | 检索/核对 | 结论 |
| --- | --- | --- |
| Ticket ↔ checklist | Ticket 03 状态、evidence 与 53 个完整测试汇总 | 状态和证据同步，Ticket 范围为 25 个测试；模型目录参数化用例覆盖 OpenAI 与 DeepSeek 两个结果 |
| ADR ↔ spec | `rg "Keychain|完整.*模型|deepseek-v4-flash-vision-exp|不兼容|24 小时" docs` | ADR-0001/0011、spec 与 requirements-alignment 没有反向表述 |
| 规则 ↔ 门禁 | 英文源码规则 ↔ 15 文件 CJK 扫描；Provider 不变量 ↔ 完整 Swift 测试 | CJK 扫描无匹配；构建 warnings-as-errors，Swift Testing 53/53 |
| features ↔ 当前产品 | `docs/features/` 尚未初始化，Ticket 10 承担全功能收口 | 本票没有可独立操作的用户入口，不提前声明当前可用功能 |

### 阶段三：事件核销

| 事件 | 核对 | 结论 |
| --- | --- | --- |
| 三个 Provider 的模型目录实现落地 | spec/ADR 中 Provider 成员枚举 | 成员数未改变，只实现既有 OpenAI、Gemini、DeepSeek；无需改枚举声明 |
| 新增视觉兼容与一次刷新状态原语 | spec 7、失败模式 10/11 | 是既有状态与通则的实现，不产生新产品决策 |
| 新增 Keychain 与普通元数据边界 | ADR-0001、隐私声明 | 安全边界未改变；签名路径缺口已分配 Ticket 10 |
| `Pending:` 注记 | `rg "Pending:" docs/.workings/v1-core docs/specs docs/adr` | 图片请求限制和 DeepSeek 真实契约测试尚未到期，继续由 Ticket 04/10 承兑 |

### 收敛结论

三阶段队列已清空；本票没有需回写 spec、ADR、CONTEXT 或原型的实现偏离。请求级模型不可用接线和签名 Data Protection Keychain 均有明确后续票，不把 seam 测试扩张为未发生的端到端验证。

---

## 2026-08-26 — Ticket 04

### 阶段一：逐句核真

| 声明面 | 对照端 | 结论 |
| --- | --- | --- |
| Ticket 04 acceptance | 三个请求工厂、独立 decoder、统一 executor 与 30 个本票测试 | 共享事件、超时注入、截断拒绝和一次请求均有公开行为证据；状态改为 completed |
| `v1-core.md` 第 5、6、8 节 | 请求、流式、错误实现 | 截图直送、单请求、10/10/90 秒、无自动重试和 1–5 分钟限流提示一致 |
| ADR-0011 | DeepSeek 独立 adapter | 使用 Chat Completions、严格终态与 JSON 最终校验；实验模型仍受账户列表和发布门禁约束 |
| 原型 | 本票实现 | 无新增视觉行为；结果窗口和错误展示仍由 Ticket 06 接入已确认原型 |

### 阶段二：关系对读

| 关系 | 检索/核对 | 结论 |
| --- | --- | --- |
| Ticket ↔ checklist | Ticket 04 状态、evidence 与 83 个完整测试汇总 | 状态和证据同步，本票测试覆盖三 Provider 共享契约 |
| research ↔ 实现 | OpenAI Responses、Gemini v1beta、DeepSeek Chat Completions | 三家 wire 协议隔离，没有以“兼容”名义复用错误 decoder |
| 规则 ↔ 门禁 | 英文源码/提示词 ↔ CJK 扫描；无重试 ↔ request count/变异 | 扫描无匹配，三项变异均准确红灯 |
| features ↔ 当前产品 | `docs/features/` 尚未初始化 | 本票只有核心 seam；Ticket 10 全功能收口前不声明用户可用 |

### 阶段三：事件核销

| 事件 | 核对 | 结论 |
| --- | --- | --- |
| 新增 Provider 统一事件/错误 | spec 6、8 节 | 成员和顺序实现既有决策，没有新增用户选择 |
| 新增 20 MB Gemini 请求体门禁 | 官方小于 20 MB 合同与原始 PNG 规则 | 计算完整序列化体；不改变保存/上传字节一致性 |
| 新增超时和限流提示数据 | spec 67、93 行 | 数值与分类一致；本票不实现持久化冷却 UI |
| `Pending:` 注记 | spec 图片限制与真实 Provider 契约 | 尚未到期；继续由 Ticket 10 的真实账户、签名产物门禁承兑 |

### 收敛结论

三阶段队列已清空；代码、research、spec、ADR、ticket 和 checklist 没有反向表述。真实 Provider 请求未执行，发布 Pending 被保留而非误报完成。

---

## 2026-08-27 — Ticket 05

### 阶段一：逐句核真

| 声明面 | 对照端 | 结论 |
| --- | --- | --- |
| Ticket 05 acceptance | 冻结、选区、PNG、快捷键实现与 22 个本票测试 | 触发后冻结 seam、部分失败、2 × 2、几何失效、同一 PNG byte object 和原子热键替换均有公开行为证据；状态改为 completed |
| `v1-core.md` 第 3 节 | capture/selection 实现 | 不在松开时重截、单屏失效、取消释放、sRGB PNG 与规范一致 |
| ADR-0010 | `CaptureSelectionSession` 与原生 capturer | 使用 display ID + 本地物理像素；新屏不加入本次，变化屏失效，其他屏保留 |
| 原型 | 本票实现 | 无新增视觉行为；选区 overlay 与操作栏由 Ticket 06 接入已确认原型 |

### 阶段二：关系对读

| 关系 | 检索/核对 | 结论 |
| --- | --- | --- |
| Ticket ↔ checklist | Ticket 05 状态、evidence 与 105 个完整测试汇总 | 状态和证据同步，本票新增 22 个行为测试 |
| research ↔ 实现 | ScreenCaptureKit、CoreGraphics、Carbon C shim | C API 被限制在窄 shim；Swift 不直接持有事件结构或回调注册链表 |
| 规则 ↔ 门禁 | 英文源码/注释 ↔ CJK 扫描；严格 Swift/C warning gate | 扫描无匹配，编译与测试通过 |
| features ↔ 当前产品 | `docs/features/` 尚未初始化 | 本票没有 App/UI 可操作入口；Ticket 10 全功能收口前不声明用户可用 |

### 阶段三：事件核销

| 事件 | 核对 | 结论 |
| --- | --- | --- |
| 新增 Carbon C shim | spec 原生 macOS 与可配置全局快捷键 | 仅实现既有能力；MainActor 协调与销毁注销补足生命周期，不产生新产品决策 |
| 新增 `cropping` 中间态 | ADR-0010 释放与几何失效语义 | 是异步重入的实现机制；取消、完成和失效终态未改变 |
| 新增 geometryChanged 捕获失败 | ADR-0010 显示器变化规则 | 将既有规则落实到捕获前后核对，不扩展用户行为 |
| 系统集成 Pending | spec Seam 3 与 Ticket 10 | 多屏、TCC、真实热键投递/冲突和签名产物尚未到期，继续保留发布门禁 |

### 收敛结论

三阶段队列已清空；实现、spec、ADR、ticket 和 checklist 没有反向表述。本票只交付可测试核心与原生 adapter，不把未执行的签名 App 系统验收误报为完成。

---

## 2026-08-27 — Ticket 06

### 阶段一：逐句核真

| 声明面 | 对照端 | 结论 |
| --- | --- | --- |
| Ticket 06 acceptance | actor/runner、schema v2、SwiftUI/AppKit 组件与 22 个本票相关测试 | 原型常量、显式单请求、旧成功替换门禁、关闭取消均有公开行为证据；状态改为 completed |
| `v1-core.md` 操作、结果、错误与关闭规则 | 本票实现 | 截图直送、提取/翻译切换、无自动重试、单活动任务、未保存结果与关闭语义一致 |
| 已确认原型 | harness 明暗实际渲染与几何测试 | 操作栏 4/3/25/6 px、顶部分段选择和左右双区结果一致；未加入标注能力 |
| 历史类型过滤前置数据 | schema v2 迁移与 typed operation | extract/translate 和 target language 已持久化，Ticket 08 可据此筛选而无需推断正文 |

### 阶段二：关系对读

| 关系 | 检索/核对 | 结论 |
| --- | --- | --- |
| Ticket ↔ checklist | Ticket 06 状态、evidence 与 127 个完整测试汇总 | 两处同步，本票新增会话/runner/UI/schema 契约覆盖 |
| design ↔ 实现 | operation freeze、runner 截图所有权、取消、最终保存失败 | 设计已回写首次 suspension 前冻结、adapter cancellation 和窄屏 leading edge |
| 规则 ↔ 门禁 | 英文代码/注释、本地化双语、严格 warning gate | CJK 源码扫描 0、28 键一致、UI 硬编码扫描 0，严格构建通过 |
| features ↔ 当前产品 | `docs/features/` 尚未初始化，Ticket 07 尚未接 App 入口 | 组件可渲染但最终用户尚无完整入口，不提前登记产品功能 |

### 阶段三：事件核销

| 事件 | 核对 | 结论 |
| --- | --- | --- |
| schema 从 1 升到 2 | legacy migration 与新版阻断 | 旧行确定性为 extract；目标语言仅 translation 有值，无反向兼容歧义 |
| 新增全局 activity lease | spec 单活动任务与重复快捷键 | lease 在所有终态释放；重复快捷键 bring-forward 的 App 接线继续由 Ticket 07 承兑 |
| 新增 UI 本地化资源 | Ticket 09 双语范围 | Ticket 06 所有新文案已经双语，不改变 Ticket 09 的整 App 扫描与系统语言接线责任 |
| 系统集成 Pending | Ticket 10 | 签名窗口、辅助功能、TCC 与真实 Provider 继续保留发布门禁，不误报已验证 |

### 收敛结论

三阶段队列已清空；设计、实现、测试、ticket 和 checklist 已同步。Ticket 06 完成可测试核心与真实 UI 渲染，App 入口和签名系统集成分别留给 Ticket 07/10。

---

## 2026-08-27 — Ticket 07

### 阶段一：逐句核真

| 声明面 | 对照端 | 结论 |
| --- | --- | --- |
| Ticket 07 acceptance | readiness/permission/provider actor、菜单与附着式 SwiftUI、16 个本票测试 | 双门禁、Later、模型原地展开、已选权限原型与双语均有公开行为和渲染证据；状态改为 completed |
| `v1-core.md` 首次引导与 Provider UI | `OnboardingContainerView`、`ProviderSetupView`、presentation snapshot | Direction A/B、8 px、成功后保留 Key 区并展开模型、无手输、取消/完成回引导、活动只读一致 |
| requirements 权限与菜单入口 | permission coordinator、menu router/container | 展示零请求、首次显式请求、拒绝/撤销不重复、成功要求重启，以及 Provider → 权限 → capture 顺序一致 |
| 隐私详情原型 | `StoragePrivacyDetailView` 与 83 键字典 | 四个扁平分区、固定 Pictures 路径、Keychain/FileVault、保留期/钉住、外部备份边界和仅关闭操作一致 |
| 已确认原型 | 10 张真实离屏 render | 引导 A、Provider B、菜单 C、权限 A 的明暗层级、Provider 顺序、固定标识和圆角已逐图核对 |

### 阶段二：关系对读

| 关系 | 检索/核对 | 结论 |
| --- | --- | --- |
| Ticket ↔ checklist | Ticket 07 status、143 测试与 evidence | 两处均已完成，测试数、render 数和发布缺口一致 |
| design ↔ 实现 | 状态入口/退出、API Key、Provider 不抢占、只读与 recovery disposition | 实现期发现的重叠权限、stale selection、当前 Provider 和只读保护已回写 review；设计无旧行为残留 |
| 原型 ↔ README/manifest | permission Direction A 选择、四套 prototype 索引 | README 明确 A 已选；原型保留 B 仅作比较历史，manifest 指向均有效 |
| 规则 ↔ 门禁 | 英文源码、双语字典、UI 文案与 render | CJK 扫描 0、83/83 键一致、硬编码扫描 0；严格构建及 143/143 测试通过 |
| features ↔ 当前产品 | `docs/features/` 不存在；Package 尚无生产 App executable | Ticket 07 交付可组合入口与 controller，但当前仓库仍无最终用户可运行产品；按目录“出现即可用”不提前初始化，Ticket 10 收口责任不变 |

### 阶段三：事件核销

| 事件 | 核对 | 结论 |
| --- | --- | --- |
| 新增状态栏/引导/权限/Provider 可见表面 | spec 的已确认入口枚举 | 成员未新增，只实现已有四类入口；管理中心仍由 Ticket 08，生命周期仍由 Ticket 09 |
| 新增统一 `unavailable` 权限状态 | 公共 Core Graphics 可观察能力与用户文案 | 这是 denied/revoked 的诚实合并，不删产品恢复分支、不虚构系统区分 |
| 本地化键从 28 增至 83 | zh-Hans/en 字典与全量键门禁 | 两语成员同步，Provider 品牌名保持不翻译；Ticket 09 仍负责系统语言偏好和整 App 扫描 |
| 新增 10 张 render 产物 | 临时目录与测试枚举 | 仅是测试证据，不进入仓库或功能目录；锁屏桌面截图未被误报为有效证据 |
| `Pending:` 注记 | `rg "Pending:" docs/.workings/v1-core docs/specs docs/adr` | 签名 TCC、状态栏交互、System Settings/重启、真实 Provider 等发布项尚未到期，继续由 Ticket 10 验收 |

### 收敛结论

三阶段队列已清空；原型选择、design、实现、双语字典、ticket、checklist 和测试证据已同步。Ticket 07 完成可组合菜单/引导 UI 与权限/Provider 状态 seam，不把尚未存在的生产 App 组合和签名系统交互误报为发布完成。

---

## 2026-08-27 — Ticket 08

### 阶段一：逐句核真

| 声明面 | 对照端 | 结论 |
| --- | --- | --- |
| Ticket 08 acceptance | schema/query、删除/保留协调器、管理中心与新增测试 | 左筛选右搜索、五档保留、钉住保护、永久删除、摘要门禁和部分失败汇总均有实现与证据；状态改为 completed |
| `v1-core.md` 历史与清理 | 本票实现 | 原文/译文本地搜索、全部结构化筛选、真实 metrics、30 天默认、24 小时门禁和无自动撤销一致 |
| requirements 删除顺序 | 文件 store + deletion coordinator | 匹配 PNG 先删、失败保留记录；缺失/替换只删内部记录；空月份仅空时移除，根目录保留 |
| 已确认原型 | 8 张当次离屏 render | 类型筛选左对齐、搜索右对齐、列表详情位于其下；History/Settings 同壳，明暗状态一致 |

### 阶段二：关系对读

| 关系 | 检索/核对 | 结论 |
| --- | --- | --- |
| Ticket ↔ checklist | Ticket 08 completed、151 测试与 evidence | 状态、测试数、render 数和生产集成缺口同步 |
| design ↔ 实现 | schema v3、唯一删除路径、retention/session/scheduler | 迁移保守时间、删除错误语义、24 小时进程门禁和 UI destination 均一致 |
| ADR-0002/0006/0008 ↔ 实现 | 本地明文边界、Pictures 所有权、数据库阻断 | 不扫描 Pictures、不认领孤儿、不删替代文件、不写 API Key/原始错误正文 |
| 规则 ↔ 门禁 | 英文代码、双语字典、严格 warning gate | CJK 代码扫描 0、双语键 diff 0、严格构建与 151/151 测试通过 |
| features ↔ 当前产品 | `docs/features/` 尚不存在；Package 无生产 App executable | 两问结论：本票没有让既有 features 变成谎，也没有可登记为最终用户现已可用的生产功能；Ticket 10 初始化目录 |

### 阶段三：事件核销

| 事件 | 核对 | 结论 |
| --- | --- | --- |
| schema 2 升到 3 | legacy 数据与 newer-schema gate | 旧记录采用迁移时刻避免立即过期；字段缺失时 metrics 显示不可用 |
| 新增保留期五成员枚举 | spec、隐私字典、设置 Picker | 7/30/60/90/180 三处一致，无自定义或永久保留入口 |
| 新增管理中心可见表面 | 原型、菜单 destination、window controller | 只实现既有 History/Settings 结构；生产 App 跳转接线仍归 Ticket 09/10 |
| 新增永久清理动作 | 确认文案、文件所有权与批量 summary | 无 Trash/撤销，钉住需显式包括，活动项不取消且跳过 |
| `Pending:` 注记 | spec 发布 Pending 与 Ticket 10 | 真实菜单栏、签名 App、Provider 和发布门禁尚未到期，不误报已验证 |

### 收敛结论

三阶段队列已清空；design、实现、测试、双语字典、ticket、checklist、spec 和 ADR 没有反向表述。Ticket 08 完成可测试的管理中心与清理能力，但不把尚未组合出的生产 App 冒充最终用户可运行产物。

---

## 2026-08-27 — Ticket 09

### 阶段一：逐句核真

| 声明面 | 对照端 | 结论 |
| --- | --- | --- |
| Ticket 09 acceptance | 5 个 Core seam、Sparkle target、native adapters、19 个本票测试 | 第二实例 gating、7 天 allowlist、双语重启策略、登录审批、六小时检查、显式下载和 callback-only ready 均有实现；状态改为 completed |
| `v1-core.md` 更新/诊断/本地化 | 最终代码与 UI 字典 | 无自动下载开关；菜单/设置共享状态；信息型更新只查看；脱敏导出和两语言三策略一致 |
| Ticket 09 design | review 后实现 | 回调串行链、UTC 完整截止日、真实 gzip 与 restart-required 已回写 review；签名 App 门禁仍归 Ticket 10 |
| 已确认原型 | 32 张中英文/明暗/四态离屏 render | 菜单更新提醒、General Settings 分区、按钮语义和长英文换行一致；未加入自动下载 UI |

### 阶段二：关系对读

| 关系 | 检索/核对 | 结论 |
| --- | --- | --- |
| Ticket ↔ checklist | Ticket 09 completed、172 测试与 evidence | 状态、测试数、render 数、Sparkle 版本和系统集成缺口同步 |
| spec/ADR ↔ 实现 | ADR-0003/0004/0009 与语言、feed 边界、单实例 lease | 没有反向表述；三架构 appcast 和签名只在 Ticket 10 配置 |
| 原型 ↔ README/manifest | companion/management README、manifest 和 HTML | 确认日期、无自动下载与演示状态一致；demo timer 没有进入生产实现 |
| 规则 ↔ 门禁 | AGENTS、双语字典、严格构建、真实 test total | 原有 tracker/layout 入口已恢复；新增键成对、warnings-as-errors 通过 |
| features ↔ 当前产品 | `docs/features/` 不存在；Package 仍无生产 App executable | 按“出现即可用”不提前初始化；Ticket 10 负责签名可运行产品和功能目录收口 |

### 阶段三：事件核销

| 事件 | 核对 | 结论 |
| --- | --- | --- |
| 新增 UI 语言运行策略 | zh-Hans/en 两成员与 system/zh-Hans/en 三偏好 | AGENTS、spec、requirements、字典与 Picker 枚举一致；无繁体或 RTL 承诺 |
| 新增 Sparkle 2.9.6 依赖 | Package.resolved、design 与 adapter | 精确版本一致；无自动下载，原始错误不展示，真实 feed/EdDSA 留 Ticket 10 |
| 新增状态 available/downloading/ready | Core、菜单、设置、状态栏 indicator | “已下载”只来自 ready callback；点击 Download 不乐观切状态 |
| `Pending:` 注记 | spec 图片限制与真实 Provider 契约 | 本票未使其到期；继续由 Ticket 10 的真实账户与签名发布门禁承兑 |
| 新通则 | AGENTS 项目能力 | 英文工作语言、双语字典、首帧语言与区域独立已落仓库必经入口 |

### 收敛结论

三阶段队列已清空；实现、review、测试、ticket、checklist、spec、ADR、原型和双语字典一致。Ticket 09 完成可组合生命周期模块与确认 UI，不把尚未存在的签名生产 App、真实系统审批或更新安装冒充已验证。

---

## 2026-08-27 — Ticket 10 development closure

### 阶段一：逐句核真

| 声明面 | 对照端 | 结论 |
| --- | --- | --- |
| Ticket 10 development scope | production executable、App composition、capture host、release scripts | 已组合出可构建的菜单栏应用和三架构开发包；formal acceptance 仍明确阻塞 |
| `v1-core.md` 全产品行为 | 生产接线与 184 个测试 | Provider-first、冻结截图、单请求、历史/清理、更新、诊断、快捷键和统一退出一致 |
| 已确认原型 | 32 + 4 张当前 render | 设置快捷键与紧凑操作栏中英文/明暗均无错位、截断或视觉方向漂移 |

### 阶段二：关系对读

| 关系 | 检索/核对 | 结论 |
| --- | --- | --- |
| Ticket ↔ checklist | Ticket 10 in progress、formal gates blocked | 状态不再错误依赖已完成的 01–09，也未标完成 |
| design ↔ 实现 | repeated capture、all-display failure、termination、atomic publishing | 旧的“活动 capture 只前置”与“全部失败走 permission”表述已修正为实际确认行为 |
| features ↔ 当前产品 | `docs/features/v1-core.md` 与 production target | 目录已初始化，但显著声明仅 development implementation、不可正式公开发布 |
| 规则 ↔ 门禁 | strict build、184/184、localization parity、CJK scan | 代码/注释/测试英文，UI 双语；0-test 兼容输出未当绿灯 |

### 阶段三：事件核销

| 事件 | 核对 | 结论 |
| --- | --- | --- |
| 新增三架构开发 DMG | executable slices、bundle metadata、checksum、codesign | Universal/arm64/x64 packaging shape 分别验证；ad-hoc 不冒充 Developer ID |
| 新增统一退出保护 | menu Quit、Command-Q、restart、Sparkle termination | 都进入 `prepareForTermination`; 未保存完成结果需显式确认 |
| 新增目标语言与快捷键 | catalog、UserDefaults、recorder、toolbar/settings | 无手动语言码、无繁体入口；快捷键冲突保持旧注册 |
| 新增 formal pipeline | credentials、HTTPS、notary、staple、Gatekeeper、EdDSA、atomic stage | 缺少真实身份/托管/Provider 凭据时 fail closed，Ticket 不完成 |

### 收敛结论

开发实现、设计、功能目录、review 与本地验证已同步。Ticket 10 保持“进行中（正式门禁阻塞）”；只有真实签名、公证、公共 HTTPS 与 live Provider 证据齐备后，才能改为 completed 或发布 v1。

---

## 2026-08-27 — Ticket 10 live Provider gate follow-up

### 阶段一：逐句核真

| 声明面 | 对照端 | 结论 |
| --- | --- | --- |
| Ticket 10 design 的 protected live-contract gate | Core runner、CLI 与 formal workflow | 三家各一次截图翻译；blocked/failed 均非零退出，报告 allowlist 与设计一致 |
| Ticket 10 issue 的 Provider 阻塞 | GitHub Secret/Variable 与真实 Gemini probe | GitHub 配置仍为空；Gemini 既有通过也有 malformed/timeout，状态继续 in progress 正确 |
| review-code/test 历史结论 | 190 tests / 46 suites、blocked smoke、live probe | 新增 follow-up 章节，不改写此前 184-test 时点记录 |

### 阶段二：关系对读

| 关系 | 检索/核对 | 结论 |
| --- | --- | --- |
| workflow ↔ Core environment names | 三个 API Key Secret + 三个模型 Variable | 名称一一匹配；key 不进入报告，model 可进入 allowlist |
| design 隐私边界 ↔ report schema/CLI | Codable 字段与编码 smoke | 无正文、图片、key、header、raw response；request ID 只输出摘要 |
| 用户请求失败规则 ↔ live runner | 单请求、10 秒首字、无自动重试 | 直接复用生产 executor；没有门禁专用 retry 或 timeout 放宽 |
| features ↔ 本轮事件 | `docs/features/v1-core.md` | 仅新增内部发布验证，不改变产品内用户行为；正式发布未就绪声明仍真，无需加入 CI 实现细节 |

### 阶段三：事件核销

| 事件 | 检索/核对 | 结论 |
| --- | --- | --- |
| 新增一个 executable/product target | Package 枚举与 CI build | 全量 build 会编译 gate；用户 App 的产品身份、菜单与启动行为未改变 |
| 测试从 184/45 增至 190/46 | Ticket 10 issue 与本轮 review | 当前计数已更新；历史施工记录保留当时时点，不反写 |
| 新增六个外部配置名 | workflow、design、GitHub 当前状态 | 正本已落 design；GitHub 尚未配置，继续列为发布阻塞 |
| `Pending:` /正式门禁 | Ticket 10 completion conditions | live runner 代码已到位，但三家真实合同、签名、公证、公共 HTTPS、签名宿主与升级验证仍未完成 |

### 收敛结论

本轮三阶段队列已清空。live Provider release gate 的代码、测试、workflow、design 和施工证据一致；功能目录没有被内部 CI 细节污染。Ticket 10 与正式发布继续保持阻塞，不以单次 Gemini 成功或离线测试替代三家真实通过。
