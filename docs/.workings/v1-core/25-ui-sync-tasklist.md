# #25 — 已确认历史 UI 同步

参考 commit：0febbb48fcd9acccdefc67dc9015ebf92605511c，含未提交修改。继续既有 feature 工作区，不切换或清除已有改动。本轮不安装、不合并。

- [x] 来源 → spec：用户要求同步目前 UI；取消的五个筛选义务不实施，新增 AC-10 至 AC-16。全历史检索 `git log --all -G 'US-001/AC-(1[0-9]|2[0-9])' -- docs/specs/v1-core.md` 无命中，现行文件亦未使用这些编号。
- [x] 原型准入：管理中心当前原型及用户同步请求覆盖工具栏、260pt 列表、类型/状态/日期、选中态；保留原生导航宽度。原型未获自动渲染证据，不等于 App 验收。
- [ ] 原生控件纵切红绿：Provider/类型/搜索/Pinned、选择保留与窗口会话。
- [x] 原生样式同步：生成8张中英/深浅/两宽度原生图，已看中文浅色与英文深色最小宽；完整物理交互仍不计通过。
- [ ] 完整验证网关及真实失败记录。
- [x] /review-code 独立审查：分层结论与未测图片乱序/鼠标路径已记 review-code.md。
- [x] /review-tests 独立审查：四例逐项核查，修复旧门禁变异插错表格；未完成用例不跳过。
- [x] Spec 终检、/features-catalog 和逐项证据归档：19个单位记录于同一 checklist，未验证产品路径保持未验证。

当前结果：严格构建通过，专项4例/App14例/独立原生XCTest2例/清单门禁6例通过。完整非App分组未通过，历史组合用例尚未取得可靠结束与选择/导航结果。试验性手势及全局激活事件泵已撤回，不改变产品置顶策略。最终日志为 /tmp/vlmsnapper-ui-sync-final-restored-tests.log；不得用其退出码代替完整报告。详细证据及阶段归档见同级 checklist.md / final-regression.md；不标 #25 完成。

测试 seam：复用生产 ManagementCenterWindowController / ManagementCenterView 的原生控件、回调和既有 AppKit 事件路径；无生产模拟开关。历史数据库/网络回归使用现有隔离测试；不读取真实截图或凭据。

## 2026-09-14 — 用户要求安装本地 App

- 授权仅本地安装，不推送、合并或发布；上方“本轮不安装”描述的是此前实施检查点。
- 已从当前工作区（参考 0febbb48fcd9acccdefc67dc9015ebf92605511c + 未提交修改）严格 release 构建 arm64 0.1.0（30）。沿用旧版开发更新 feed、公开 Sparkle key、Developer ID Application: Longfei Zhou (RHQ28XS7D9) 及嵌入 provisioning profile。
- build/sign/独立随机 service 的 Data Protection Keychain CRUD 均退出0。日志及签名元数据：/private/tmp/vlmsnapper-local-build30.L5x2XY/。不是 notarized 正式发布版。
- 旧版正常退出，无强杀。旧 App 保留于 /Applications/VLMSnapper.app.backup-20260914-build29-before-ui-sync；未重置用户配置、历史、Keychain 或屏幕录制权限。
- /Applications/VLMSnapper.app 已替换并启动，确认版本30、codesign深度严格验证通过、PID35526；安装可执行文件与签名构建 SHA-256 同为 972a42d5817f7848b6605bd248ed1d143e875467738255aa8f079f8c7e2d8471。
- 安装成功不代表交互验收完成。#25 仍待用户实机验证，前轮历史组合测试失败及 #24 诊断未被本次安装消除。
