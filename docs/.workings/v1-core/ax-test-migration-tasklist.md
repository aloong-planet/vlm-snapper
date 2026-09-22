# Provider 坐标用例迁移（2026-09-16）

范围：替换 ProviderCredentialInteractionTests 中过期的 Validate / 清空坐标流程；保留真正验证鼠标命中区域的其他测试，不宣称全仓已无坐标。

- [x] 评估：四参数 editingEnablesValidation 与 otherProviderJobBlocksNativeSubmission 共 5 条已知失败；unsafeDraftCannotValidate 的点空白负向断言也不可靠。
- [x] 将临时 AX fixture 固化为测试专用 target，每次从当前源码构建；生产 App 不加测试开关。
- [x] AX：空/预填、密码/明文、清空/重新输入、快照刷新、其他 Provider 作业锁定→解锁、不同窗口尺寸、非法输入。
- [x] 保留独立键盘输入/粘贴/Return/载入更新/关闭重开/焦点导航覆盖；移除旧坐标辅助方法和过期截图生成代码（未删除已有历史图片）。
- [x] 负对照：回调到达但丢弃结果时必须在最终成功断言失败，不以操作返回成功代替业务效果。
- [x] 全量回归：严格构建、非 App 测试、App 测试、两项隔离原生 XCTest、脚本门禁、外部 AX。
- [x] review-code：四层独立结论。
- [x] review-tests：三个维度及每项失败条件。

测试边界：真实生产 View / CredentialEditor / AppKit 字段；网络与 Keychain 停在公开提交回调。AX 不替代物理鼠标命中、硬件键盘、真实账户鉴权。全量原生测试可能激活测试窗口，AX 子集保持后台。

结果见 [完整回归记录](ax-test-migration-verification.md)。
