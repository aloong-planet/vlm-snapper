# 管理中心实机反馈与诊断（2026-09-14）

## 来源与范围

用户在本地 build 30 测试后报告：默认窗口太小；侧栏过宽且信息不符原型；历史单击不能切换；从历史双击打开结果后关闭结果应返回列表，而非所有窗口不可见。

本轮仅诊断、添加失败回归测试，未交付修复、未更新安装包。源版本参考 `0febbb48fcd9acccdefc67dc9015ebf92605511c` 加既有未提交修改。此前将选择失败留在原生测试工装问题下，不能再据此搁置：本轮已获用户实机复现并得到手势对照证据。

## 已核实证据

### 默认尺寸被挂载过程覆盖

`HistoryWindowNativeTests.testOpeningKeepsDesignedDefaultContentSize` 检查生产控制器公开窗口：初始化内容区 1200×720；`show(.history)` 后变为 920×620，断言失败。

临时边界日志进一步确定：`contentViewController` 挂载前为 1200×720，挂载后立即为 920×620。关闭 hosting controller 的 sizingOptions 无效，不能以此作为修复。临时日志已清除。

- `/tmp/vlmsnapper-history-size-red.log`
- `/tmp/vlmsnapper-history-size-options-probe.log`
- `/tmp/vlmsnapper-history-size-attachment-probe.log`

### 单击与双击手势冲突

最小场景：生产管理窗口、两条隔离历史 fixture、真实 key window、第二行中心的原生鼠标事件，观察选中行和公开 onSelectRecord；不直接设置选择状态。

纠正 mouseUp 投递后，同一测试得到对照：

1. 原实现失败：选中行仍是 0，选择回调未触发。
2. 临时仅移除行上的 `onTapGesture(count: 2)`：XCTest 1 test / 0 failures，0.453 秒。
3. 恢复原手势：再失败，选中行仍是 0，回调未触发。

这支持双击手势拦截列表单击的因果判断。移除双击不是最终修复，双击打开仍须保留，并补测同一行文字、留白、双击及键盘选择。所有生产探针已恢复。

- `/tmp/vlmsnapper-history-minimal-red.log` 与 `-repeat.log`：原合成事件版本连续两次红。
- `/tmp/vlmsnapper-history-native-event-probe.log`：修正事件投递并移除手势的完整绿。
- `/tmp/vlmsnapper-history-restored-gesture-red.log`：同一投递方式恢复手势后的红。

### 测试本身的缺陷

旧 `combinedQueryAndSelection` 本轮仍在 key-window 前置条件失败，未跑到单击。新隔离 XCTest 能获得焦点。

原先连续 `window.sendEvent(mouseDown)`、`window.sendEvent(mouseUp)` 的方式也不适合原生列表的鼠标追踪循环；预先把 mouseUp 放入 NSApplication 事件队列，再发送 mouseDown，才取得完整测试结果。中途退出、只有退出码 0 却无 XCTest 结束汇总的实验不算通过。

### 侧栏信息缺项（静态对照）

原型具备「资料库」「设置中心」分组，历史总数、钉住总数及 Provider 数量；当前 App 仅四个按钮与分隔线。原型动态历史数量来自全量 fixture，而非当前过滤结果。两者当前侧栏宽度均为 218，因此缩窄是本轮新增调整，不是已有原型尺寸的回补。

### 关闭结果缺少返回路径（静态追踪）

从历史打开结果会调用管理窗口隐藏；结果 `windowShouldClose` 最终只 `orderOut`，模型关闭/丢弃工作区后没有恢复管理窗口的动作。需区分「从历史进入」与「新截图进入」，不能每次关闭结果都打开管理中心。

## 待确认的布局建议

更新：用户已确认 1200×780 默认内容区、180pt 侧栏。原型已按此调整，等待更新后的视觉预览确认；其余条目仍作为后续实现与验收要求，不表示已完成。

- 默认内容区 1200×780pt；按当前屏幕可用空间约束，不遮挡菜单栏或 Dock。
- 左侧菜单 180pt；中间历史列表继续 260pt；剩余宽度给详情。
- 补回分组及真实数量，保持已确认图标、无选中边框。
- 初始化挂载后应用默认尺寸；普通刷新、设置往返、暂时隐藏和结果返回不得重置用户手动尺寸。

### 原型更新核对

- 进一步全文件检查发现：此前「两者侧栏均 218」仅准确描述原型基础样式；历史页后续规则覆盖为 200，媒体查询还含 195。现统一为 180，去掉相互覆盖的侧栏和历史列表宽度规则。
- 保留分组、数量与现有当前 Provider 摘要；中间列表统一 260。默认原型外框 1202×828，扣除 46px 模拟标题栏及边框后内容区为 1200×780；默认框受桌面预览可用空间约束。
- 原生 App、安装包均未改动。只完成原型静态检查，不能用它抵扣 App 验收。
- CUA 首次连接超时，重试成功列出已有预览；读取已有页随后被 Browser Use URL policy 拒绝（本地 file URL），未改用其他入口绕过，浏览器渲染/交互验收待用户刷新检查。

## 修复验收清单（尚未实现）

- [ ] 更新并确认尺寸/侧栏原型，再同步 spec 与 ticket 承兑映射。
- [ ] 挂载真实页面后默认尺寸生效；小屏边界不越屏；用户手动缩放不被刷新重置。
- [ ] 侧栏分组、数量、宽度与确认原型一致；中英文与明暗渲染。
- [ ] 单击整行切换选择与详情，不打开结果；双击同一行正确打开且不触发 Provider 请求。
- [ ] 从历史进入结果后，红色关闭钮或 CmdW 恢复原管理窗口，保留筛选/搜索/Pinned、选择及滚动位置。
- [ ] 取消未保存结果的丢弃确认时不返回列表；确认关闭后才恢复。
- [ ] 新截图来源关闭结果不凭空打开管理中心；真正退出 App 不重新弹窗。
- [ ] 代码 review。
- [ ] 测试 review（包括真实事件投递、完整结束汇总、无假绿）。
- [ ] 全量验证与安装版交互验收；目前不得声明通过或收口。

复现命令：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter HistoryWindowNativeTests
```

测试仅使用缺失截图路径的隔离记录，不读写用户实际历史、Keychain 或 Provider API。
