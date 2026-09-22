# 测试提前退出：修复与验证

日期：2026-09-15。基准 commit：0febbb48fcd9acccdefc67dc9015ebf92605511c，当前工作树含之前的产品改动。本轮仅改历史交互测试宿主、完成报告检查脚本及 CI 接线。

## 失败与定位

- `/private/tmp/vlmsnapper-exit-history-baseline.log`：原 Swift Testing 历史套件前三项通过，第四项开始后进程退出 0，无完整报告；外层完成检查退出 1。
- 单独 combinedQueryAndSelection 通过；queryWindowLifetime 与它同进程执行可以重现提前退出。不是据一次孤立通过判定解决。
- `/private/tmp/vlmsnapper-exit-stack2.log` 的正常 exit 栈经过 Swift 并发 runtime 的 async-main drain 和生成的包测试 runner main，不是生产应用 main。
- `/private/tmp/vlmsnapper-exit-runloop-stop4.log` 捕获到测试宿主外层 CFRunLoop 停止后退出。调试器会影响时序；尚未确定触发停止的具体私有调度块，不推广为所有 Swift/AppKit 版本的缺陷。
- 分别去掉嵌套 RunLoop、停止派发激活事件、关闭窗口动画，以及组合去掉动画和嵌套 RunLoop，都未稳定解决全组提前退出。这些试验已撤回，不能把其中一次双例通过当因果证据。

## 修复边界

五项事件驱动的历史测试迁到已有 XCTest 宿主，保留生命周期前置顺序、真实生产窗口、合成事件、26 条期望与 25 条必需前置检查。没有跳过用例、缩短路径、放宽时限或修改生产焦点策略。

CI 的两个 Swift Testing 命令均保留 pipefail，并增加成功、非空、完整结束报告检查。其余两个隔离 XCTest 命令已经检查各自的一项完成报告，继续保留。此脚本不是测试发现数量核对器，也不替代退出码；专用于含 Swift Testing 的两条 CI 命令，XCTest-only 的零项 Swift Testing 尾注不计成功。

## 验证记录

| 验证 | 结果与证据 |
| --- | --- |
| 首次迁移 | 5 项 XCTest 完成并通过，19.429 秒；exit-xctest-host.log |
| 换回旧宿主变异 | 重新编译原 Swift Testing 源码，日志出现原 suite/测试标题；第四项后到第五项开始，再次退出 0 且无完成报告；exit-host-mutation.log |
| 精确还原后 | 5 项 XCTest 完成并通过，19.592 秒；exit-restored-history.log |
| 第一次原始非 App 全套 | 8 项 XCTest 通过；331 项 Swift Testing 完整结束，5 条失败；exit-fixed-full.log |
| 第二次原始非 App 全套 | 8 项 XCTest 通过；331 项 / 72 suites 完整结束，仍为相同 5 条失败，进程 exit 1；exit-restored-full.log |
| App 回归 | 15 项 / 1 suite 完成并通过，9.247 秒；exit-app-regression.log，完成脚本 exit 0 |
| 完成脚本 TDD | 缺失报告 fixture 对空检查实现失败，补检查后通过；真实旧日志也被拒绝 |
| CLI 回归 | 5 项 unittest 通过，覆盖空/零测试/失败/混合/逆序/迟到活动/缺文件/CRLF/正常报告 |
| shell 门禁反例 | 旧不完整日志 + producer exit 0 → exit 1；有效报告 + producer exit 7 → exit 7；有效报告 + exit 0 → exit 0。验证实际 bash pipefail、tee 和检查 CLI，不用内部函数 mock |
| 严格编译 | warnings-as-errors / C warnings gates 通过；exit-strict-build.log |
| 静态检查 | bash -n Scripts/*.sh、git diff --check 通过 |

上表日志统一位于 `/private/tmp/vlmsnapper-` 前缀下，例如 exit-restored-full.log 的完整路径是 `/private/tmp/vlmsnapper-exit-restored-full.log`。临时日志是本次证据，不是长期产品规范。

## review-code

- 【① 底层前提】exit 0 不能证明完成，已反例证实；宿主替换使用相同用例并做还原。注释仅描述观测，不断言具体 AppKit 私有调用是唯一根因。
- 【② 可运行性】五例 XCTest 自动发现、顺序及全套共存均实跑；缺失报告会造成整条 CI 的错误放行，属于上层逃逸，本轮已补门禁。没有生产生命周期变更。
- 【③ 安全正确性】检查器只读指定日志；失败默认拒绝。CI 同时检查真实进程退出状态，不依赖日志单独证明成功。未读取真实密钥或操作生产数据。
- 【④ 一致性】全量枚举 .github/workflows 与 Scripts 中的 swift test 调用：两条混合运行补报告检查、两条隔离 XCTest 保留原检查。迁移范围仅历史五例；旧窗口等待问题不据此关闭。未引入新测试抽象或生产注入。

## review-tests

- 【覆盖】五个原用例逐项保留初始图片回调、Provider 筛选、窗口 query 生命周期、组合筛选/选择、渲染；脚本输入形态源自真实截断日志，并覆盖缺失/空/失败/正常报告。GitHub 托管 runner 尚未运行；需后续合法推送后验证。
- 【设计】沿用真实生产窗口及公开操作/回调，迁移只改测试宿主和等价断言。CLI 测试经子进程执行脚本，未 mock 自有模块。窗口编号化测试名有意保留触发问题的前置顺序，而非以重排藏掉问题。
- 【假通过】旧宿主重新编译后确实重现无完成报告；精确还原后原断言完成。脚本无检查时反例在 returncode 断言失败，补实现后为绿；pipeline 的退出码与完整性分别打反例。合成事件/渲染不等于物理输入、VoiceOver、签名 App Keychain 或真实 API 验收，此缺口在测试头保留。

## 未解决项及归宿

全套完成后暴露 ProviderCredentialInteractionTests.swift:237 的四组参数和 :358 的一组失败：提交回调数组为空。影响是 Provider 原生交互回归门禁，尚不能断言生产 Validate 功能损坏；测试使用固定点击坐标，是否命中控件仍待验证。

建议下一步单独定位命中目标/回调路径，不调松断言、不重跑直到绿。归入本地 #24 的后续测试诊断记录；本次不改它，不关闭 #24 全票或 #23 收口。不满足合并门禁，因此未推送/合并。

测试代码不进入 App 安装包，本轮未修改或覆盖已安装的 0.1.0 (33)。不创建备份、不更改用户数据。
