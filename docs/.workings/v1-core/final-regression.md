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
