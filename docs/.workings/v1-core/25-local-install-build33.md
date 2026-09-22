# 2026-09-15 本地安装 build 33

用户要求直接覆盖安装，不备份；此后本项目代码改动完成且相关验证、构建与签名校验通过后自动安装。持续偏好已写入项目 AGENTS.md。

- 来源：codex/remaining-feature-requirements，0febbb4 + 当前工作树，包含历史详情右上角重试图标及内联真实重试功能。
- arm64，0.1.0 (33)，安装路径 /Applications/VLMSnapper.app。
- release 严格编译、Developer ID 签名、嵌入 profile/entitlements、包结构/版本检查、随机隔离服务下 Keychain CRUD 均通过。
- 正常退出旧版后直接替换 App；未创建旧 App 备份，未清理既有备份。未改动历史、设置、截图、真实凭据或系统权限。
- 安装后的深度签名/profile 校验通过，可执行文件与本次构建产物逐字节一致；已启动新版。
- 日志及签名元信息：/private/tmp/vlmsnapper-local-build33.y0PmE1/。
- 未提交、推送、合并或发布。此前 16 项相关测试通过，但全套原生测试未完成；本次安装不替代用户交互验收。

建议验收：打开一条原图仍在的历史记录，检查详情右上角重试图标与悬停提示，点击后确认进度及结果在右侧显示。
