# 原图滚轮缩放一致性回归 — 2026-09-22

本次按spec增量实施，不是全feature收口。版本参考 `6a5eb11` + 本轮未提交修改；承兑映射及缺口在 `../v1-core/checklist.md` 本轮AC-20段，未另维护票状态。

## 阶段一：逐句核真

| 声明面 | 对照端与结论 |
|---|---|
| spec REQ-002/AC-20、失败模式26 | wheel原生入口、限位、惯性忽略、拖拽、独立sheet；原子行为已对照，物理设备/超大图边界缺口写入清单 |
| features历史图片段 | 不再把滚轮描述为原尺寸下滚动；更新为指针缩放、拖拽、滚动条及适应按钮，范围与spec一致 |
| 已确认原型showOriginal | 对照倍率上下限、指针位置、拖拽、按钮、关闭复位，交互一致；AppKit原生实现不复制DOM代码 |
| 中英history.zoomHint与Strings | 两语均为滚轮缩放/拖拽平移，已出现在当前原生渲染 |
| CONTEXT / ADR-0006 | 只处理已验证图像快照、不写文件、不修改历史身份及路径归属；无需新术语或架构决策 |

## 阶段二：关系对读

| 关系 | 本轮结论 |
|---|---|
| v1-core与features/specs索引 | 原功能内的图片交互增量，名称及索引概述不变 |
| 原图/原尺寸/zoom/滚轮同义陈述 | 检索现行spec/features及管理中心原型；同步失败模式26和features滚动描述，历史施工记录保留当时语义 |
| 规则与验证网关 | 新XCTest自动进入non-app；AX保留入口/按钮回归。58项旧checklist门禁仅证明旧表所有权，不证明新增AC-20；新增AC由本轮人工原子映射及事件测试查证 |
| 规则与模板 | 无模板/skill/通则更改，无需生成第二套规则 |

## 阶段三：事件核销

| 事件 | 本轮结论 |
|---|---|
| 新用户交互及提示 | 滚轮与拖拽仅预览内生效；一个提示key中英成对；不改变Provider/语言/平台成员集 |
| 新原生测试 | 3例，包含旧实现红与上限/拖拽变异红；完整网关重编译后通过 |
| Pending枚举 | `rg -n 'Pending:' docs/specs/v1-core.md docs/features/v1-core.md docs/prototypes/management-center/prototype-management-center.html` 得到spec第64/371/373行硬件与Provider发布门槛；本轮未使其到期 |
| 安装本地测试版 | 不视为发布或用户实机验收；安装证据单独记录 |

## 全量网关

`bash Scripts/test-local-regression.sh`：退出0；摘要 `/private/tmp/history-zoom-full.log`；完整证据 `/var/folders/9h/52q4kxb115j2nglbz0kfpkh00000gn/T/vlmsnapper-full-regression.RmWJQU/`。

- strict-build（warnings-as-errors）、脚本测试、shell语法、旧表所有权全部通过。
- non-app：346个Swift Testing测试 + 12个XCTest通过（含新增3例）。
- app：17个Swift Testing测试通过；原生粘贴/关闭2例分进程通过。
- AX：17个场景通过（含2个明确指定步骤的负对照）。
- 当次fit/zoom原生渲染已核对，截图在系统临时目录 `history-zoom-fit.png`、`history-zoom-zoom.png`。

本轮文档队列已处理，无新冲突。真实设备方向/手感、惯性和原有硬件Pending不记验收通过；不宣称全feature完成或正式发布就绪。
