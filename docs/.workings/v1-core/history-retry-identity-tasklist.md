# 历史重试身份修复

Spec：[v1-core](../../specs/v1-core.md)；承兑：既有 #25；来源及实现基线：`0febbb48fcd9acccdefc67dc9015ebf92605511c` + 前序未提交改动。

本轮接续原分支，不重置或搬移前序修改。已 fetch origin，`git log origin/main..HEAD` 为空；工作区不是干净基线。纯数据语义修正，沿用已确认的按钮与状态，不重画原型。

- [x] 按当前 spec 更新票及逐项映射，旧新增记录验收失效。
- [x] 红：生产历史入口 + 真实临时 SQLite，提取/翻译均验证原 ID 更新。
- [ ] 绿：显式恢复记录身份；补连续重试、重开历史、失败、保存失败及目标失效边界。
- [ ] 全量验证：严格构建、脚本、非 App/App、独立原生用例、外部 AX。
- [ ] 独立第 5 步：review-code。
- [ ] 独立第 6 步：review-tests。
- [ ] Spec 终检与 features-catalog 文档一致性回归。
- [ ] 构建签名、校验并无备份覆盖安装，保留用户数据；无提交/推送/合并。

## spec → tickets → 验证

各项均由 #25 实现/回归，#23 后续全功能核销。此表在执行前均为未验证，不借旧 green 结果抵扣。

| 覆盖单位 | 计划机制 |
|---|---|
| v1-core::REQ-002/AC-03 | Test：历史详情及历史结果入口重跑，同 ID/条数/PNG 文件集合不变，连续重试。 |
| v1-core::REQ-002/AC-04 | Test：原图缺失/替换后零上传、原记录仍可读。 |
| v1-core::REQ-002/AC-07 | Test：生产回调忙碌/禁用及现有历史按钮回归；Evidence：安装版仍需用户验收。 |
| v1-core::REQ-002/AC-08 | Test：受控 HTTP 验证当前模型、原类型/语言。 |
| v1-core::REQ-002/AC-09 | Test：窗口会话关闭重开/应用持有结果；既有退出确认组合回归。 |
| v1-core::REQ-002/AC-10 | Test：SQLite 公开读回完整结果、Pin/时间/原图/其他记录不变。 |
| v1-core::REQ-002/AC-11 | Test：失败/截断/取消保留持久化快照；重建不发送请求。 |
| v1-core::REQ-002/AC-12 | Test：真实 SQLite 写失败→恢复→只本地保存，HTTP 数不变。 |
| v1-core::REQ-002/AC-13 | Test：公开删除后重试或保存拒绝，无新增/错误更新。 |
| v1-core::REQ-002/AC-14 | Test：重复点击、配置作业、未保存结果均不重复请求。 |
| v1-core::REQ-002/AC-15 | Test：切换目标后结果仍归原 ID，原生详情渲染。 |
| v1-core::REQ-002/AC-16 | Test：请求/未保存期间删除清理不改目标；终结后恢复。 |
| v1-core::REQ-002/AC-17 | Test：新建 App/读库，列表/详情/搜索/筛选均使用已更新行。 |
| v1-core::US-001/AC-02 | Test：新文字可搜，旧文字不再匹配。 |
| v1-core::US-001/AC-05 | Test：新 Provider 属性查询、原生 Provider 筛选回归。 |
| v1-core::US-001/AC-09 | Test：重试期间 Pin 变更提交后保留。 |
| v1-core::US-001/AC-10 | Test：历史查询组合现有用例回归。 |
| v1-core::US-001/AC-12 | Test：查询失配选择协调现有用例回归。 |
| v1-core::CON-001 | Test：历史打开/读取零上传，只有显式重试上传。 |
| v1-core::REQ-003/AC-01 | Gate：本地化检查；无新增界面形态。 |

双向核对：本轮新增 AC-10–17 和受影响 AC-03/08/09 均由同一票承兑，共享及回归条件按上表承接，不将实现拆成界面/存储半票；各机制对应 spec 已定义义务。其余范围沿用 checklist 的来源审查结论，不重开无关任务。

