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
