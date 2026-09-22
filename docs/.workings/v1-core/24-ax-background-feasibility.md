# AX 后台 PoC：授权前准备

## 2026-09-16 后续：固定通用客户端已安装

后续授权与执行改用 `/Users/loong_zhou/Applications/AXTestTools/AXRunner.app`，不再授权下文历史记录中的临时 Runner。通用源码及使用说明：`/Users/loong_zhou/Developer/ax-test-tools/README.md`；项目步骤已迁入 `Tests/AXScenarios/provider-background.json`。fixture目标仍可临时构建，授权身份由固定Runner承载。

固定客户端 Developer ID 签名安装完成；重新preflight和scenario都返回 `accessibility_permission_required / 77`，仍未启动fixture或验证真实AX交互。语法合法不表示selector已经实机核实。9项通用执行语义测试及结果变异检查不能代替本页要求的真实负对照。

以下保留原PoC的历史过程。

2026-09-16，当前结论：**运行前置权限阻断，尚未验证 AX 后台交互可行性**。

## 范围

临时工程 `/private/tmp/vlmsnapper-ax-poc.jJXSUo/AXFixture.xcodeproj`。

- AXFixture：通过本地 package 使用当前生产 ManagementCenterView、ProviderCredentialEditor 和原生密码字段；测试自己的 NSWindow 非激活启动，不调用会主动激活的生产 controller.show。结果止于 onValidate 的精确假值检查，不接真实 Provider/Keychain/用户历史。
- AXRunner：独立进程，通过系统 AX 子树枚举、AXValue 写入、AXPress、窗口结果标题查询验证。无 CGEvent、真实鼠标键盘、剪贴板或强制激活操作。只读取 fixture 控件树；其他应用仅观察前台 PID/激活事件，不读取内容。
- 未改生产源码，未安装、推送或合并。无产品行为变化，features 无因此变假的描述；不适用产品 UI 原型/i18n 更新。沿用用户批准的小 PoC，不建立正式产品分支。

## 已执行证据

1. `AXProbe.swift` 无提示调用 AXIsProcessTrusted。初次用默认 CommandLineTools 编译遇到 module cache 权限错误；改用明确 Xcode DEVELOPER_DIR 与临时 module cache 后可编译。
2. CLI 沙箱内：AX_TRUSTED=false / FRONT_PID=-1，exit 77。沙箱外只读预检：AX_TRUSTED=false / 有效前台 PID，exit 77。因此不能只归因为沙箱看不到桌面。
3. Xcode 初次构建因 Notification 非 Sendable 跨 actor 编译失败；改为在回调外提取 pid_t 后传入 MainActor。此编译失败不计测试有效红。
4. `build-retry.log`：xcodebuild exit 0，BUILD SUCCEEDED。AXRunner codesign --verify --strict 通过，Info.plist LSUIElement=true。
5. `open -g -W -n .../AXRunner.app` 后，`runner-result.log` 明确 AX_TRUSTED=false、BASELINE_FRONT_PID 有效、EXIT_CODE=77。open 自身 exit 0 只证明启动请求完成，不代表子程序测试通过。
6. 客户端在权限 guard 退出，未启动 AXFixture，未进行密码写入或按钮动作。未弹出授权请求、未修改系统权限。

## 补测前提与步骤

用户如同意，手工在系统设置 → 隐私与安全性 → 辅助功能中添加并启用：

`/private/tmp/vlmsnapper-ax-poc.jJXSUo/DerivedData/Build/Products/Debug/AXRunner.app`

这是测试专用客户端，不是正式 VLMSnapper。授权允许它通过辅助功能控制其他 App；本 PoC 实现将操作限制到本次启动的 fixture。测试结束可撤销授权。未自动打开设置或授予权限。

获授权后，先无 flag 测可见但后台窗口；如通过，再分别测 `--hidden` 与 `--drop-result`。运行器 `--blocked` 是后续诊断入口，当前成功判据仍要求提交结果，不能将它计为已实现的独立阻断断言。不能把其他输入方式替换 AXValue 后的通过说成 AXValue 通过。

若字段不可写、写入未触发 editor、SwiftUI 控件不可发现或 AXPress 抢焦点，按实际失败报告，不修改生产逻辑制造绿。只有局部路径成功时，报告局部结论。

## review-code

- 【① 底层前提】独立 AX 客户端需要自己的可用授权；预检确认为 false，不沿用 XCUITest 通过结论。构建来源为当前 package，不依赖上次旧二进制。
- 【② 可运行性】两个 target 编译成功；运行只到权限 guard，真实控件枚举/写入/动作/结果全部未验。正常路径只终止自己启动且 bundle ID 匹配的 fixture；fixture 60 秒自退出作为实验兜底，不是生产等待策略。窗口装配与生产 controller.show 不同，显式列为边界。
- 【③ 安全正确性】只用 poc-key-ax-only；不记录 AXValue 或其他应用树。无 TCC 修改、权限提示、焦点写入或外部服务。启动配置 activates=false、fixture accessory；这些是设计配置，不是已验证不抢焦点。
- 【④ 一致性】生产文件无变动。实验 app 的英文标题是精确结果观测面，不是产品文案或真实网络结果。按 label+role 严格唯一匹配仅用于这一固定英文 PoC，不宣称可直接迁移到全 Provider/多语言。

## review-tests

- 【覆盖】权限阻断与编译已验证；后台控件发现、精确数据提交、前台保持、隐藏窗口、结果负对照待授权。没有完整生产 App、网络、Keychain、键盘焦点或鼠标命中覆盖。
- 【设计】公开生产 View/editor 装配，假服务结果在公开 onValidate 边界；没有私有成员 cast 或直接调用提交。前台检查含前后 PID 与 workspace 激活通知，但不能冒充连续用户键入验收。
- 【假通过】成功需 AX 写成功、Validate enabled、AXPress 成功、精确回调结果和前台不变同时满足。缺任一应非零；尚未通过真实反例验证这些断言。权限退出77与编译失败不计红绿测试。前台事件监测没有故意抢焦点的真实负对照，不宣称已证明短暂切换必能捕获。