## 2026-09-16 实施进展与停止点

> 下文保留当时停止点；已由文件末尾“接续完成自动化验证”取代，不代表当前仍在等待需求确认。

以下不代表本票完成；实现期检查不能抵扣尚未进入的独立 review-code / review-tests。

已改：历史详情和历史结果恢复时显式绑定原记录；成功 UPDATE、失败保留、保存失败保留目标；会话恢复旧文本；翻译重试保留原语言；复核磁盘原图及目标存在性；目标消失给出本地化原因；结果工作区的活动任务和未保存结果也保护历史删除/清理。未创建重复记录清理逻辑，未提交、推送、合并或安装。

### 红绿证据

- `/private/tmp/history-retry-red.log`：两个 App 入口参数均出现条数 2/3/4 而非 1、原 ID 仍是旧文字，共 12 个断言失败。首次沙箱缓存错误不算红证据。
- `/private/tmp/history-retry-green.log`：原 ID 更新修复后提取/翻译通过。
- `/private/tmp/history-retry-boundaries-red.log`：原语言被全局参数覆盖、已删除目标及替换图片仍请求，7 项失败；`history-retry-boundaries-green2.log` 修复后通过。
- `/private/tmp/history-retry-restoration-red.log`：失败后会话的 committedResult 为 nil；`history-retry-restoration-green.log` 恢复旧结果后通过。
- `/private/tmp/history-retry-error-red.log`：目标删除后只有通用保存错误；修复后原因代码为 history_record_unavailable。
- `/private/tmp/history-retry-root-red.log`：合法目录 URL 没带 isDirectory 时，保存后 load 抛 ownershipMismatch；统一目录 URL 表示后 load/discard 两种参数均通过。范围内 load/discard 两处所有权比较同时核对，符号链接和哈希保护未取消。不能仅把测试输入换成 isDirectory:true 来掩盖此边界。
- `/private/tmp/history-retry-focused.log`：35 项定向测试通过（不是最终全量门禁）。
- `/private/tmp/history-retry-final-targeted.log`：最终追加 PNG 文件数与重建 App 读回后的 17 项定向测试通过，退出 0。

### 全量门禁

- 第一次 `/private/tmp/history-retry-full-regression.log` 在 non-app 退出 1，揭示上述目录 URL 问题；保留失败，不当通过。
- 修复后 `/private/tmp/history-retry-full-regression-final.log`：strict-build、18 项脚本检查、checklist、shell、341 项非 App Swift Testing、16 项 App Swift Testing、非 App XCTest 及两项独立原生测试通过；AX 到第 8 场景启动失败，整轮退出 1。
- 详细日志：`/var/folders/9h/52q4kxb115j2nglbz0kfpkh00000gn/T/vlmsnapper-full-regression.bo6S7A/`。
- AX 失败为 `launch_failed_or_timed_out`，stage=target、steps=[]，不是业务断言失败。只读核对到迟到测试进程；请求正常退出前的身份复核未通过，没有终止该进程。随后再次读取确认进程已自行退出。
- 不改断言完整重跑 `/private/tmp/history-retry-ax-rerun.log`，15 场景全部通过（含预期失败反例），退出 0。各阶段已有通过证据；不能描述成一次整轮全绿。

### 尚未核销

1. **范围待确认**：REQ-002/AC-10 写了提示词版本，但现行 StoredOperation / SQLite schema 没有该字段。已经向用户提出：建议本次只修复已有字段，提示词版本持久化另定范围；用户尚未回答。未擅自移除 AC，也未新增数据库迁移；spec 保留明确 Pending。
2. **原生入口验收缺口**：历史结果窗口重新打开后的 Run Again，进程内 AX 树没有可定位的按钮（日志 `history-retry-reopen-red2.log` / `red3.log`）。属于测试访问能力不足，不算业务红。不引入坐标回退，不保留不能执行目标动作的假用例；测试文件头已注明补测条件。该入口绑定的代码已接入，Core 恢复行为可验证，实际安装版点击仍须验收。
3. 窗口隐藏/重开、选中其他记录后迟到响应、迟到删除确认等组合仍要逐项补证，不能用总测试数抵扣；正式双 review、终检、最终文档回归及安装均未标完成。

