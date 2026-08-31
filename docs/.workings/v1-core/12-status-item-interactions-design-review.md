# Ticket 12 design review

## Review result

方案可以实现，且不需要新增视觉方向。用户已确认 companion-shell 原型。设计审查发现并修正了两个容易被“点击后关闭面板”掩盖的状态问题：恢复 sheet 不能被提前关闭；右键菜单也不能为了视觉切换而先销毁可能承载恢复或退出取消状态的 popover。

## Facts checked

1. 当前 `MenuBarPanelController` 只配置一个 target/action，没有调用 `NSControl.sendAction(on:)`，因此右键没有独立路径。
2. 当前 SDK 将状态项的自定义入口放在 `NSStatusItem.button`，按钮的 `sendAction(on:)` 是当前 API；旧的 `NSStatusItem.sendActionOn` 已弃用。
3. AppKit 提供 `NSMenu.popUpContextMenu(_:with:for:)` 和 `NSPopoverDelegate.popoverDidClose`，不需要 Carbon 或时间延迟猜测。
4. 主面板 Capture Screen 已接到 `MenuBarContainerView.routeCapture()`；ready 分支最终调用的 `VLMSnapperApplicationModel.capture()` 与全局快捷键一致。
5. 当前缺失的是 popover 关闭完成与 ready capture callback 之间的宿主时序，不是第二套截图实现。
6. 当前显式 Quit 回调先调用模型 `prepareForTermination()`，再调用 `NSApp.terminate(nil)`；应用代理也会在 `applicationShouldTerminate` 再次执行相同准备。把右键 Quit 直接交给应用代理可消除这条重复协调路径。

## Findings and corrections

### 1. Unconditional popover dismissal — rejected

失败序列：用户未配置 Provider → 点击 Capture Screen → popover 先关闭 → SwiftUI 将 `activeSheet` 设为 Provider → sheet 已失去可见宿主，用户看不到恢复界面。

修正：先计算 `MenuCaptureRoute`。只有 `.capture` 分支通过宿主关闭后执行；`.configureProvider` 与 `.recoverPermission` 仍原地展示 sheet。

### 2. Fixed delay before capture — rejected

失败序列：代码调用 `performClose` 后等待任意 dispatch 延时 → 慢机器上 popover 尚未关闭，快机器上等待无意义 → 冻结帧可能包含 VLMSnapper 面板或产生不稳定延迟。

修正：使用 `popoverDidClose` 作为唯一完成信号；隐藏状态则立即执行。

### 3. Duplicate termination preparation — removed

失败序列：菜单 closure 先准备终止 → `NSApp.terminate` → application delegate 再准备一次 → 活动状态可能被重复关闭或弹出两次确认。

修正：右键菜单只请求 `NSApp.terminate(nil)`，应用代理保持唯一协调入口；删除主面板专用 Quit callback 及其失去用途的模型方法。

### 4. Closing an active popover before showing Quit — rejected

失败序列：Provider/permission sheet 打开或结果存在未保存状态 → 右键先关闭 popover → 用户点击 Quit 后在确认中取消 → 应用继续运行，但原 sheet 状态已丢失。

修正：上下文菜单作为原生临时表面弹出，不主动关闭现有 popover。取消菜单或取消退出都保留原状态。

### 5. UI-only tests — insufficient

只渲染截图无法证明鼠标事件、关闭时序或 closure 路由。

修正：增加事件分流、菜单内容与动作、dismissal 时序和 capture route 行为测试；渲染测试只负责主面板视觉回归。

## Approved implementation boundary

允许修改状态项 controller、菜单容器/面板、生产 application delegate/model wiring、相关 UI 测试和当前行为文档。不得改动截图核心、Provider adapter、数据库、更新器或现有 termination coordinator 的业务规则。
