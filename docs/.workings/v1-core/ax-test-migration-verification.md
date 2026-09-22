# Provider 无坐标测试迁移与全量回归

日期：2026-09-16。基于 `0febbb48fcd9acccdefc67dc9015ebf92605511c` 与当前工作树既有改动；本轮没有提交、推送或安装生产 App。

## 结果

最终命令 `bash Scripts/test-local-regression.sh` 退出 **0**，输出 `Full local regression passed`。

| 验证 | 结果 |
| --- | --- |
| 严格 Swift/C 构建（warnings-as-errors） | 通过 |
| 非 App Swift Testing | 335 tests / 72 suites 通过，完整结束标记有效 |
| 同组原生 XCTest | 8 tests / 0 failures |
| App Swift Testing | 15 tests / 1 suite 通过，完整结束标记有效 |
| 独立主菜单 Paste XCTest | 1 test / 0 failures |
| 独立持续关闭期间完成 XCTest | 1 test / 0 failures |
| Python 脚本测试 | 18 tests 通过，其中新增报告门禁 7 项 |
| 清单门禁、逐脚本 bash 语法 | 通过 |
| 外部后台 AX | 14 正向场景通过 + 1 负对照按预期拒绝 |
| Python -O 下报告门禁 | 7 tests 通过，拒绝反例不依赖 assert |
| git diff --check | 通过 |

定向 ProviderCredentialInteractionTests：7 个方法（含 4 组初值×输入方式和 3 组非法输入参数）全部通过；Native API Key 字段测试仍由全量覆盖，未删除保护测试。保留物理键鼠、签名 Keychain、联网账号的独立验收边界。

## 新旧映射及有效性

映射见 [测试说明](../../../Tests/AXScenarios/README.md)。旧坐标失败关联的 2 个方法没有以删 coverage 的方式消失：键盘/Return 责任留在原生套件，按钮责任改由生产 View 的 AX 行为覆盖。另一非法输入方法的坐标负测也移除，以按钮 enabled→disabled→enabled 交叉对照和原生 Return 拒绝替代。

新夹具 `Tests/AXFixture` 属于单独 SwiftPM executable target；打包脚本仍只构建/复制 VLMSnapperApp，fixture 不进入生产安装包。授权客户端仍是固定 AXRunner，临时目标路径变化不要求给目标授权。

负对照不是“任何失败都算过”：前 5 步必须成功，第 5 步看见 `AX fixture result dropped`（公开提交回调已到达），第 6 步等待成功标题必须 `wait_timeout`。要求 report.exitCode=1、进程退出1、stage=step_6、正常清理。最终实测满足；正常场景通过精确 Provider/假值/首次提交结果。权限、前台变化、错误控件、早期超时不能冒充这次预期失败。

## 保留失败证据

首轮全量路径 `vlmsnapper-full-regression.X0hEPz`：335 项已通过，但运行期间修改入口脚本导致后续读取错误，脚本退出127；**不计全量通过**。固定脚本后重新执行全部阶段，最终运行 `vlmsnapper-full-regression.uUlt6i` 退出0。没有重跑某个失败业务断言直到绿，也没有延长等待或削弱断言。

最终 AX evidence：`/var/folders/9h/52q4kxb115j2nglbz0kfpkh00000gn/T/vlmsnapper-ax-regression-xgdvofv_`。最终完整日志及 AX 场景/报告复制至 [ax-test-migration-logs](ax-test-migration-logs/)；不归档二进制或任何真实凭据。

## 收口边界

- 本轮仅测试代码、执行入口、CI 报告门禁与 Testing Decisions 更新；产品实现及 UI 无变化，未覆盖安装 App。
- 未创建 release、PR 或合并；没有清理用户数据或既有 App 备份。
- 当前5条旧坐标失败已由新用例替代并完整回归通过；不代表 #24 历史焦点/toolbar 偶发等待根因已确认。
- 全量中的原生测试可能激活窗口；只有 AX 部分验证非激活后台动作。托管 CI 运行报告门禁，不声称已获得 AX 桌面权限。
