# 测试自审 — 2026-09-22

## 维度一：覆盖

| 本轮用例/输入 | 覆盖 | 边界 |
|---|---|---|
| HistoryInteractionTests.test06HistoryThumbnailKeepsAspectRatioAndHeight；1200×300 宽图、1200×780 窗口 | 真实像素的比例与 100pt 上限 | 上下零 padding、全宽边框及小标题另以生成整窗图人工核对；非物理点击 |
| AX history-image；生产 ManagementCenterView、窄窗口 | 打开预览、100%/适应切换、关闭、再次打开 | AXPress 非鼠标坐标；未验证 Esc/长图滚动/父窗口关闭 |
| AX history-image-missing | 缺图有历史页但无原图按钮 | 指定 step_2 为预期失败，不能任意错误就通过 |
| historyRetryUpdatesOriginalRecord；提取/翻译，真实应用装配与受控 HTTP | 进行中 Preparing 渲染存在且无 Retry 标题；成功新内容可见且无 Retry/Done | 完整结果、失败保护与落库原 ID 断言保留；不是在线 Provider 验证 |
| 既有全量测试 | 原生历史查询/选择、重试身份及生命周期、配置、权限、持久化等回归 | 不抵扣现行 spec 已保留的硬件/发布 Pending |

图片 fixture 保留用户截图的宽图比例形态，几何定位使用单色填充而非正文 OCR；重试 fixture 保留多段原文和可选译文。安装版 Esc、关闭父窗口、长图和多显示器等缺口已写入测试文件头，需用户本机验收，不写成通过。

## 维度二：case 设计

仅在外部 HTTP/凭据边界控制 fixture；生产 View 与真实业务装配未 mock。预览用 View 的公开图像输入，不调用 private 方法。图片测量的 400×100 为用户确认规格和输入比例的独立真值，不 import 实现常量。用户图像选择身份校验保留原生产保护。

原来等待 HTTP 请求后立刻 OCR 是上游/下游传播错位，修为直接轮询 Preparing 可见文本。内进程 AX helper 无法识别 SwiftUI 虚拟节点，已删除而非当作红绿证据。AX 脚本 case 约束按历史/凭据两类行为分别核对，不把新增历史 case 硬套 Validate。

## 维度三：假通过

`/private/tmp/history-detail-mutation.log`：将本次缩略图 100→210、恢复真实 retry content 的 Retry 标题，重建后图片尺寸断言失败，提取/翻译的进行中及成功正文标题断言均失败；报告中实际 OCR 含 Retry。仅用精确补丁撤销变异，无 git restore/reset。还原后的完整回归退出 0。

负向 AX 场景必须先出现 ready 窗口，再在指定按钮等待处失败；成功 AX 场景两次打开关闭，最终回到 ready 主窗口，不只断按钮存在。此前 `/private/tmp/history-detail-red.log` 的 nil 不计有效红灯。无条件 return 跳测、构建失败冒充断言红、未等待异步的新增路径。

全量结果：严格构建；18 脚本测试；58 条既有 ownership 行检查；346 个非 App Swift Testing + 9 个 XCTest；17 个 App Swift Testing；两个隔离原生 XCTest；17 个 AX 场景。日志总入口 `/private/tmp/history-detail-full.log`，分阶段证据 `.../T/vlmsnapper-full-regression.DZts05/`。这些结果允许本地试装，不等同用户验收或全 feature 收口。
