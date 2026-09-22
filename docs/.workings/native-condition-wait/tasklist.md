# 原生测试条件等待

本轮仅调整测试同步，不改变产品行为。沿用已推送的恢复分支，避免将其尚未合并的恢复内容丢掉或重复移植；不推送、合并或发布。

## 验收口径

- 立即检查具体断言对应状态，仅未满足时每 10 ms 重查。
- 原固定 100/50 ms 分别作为对应等待的上限；已有 2 秒条件等待不延长。
- 不把“没有发生”简单换成立即为真的等待条件；同步回调直接断言，异步负向观察保留完整观察窗口。
- AXRunner 没有逐点击固定等待，本次不修改独立 AX 工具；保留其前台防护及清理。
- 不改变产品 Sources/UI、凭据、历史数据和本地安装。

## 任务

- [x] 等待契约红绿测试及调用点替换
- [x] 定向重复测试与全量本地回归
- [x] 独立代码自审（review-code）
- [x] 独立测试自审（review-tests）

本次不涉及用户可见行为：features 中没有因此失实或缺失的产品描述，不需要原型调整或重装相同 App。按项目能力声明，i18n 已启用，但本次不新增产品文案。

## 2026-09-22 本机测量

基线：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --scratch-path /private/tmp/vlmsnapper-condition-wait-build --filter 'HistoryInteractionTests|ProviderCredentialInteractionTests'`，退出 0；历史 5 项 21.138 秒，Provider 7 项（含参数化输入）5.597 秒。基线只测一轮，不作为普遍性能承诺。

最终定向命令：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'NativeConditionWaitTests|HistoryInteractionTests|ProviderCredentialInteractionTests|MenuBarPanelActionButtonTests'`。

连续三轮均退出 0；每轮另外检查 XCTest 完成 5 项、Swift Testing 完成 13 项/3 suites，防止提前退出被当成通过。

| 轮次 | 历史交互（秒） | Provider 交互（秒） |
|---|---:|---:|
| 1 | 15.330 | 2.251 |
| 2 | 15.567 | 2.057 |
| 3 | 15.432 | 2.002 |

日志：`/private/tmp/vlmsnapper-wait-repeat-{1,2,3}.log`。表内是测试框架报告的套件时间，不包含编译、启动及所有全量测试，也不是单次点击耗时。

## 环境与边界

- 首次命令未设置项目 Xcode 工具链，SDK 不匹配；改用项目网关指定的 Xcode。
- 工作区恢复后的 `.build` 同时残留旧路径依赖和 PCH；单独修依赖路径不足以修复 PCH。最终将旧构建缓存移到 `/Users/loong_zhou/.openclaw/workspace/tmp/vlmsnapper-stale-build.CQQoB4/build`，保留可恢复性，并在当前路径全新构建。没有改产品依赖版本或用户数据。
- 初版等待写错 fixture 状态导致一次定向失败；已纠正，见代码自审。首轮全量绿后又消除了重复扫描，最终三轮定向完成，最终全量再次通过。

## 最终全量网关

`bash Scripts/test-local-regression.sh`：退出 **0**。

- 严格构建、Python 脚本测试、需求清单校验、Shell 语法：通过。
- 非 App：Swift Testing **346 项 / 75 suites**，另含原生 XCTest **8 项**，全部通过。
- 应用集成：**17 项**，通过。
- 原生菜单粘贴、关闭窗口期间完成验证：各 **1 项**，通过。
- AX：**15 场景**，全部通过。

证据目录：`/var/folders/9h/52q4kxb115j2nglbz0kfpkh00000gn/T/vlmsnapper-full-regression.BmAuDe`。
AX 证据：`/var/folders/9h/52q4kxb115j2nglbz0kfpkh00000gn/T/vlmsnapper-ax-regression-8in4q9si`。

最终改动仅测试及本轮施工文档；没有提交、推送、合并或重新安装产品 App。

## 后续授权

2026-09-22：用户确认“提交并推送”。本次提交上述已验证改动到当前恢复分支并推送 origin；不包含合并或发布授权。上面的未提交描述是上一轮交付时的状态。
