# ADR-0009: 每个用户只允许一个应用主实例

- 状态: 已接受（2026-08-25）

## 背景与问题

VLMSnapper 是无 Dock 图标的菜单栏应用，持有全局截图快捷键、单一活动模型任务、SQLite 历史数据库、Pictures 中的受管理截图、自动清理调度和 Sparkle 更新状态。用户可能重复双击、使用 `open -n`，或并行安装并启动共享 Bundle Identifier 的不同架构构建。多个完整实例会破坏单任务约束，并造成快捷键冲突、数据库并发写入和重复清理。

## 备选项

1. 允许多个完整实例，由 SQLite 和文件锁分别协调——否决，因为全局快捷键、单一活动任务、菜单栏状态和 Sparkle 仍会冲突
2. **每个 macOS 用户只允许一个主实例，后续实例只负责唤醒后退出**
3. 检测到已有实例时直接静默退出——否决，因为用户重复打开应用时需要得到可见反馈

## 决策

选定**方案 2**。第二实例不得打开或修改历史数据库、注册全局快捷键、执行自动清理或触发更新检查；它只向现有主实例发送激活通知，然后立即退出。主实例存在活动模型任务时将结果窗口带到前台，否则展开菜单栏菜单。

实例互斥按当前 macOS 用户隔离。异常退出留下的陈旧状态必须可由后续启动安全回收，不能永久阻止应用启动。Universal、Apple Silicon 和 Intel 构建共享身份，因此并行安装时仍由最先启动者成为主实例。

## 后果

- 正面：数据库、受管理截图、快捷键、清理和更新调度始终只有一个写入者和协调者。
- 正面：重复启动给用户明确反馈，而不是再创建一个看似相同的菜单栏图标。
- 负面：用户不能同时运行不同 Provider 或不同架构的独立 VLMSnapper 会话。
- 中性：Sparkle 安装器及签名辅助进程不是应用主实例，不应被主实例互斥机制误拦截。

## 来源

- [VLMSnapper v1 需求对齐记录](../.workings/v1-core/requirements-alignment.md)
- [ADR-0004: 为三个发行架构使用独立 Sparkle appcast](0004-separate-sparkle-feeds-per-distribution-architecture.md)
- [ADR-0005: 固定直接分发应用身份](0005-stable-direct-distribution-application-identity.md)
- [ADR-0008: 历史数据库故障时禁止静默重建](0008-preserve-failed-history-database-before-reset.md)
