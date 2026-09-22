# 2026-09-14 本地安装 build 31

用户明确要求“安装app”；本次仅本地测试安装，不提交、推送、合并或发布，不改变 #25 未完成的验收状态。

- 来源：`codex/remaining-feature-requirements`，基线 `0febbb4` + 当前未提交工作树。
- arm64，0.1.0 (31)。沿用本地开发更新源，不具备正式发布含义。
- `Scripts/build-macos-app.sh` release 严格编译通过；Developer ID 签名、嵌入 profile / entitlement 校验、结构与版本校验、随机隔离凭据的 Data Protection Keychain CRUD 均通过。
- 构建及验证日志：`/private/tmp/vlmsnapper-local-build31.3Yfw2m/` 下 `build.log`、`sign.log`、`verify.log`、`keychain.log`。
- 正常退出旧进程后安装至 `/Applications/VLMSnapper.app`，启动新版。未强制终止、清理历史、读取真实 API Key 或重置 TCC。
- 原 build 30 保留在 `/Applications/VLMSnapper.app.backup-20260914-build30-before-navigation`，可回退。

待实机检查：Provider / Settings 跳转及侧栏高亮；默认窗口、缩窄导航和扩大的详情；单击切换历史、双击打开后关闭返回原列表。#24 同进程原生失败/挂起及 #25 checklist 中未验证组合仍未解决，签名或安装成功不抵扣这些验收缺口。
