# 本地安装 — 2026-09-22

- 安装目标：`/Applications/VLMSnapper.app`，0.1.0 (40)，arm64。
- 来源：当前分支 `codex/history-retry-success-cleanup`，`6a5eb11` + 已保留前轮与本轮未提交修改；无提交/推送/合并/发布。
- 全量回归退出0后构建；release warnings-as-errors通过。
- Developer ID签名、Provisioning Profile、hardened runtime及时间戳校验通过。
- 随机测试条目的Data Protection Keychain CRUD通过；未操作用户API Key。
- 旧App正常退出，经pgrep确认退出后直接ditto覆盖，无备份。安装后再次签名校验，二进制cmp与验证产物一致，读取版本确认40，并启动App。
- 不删除历史、设置、截图、用户凭据或旧备份。仅删除本轮测试产生的4个可再生成Python字节码缓存。

证据：`/private/tmp/history-zoom-build.log`、`history-zoom-sign.log`、`history-zoom-keychain-smoke.log`、`history-zoom-installed-verify.log`。构建及签名元数据：`/private/tmp/vlmsnapper-history-zoom.pkJuyH/`。

请用户在历史详情点击图片，用真实鼠标滚轮/触控板测试缩放方向与手感、左键拖拽、适应窗口复位和关闭重开。自动化原生事件及AX验证已通过，不代替这项设备体验验收。

## 用户验收补记

2026-09-22 用户回复“验收通过，合并”，确认本次安装版交互验收，并授权提交、推送及合并。保留此前执行记录；没有新的发布授权，不重复安装同一代码。
