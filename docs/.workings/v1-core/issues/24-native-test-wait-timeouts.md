# 24 — Diagnose intermittent native test wait timeouts

**Status:** ready-for-agent

**Blocked by:** none

## 需求来源与分类

[v1-core spec](../../../specs/v1-core.md)；参考 commit：0febbb48fcd9acccdefc67dc9015ebf92605511c，含未提交改动。
这是测试基础设施的技术诊断票，不是新产品功能；不为它虚构产品 REQ。支撑现有原生 Provider/截图组合验收及 v1-core::REQ-001 的回归验证。
流程依据：/review-tests 的真实失败证据与验证边界；/to-tickets 的 Gate/Test/Evidence。
现有断言和超时标准不因引入新清单而被削弱。

## Problem and scope

Historical native integration runs occasionally exceeded the bounded wait for the Provider management window to become key, or for the capture toolbar to appear after selection. These are two different wait boundaries; neither original timeout has a confirmed root cause. A visible window is not proof that it is the key window receiving keyboard/menu actions.

The independently reproduced isolated-deinitializer/TaskLocal teardown crash has a test-owned lifetime correction. It must not be presented as the explanation or resolution of these earlier deadlines. Ten consecutive complete App/native suite pairs passed after that correction, but a passing sample does not prove the timeouts cannot recur.

## Impact

Affected acceptance paths are the native main-menu Paste test and the application capture/toolbar integration test. A timeout fails CI/acceptance and can obscure whether the test setup or application window lifecycle is at fault. The current evidence does not establish a user-visible focus defect. The production application must not be forced permanently foreground or changed solely to make a test pass.

## 技术前提与流程验收

- [ ] Reproduce each failing boundary separately, or explicitly retain its root cause as unconfirmed. — **Evidence**: preserve the first failing run with setup, source commit, actual wait and complete report; no diagnosis-by-green-rerun.
- [ ] At the failing wait, record only non-secret window visibility/key state, activation, responder type and workflow stage; do not record field contents, clipboard contents, screenshots or credentials. — **Evidence**: inspect every diagnostic output field and retained sample.
- [ ] Distinguish application activation, key-window ownership, field-editor focus and toolbar creation; identify the first violated precondition before proposing a fix. — **Evidence**: ordered event/state trace and explanation of the first divergence, separately for each boundary.
- [ ] Use an event/state-based bounded wait if evidence supports it; do not increase sleeps/deadlines or remove assertions to manufacture a pass. — **Test**: a state-transition test and unchanged deadline/negative control; if not yet justified, report blocked rather than change production focus.
- [ ] Prove a targeted fault fails the intended assertion, then run the repaired test and neighboring lifecycle tests in fresh and shared processes with exit-code and completion-report checks. — **Gate**: both execution modes must complete and report all expected cases; **Test**: target mutation red and restored result.
- [ ] Record remaining uncertainty, including possible observer effects, instead of treating repeated green runs as a root-cause explanation. — **Evidence**: per-boundary unresolved list in the final diagnosis; no blanket “fixed” verdict.

## Comments

- 2026-09-16 用户授权评估并替换旧测试后，Provider 固定坐标子问题完成迁移：保留 AppKit 输入/粘贴/Return，按钮由当前源码构建的生产 View AX 场景覆盖。14 正向场景与1严格负对照通过；完整本地门禁退出0，335非App + 15App Swift Testing、10 XCTest、18 Python tests 全通过。旧5条坐标失败已不再是当前待修项。原焦点/toolbar等待问题仍保持未确认，不关闭本票。映射和日志见 [迁移验证](../ax-test-migration-verification.md)。

- 2026-09-15 XCUITest 可行性 PoC 已验证：独立 UI runner 驱动复用生产 Provider UI 的薄 App，通过稳定标识完成密码输入、920/1200pt 两尺寸点击，以及 disabled→enabled 提交；最终 2 项通过，丢弃回调结果的负对照按预期失败。两处临时生产标识已精确撤回。验证止于公开回调，不含真实服务/Keychain/完整 App，也不关闭本票的焦点、toolbar 或原五条固定坐标失败。后续建议在本票中正式接入少量 Provider UI 用例，等待实施授权。见 [实验与验证边界](../24-xcuitest-feasibility.md)。

- 2026-09-15 五条 Provider 失败已独立定位为测试旧点击坐标问题：1200pt 窗口旧 x=1125，而 Provider 卡片宽度封顶居中；改用实际输入框右边缘 x=1032.5 后同组 7 项全部通过，还原后五条原断言重现。生产代码/焦点/等待不变。四处同类坐标中也包含负向点击，存在点空白却假通过风险，建议下一步在本票修复定位并补命中对照。见 [完整诊断](../24-provider-click-diagnosis.md)。本轮仅诊断，临时变更已还原，尚未把修复记为完成。

