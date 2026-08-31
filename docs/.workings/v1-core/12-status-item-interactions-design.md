# Ticket 12 — Status item interactions design

## Scope

本票只调整菜单栏状态项的点击分流、退出入口位置和主面板截图按钮的宿主衔接。截图冻结、选区、裁切、持久化、Provider 请求以及应用终止协调继续使用现有实现，不复制业务流程。

已确认的原型位于 `docs/prototypes/companion-shell/`：左键入口是主面板，右键入口是只含“退出 VLMSnapper”的原生上下文菜单；主面板不再保留退出按钮。

## Interaction contract

### Status item

状态栏按钮订阅左键抬起与右键抬起事件：

- `.rightMouseUp` 显示原生 `NSMenu`；
- 其他由状态栏按钮送达的激活事件保持既有主操作语义，打开或关闭 `NSPopover`；
- 右键菜单只创建一个本地化 Quit item，不添加设置、历史、更新或分隔线。

显示上下文菜单时不主动销毁已打开的 popover。这样若 Provider sheet、权限恢复 sheet 或未保存结果确认阻止退出，原界面状态仍可保留；应用真的终止后，系统自然回收两个表面。

Quit item 不直接调用模型私有退出方法。它请求 `NSApp.terminate(nil)`，继续由 `VLMSnapperApplicationDelegate.applicationShouldTerminate` 作为唯一终止协调入口调用 `prepareForTermination()`。这避免按钮路径和 Command-Q 路径出现重复准备或不同语义。

### Capture button

主面板的 Capture Screen 按钮继续调用 `MenuBarContainerView.routeCapture()`。路由顺序不变：

1. Provider 不可用：保留 popover，显示 Provider 配置 sheet；
2. Provider 可用但权限不可用：保留 popover，显示权限恢复 sheet；
3. 两者均可用：请求宿主关闭 popover，并在 `popoverDidClose` 后调用现有 `callbacks.onCapture`。

`callbacks.onCapture` 仍指向 `VLMSnapperApplicationModel.capture()`，与全局快捷键共享同一入口。活动结果窗口、替换选区和真实 `ScreenCaptureKit` 截图行为都继续由该入口决定。

## Host seam

`MenuBarPanelController` 向 SwiftUI 内容注入一个主线程隔离的 dismissal coordinator。容器把待执行 closure 交给该 coordinator：

- popover 未显示时立即执行；
- popover 正在显示时保存一次待执行动作、请求关闭，并仅在 `popoverDidClose` 回调后执行；
- 普通 transient 关闭没有待执行动作，不触发截图。

环境中没有 coordinator 时立即执行 capture callback，使 preview、离屏渲染和非 popover 宿主不依赖 AppKit controller。

一个窄的 `MenuBarPanelDismissalCoordinator` 封装“是否显示、请求关闭、关闭后执行”的时序，可在不真实显示状态栏 UI 的测试中证明回调顺序。`MenuCaptureActionHandler` 封装三种路由对应的可见动作，防止未来把配置或权限分支误改成关闭面板。

## User-operation failure modes

1. 左键点击隐藏的状态项面板：打开主面板。
2. 左键点击已显示的状态项面板：关闭主面板，不触发其他动作。
3. 右键点击状态项：显示一个 Quit item；不触发截图或打开主面板。
4. 右键菜单被点外取消：应用与现有 popover 状态都不改变。
5. 点击 Quit 且没有阻塞：应用代理完成协调终止。
6. 点击 Quit 但未保存结果确认取消：应用保持运行，现有 popover/sheet 状态不因显示右键菜单而丢失。
7. 点击 Capture Screen 且 Provider 未配置：显示 Provider sheet，不关闭 popover，不截图。
8. 点击 Capture Screen 且权限未就绪：显示权限恢复 sheet，不关闭 popover，不截图。
9. 点击 Capture Screen 且已就绪：先关闭 popover；只有关闭完成后才进入现有截图链路，冻结画面不会包含菜单面板。
10. popover 已因其他原因关闭后执行 ready capture action：截图 closure 立即执行，不等待不存在的关闭通知。
11. transient 关闭或 Escape 没有 pending action：不启动截图。
12. active workspace 已存在：同一 `capture()` 入口只前置结果窗口，不开始第二次截图。
13. selection 已存在：同一 `capture()` 入口按现有行为替换旧冻结选择，不创建平行状态机。

## TDD seams and gates

纵切顺序：

1. 先用失败测试锁定事件分流：右键进入上下文菜单，左键及无鼠标事件保持主操作。
2. 先用失败测试锁定上下文菜单只有一个本地化 Quit item，并能调用注入的退出 closure。
3. 先用失败测试锁定 dismissal coordinator：面板显示时回调延后到 didClose，隐藏时立即回调。
4. 先用失败测试锁定三种 capture route：只有 `.capture` 使用关闭后截图动作，两个恢复分支保持面板。
5. 更新渲染测试，证明主面板不再渲染 Quit 行且现有界面仍可离屏渲染。

每个纵切执行目标测试与 warnings-as-errors build；整体执行完整 Swift 测试、现有 UI 渲染、`git diff --check`、本地化键一致性和本票源码/测试 CJK 扫描。

## Out of scope

- 不改变截图快捷键、冻结帧、选区或操作栏。
- 不增加右键设置、历史、更新检查或其他菜单项。
- 不增加截图标注或编辑。
- 不改变退出确认文案或更新安装流程。
