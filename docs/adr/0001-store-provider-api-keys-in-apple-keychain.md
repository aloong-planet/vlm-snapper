# ADR-0001: 使用 Apple Keychain 保存 Provider API Key

- 状态: 已接受（2026-08-24）

## 背景与问题

VLMSnapper 需要长期保存用户为 OpenAI、Gemini 和 DeepSeek 配置的 API Key，同时保持菜单栏应用无需每次启动输入主密码。API Key 属于小型用户秘密，不能以明文、可逆混淆或与解密材料共置的方式写入 app 配置。

## 备选项

1. **使用 Apple Keychain 为每个 Provider 保存独立的 app 专属条目**
2. 使用主密码派生密钥，再用 AES-GCM 加密 app 配置——否决，因为用户每次重启后需要解锁，忘记主密码时凭据无法恢复，并增加密码派生与迁移的实现和审计面
3. 由 app 自持密钥并把 API Key 密文写入配置——否决，因为解密材料必须随 app 或配置持久化，不能建立可信的安全边界

## 决策

选定**方案 1**：我们使用 Apple Keychain 保存 Provider API Key。OpenAI、Gemini 和 DeepSeek 使用彼此独立的 app 专属条目并禁用同步；app 配置只保存 Provider 状态、当前模型和模型列表刷新时间等非秘密元数据。

## 后果

- 正面：凭据由 macOS 的加密存储和访问控制保护，不需要自建密钥管理，也不要求用户每次启动输入主密码。
- 负面：API Key 不随普通 app 配置备份迁移；Developer ID Team ID 和签名身份必须保持稳定，否则更新版本可能无法访问既有条目。
- 中性：删除 Provider 或清除配置时必须同时删除 Keychain 条目；日志、崩溃报告、历史记录和配置导出不得包含 API Key。

## 来源

- [VLMSnapper v1 需求对齐记录](../.workings/v1-core/requirements-alignment.md)
- [Apple: Using the keychain to manage user secrets](https://developer.apple.com/documentation/security/using-the-keychain-to-manage-user-secrets)
- [Apple: Storing Keys in the Keychain](https://developer.apple.com/documentation/security/storing-keys-in-the-keychain)
