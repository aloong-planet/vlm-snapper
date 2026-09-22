# 2026-09-15 历史详情重试验证

基线：`codex/remaining-feature-requirements`，HEAD `0febbb4` 加当前未提交修改。本轮未安装、提交、推送或发布，不覆盖前轮安装验收结论。

## 已有证据

| 检查 | 证据与结果 |
|---|---|
| 缺接线红测 | `/private/tmp/vlmsnapper-history-retry-red.log`，预期未发出图片请求，退出1 |
| 请求和恢复 | `/private/tmp/vlmsnapper-history-retry-final.log`，提取/翻译两种路径，退出0；含重复点击、互斥、截断、SQLite写失败、本地保存与图片替换 |
| 删除保护红测 | `/private/tmp/vlmsnapper-history-retry-delete-red.log`，源记录被删导致最终3条而非4条，退出1；只改当前新增保护，不恢复整个文件 |
| 原生可见结果 | `/private/tmp/vlmsnapper-history-retry-rendered-result.log`，生产右侧详情的渲染 OCR 读到 Retried result/Translated result，退出0；不是只断言内存字段 |
| 首次详情/外观 | `/private/tmp/vlmsnapper-history-retry-ui-final.log`，2测试通过；8组中英、明暗、920/1200宽 PNG 位于系统临时目录 `vlmsnapper-history-ui-sync`，已查看浅色1200和深色920，重试在右上角且与Pin/Delete同排 |
| 应用组合组 | `/private/tmp/vlmsnapper-history-retry-app-suite.log`，15测试通过，退出0（新增OCR断言单独日志如上） |
| 严格构建 | `/private/tmp/vlmsnapper-history-retry-build.log`，warnings-as-errors退出0 |
| 清单门禁 | `verify-feature-checklist.py`：58 requirements；Scripts单测日志 `/private/tmp/vlmsnapper-history-retry-checklist-tests.log` |

## 不计为通过

最终补充：`/private/tmp/vlmsnapper-history-retry-verified-final.log`，16项测试、2个suite通过，退出0；包含提取/翻译的原生详情OCR。`/private/tmp/vlmsnapper-history-retry-initial-mutation.log`移除initial回调后在选中ID为nil处红，退出1，只还原该行后已包含在最终绿测。`/private/tmp/vlmsnapper-history-retry-clear-red2.log`故意保留只保护源记录的旧实现，清空新记录后在本地保存成功断言处红（6条），退出1；最终改为暂停全部历史删除，源记录与待保存新记录同时受保护。测试仅在失败断言记录后恢复隔离DB，避免红测清理阻塞于未保存状态，未把恢复后的结果计作通过。

- 全核心/UI组 `/private/tmp/vlmsnapper-history-retry-full-core-ui.log` 运行3分35秒后仍无 Swift Testing 完成摘要；仅停止本次父/子PID4322/5532，返回143。未诊断其根因，也不称为代码测试通过。作为既有原生测试不稳定事项 #24 的本次补充证据；#25/#23不据此收口。
- 并行发起的旧 Provider editor 检查在构建等待阶段60秒超时，退出124；没有得到该门禁验证结果，不能归因于重试业务。此调用不替代本轮测试。
- NSView AX遍历未列出SwiftUI重试图标，并非按钮不可见证据。新建初始加载测试只验证真实选中回调；图标及结果可见性分别由原生渲染与渲染OCR验证。
- 没有真实API调用。安装版物理点击/hover、进行中关闭重开、未保存退出确认、自动清理时序仍待验收。默认铺满屏幕与取消双击不是本轮已实现项。
- 首次清空负向用例清理未结束，已停止本次测试28381/28818，143；调用`sample`命中了PATH中的同名Python脚本而非系统采样器，未取得栈，不据此宣称已证实停顿根因。后续测试增加失败后的隔离DB恢复，再次负测已在正确断言上退出1。
