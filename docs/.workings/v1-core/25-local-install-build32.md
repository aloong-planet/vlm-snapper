# 2026-09-14 本地安装 build 32

用户要求安装本地 App。仅本地测试更新，不提交、推送、合并或发布。

- 来源：codex/remaining-feature-requirements，0febbb4 + 当前工作树，包含记录栏原生样式对齐。
- arm64，0.1.0 (32)，安装路径 /Applications/VLMSnapper.app。
- release 严格编译、Developer ID 签名、嵌入 profile / entitlements 校验、包结构和版本检查、随机隔离服务下的 Keychain CRUD 均通过。保留开发测试更新源。
- 日志与签名元信息：/private/tmp/vlmsnapper-local-build32.yEcPwk/。
- 旧 App 正常退出后更新；旧 build 31 保存在 /Applications/VLMSnapper.app.backup-20260914-build31-before-history-style，可回退。
- 未清理历史、读取真实 API Key 或重置屏幕录制权限。

建议验收：记录栏选中蓝底、未选中悬浮灰底、悬浮选中项不变色、圆角与留白；单击记录切换详情；键盘焦点和上下移动。实际验收未因安装成功自动通过。前轮尚未同步的默认铺满/取消双击/内联重试不在本次安装范围内。