### 实现期发现归因

根因是新历史入口建立了全新的 runner，却没带入持久化 ID；原先仅同一 runner 的再次执行有 ID 缓存。测试又把新增条数作为正确预期，故旧测试不会报警。本轮用“从数据库已存记录 + 新执行上下文进入”的生产回调测试作防御，且断言公开读回的原 ID 和实际条数，不只核对内存详情。目录 URL 与旧文本恢复缺口为本次红绿和全量回归进一步揭示的相关边界。

## 2026-09-16 接续完成自动化验证

- 用户同意移除历史提示词版本持久化，本轮不迁移数据库；此前未确认事项解除。旧独立历史结果入口已被用户取消，当前原型/实现统一为右侧展示与重试，不再要求不存在入口的 AXPress 验收；不是以删除要求掩盖有效路径缺口。
- 新 lifecycle 集成测试实测隐藏/重开、选中其他记录后完成、关闭窗口后完成不重新激活、迟到删除/保留期确认与保护解除。新测试先发现迟到保留期确认删除 2 条记录，现已加保护。
- 失败正文渲染测试先发现此前保留的 committedResult 导致 UI 隐藏旧正文；已修复条件，并用只存在于正文的第二段文字 OCR 防止标题造成假通过。
- 已确认的首次普通窗口铺满屏幕、双击无额外动作已同步；两个原生测试均在旧行为上先红后绿。两个已取消入口的旧测试移除/替换，不删除仍有效的失败断言。
- 完整 gate `/private/tmp/history-retry-full-closeout.log` 退出 0：340 非 App、17 App Swift Testing，XCTest、独立 native-paste/native-closed、15 AX 场景（含预期失败反例）通过。明细目录 `vlmsnapper-full-regression.d2Y48V`。此前失败记录保留，不把 AX 重跑当上一轮全绿。
- 定向证据：`history-retry-boundaries-current-red.log`、`history-retry-failed-body-red.log`、`history-retry-lifecycle-final.log`、`history-retry-complete-targeted.log`。曾因 CLT 缺 Testing 模块编译失败，以及未取消 sheet 导致测试关闭不了窗口，均与业务 red 区分。
- 本轮 review-code/review-tests 三维/四层结论和 final-regression 三张表已追加；checklist 顶部逐单位查证且记载 AC-05 批准撤销不复用。最后 `git diff --check` 与带路径的 checklist 检查通过（未传路径的首次调用报 usage，未计通过）。
- 自动化不替代安装版人工验收；真实硬件、账户发布门禁及 #23 全 feature 核销仍保留。未提交、推送、合并、打标签或发布。

### 本地安装

- 已构建并直接覆盖 `/Applications/VLMSnapper.app`，版本 `0.1.0 (37)`；不备份旧 App，不清理用户数据、历史重复项或已有备份。
- 产物 `/private/tmp/vlmsnapper-local-build37.RGq6Oa/VLMSnapper.app`，同目录保留 build/sign/verify/keychain/installed-verify 日志及 signing-metadata.plist。
- Developer ID、provisioning profile、资源/entitlements、安装后深度签名检查通过；构建与安装可执行文件 cmp 一致。随机独立服务的 Data Protection Keychain CRUD 验证通过，未读取或替换用户 API Key。
- 旧实例正常退出后覆盖，未强杀；新版启动只读确认唯一已安装实例 pid 60454、build 37、正确路径。此为本地签名测试版，不是公证发布版。
- 用户待验：记录当前条数，选中已存在的提取/翻译记录各连续重试两次，应只更新当前记录；失败时旧正文仍可读；运行时切换其他记录/关闭重开不串结果且不增加行。

### 2026-09-22 用户验收与工作区恢复

- 用户已明确确认上述 build 37 验收通过。仅核销本轮历史重试实机清单，不替代其他硬件/发布门禁。
- 用户随后授权恢复缺失的临时工作区并推送。恢复来源、差异及新的完整回归证据见 [恢复核查](workspace-recovery-20260922.md)；不合并、不发版。
