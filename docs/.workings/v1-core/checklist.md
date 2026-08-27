# VLMSnapper v1 实现核销清单

本清单把 `docs/specs/v1-core.md` 的行为分配给实现票。每票完成时必须补充 gate、测试名和可复查证据。

| 票 | 承兑范围 | 状态 |
| --- | --- | --- |
| 01 | 原始 PNG → 准备记录 → 单次 Provider 提取请求的持久化门禁；失败不联网 | 已完成 |
| 02 | 历史数据库、结果终态、失败恢复、受管理截图所有权与最终落库重试 | 已完成 |
| 03 | Provider 配置、Keychain、完整模型列表、刷新与视觉兼容状态 | 已完成 |
| 04 | OpenAI、Gemini、DeepSeek 图片流式适配器与归一化错误 | 已完成 |
| 05 | 多显示器冻结、选区裁切、全局快捷键与原始 PNG | 已完成 |
| 06 | 操作栏、核心结果窗口、单活动任务、取消和重新执行 | 已完成 |
| 07 | 菜单栏、首次引导、权限恢复与 Provider 配置 UI | 已完成 |
| 08 | 管理中心、搜索筛选、钉住、保留期与清理 | 已完成 |
| 09 | 单实例、诊断、本地化、登录项与 Sparkle 更新 | 已完成 |
| 10 | 三架构直接分发、签名/公证/appcast 门禁与全功能收口 | 进行中（正式门禁阻塞） |

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

## Ticket 04 evidence

- Gate: `swift build -Xswiftc -warnings-as-errors`、完整 `swift test` 83/83、`git diff --check`、本票源码与测试 CJK 扫描；Swift 命令使用匹配的完整 Xcode toolchain。
- Tests: 三 Provider 共享录制契约、三个官方请求体、SSE 任意字节边界、结构化 JSON 增量与 Unicode 边界、首字/停滞/总超时、单请求无重试、HTTP 错误和截断/不完整终态。
- Evidence: `ProviderRequestFactory.swift`、`ProviderAdapterExecutor.swift`、三个独立 stream decoder、`OrderedStructuredOutputParser.swift`、`ProviderStreamTimeout.swift`；`review-code.md` 与 `review-tests.md` 的审查和三项变异证据。真实账户与签名 Provider 限制仍按 Ticket 10 发布门禁保留，不冒充已验证。

## Ticket 05 evidence

- Gate: 严格 `swift build -Xswiftc -warnings-as-errors -Xcc -Wall -Xcc -Wextra -Xcc -Werror`、完整 `swift test` 105/105、`git diff --check`、本票 Swift/C 源码与测试 CJK 扫描；Swift 命令使用匹配的完整 Xcode toolchain，Keychain 全套测试在允许访问登录 Keychain 的宿主执行。
- Tests: 冻结协调 4 例、选区状态机 7 例、PNG 裁切 4 例、快捷键协调 6 例及 Carbon registrar 生命周期 1 例，覆盖权限/全部失败/部分失败、2 × 2、几何失效、裁切期间取消与竞态、坐标溢出、sRGB 像素内容、原子替换和销毁注销。
- Evidence: `CaptureFreezeCoordinator.swift`、`CaptureSelectionSession.swift`、`ScreenCaptureKitFrozenDisplayCapturer.swift`、`SRGBPNGCropper.swift`、`GlobalShortcutCoordinator.swift`、`CarbonGlobalShortcutBackend.swift` 与窄 C shim；`review-code.md`、`review-tests.md` 的分层审查和红灯/变异证据。真实多显示器、TCC、快捷键冲突和签名 App 回调仍按 Ticket 10 集成门禁保留。

## Ticket 06 evidence

- Gate: 严格 `swift build -Xswiftc -warnings-as-errors -Xcc -Wall -Xcc -Wextra -Xcc -Werror`、完整 `swift test` 127/127、`git diff --check`、源码/测试 CJK 扫描、本地化键一致性与 UI 硬编码文案扫描；Swift 命令使用匹配的完整 Xcode toolchain，Keychain 全套测试在允许访问登录 Keychain 的宿主执行。
- Tests: 操作会话 9 例、持久化 runner 7 例、操作栏定位 3 例、Provider 错误码 1 例及 SQLite 类型/迁移 2 例，覆盖显式单请求、全局排他、等待期间冻结操作、关闭取消、旧成功保留、截图复用/回滚、Provider 取消归一化、最终保存重试、4 px 间距与窄屏长操作栏。
- Evidence: `OperationWorkspaceSession.swift`、`PersistedOperationWorkspaceRunner.swift`、`ProviderPreparedOperationStreamer.swift`、schema v2 的 `SQLiteHistoryStore.swift` 以及 `VLMSnapper/UI/` 原生组件；light/dark harness 实际渲染已核对确认原型。签名 App 的窗口交互、辅助功能遍历、TCC 与真实 Provider 仍按 Ticket 10 集成门禁保留。

## Ticket 07 evidence

