# 测试自审

## 维度 1：覆盖完整性

本次实质修改 1 项原生窗口测试：首次铺满可用区域、保留普通窗口、调整后的真实有效尺寸、隐藏后切页保持尺寸。外部环境数据来自实际 NSScreen.visibleFrame，而不是预设桌面分辨率。小屏最终覆盖由同一 PR 的 macOS CI 提供；本机超屏对照仅证明同类失败机制，不冒充小屏 CI 已通过。

## 维度 2：case 合理性

沿用真实控制器和 NSWindow 的公开接口，无私有状态写入、内部 mock 或重复实现算法。contentRect 仅用于构造合法输入；行为期望是用户已调整框架的独立 NSRect 值快照。新增 XCTAssertNotEqual 避免根本没有调整而假绿。环境不满足最小尺寸时明确失败，不以 return 静默成功。

## 维度 3：假通过排查

逐项检查恒真、输入别名、同常量重算、守旧路径、条件静默跳过、未执行断言：未命中。NSRect 是值类型，重新显示后的比较并非同一个可变对象别名；断言均同步执行。

本地旧 fixture 超屏复现日志 `/private/tmp/vlmsnapper-pr28-resize-red.log`，退出 1。修正 fixture 后 `/private/tmp/vlmsnapper-pr28-resize-green.log`，退出 0。
有效性变异：将生产 show 中 `if !hasPresented, let window` 临时改为每次铺满。swift test 重新编译 ManagementCenterWindowController 后运行，`/private/tmp/vlmsnapper-pr28-resize-mutation.log` 退出 1，准确失败于最终框架相等断言（全屏 1512×897 与已调整 1100×732 不等）。按等价补丁撤销这一行，未使用 git restore/checkout 丢弃正式修改。

该测试验证控制器/AppKit 几何行为，不声称覆盖真实鼠标拖拽、显示器热插拔或独立全屏交互；此次产品范围没有新增这些行为。
