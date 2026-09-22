# 成功重试冗余文案清理

来源：用户 2026-09-22 截图红框，要求删除完成后“重试 / 完成”。基线 main `6a5eb11`。
范围：仅成功态正文的冗余过程标题与状态；保留右上角图标、原文译文、指标及进行中/失败/取消/待保存反馈，不改历史数据。
原型已确认的详情正文无独立成功提示；按纯文案删除例外不新增原型或重新选型。图标、主题和 i18n 锚点已读取，沿用现有本地化，无新增颜色或图标。已批准的 Provider 标识沿用，不替换。

- [x] 真实重试集成 + 渲染红绿
- [x] 全量回归
- [x] 独立代码自审
- [x] 独立测试自审
- [x] 现行文档同步及一致性回归
- [x] 无备份签名安装，保留用户数据

不提交、推送或合并；用户此前合并授权已由 PR #28 完成，不延伸到本轮。

## 验证证据

`PYTHONDONTWRITEBYTECODE=1 bash Scripts/test-local-regression.sh` 退出 0。
证据目录 `/var/folders/9h/52q4kxb115j2nglbz0kfpkh00000gn/T/vlmsnapper-full-regression.jfkg0H`：严格构建、18 项脚本测试、58 条清单、Shell 校验、346 项非 App Swift Testing / 75 suites、8 项原生 XCTest、17 项 App 测试、两项独立原生测试及 AX 15 场景全部通过。
App 日志第 20–23 行：提取和翻译重试渲染回归通过；红测两种操作均准确识别被要求移除的文案。

## 本地安装

arm64 0.1.0 (38)，`/Applications/VLMSnapper.app`。正常退出后 ditto 覆盖，无旧 App 备份；Developer ID/profile/entitlements 深度验证及构建与安装可执行文件 cmp 通过。隔离随机服务的 Data Protection Keychain CRUD 通过，未读取用户 API Key。已启动新版。
日志：`/private/tmp/retry-success-build.log`、`/private/tmp/retry-success-sign.log`、`/private/tmp/retry-success-keychain.log`、`/private/tmp/retry-success-installed-verify.log`。不重置用户权限、设置或历史；未提交、推送或发布。