- Gate: 严格 `swift build -Xswiftc -warnings-as-errors -Xcc -Wall -Xcc -Wextra -Xcc -Werror`、完整宿主 `swift test` 143/143、10 张 AppKit/SwiftUI 明暗离屏渲染、`git diff --check`、源码/测试 CJK 扫描、83 个本地化键一致性与 UI 硬编码文案扫描。
- Tests: 引导/菜单路由 4 例、权限恢复 6 例、Provider presentation 5 例和真实 UI 渲染 1 例，覆盖必要条件门禁、Later 恒可用、Provider 优先路由、显式一次 TCC、拒绝/撤销恢复、成功后重启、重叠点击、模型原地展开、无自动选择、异步切换隔离、活动请求只读与五个入口表面明暗渲染。
- Evidence: `OnboardingSession.swift`、`ScreenCapturePermissionCoordinator.swift`、`ProviderSetupSession.swift`、`UserDefaultsPermissionRequestHistoryStore.swift` 与 `VLMSnapper/UI/` 的 onboarding/menu/provider/privacy/permission 组件和状态栏 controller；`review-code.md`、`review-tests.md` 的分层审查与三项行为/变异红灯；`final-regression.md` 的三阶段一致性表。签名 TCC、真实状态栏点击、System Settings 与一键重启仍按 Ticket 10 集成门禁保留。

## Ticket 08 evidence

- Gate: 严格 `swift build -Xswiftc -warnings-as-errors -Xcc -Wall -Xcc -Wextra -Xcc -Werror`、完整宿主 `swift test` 151/151、8 张管理中心明暗离屏渲染、`git diff --check`、源码/测试 CJK 扫描和双语本地化键一致性。
- Tests: 历史查询/钉住/metrics 2 例、删除协调 2 例、保留期/24 小时调度 2 例、runner metrics 1 例、空月份目录 1 例和管理中心渲染 1 例，覆盖类型与本地搜索组合、完整筛选、Provider usage、活动/钉住跳过、缺失/替代文件、部分失败继续、缩短确认、延长不清理、启动一次与 24 小时边界、空态和后台清理失败提示。
- Evidence: `HistoryManagement.swift`、`HistoryRetention.swift`、schema v3 的 `SQLiteHistoryStore.swift`、`FileSystemScreenshotStore.swift`、`PersistedOperationWorkspaceRunner.swift` 以及 `ManagementCenterView`/window controller；`review-code.md`、`review-tests.md` 的分层审查和两项目标行为变异证据；`final-regression.md` 的三阶段一致性表。生产 App 组合与真实菜单栏到窗口接线仍按 Ticket 09/10 门禁保留。

## Ticket 09 evidence

- Gate: Sparkle 2.9.6 exact dependency、严格 Swift/C warnings-as-errors build、完整宿主 `swift test` 172/172、32 张中英文/明暗/更新状态离屏渲染、系统 gzip 解压验证与 `git diff --check`。
- Tests: 语言 3 例、登录项 2 例、单实例 3 例、诊断 4 例、更新生命周期 4 例、Sparkle 用户驱动 3 例和 UI 2 例，覆盖完整偏好列表、默认登录启用/审批、真实排他锁恢复、allowlist/截止日/gzip、六小时且不自动下载、reply 单次消费、回调顺序及共享菜单/设置状态。
- Evidence: `ApplicationLanguage.swift`、`LoginItemCoordinator.swift`、`PrimaryInstanceCoordinator.swift`、`DiagnosticLogStore.swift`、`UpdateLifecycle.swift`、独立 Sparkle target 与原生 UI adapters；`review-code.md`、`review-tests.md` 和 `final-regression.md` 的 Ticket 09 章节。签名进程唤醒、真实 SMAppService/appcast/安装和退出协调仍由 Ticket 10 验收。

## Ticket 10 evidence

- Development gate: strict Swift/C warnings-as-errors build, full Swift Testing 184/184 in 45 suites, 32 Ticket 09 and 4 Ticket 10 bilingual light/dark renders, localization-key parity, shell/YAML syntax checks, and separate Universal/Apple Silicon/Intel ad-hoc DMG verification.
- Implemented surfaces: production accessory executable, application composition, frozen overlay, searchable target-language picker, persistent custom shortcut, menu/history/settings/onboarding/result routing, hourly cleanup wake with a 24-hour core gate, sanitized diagnostic export, and coordinated termination for Quit, Command-Q, language restart, and Sparkle installation.
- Release pipeline: exact three-member manifest, separate architecture feeds, fail-closed credentials and HTTPS validation, nested hardened-runtime signing, app and DMG notarization/stapling/Gatekeeper checks, EdDSA verification, and atomic six-file staging.
- Formal gate remains blocked: no local Developer ID identity or notarization evidence, no public HTTPS feed/download host, and no protected live OpenAI/Gemini/DeepSeek credentials. Development DMGs are not release evidence; Ticket 10 stays in progress.
