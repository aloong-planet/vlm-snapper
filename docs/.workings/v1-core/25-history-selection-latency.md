# 2026-09-14 历史条目单击延迟诊断

范围：用户报告点击历史消息左侧条目切换详情不流畅。按历史记录列表而非最左侧 History/Provider/Settings 功能导航复现；不将本结论扩大到所有导航。来源为 build 31 对应当前工作树（0febbb4 + 未提交代码）。本轮只诊断，不交付修复或重新安装。

## 反馈环

生产 `ManagementCenterView`、`ManagementCenterWindowController`，两条短文本历史记录，真实 NSWindow 的程序化鼠标事件；测鼠标事件发送前到选择回调可观测更新，保持已有选中行/不打开结果断言。没有数据库、网络、PNG 解码、真实密钥。不是已安装 App 的物理点击端到端时间。

命令：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter HistoryWindowNativeTests.testSingleClickSelectsAnotherHistoryRecord`。
临时诊断断言为 <150ms，仅用于区分即时选择与约半秒等待，不是已经商定的产品性能指标。后续三次通过临时环境开关只测单击，明确不承兑双击回归；首次基线仍走完整原用例。

| 对照 | 单击到选择耗时 | 诊断断言 | 完整日志 |
|---|---:|---|---|
| 原实现第一次 | 439.66ms | 失败 | /tmp/vlmsnapper-history-latency-baseline.log |
| 原实现第二次 | 424.74ms | 失败 | /tmp/vlmsnapper-history-latency-baseline2.log |
| 仅暂时移除双击手势 | 57.48ms | 通过 | /tmp/vlmsnapper-history-latency-no-double.log |
| 还原双击手势 | 440.42ms | 失败 | /tmp/vlmsnapper-history-latency-restored.log |

四次均重建所测代码、完整结束。系统 NSEvent.doubleClickInterval 为 0.5s。程序化事件夹具还有 #24 同进程不稳定问题；上述隔离 A/B/A 结果不替它结案。

## 原因与影响

候选依次为：单/双击竞争、详情/列表渲染负担、测试事件调度。最小数据已复现；只改变双击识别器后延迟降低，原样还原后延迟恢复，支持当前 `.onTapGesture(count: 2)` 与单击识别组合在选择前引入等待。此对照没有覆盖大型真实截图的额外解码延迟，不能声称实际用户路径的所有开销都已排除。

实际产品路径位于 `VLMSnapper/UI/ManagementCenterView.swift` 的 `historyContent`。此前修复让单击最终能够选择，却仍与双击判定耦合；旧测试允许两秒内最终选中，只防“不能选择”，不防“约半秒后才选择”，所以未发现流畅性退化。双击处理在移除时仍属于需求，仅用作诊断反例，不能将去掉双击作为修复。

建议在 #25 内修复：第一次点击立即选择，第二次点击只附加打开结果动作，避免用排他性的双击判定阻塞选择；以原生选择/双击事件分离的方式验证，不调系统双击速度、不加 sleep、不取消双击功能。修复时补即时选择、双击打开一次、快速跨行点击及查询/返回组合回归。当前待用户授权修复。

## 清理

双击实现已原样还原；临时计时、150ms 断言、环境开关已移除，未修改已安装 build 31。保留日志与本诊断，未把一次对照变快记为产品已修复。
