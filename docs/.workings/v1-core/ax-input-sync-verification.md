# AX 输入同步修复验证 — 2026-09-16

基准：`0febbb48fcd9acccdefc67dc9015ebf92605511c` + 既有未提交工作 + 本次输入组件修复。没有提交、推送、合并或发布。

## 范围与来源

用户确认继续修复已独立定位的 AX 写值后 Validate 不启用问题。本次直接修复既有 spec 的 Provider 输入一致性，不另开票、不改变配置替换规则，不把整个 #24 或 #23 记为完成。

成功条件来自 [现行 spec](../../specs/v1-core.md) 的 Provider 配置及 FM-32/33/34/37/38/42：精确值进入同一草稿；可验证状态一致；清空不删除保存值；只读不接受修改；显隐不提交。验证扩展为标准 AX 输入是已批准的技术前提。其他截图、历史、更新需求不受本次组件改动影响；本轮不迁移无关旧编号或缩小既有验收范围。

## 证据（均为假凭据）

日志位于 [ax-input-sync-logs](ax-input-sync-logs/)。

| 检查 | 结果及边界 |
|---|---|
| 修复前 setter 测试 | `ax-input-red.log`：密码、明文两参数均在草稿及原生字段值断言失败。直接调用标准 setter 的未挂窗字段与外部 AX 不是同一 seam；外部原始红是前轮 step3 超时，不拿前者冒充后者 |
| 修复后原生组件 | `ax-input-editor.log`：7 项测试通过，覆盖两种模式精确 UTF-8、无自动提交、禁用/只读/隐藏、清空/非法类型/载入，以及有系统编辑器时 AX 写入后继续编辑；原有显隐选区及粘贴回归通过 |
| 外部 AX 密码 | `secure-result.json`：原场景 5 步，exit 0；真实生产视图从输入到精确回调结果 |
| 外部 AX 明文 | `plain-result.json`：真实显隐按钮切明文，6 步，exit 0 |
| 跨 Provider 活动 | `blocked-result.json`：草稿可编辑、Validate 禁用，3 步，exit 0；不是输入框禁用测试 |
| 丢弃结果负对照 | `drop-result.json`：第 5 步确认确实进入丢弃回调，第 6 步等成功结果超时，exit 1，预期失败；证明点击成功不等于业务成功 |
| 严格构建 | `ax-input-strict.log`，warnings-as-errors，exit 0 |
| 应用组合 | `ax-input-app.log`：15 项完成，exit 0，完成摘要校验通过 |
| 原生菜单/窗口 | `ax-input-native-paste.log` 与 `ax-input-native-closed.log`：各 1 个 XCTest，exit 0。此处依据 XCTest 1 项而非 Swift Testing 的 0 项摘要 |
| 全量非应用组 | `ax-input-non-app.log`：334 项、72 suites，5 issues，exit 1。失败均为既有 `ProviderCredentialInteractionTests` 坐标点击后的提交断言（237 四参数、358 一项）；输入值断言通过。与 [既有单变量定位](24-provider-click-diagnosis.md) 的失败位置和机制一致。该运行早于新增挂窗 setter 回归，最终该新增项由定向组补测；不得称最终全量通过 |

## Review 边界

- 保护分支的临时移除变异被工具安全策略拒绝，补丁未落盘、未执行变异；不能宣称这些负向断言完成了变异证明。正向 AX 输入与反向禁用/隐藏条件测试仍已执行。
- 本轮未访问真实 Provider 账户、真实密钥或真实截图。正式签名自检使用随机 service 和假 Keychain 项。
- AX 场景观测期间没有前台变化，但瞬时激活事件的负对照仍未完成。无坐标 AX 操作不替代物理鼠标、键盘焦点、视觉和遮挡验收。
- fixture 位于临时目录，使用本次源码重新构建；Runner 固定签名身份不变。完全隐藏窗口与当前可见后台窗口不是同一覆盖范围。
- 不修复旧坐标测试来凑绿、不跳过其结果；该真实未完成项继续归 #24。全量网关未完成，不提交或开 PR；本地测试安装以本次相关回归、严格 release 构建、签名和 Keychain 自检为边界，不代表完整交付。

## 安装

已无备份更新 `/Applications/VLMSnapper.app`，版本 `0.1.0 (34)`。构建目录 `/private/tmp/vlmsnapper-local-build34.hVfr2M` 保留 build/sign/verify/keychain/install/installed-verify 日志：release 严格构建、Developer ID/profile/entitlements 校验、随机 service 的 Keychain CRUD、正常退出与覆盖安装均 exit 0；安装后可执行文件与本轮签名产物 cmp 一致，版本读回 34，已发送后台启动。未清理用户历史/截图/设置/凭据；没有备份、提交或发布。
