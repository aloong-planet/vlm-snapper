# Provider 无坐标交互回归

从仓库根目录执行 `python3 Scripts/test-provider-accessibility.py`。每次先从当前源码构建 `Tests/AXFixture`，再生成场景 JSON 和独立 App，交给固定授权的 AXRunner；不复用临时 PoC 或旧二进制。只运行某条时可加 `--case wide-empty-secure`，同样先构建。

通用 Runner 源码：`/Users/loong_zhou/Developer/ax-test-tools`；固定授权客户端：`/Users/loong_zhou/Applications/AXTestTools/AXRunner.app`。可用 `--runner /absolute/path/to/Scripts/run.sh` 指定工具脚本。缺少工具、授权、步骤、清理失败或前台变化均失败，不静默跳过。无需给每次生成的 fixture 重新授权，AX 客户端身份没有变化。

场景源维护于 `Scripts/test-provider-accessibility.py` 的 `cases()`，不是两套清单。生成的 JSON、构建日志、Runner 报告保留在命令输出的 Evidence 目录；旧的四份硬编码临时路径 JSON 已删除。

## 覆盖与旧测试映射

| 原有责任 | 现行覆盖 |
| --- | --- |
| 输入或粘贴后 Validate 提交 | AX secure 与 8 个尺寸×初始值×显隐组合；原生 editsSubmitViaReturn 独立验证 AppKit 编辑/粘贴绑定和 Return |
| 清空按钮后禁用，再输入恢复 | 8 个组合均真实 AXPress Clear → AXEnabled=false → 输入 → AXEnabled=true → 提交 |
| 窗口发布快照不丢草稿 | AX Publish fixture snapshot 后仍提交精确假值；原生 controller.update / 载入测试保留 |
| 另一 Provider 作业锁定后解除 | AX blocked-wide/narrow 从禁用到启用，再真实 AXPress 提交；原生 Return 锁定/解除独立覆盖 |
| 非法输入不得提交 | AX newline / carriage-return / over-limit 用同一个按钮做启用→禁用→启用正负交叉；原生 Return 拒绝边界保留 |
| 关闭重开、恢复基线、菜单粘贴、焦点导航 | 原生 ProviderCredentialInteractionTests 原有独立用例保留 |

共 14 个正向场景和 1 个负对照。drop-result 先确认生产按钮的提交已到达公开回调，再故意不发布成功效果；仅第 6 步 wait_timeout 且前 5 步完成、目标正常退出才算负对照通过。权限失败、选错控件、前台变化、提前退出不可被计作预期红。报告门禁有独立 Python 反例测试，python3 -O 下仍有效。

## 全量入口

执行 `bash Scripts/test-local-regression.sh`：严格构建、全部 Python 门禁、非 App XCTest/Swift Testing、App Swift Testing、两项独立原生 XCTest、AX 回归。每个阶段退出码及完成标记均是硬门禁；任一失败即停止。AX 需要已登录、未锁屏、有授权的本地桌面，GitHub 托管 CI 不声称覆盖它。

只有 AX 子集使用非激活窗口；完整原生套件可能短暂激活窗口，勿将完整回归称为“全后台”。

## 边界

使用真实生产 ManagementCenterView、ProviderCredentialEditor、AppKit 字段与按钮。仅把网络/安全存储截止在公开提交回调，使用非秘密固定数据。测试控制按钮只属于独立 fixture，不进入正式 App。不会访问真实 Keychain、Provider 或历史记录。

AX 输入不是键盘粘贴，AXPress 不是物理鼠标命中，也不证明前台焦点、完全隐藏窗口或真实服务鉴权。保留原生输入测试及其他专门验证鼠标命中区域的测试；不为追求“零坐标”删除它们。
