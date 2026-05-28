# 问题与优化记录

> 日常使用中发现的问题、可优化点、待确认需求等，后续逐步处理。

---

## 1. 批量刷新 Token 后账号状态未同步

**发现场景**：批量购买几十个账号导入后，使用"批量刷新令牌"功能，接口返回了成功/失败数量，但账号列表里的状态没有任何变化。

**当前行为**：
- 刷新失败的账号状态仍为 `active`，看不出哪些 Token 已失效
- 刷新成功的账号如果之前是 `error` 状态，也不会被清除
- 只能看接口返回的 JSON 才知道结果

**期望**：刷新失败时账号状态应有所体现，刷新成功时应自动恢复。

**相关代码**：
- `backend/internal/handler/admin/account_handler.go` — `BatchRefresh` handler

---

## 2. 测试连接对 401 的处理过于激进

**发现场景**：单个账号点击"测试连接"，OpenAI OAuth 账号返回 401 `token_invalidated`，账号立即被标记为错误状态。但这个账号有 `refresh_token`，本可以通过刷新恢复。

**当前行为**：
- 测试连接直接用 DB 里的 `access_token` 发请求，不经过 `TokenProvider`
- 遇到 401 就标记为 `error`，不尝试用 RT 刷新
- 网关流量遇到同样情况时会自动用 RT 刷新，所以网关是正常的

**期望**：测试连接应该先尝试刷新 Token，或者 401 时先尝试用 RT 恢复再决定是否标记错误。

**相关代码**：
- `backend/internal/service/account_test_service.go` — `testOpenAIAccountConnection`

---

## 3. 新导入的 OAuth 账号定时刷新不会覆盖

**发现场景**：批量导入账号时，导入数据里没有 `expires_at` 字段。导入后以为定时刷新服务会自动维护 Token，但实际上新账号从来没被刷新过。

**当前行为**：
- 定时刷新服务通过 `expires_at` 判断是否需要刷新
- `expires_at == nil` 时，所有平台（OpenAI 除外限速场景）都返回"不需要刷新"
- 导致新导入的 OAuth 账号永远不会被定时服务主动刷新

**临时应对**：导入后手动执行一次"批量刷新"，`expires_at` 会被写入，之后定时服务正常接手。

**期望**：缺少 `expires_at` 但有 `refresh_token` 的 OAuth 账号，定时服务应该视为需要刷新。

**相关代码**：
- 各平台的 `NeedsRefresh()` 方法（`token_refresher.go`、`gemini_token_refresher.go`、`kiro_token_refresher.go`、`antigravity_token_refresher.go`）
