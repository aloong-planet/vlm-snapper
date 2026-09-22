# XCUITest 无手写坐标可行性验证

日期：2026-09-15。环境：macOS 26.0.1，Xcode 26.0.1 (17A400)。本机实验，不是 CI 验收或整套测试迁移。

## 架构与范围

临时工程 `/private/tmp/vlmsnapper-xcuitest-poc.dDSU1z/Probe.xcodeproj` 含独立 ProviderProbe App 与 ProviderUITests UI Testing Bundle。App 通过本地 Swift Package 引用当前生产 VLMSnapperCore/UI，使用真实 ManagementCenterWindowController、ProviderCredentialEditor、原生密码字段和 SwiftUI Validate。

只在生产控件临时增加不可见标识：Validate 的 `.accessibilityIdentifier("provider.validate")`，NSSecureTextField 的 `setAccessibilityIdentifier("provider.api-key")`。没有修改生产点击/禁用/提交逻辑。外部 runner 用唯一 `.matching(identifier:).element`、click/typeText 操作，不使用自算坐标、AX Press 或直接调用业务回调。

验证结果止于公开 onValidate 回调：薄 App 接收 fixture 后更新自己的窗口标题，使外部测试能验证输入到达回调。没有使用 VLMSnapperApplicationModel/真实 Provider/Keychain/历史库，不将它说成完整生产 App 或真实 API 验收。测试数据均为无秘密的 poc-key-*。

## 验证过程

所有日志与 xcresult 位于上述临时工程目录。命令模板：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project Probe.xcodeproj -scheme ProviderProbe \
  -destination 'platform=macOS' -derivedDataPath DerivedData test
```

1. **运行器启动 + 缺失标识的红**：build-red.log。App 已启动，外部 AX 树明确显示原生 SecureTextField 和 SwiftUI Validate，但没有 provider.validate。等待该标识失败，Xcode exit 65。这不是编译/setup 失败。
2. **首次正向路径**：build-green.log。添加标识后，在同一 App 会话通过测试菜单改变窗口宽度为 920/1200pt，分别输入、点击、等待回调标题；1 项通过，20.238 秒，Xcode exit 0。
3. **强化断言与占用控制**：verified-green.log。两项完整通过：占用中输入/Return 不提交，解除占用后同一标识变为 enabled 并 click 成功（20.807 秒）；实际宽度断言 + 两种尺寸输入点击成功（25.702 秒），exit 0。
4. **结果负对照**：negative-result.log。只让临时 App 在收到回调时显示 Negative control reached 并丢弃结果。外部查询独立打印 POC_DROPPED_RESULT_REACHED=true，随后测试在预期 Validation received 标题不存在处失败，13.972 秒，exit 65。证明测试不是仅检查控件存在/点击无异常。负对照已撤回。
5. **还原后复跑**：restored-green.log；2 项测试、0 失败，47.516 秒，完整 All tests 汇总与 TEST SUCCEEDED。最终 xcresult 为 `DerivedData/Logs/Test/Test-ProviderProbe-2026.09.15_23-10-17-+0800.xcresult`。

实验结束后，两处生产标识已精确撤回；逐字比对本轮改动前保存的文件内容，两个文件均完全一致，保留用户原有改动。临时目录保存 `production-identifiers.patch`，在还原后的源码上 `git apply --check` 通过；复现实验需有意重加这两项标识。未替换已安装 App。

实际几何由 runner 读出，仅用于断言/诊断，不参与 click 定位：

| 场景 | 窗口 frame | Validate frame |
| --- | --- | --- |
| Compact | (156,56,920,652) | (965.5,361,72.5,24) |
| Wide | (156,56,1200,812) | (1183,361,72.5,24) |

按钮实际移动 217.5pt，测试仍以同一个标识 click。尺寸通过测试专用菜单调整，并非模拟拖拽窗口边界，所以只证明调整后的控件交互，不证明 resize 手势本身。

## 环境与未覆盖项

- 系统默认 xcode-select 指向 CommandLineTools，命令显式使用 DEVELOPER_DIR。
- 已安装 xcodeproj gem 1.22.0 不认识本地 Package 引用；临时生成器加了对应对象类型适配，生成的工程经 xcodebuild 实跑通过。不要求改变正式项目构建。
- 初次失败 run 的系统 logarchive 收集报 `/var/tmp/... Permission denied`，但 xcresult 和原测试断言仍完整。未更改系统目录权限。
- 一次成功运行中 XCUITest 检测到其他应用窗口干扰，随后继续完成。不能将此样本解读为已解决所有焦点/遮挡或 CI 可靠性问题。
- 尚未覆盖真实发布签名/系统权限、真实网络/密钥、所有 Provider、全语言/全部布局、CI runner 或长期稳定性。未人为制造遮挡来验证 hittable 的负例。
- 同标识的 disabled/enabled 对照已做；回车禁止提交检查是本机同步回调夹具下的可观察结果，不是生产异步请求绝不发生的完整证明。

## review-code

- 【① 底层前提】独立 runner 实际发现了进程内探针拿不到的 SwiftUI 节点；用实测推翻“进程内取不到就无法测试”的推断。缺标识红发生在目标查询，不是运行器失败。
- 【② 可运行性】真实构建、启动、密码输入、两尺寸点击以及占用前后完成；前台环境干扰仍作为限制。测试 App 的可见结果止于公开回调，不扩张为真实服务结果。
- 【③ 安全正确性】独立 bundle ID、无网络/Keychain 存储接线、不触碰已安装 App。初次红的 debugDescription 包含系统菜单元数据，后来删除全应用树输出；不公开该原始日志。正式迁移应限制截图/树日志范围。
- 【④ 一致性】生产修改只两项不可见标识，实验后精确还原。临时菜单/标题是实验观测面，不是产品功能；features 没有因此变假的句子或待补产品行为。泛化标识仅用于当前单卡片 PoC，正式接入应考虑 Provider/窗口作用域。

## review-tests

- 【覆盖】两个用例枚举：1. 空字段 disabled、两尺寸输入/click/结果；2. 外部 Provider 占用时字段可编辑、Validate disabled、Return 不提交、解除后 enabled/click/结果。未覆盖项明确列在上节，不以此核销整个 #24。
- 【设计】真实生产 View/controller/editor，在公开配置/回调边界装配假服务结果；无私有反射、控件像素识别或直接调用提交。外部测试只查询 AX、发送系统事件和读取可见标题。专用菜单改变测试窗口尺寸/占用配置是明确 fixture 控制，不冒充生产用户的真实网络作业。
- 【假通过】缺标识失败、丢结果失败均已看到；尺寸不是仅记录日志，而是断言 920/1200；结果断言在 click 后等待真实可见标题。不存在未 await 的异步断言或条件跳过绿。物理人工操作与在线服务不在本实验边界内。

## 下一步建议

可用这条路径正式替换当前依赖固定坐标的少量 Provider UI 用例，保留快速 SwiftPM 单元/集成测试。优先把独立 runner、稳定标识、隔离数据/签名与 CI 前台环境做成可复现接线，再迁移，不一次性替换整个测试体系。原五条固定坐标失败尚未修复；本轮不推送合并。
