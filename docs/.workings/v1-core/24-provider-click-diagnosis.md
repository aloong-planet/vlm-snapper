# Provider 五条失败断言独立定位

2026-09-15；用户要求只定位。基准 commit 为 0febbb48fcd9acccdefc67dc9015ebf92605511c，工作树包含此前 UI 改动。

## 结论

这五条断言的直接原因是测试点击坐标过期，并非本轮证据所显示的生产提交链路失效。测试把 Validate 横坐标写成 `content.bounds.width - 75`；当前 1200pt 窗口的 Provider 内容最大宽度为 850pt 且居中，按钮并不跟随窗口右边沿。

实测旧点击 x=1125，新对照点击 x=1032.5（原生输入框 frame.maxX），偏差 92.5pt。仅改变这项点击坐标、不改变任何生产代码、状态、超时或回调断言，整组 7 项测试通过；精确还原旧坐标并重编译后，原五条失败全部重现。

## 证据链

1. 独立命令：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer /usr/bin/xcrun swift test --filter ProviderCredentialInteractionTests.otherProviderJobBlocksNativeSubmission`。baseline 日志最终报告 1 项 / 1 issue，0.949 秒，exit 1，失败是提交数组为空。
2. 排序假设：点击位置过期；占用解除未恢复按钮；按钮命中但提交链路不工作。每个假设均先告知用户，再加探针。
3. 辅助功能探针没有拿到 SwiftUI 虚拟按钮节点，不能据空结果判定按钮不存在/禁用；改用测试自身渲染图和单变量鼠标对照。未访问用户密钥、剪贴板或真实 API。
4. `/private/tmp/vlmsnapper-provider-diagnosis-hit.log`：两项参数化测试的五条失败重现，测试窗口 1200×780；isKeyWindow=false。
5. `/private/tmp/vlmsnapper-provider-diagnosis-coordinate-control.log`：输入框 frame=(290.5,521,742,16)，只将四处旧点击 x 改为各自输入框 maxX，原 y 和事件发送路径不变。7 项 / 1 suite 全部通过，6.036 秒，exit 0；五个正向场景的 key 仍为 false。因此“改变了焦点才通过”不能解释本对照。
6. `/private/tmp/vlmsnapper-provider-diagnosis-restored.log`：撤销所有临时坐标变化和探针，重编译原测试；7 项完整结束，:237 的四组参数及 :358 的一组仍失败，5.936 秒，exit 1。

baseline 日志：`/private/tmp/vlmsnapper-provider-diagnosis-baseline.log`。测试渲染图：`/private/tmp/vlmsnapper-credential-empty.png`，仅含 fixture 假凭据掩码。辅助功能失败探针单独保留在 buttons.log，不当作按钮状态证据。

## 为什么之前没发现

- `ProviderCredentialInteractionTests.swift:227-228` 的注释称坐标适配最小宽度、预填正向用例证明命中；当前窗口不是该假设的旧布局，且预填正向用例同样失败，注释已过时。
- 前一轮测试宿主提前退出使完整测试结果未呈现；完成报告门禁修复后才暴露这些断言。不能用之前 exit 0 证明它们通过过。
- 全 Tests 检索同类表达式共四处，均在这个文件：:121 非法草稿禁用点击、:229 正向验证及复用、:334 占用中点击、:356 占用解除后点击。前两种负向路径若点到空白，回调为零也会假通过；这两类点击需要与正向路径使用同一个真实命中目标。
- App 测试既有 `ProviderApplicationTests.swift:1118-1122` 采用输入框实际 frame.maxX，没有采用窗口右边沿。横向对照可复用其做法，但它仍是相对几何定位，不保证未来任意布局都有效。

## 建议处理及归宿

建议下一步在 #24 修复测试：收拢这四处 Validate 定位，使用实际控件位置并验证目标命中；保持真实 mouseDown/mouseUp 路径，不直接调用提交回调或 AX press 冒充点击。覆盖最小/默认窗口宽度，正向与负向共享目标，负向用例增加能证明点击命中的对照。删除过时的“预填已证明命中”注释或替换为本轮可验证的前提。

本轮不修改 App 来迎合过期测试、不宣称物理鼠标或真实网络验证通过。辅助功能定位在当前 runner 不可用，应明确保留限制，不能假造获取到按钮 frame 的证据。原 #24 的窗口聚焦/toolbar 超时是另外的问题，未由此解释或关闭。

诊断结束已精确还原 ProviderCredentialInteractionTests.swift，git diff 对该文件为空；临时 `[DEBUG-provider-hit]` 探针全部移除。未安装、提交、推送、合并。
