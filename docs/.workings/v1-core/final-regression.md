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