- 2026-09-15 提前退出子问题已作局部修复：历史原生事件五例从 Swift Testing async-main 宿主迁到 XCTest，旧宿主变异重现 exit 0 无报告、还原后五例通过；两次非 App 全套均完整结束，未再提前退出。增加 CI 完整报告检查，不能仅凭 exit 0 判通过。此结论不关闭旧焦点/toolbar 等待问题，详见 [验证与分层审查](../24-early-exit-verification.md)。
- 同次全套暴露 5 条真实失败断言（ProviderCredentialInteractionTests.swift:237 四组、:358 一组），提交回调为空；影响原生 Provider 交互回归，固定坐标是否打中当前按钮待查，不等于已确认生产 Validate bug。建议下一步单独诊断，归本票后续项；当前保持失败，不放宽断言，不推送合并。

- 2026-09-14 本轮导航同步追加：`/tmp/vlmsnapper-navigation-final.log` 同进程 HistoryWindowNativeTests 共 3 例，菜单和尺寸通过、单击等待第二条选中失败；`/tmp/vlmsnapper-history-interaction-final.log` 前 3 例完成后进入渲染，退出 0 却缺少总完成报告，不计通过。`/tmp/vlmsnapper-navigation-full.log` 非 App 全量进入 Swift Testing 后超过四分钟未结束，定向中止本轮 swift-test/测试子进程，exit 130。未操作另一个 worktree 的既有进程。隔离 App 集成 14 例完整通过（navigation-app.log）不解释上述失败。
- 单击断言另做有效性校验：只移除当前新增的单击处理，生产 View 被重编译，`/tmp/vlmsnapper-single-mutation.log` 在第二条选中等待处失败；只还原该段后 `/tmp/vlmsnapper-single-restored.log` 同一测试完整通过（0.871s，含双击）。这证明该断言能捕获这项缺陷，不证明它在同进程稳定，也不是物理鼠标验收。

- 2026-09-14 #25 原生UI同步遇到新的合成鼠标夹具不稳定：/tmp/vlmsnapper-history-key-window.log 首先失败于 isKeyWindow=false；模仿隔离 XCTest 显式消费 appKitDefined 激活事件后焦点为真，但第二行选择/设置返回失败（history-activation-events.log）。共享进程及异步试验有退出0却无完整结束报告（history-gesture-check.log、history-async-interaction.log、history-row-hit-target.log、vlmsnapper-ui-sync-final-full-tests.log），不计通过。全局事件泵及生产手势试验已撤回。同期独立XCTest主菜单Paste/持续关闭完成各1例通过，尚不足以解释差异。#25 保留验收缺口，建议本票后续以隔离原生夹具/事件路径继续诊断；这不是原来超时的根因结论。未修改生产焦点/超时策略，也不永久置顶。

- 2026-09-09 unforced reproduction during display-reconfiguration regression: `/private/tmp/vlmsnapper-display-native.log`, rebuilt current source, process exit 1, 3 native tests / 1 failure. Paste waited five seconds at `key-window-wait`: the target management window was visible and `canKey=true`, but `active=false`, `key=-1`, `main=-1` throughout the recorded wait; it failed before Paste or Validate. Both subsequent lifecycle/closed-window tests passed, and the process completed without SIGABRT. This is now a captured failure at the original key-window boundary, not proof of why activation failed, not the toolbar deadline, and not an installed-app defect. Preserve this run rather than rerun until green; production focus behavior remains unchanged.

- 2026-09-09: user requested recording the focus issue before Ticket 23 closeout. This ticket tracks the remaining diagnostics, not an implemented production fix. Historical observations and the separate teardown reproducer are in `../native-flake-diagnosis.md`; recent complete-run evidence is in `../native-lifetime-tasklist.md`.

- 2026-09-09 Provider-icon regression: current build, App suite exit 1, 14 tests /
  1 failure in nativeCaptureAndRerunPreserveHistoryWhileProviderValidationIsExclusive,
  ProviderApplicationTests.swift:321 (toolbar wait after drag). Log:
  /private/tmp/vlmsnapper-provider-marks-app.log. Desktop inspection independently
  reported the Mac locked. This records the environment, not a proven causal
  explanation. No rerun/timeout change or production focus change; native
  key-window acceptance deferred until an unlocked interactive session.
