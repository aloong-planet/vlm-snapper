# 本地安装 — 2026-09-22

- 版本：0.1.0 (39)，arm64。
- 安装路径：`/Applications/VLMSnapper.app`。
- 暂存产物：`/private/tmp/vlmsnapper-history-detail.8Oj1Sc/VLMSnapper.app`。
- 全量网关退出 0 后 release 构建、Developer ID 签名和 Provisioning Profile 校验通过。
- 随机隔离 service 的 Data Protection Keychain CRUD 通过，测试项已删除，未读取或修改用户 API Key。
- 旧 App 正常退出，确认无旧进程后 ditto 直接覆盖；无备份、无用户历史/截图/设置清理。
- 安装后再次校验签名，主二进制与暂存产物 cmp 相同；读取版本 0.1.0/39，启动成功。
- 构建、签名、安装校验日志：`/private/tmp/history-detail-build.log`、`/private/tmp/history-detail-sign.log`、`/private/tmp/history-detail-installed-verify.log`。
- 未提交、推送、合并或发布。安装版人工交互验收边界见本轮 checklist/review-tests。
