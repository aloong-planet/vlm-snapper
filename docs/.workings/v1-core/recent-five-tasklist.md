# 最近记录默认五条

用户明确要求直接同步原型、App、文档并安装，不再单独等待原型确认。范围：菜单栏最近记录最多五条；不足五条显示实际数量；完整历史列表不变。沿用当前宽度、行样式、入口和排序。本次继续当前未提交工作区，不新开分支、不提交或推送。

- [x] 原型补足五条，保留现有样式。
- [x] TDD：通过临时 SQLite 历史和真实菜单渲染观察数量、截断、空/不足五条；不访问个人历史。
- [x] 同步 App 的数据截取和视图数量限制。
- [x] 回归测试与 App 视觉核对；原型源码核对五条、样式不变。浏览器安全策略拒绝本地 HTML 预览，自动视觉核对未完成，不绕过。
- [x] 独立 review-code。
- [x] 独立 review-tests。
- [x] spec / features / 原型文档一致性回归。
- [x] 签名校验后覆盖安装，无备份，保留用户数据。

## 验证和安装证据

- 红：`/private/tmp/vlmsnapper-recent-five-red.log`，6 条样本的第 4、5 条缺失断言失败；空/2 条通过。
- 定向绿：`/private/tmp/vlmsnapper-recent-five-green-isolated.log`；最终完整 App suite 覆盖 0、2、5、6 四组输入全部通过。
- 完整门禁：`/private/tmp/vlmsnapper-recent-five-regression.log`，严格构建、18 项 Python、checklist、shell 语法、335 + 16 项 Swift Testing、8 + 2 项 XCTest 通过。首次 AX 在 step_13 因 `foreground_changed` 中断，保留失败、不冒称单轮全绿。
- AX 不改断言单独重跑：`/private/tmp/vlmsnapper-recent-five-ax-rerun.log`，15 场景全部通过（含 1 个预期失败的反例），退出码 0。全部门禁阶段最终均有通过证据。
- 原生视觉：系统临时目录 `vlmsnapper-ticket13-renders/menu-en-light.png` 与 `menu-zhHans-dark.png` 实际查看，五行与 footer 完整；测试画布调整至 530pt 后英文箭头也完整。
- 本地包：`/private/tmp/vlmsnapper-local-build36.vpbBA0/`；build/sign/verify/keychain/install/installed-verify 日志保留。
- 安装位置 `/Applications/VLMSnapper.app`，0.1.0 (36)，Developer ID、profile、entitlements、深度签名及隔离 Keychain CRUD 均通过。覆盖前正常退出；包内同步，无备份，无用户数据删除，无提交/推送/发布。
