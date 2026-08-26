# VLMSnapper v1 实现核销清单

本清单把 `docs/specs/v1-core.md` 的行为分配给实现票。每票完成时必须补充 gate、测试名和可复查证据。

| 票 | 承兑范围 | 状态 |
| --- | --- | --- |
| 01 | 原始 PNG → 准备记录 → 单次 Provider 提取请求的持久化门禁；失败不联网 | 已完成 |
| 02 | 历史数据库、结果终态、失败恢复、受管理截图所有权与最终落库重试 | 已完成 |
| 03 | Provider 配置、Keychain、完整模型列表、刷新与视觉兼容状态 | 已完成 |
| 04 | OpenAI、Gemini、DeepSeek 图片流式适配器与归一化错误 | 待开始 |
| 05 | 多显示器冻结、选区裁切、全局快捷键与原始 PNG | 待开始 |
| 06 | 操作栏、核心结果窗口、单活动任务、取消和重新执行 | 待开始 |
| 07 | 菜单栏、首次引导、权限恢复与 Provider 配置 UI | 待开始 |
| 08 | 管理中心、搜索筛选、钉住、保留期与清理 | 待开始 |
| 09 | 单实例、诊断、本地化、登录项与 Sparkle 更新 | 待开始 |
| 10 | 三架构直接分发、签名/公证/appcast 门禁与全功能收口 | 待开始 |

## Ticket 01 evidence

- Gate: `swift build` 与完整 `swift test`；二者必须使用匹配的 Xcode toolchain，测试输出还必须包含 Swift Testing 的 6/6 passed 汇总。
- Tests: `persistedExtractionReachesSelectedProvider`、`screenshotPersistenceFailureNeverReachesProvider`、`historyPreparationFailureRollsBackScreenshot`、`failedRollbackReportsOrphanPath`、`mismatchedPreparedRecordIsRejected`、`mismatchedPreparedSelectionIsRejected`。
- Evidence: `Sources/VLMSnapperCore/ExtractionCoordinator.swift` 的公开工作流 seam；`Tests/VLMSnapperCoreTests/ExtractionCoordinatorTests.swift` 的系统边界假件和行为断言；`review-code.md` 与 `review-tests.md` 的审查和变异证据。

## Ticket 02 evidence

- Gate: `swift build -Xswiftc -warnings-as-errors`、完整 `swift test`、`git diff --check`、源码与测试 CJK 扫描；Swift 命令使用匹配的完整 Xcode toolchain。
- Tests: `FileSystemScreenshotStoreTests` 10 例与 `SQLiteHistoryStoreTests` 12 例，覆盖原始字节、命名、防覆盖、所有静态符号链接形态、路径/SHA 所有权、终态 payload、启动恢复、schema/损坏阻断和保留式重置。
- Evidence: `FileSystemScreenshotStore.swift`、`SQLiteHistoryStore.swift`、`HistoryDatabaseResetter.swift`；`review-code.md` 与 `review-tests.md` 的分层审查和三项变异证据；`final-regression.md` 的三阶段文档一致性表。

## Ticket 03 evidence

- Gate: `swift build -Xswiftc -warnings-as-errors`、完整 `swift test` 53/53、`git diff --check`、15 个源码与测试文件的 CJK 扫描；Swift 命令使用匹配的完整 Xcode toolchain。
- Tests: Provider 配置 16 例、官方目录 5 例、元数据 3 例和 Keychain 1 例，覆盖完整分页、失败零写入、崩溃协调、缓存替换/保留、首个与已记忆 Provider、冻结竞态、视觉证据、路径防护和真实 Keychain 生命周期。
- Evidence: `ProviderConfiguration.swift`、`ProviderModelCatalog.swift`、`AppleKeychainProviderCredentialStore.swift`、`FileProviderMetadataStore.swift`；`review-code.md` 与 `review-tests.md` 的分层审查、行为红灯和变异证据；`final-regression.md` 的三阶段文档一致性表。
