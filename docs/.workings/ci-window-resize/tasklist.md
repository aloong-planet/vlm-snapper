# CI 原生窗口尺寸测试修复

## 范围和成功标准

修复 PR #28 的测试 fixture，不修改产品窗口策略。沿用当前 PR 分支；用户已授权修复并继续合并。
承兑 `v1-core::US-001/AC-17`：首次铺满屏幕可用区域，不进入独立全屏；临时隐藏与页面切换后保留用户框架。

测试 seam：真实 ManagementCenterWindowController 的 show/hideForCapture 和公开 NSWindow 几何属性，不 mock 控制器或改系统屏幕分辨率。

- [x] CI 日志及本地超屏尺寸复现
- [x] 屏幕内有效尺寸 fixture 与定向绿测
- [x] 恢复尺寸回归的变异检验
- [x] 全量本地网关
- [x] 独立代码自审
- [x] 独立测试自审
- [ ] 推送、CI 通过、按既有授权合并

## 初始证据

CI run 35707540804：1100pt 宽的窗口重新显示变为 1024pt；断言失败在重新显示后的严格框架相等检查。
本机以当前可用宽度 + 76pt 复现：1588pt → 1512pt，测试退出 1；日志 `/private/tmp/vlmsnapper-pr28-resize-red.log`。
原测试用固定 1100×700 content size，忽略 CI 较小屏幕与标题栏尺寸。此次保留严格断言，先证明调整尺寸真实生效且窗口仍在屏幕内。

本轮无用户可见变化；features 没有失实或缺失的描述，无需原型、产品文案变更或重新安装相同 App。项目已启用 i18n，本次不新增产品文案。

## 最终本地验证

`PYTHONDONTWRITEBYTECODE=1 bash Scripts/test-local-regression.sh` 退出 0。
严格构建、脚本测试 18 项、清单 58 项、Shell 校验、非 App Swift Testing 346 项 / 75 suites 和原生 XCTest 8 项、应用集成 17 项、独立原生粘贴及关闭窗口测试各 1 项、AX 15 场景全部通过。
证据目录：`/var/folders/9h/52q4kxb115j2nglbz0kfpkh00000gn/T/vlmsnapper-full-regression.E6hQm6`；AX：`/var/folders/9h/52q4kxb115j2nglbz0kfpkh00000gn/T/vlmsnapper-ax-regression-szalzmvj`。

Spec 终检：首次铺满、普通窗口模式、调整尺寸生效、隐藏后切页保持原框架四项均由真实窗口断言兑现，没有扩张产品需求。远程 CI 与合并状态以 GitHub 当前 PR #28 为准，此处为提交前本地验证记录。
