# Provider 回归：离线与真实模型

## 何时运行

离线回归验证可复现的代码行为，不证明当前账户、模型和真实服务兼容。修改 Provider 请求、提示词、解析或结果校验时，应另跑受影响 Provider/模型的真实门禁。真实调用失败不得用离线绿灯抵销，也不得自动重试或换模型取得绿灯。

```bash
bash Scripts/test-local-regression.sh --offline
bash Scripts/test-local-regression.sh --live-provider deepseek --live-model deepseek-flash
```

第二条先执行全量离线检查，再执行指定模型的真实提取、翻译各一次；任一步失败，整条命令非零退出。原生离线测试可能激活窗口。无参数保留离线模式，并明确打印真实模型未测。

只运行真实检查：

```bash
bash Scripts/test-live-provider.sh deepseek deepseek-flash /private/tmp/provider-report.json
```

## 凭据与副作用

- 默认从对应的 `OPENAI_API_KEY`、`GEMINI_API_KEY` 或 `DEEPSEEK_API_KEY` 环境变量读取；不要把 Key 写进命令、仓库或日志。
- 本地使用已保存的受保护 Keychain 时，追加 `--keychain`，并在环境中提供 `MACOS_SIGNING_IDENTITY`。脚本用已有 Developer ID 身份和 provisioning profile 构建临时签名测试程序；profile 默认取已安装 App，可由 `MACOS_PROVISIONING_PROFILE` 指定。不申请新权限、不改 Keychain、不安装或启动产品 App，临时程序退出后删除。
- 明确选择单一 Provider/模型；每次最多两次付费请求，不重试、不回退。只上传程序生成的白底已知文字图片，不读或上传用户历史截图。
- 缺凭据返回 `blocked` 且进程非零退出；签名、Keychain 读取或报告写入失败同样非零退出，不是跳过成功。
- JSON 只含 Provider、模型、操作、阶段、耗时、状态以及可用的脱敏请求标识和用量。没有 API Key、图片、正文或原始响应。

## 判据与边界

经过生产请求构造、HTTP/SSE 解码和最终结果校验后，识别文字须与图片中的 `VLMSnapper` 一致：提取按行内 Markdown 解析后的文字比较，允许加粗等格式；翻译片段的原文仍按纯文本比较。两者只忽略空白差异，不忽略大小写、标点或额外文字，翻译须非空。HTTP 200、stop、DONE 或收到 completed 事件单独都不是成功标准。已知有文字的图片返回空、文字错误、流不完整或翻译为空都失败。

这是一张合成图片的契约烟测，不是 OCR 准确率、翻译质量、任意截图或全部模型的验收，也不改变产品对真正无文字图片的需求。一次通过只说明该次指定账户/模型/操作通过。

既有发布流程保持兼容：`VLMSnapperLiveProviderGate --output <report.json>` 仍检测全部三家 Provider，使用各家的 API Key 和 `VLMSNAPPER_OPENAI_MODEL`、`VLMSNAPPER_GEMINI_MODEL`、`VLMSNAPPER_DEEPSEEK_MODEL`。六条报告必须全部通过；单一模型测试不能替代发布门禁。
