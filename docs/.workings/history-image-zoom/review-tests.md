# 原图滚轮缩放测试审查 — 2026-09-22

## 1. 覆盖

| 新用例全集 | 输入与断言 |
|---|---|
| testWheelZoomsAroundPointerAndReverses | 1200×300横图，离中心80pt的指针点，正负滚动，倍率/窗口锚点几何及生产渲染 |
| testZoomLimitsAndIgnoredEvents | 零增量、带momentumPhase事件、大量正负滚动，初值不变和8/0.05限位 |
| testDraggingPansMagnifiedImageWithoutChangingZoom | 1200×1600长图，先滚轮放大后左键移动50/60pt；双轴位移与倍率不变 |

既有外部AX用例覆盖生产详情的图片入口、100%/适应按钮、关闭重开和缺图。新fixture使用实际截图常见横宽/长图比例，像素内容是非敏感绘制文本；本轮验证几何而非文件解析。没有读取用户历史或上传内容。

缺口：直接调用公开原生响应入口不是物理事件分发；真实鼠标/触控板方向、灵敏度、惯性体验及超大图低于5%的适应边界尚无实机证据。已在测试文件头和验收清单注明；不以程序化事件冒充实机验收。

## 2. Case设计

生产HistoryImagePreview置于NSHostingView，按公开NSScrollView类型查找并检查系统几何。不cast私有子类、不修改私有状态、不mock自有逻辑。窗口及本地化协调按既有模式隔离。合成CGEvent仅供原生事件入口测试，不称端到端硬件输入。没有私有测试模式进入产品。

修复测试辅助函数读取windowNumber的并发隔离warning：先在MainActor上下文取得Int，再供XCTest autoclosure使用，不削弱编译设置。

## 3. 假通过与反例

- 初始红：`/private/tmp/history-zoom-red.log`，旧实现滚轮后倍率仍1.0，放大断言失败。
- 变异：仅把上限8改成4、拖拽位移乘0。`/private/tmp/history-zoom-mutation.log` 显示重编译生产HistoryImagePreview与测试，随后x/y位移两断言和8倍上限断言准确失败，退出1。没有编译失败冒充行为红。
- 还原仅两行变异，保留所有正式修改；全量回归重编译并重跑三例。
- 断言期望来自需求固定倍率与独立窗口坐标差，不import实现常量；用例无静默skip、空循环或未等待callback。零输入/惯性用例以初始倍率为可观察量；未额外声称每条分支均单独做过变异。

渲染取证：系统临时目录 `history-zoom-fit.png` / `history-zoom-zoom.png`，当次生产View；人工读图看到倍率变化及按钮文案变化。测试绿不取代视觉读图或安装版设备手感。

## 2026-09-22 PR #29 CI 可移植性修正

CI run `35746203707` 的唯一XCTest失败为初始倍率0.753333与写死0.8不符。产品预览宽度受当前屏幕visibleFrame限制，测试把本机1000pt窗口的倍率当成了所有桌面的要求。前轮本地验证没有不同屏幕尺寸，因而没有拦住这一测试假设。

仅修改该断言：通过AppKit公开坐标转换取得实际图片与视口的渲染宽高，检查图片横向留白总计40pt且高度不超视口；滚轮倍率变化、指针锚点、反向恢复等断言保留。不是提高容差或删除适应验证。

新断言的负对照：暂时将生产setFitMode的适应倍率改为1，重新编译运行，准确在图片宽1200而期望960的几何断言失败（`/private/tmp/pr29-fit-mutation.log`，退出1）。只恢复这一行，产品最终无改动。定向三例随后使用完整网关验证；CI当前显示器上的通过仍以重跑结果为准。

审查维度：①原适应/缩放/平移覆盖保持，修正跨屏幕输入；②使用公开系统几何，不测私有倍率算法；③负对照证明新断言可红，未吞异常或跳过CI。此变更不改变用户已验收的App二进制，无需重新安装。

修正后全量本地网关退出0：`/private/tmp/pr29-portability-full.log`；完整日志目录 `.../T/vlmsnapper-full-regression.eywpsO/`。strict-build、脚本/清单、346 non-App + 12 XCTest、17 App、2独立原生与17 AX场景全部通过。
