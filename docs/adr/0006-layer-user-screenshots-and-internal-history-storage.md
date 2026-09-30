# ADR-0006: 将原始截图与应用内部历史分层存储

- 状态: 已接受（2026-08-25）

## 背景与问题

VLMSnapper 需要启用 App Sandbox，同时保存用户可在 Finder 中查看的原始截图以及仅供应用检索和重新执行使用的内部历史数据。Apple 为 Pictures 目录提供专用读写 entitlement；实际 Mac App Store 审核案例也表明，把用户可见且需要长期持有的文件只放在应用 Container 中，可能被视为不符合用户数据存储预期。另一方面，数据库、索引、派生文字和日志属于应用内部数据，放入 Container 能保持最小文件访问权限和清晰的数据所有权边界。

## 备选项

1. 所有截图和内部数据都保存在 App Sandbox Container——否决，因为原始 PNG 对用户可见且具有独立使用价值，只放在隐藏 Container 中存在审核和卸载丢失风险
2. **原始 PNG 固定保存到 `~/Pictures/VLMSnapper/`，内部历史数据保存在 Container**
3. 首次启动要求用户选择 Documents 或其他目录并持久化 security-scoped bookmark——否决，因为增加首次配置、授权失效和恢复流程，而 Pictures 已有与截图功能直接匹配的专用 entitlement
4. 所有数据都放到 Pictures 子目录——否决，因为数据库、索引和日志不属于用户图片，会污染用户目录并扩大误改风险

## 决策

选定**方案 2**。应用启用 App Sandbox，并声明 `com.apple.security.assets.pictures.read-write`。原始无损 PNG 固定保存到系统 Pictures 目录下的 `VLMSnapper/` 子目录；应用通过系统目录 API 获取路径，不硬编码用户主目录，也不把 Container 中的代理路径作为用户可见路径。

历史数据库、模型返回的原文与译文、搜索索引、操作状态和日志保存在 App Sandbox Container 内的 `Library/Application Support/VLMSnapper/`。第一版不允许修改截图目录，也不实现目录迁移。

设置页提供“在 Finder 中显示截图目录”，打开并展示解析后的 `~/Pictures/VLMSnapper/`。自动清理和手动删除必须同时处理内部记录与对应 PNG；首次引导和清理设置明确告知用户，未钉住的 PNG 会按保留期限被永久删除。

## 后果

- 正面：用户可以在 Finder 中直接找到原始截图，卸载应用不会因删除 Container 而连带移除 PNG；存储位置与截图产品语义及 Pictures entitlement 一致。
- 正面：数据库、索引、派生文字和日志仍留在 Container，不需要为内部数据申请额外用户目录权限。
- 负面：应用需要申请整个 Pictures 目录的读写 entitlement，并在审核说明中明确其用途是创建、浏览和自动清理 `VLMSnapper` 子目录中的截图。
- 负面：用户在 Finder 中移动、改名或删除 PNG 后，历史详情必须能够处理文件缺失，不能把数据库记录误判为仍有可用原图。
- 中性：第一版固定目录避免 security-scoped bookmark 生命周期，但以后若支持自定义目录，必须另行设计授权持久化、失效恢复和迁移语义。

## 来源

- [VLMSnapper v1 需求对齐记录](../.workings/v1-core/requirements-alignment.md)
- [Apple: App Sandbox](https://developer.apple.com/documentation/security/app-sandbox)
- [Apple: Pictures Folder Read/Write entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.assets.pictures.read-write)
- [Apple: Accessing files from the macOS App Sandbox](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox)
- Transfer 的 App Store Guideline 2.4.5(i) 审核案例 `docs/.workings/mas-review/01-container-path-2.4.5i.md`

## 后续澄清

- 原始 PNG 保存成功时在内部历史中记录 SHA-256。用户在 Finder 中删除、移动或替换图片后，保留已有文字结果和元数据，但禁用依赖原图的重新执行。
- 手动删除和自动清理只允许删除路径仍存在且 SHA-256 与记录一致的 PNG；同路径的不同文件属于用户数据，应用不得上传、覆盖或删除。
- 模型操作采用“先原子保存 PNG、后上传”的顺序。PNG 保存失败时不调用 Provider、不计入模型重试，只在当前会话保留内存副本供用户修复本地问题后重试；窗口关闭或应用退出后丢弃该副本且不创建历史记录。
- Provider 调用还要求状态为“准备请求”的历史记录已经写入 PNG 路径和 SHA-256。该记录创建失败时，应用不上传，并删除本次刚创建且摘要一致的 PNG；删除失败的文件视为未被历史认领的孤儿文件，只向用户提示位置，不交给自动清理处理。
- Provider 已返回完整结果但最终落库失败时，应用保留内存结果供复制和本地重试，绝不为修复存储错误而再次调用模型。用户放弃未保存结果后，保留 PNG 和预创建记录，并在下次启动将操作归类为“结果保存失败”。
- `~/Pictures/VLMSnapper/` 下按截图创建时的本地年月使用单层 `YYYY-MM/` 子目录，例如 `2026-08/`；不拆成 `YYYY/MM/` 两层。
- 缺失的根目录和年月目录在下次保存时自动重建；如果任一路径组件是普通文件、符号链接或解析后越出系统 Pictures 目录，则拒绝保存与上传，且不得覆盖、删除或跟随该路径。固定保存位置不借由符号链接提供隐式自定义能力。
- 根目录和年月目录采用惰性创建：安装、启动和引导页不创建；第一次模型操作保存前创建两者。设置页主动要求在 Finder 中显示且根目录不存在时，只创建根目录。历史清空后仍保留根目录。
- 应用逻辑不得利用 Pictures entitlement 扫描或索引 `VLMSnapper/` 以外的内容。目录内也只有当前安装创建且数据库记录路径与 SHA-256 的文件才受管理；重装或清除 Container 后遗留的 PNG 不自动导入、认领或清理。
- 2026-09-24：显式历史原文翻译只使用已有文字记录，不创建或重读 PNG；缺图不阻止该动作。完整对应结果保存成功才原子替换同一历史记录的操作与结果，失败、取消或中断保留原提取。转换后的截图重跑仍遵循原图路径和摘要校验；本项不改变图片上传前的存储门禁。
