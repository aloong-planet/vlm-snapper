# VLMSnapper v1 — Ticket 01 test review

审查范围：`ExtractionCoordinatorTests` 的 6 个公开行为用例。

## 维度 1：覆盖是否完整

- 成功：保存和上传都接收同一份原始 PNG；准备记录保留相同截图、operation ID、Provider 和模型；Provider 恰好调用一次。
- 截图保存失败：归一化为截图持久化错误，Provider 零请求。
- 准备记录失败：安全回滚原截图，Provider 零请求。
- 回滚失败：报告孤儿路径，Provider 零请求。
- 准备记录身份不一致：分别覆盖截图 SHA-256 不一致与模型选择不一致，均回滚且不请求 Provider。
- 本票明确不承兑真实文件系统、SQLite、HTTP 流式、Provider 错误、取消与最终结果落库，这些缺口分别由 Ticket 02、04、06 补测。
- PNG 在本 seam 中是完全不解析的 opaque bytes，因此 fixture 的 PNG 内部结构不会进入任何分支；真实 PNG 编码形态应在 Ticket 05 的截图编码集成测试中验证。

## 维度 2：case 设计是否合理

- 所有状态都从公开 `startExtraction` 入口到达，没有 cast 私有状态或绕过协调器。
- 只使用系统边界假件：截图存储、历史存储、Provider；没有 mock 项目内部模块。
- Provider 请求计数属于“不得联网/恰好一次”的外部边界可观察量，调用次数本身就是规格，予以保留。
- 期望值使用独立字面量或预先构造的领域值，没有复用生产常量或按实现算法重算。

## 维度 3：假通过检查

- 红绿记录：成功路径最初因 `notImplemented` 在公开 seam 红；截图保存、准备记录、回滚失败与准备记录身份不匹配分别在对应断言处红过。
- 变异 1：把传给截图存储的字节改为空 `Data()`；已确认变异到达生产调用点，用例在 `SuccessfulScreenshotStore` 的 0 bytes vs 5 bytes 断言处红。
- 变异 2：移除准备记录的 `ProviderSelection` 比较；已确认 guard 只剩截图比较，用例在“应拒绝不匹配选择”和 Provider 零请求断言处红。
- 变异 3：插入第二次 Provider 调用；已确认源码存在两个调用点，用例在 `requestCount == 1` 断言处红。
- 三次变异均使用事先保存的正式源文件精确还原，并以 `cmp` 逐字节确认；最终完整测试 6/6 通过。
- 曾出现一次测试夹具编译错误（actor 缺少显式初始化器），它没有进入产品行为路径，因此未当作红测证据。

## 结论

本票承兑范围内覆盖完整，case 可达且针对系统边界，三项高风险断言通过独立变异检验；未发现剩余假通过。
