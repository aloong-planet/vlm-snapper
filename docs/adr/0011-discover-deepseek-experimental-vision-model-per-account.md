# ADR-0011: 以官方账户模型列表发现 DeepSeek 视觉实验模型

- 状态: 已接受（2026-08-25）

## 背景与问题

DeepSeek 当前公开文档把 V4 描述为纯文本模型，公开模型示例和请求 schema 也没有列出 `deepseek-v4-flash-vision-exp`。用户同时确认：该 ID 由 xnote 内置 DeepSeek 配置通过官方 `https://api.deepseek.com/models` 自动返回，并且使用同一官方 Endpoint 成功发送过图片。这构成账户级实验能力证据，但不是所有账户都可用的公共 API 保证，也尚未由 VLMSnapper 的集成测试独立复现完整流式契约。

## 备选项

1. v1 完全移除 DeepSeek——否决，因为目标账户已经能通过官方 Endpoint 发现并使用视觉实验模型
2. 在所有账户中硬编码并预选 `deepseek-v4-flash-vision-exp`——否决，因为公开文档未收录，模型可能按账户灰度、改名或下线
3. **保留 DeepSeek Provider，仅按官方账户模型列表发现并选择该实验模型**

## 决策

选定**方案 3**。DeepSeek 保留为 v1 Provider，官方 Base URL 固定为 `https://api.deepseek.com`。`deepseek-v4-flash-vision-exp` 只有在当前 API Key 完整刷新官方 `/models` 且返回该精确 ID 时才成为可选择的视觉候选；应用不手动注入、不默认选中，也不使用自定义网关补齐。

公开文档与账户能力的差异必须在代码和发布验证中显式保留。发布前使用受保护的真实 Key 执行契约测试，验证图片输入、流式输出、结构化结果、取消、超时、截断、错误映射和 usage。模型未返回或契约测试失败时，DeepSeek 不得标记为发布就绪；运行时刷新确认模型消失后，继续按既定规则清除当前模型并要求重新选择。

契约测试还必须确定实验模型的请求大小计量和安全限制，并把结果写入随签名应用发布的版本化 Provider 配置。限制未知时不得上传，也不得通过远程未签名规则临时放开。

DeepSeek adapter 必须把实验模型的流式协议归一化为应用统一的 `sourceDelta → translationDelta → metadata → completed` 事件。如果模型没有原生 JSON Schema，可使用内置英文提示词和固定边界标记增量解析；但必须通过最终结构校验，失败时立即说明原因并等待用户主动重试，不得自动追加请求，也不得降级为两次请求、非流式或其他模型。

## 后果

- 正面：v1 可以支持目标账户实际具备的 DeepSeek 视觉能力，同时不向其他账户虚假承诺必然可用。
- 正面：模型可用性仍由官方 Endpoint 和完整账户列表控制，不引入手动模型 ID 或第三方网关。
- 负面：实验模型可能随时改名、撤回或改变协议，DeepSeek 的发布和回归测试风险高于 OpenAI、Gemini。
- 中性：用户确认属于产品证据；在受保护 Key 的集成测试完成前，不能报告 VLMSnapper 已独立验证该契约。

## 来源

- [VLMSnapper v1 需求对齐记录](../.workings/v1-core/requirements-alignment.md)
- [DeepSeek Models API](https://api-docs.deepseek.com/api/list-models/)
- [DeepSeek Chat Completions](https://api-docs.deepseek.com/api/create-chat-completion)
- [DeepSeek V4 vision statement](https://api-docs.deepseek.com/quick_start/agent_integrations/github_copilot/)
- Canonical provider 调研：`~/research/macos-screenshot-ocr-translator/provider-contracts-2026-08-25.md`
