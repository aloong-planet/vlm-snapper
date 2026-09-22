# 历史重试新增记录：诊断与修复建议（2026-09-16）

## 用户要求与本轮边界

用户要求：对历史记录重试时，更新该记录的原文/译文，不新增历史。此次仅定位及分析；没有修改生产实现、没有安装。临时诊断断言已按原行恢复，不回滚工作区其他改动。用户最新要求优先于下列已有文档中的相反描述。

## 可复现证据

命令：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter ProviderApplicationTests.historyRetrySendsOnceAndPreservesArchivedResult`。

复用已有隔离 fixture，经真实 managementCallbacks().onRetryRecord 进入业务链路；临时仅把首次成功后的条数断言从 2 改为用户要求的 1。

- 日志 `/private/tmp/vlmsnapper-history-retry-diagnosis.log`，退出码 1，测试执行 2.256 秒。
- 提取、翻译两个参数均准确失败：`(model.historyRecords.count → 2) == 1`。
- 其余断言通过，包括只发一次图片请求、原记录仍为 Archived original、新记录为 Retried result。不是重复点击生成两个请求，也不是列表重复绘制。
- 最小症状在首次成功后即可观察，无需后续截断、写库失败等流程；这些既有流程未引发此次两项断言失败。
- 对照命令 `swift test --filter PersistedOperationWorkspaceRunnerTests.rerunReplacesExistingHistoryRecord` 通过；日志 `/private/tmp/vlmsnapper-history-retry-existing-fix.log`。
- 安装 build 36 的可执行文件与本轮上一阶段签名产物 cmp 一致，未把运行旧版作为归因。

## 假设核对与根因

1. 新建 runner 丢失历史身份：成立。ApplicationModel 的 startHistoryRetry 读取原记录用于截图、类型、目标语言，却创建不携带该记录身份的新 runner/session（754–756 行）。
2. 已携带原身份但数据库误插入：不成立于当前路径。runner 初始化 preparedOperations 为空；execute 148–161 行走 prepareOperation；SQLiteHistoryStore 174–219 行明确生成 UUID 并 INSERT。UPDATE replace 接口已经存在，但此路径没有选择它。
3. 安装旧包：当前产物对照不支持。源代码路径本身能稳定复现。

旧修复提交 7567079（PR #17）增加了 runner 内按操作槽保存的身份，只保证同一 runner 连续执行时复用。历史详情入口后来以新 runner 接线，没有恢复已持久化身份。openHistoryRecord 也创建未绑定身份的 runner，是同类入口；修复时需一并覆盖，避免从菜单重新打开历史后首次重试仍新增。

## 为什么回归没有拦住

- ProviderApplicationTests.swift 315–317 行明确期待条数为 2、旧记录内容不变，后续失败/重试还期待 3、4 条。因此不是没有测试，而是历史入口测试的业务预期与用户要求相反。
- CONTEXT.md 103–104、spec REQ-002/AC-08–09、features 历史重试段落分别维护了“历史重跑创建新记录”的描述；结果窗口段落另写原地替换。实现、测试、文档围绕分叉语义自洽，但没有守住用户所要的统一重试语义。
- 本次五条菜单改动仅修改最近列表截取，不是该新增路径的来源。

## 建议修复（尚未实施）

1. 明确区分新截图操作与既有记录重试：后者通过类型化初始化/恢复入口显式绑定持久化 operationID、原图引用、操作类型与目标语言，不靠前一轮 runner 内存缓存判断身份。历史详情和重新打开历史两入口复用同一恢复能力。
2. 复用现有 replace 更新接口：只有结果完整成功时原子更新同一行的原文、译文、实际 Provider/模型及指标；保留 ID、原图、创建时间和 Pin。不插入后再删除，不按图片内容猜测合并不同记录。
3. 失败、取消、超时保留此前持久化结果，当前失败提示只属于本次尝试。保存失败保留内存结果和目标 ID；重试保存只 UPDATE，不再发网络请求。原目标不存在时明确报错，禁止自动降级为 INSERT。
4. 同步持久化结果与详情显示，避免 historyRetry 的暂存结果只覆盖视觉而没有更新原记录。成功后重新读库；切换记录、关闭重开、App 重启均显示已更新内容。
5. 先同步当前 spec、CONTEXT、features、ticket/checklist 中新增历史的相反条款，再改对应测试。既有原型无需重画，按钮和布局不变。

## 必须新增/修正的回归

- 已落库记录、全新 runner、提取/翻译：条数不变、ID 不变、按原 ID 读回新文字/译文；重新初始化 App 后仍然成立。
- 连续两次重试、菜单重新打开历史后重试：仍只有同一条；快速重复点击只发送一次。
- Provider 失败/取消/截断：原记录内容保持；不得新增失败副本。
- 成功但写库失败 → 重试保存：原 ID 更新、网络请求数不增加。
- 保留原图引用、Pin、创建时间和其他记录；验证当前 Provider/模型与原操作/语言正确。
- 原图失效、目标被移除、删除/清理互斥、切换详情及窗口生命周期：拒绝不安全请求、不串记录、不静默新建。

历史上已生成的重复记录不在本次诊断中自动清理；不能单凭截图相同判断哪条可删。若需要清理须另行确定规则和授权。
