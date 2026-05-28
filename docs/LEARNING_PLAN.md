# Sub2API 项目学习计划

> 状态标记：⬜ 未开始 | 🔄 进行中 | ✅ 已完成

---

## 项目全景速览

| 维度 | 说明 |
|------|------|
| **定位** | AI API 网关平台：管理多个 AI 账号的订阅配额，对外分发 API Key，负责认证、计费、负载均衡和请求转发 |
| **后端** | Go 1.26 + Gin + Ent ORM + PostgreSQL + Redis + Wire 依赖注入 |
| **前端** | Vue 3.4 + Vite 5 + Pinia 2 + TailwindCSS 3 + vue-i18n 9 |
| **部署** | Docker Compose / 源码编译 / 安装脚本 |
| **核心能力** | 多平台兼容（Claude / OpenAI / Gemini / Antigravity / Kiro）、智能调度、Token 级计费、内置支付系统 |

---

## 阶段 1：宏观理解与本地跑通 ⬜

**目标**：搞清项目做什么、怎么部署、怎么跑起来

| # | 内容 | 关键文件 | 状态 |
|---|------|----------|------|
| 1 | 读 README_CN.md 理解功能全景 | `README_CN.md` | ⬜ |
| 2 | 读 DEV_GUIDE.md 搭建本地开发环境 | `DEV_GUIDE.md` | ⬜ |
| 3 | 了解部署方式（Docker Compose / 源码 / 安装脚本） | `deploy/.env.example`、`deploy/docker-compose.local.yml` | ⬜ |
| 4 | Docker Compose 启动并走通 Setup 向导 | `docker compose -f deploy/docker-compose.local.yml up` | ⬜ |
| 5 | 完成首次全链路验证：创建 Group → 添加 Account → 创建 API Key → curl 调用 `/v1/messages` | - | ⬜ |

**为什么先跑通**：后续看代码时，每个抽象概念都能对应到实际的 UI 操作和请求链路。

---

## 阶段 2：数据模型与表结构关系 ⬜

**目标**：搞清核心实体的字段、关系和生命周期。这是整个项目的根基。

| # | 内容 | 关键文件 | 状态 |
|---|------|----------|------|
| 1 | Ent Schema 体系 — 35+ 实体定义总览，建立全局数据地图 | `backend/ent/schema/*.go` | ⬜ |
| 2 | 核心表 User — 用户 / 角色 / 余额 / 并发 / TOTP | `backend/ent/schema/user.go` | ⬜ |
| 3 | 核心表 Account — AI 账号 / 凭证类型（api_key/oauth/cookie/upstream/bedrock/service_account）/ 调度状态 / 优先级 / 并发 | `backend/ent/schema/account.go` | ⬜ |
| 4 | 核心表 Group — 分组 / 平台 / 计费规则 / 模型路由 / 限流策略 / RPM / Claude Code 限制 | `backend/ent/schema/group.go` | ⬜ |
| 5 | 核心表 APIKey — 用户密钥 / 配额 / 限流（5h/1d/7d 窗口）/ IP 黑白名单 / Group 关联 | `backend/ent/schema/api_key.go` | ⬜ |
| 6 | 核心表 UsageLog — 使用记录 / token 计数 / 费用 / 乘数 / 计费层级 / 流标记 | `backend/ent/schema/usage_log.go` | ⬜ |
| 7 | 关联表 account_group — Account ↔ Group 多对多 | `backend/ent/schema/account_group.go` | ⬜ |
| 8 | 关联表 user_subscription — 用户订阅 / 日周月用量窗口 / 花费追踪 | `backend/ent/schema/user_subscription.go` | ⬜ |
| 9 | 关联表 subscription_plan — 可购买的订阅计划 | `backend/ent/schema/subscription_plan.go` | ⬜ |
| 10 | 关联表 user_allowed_group — 用户可访问的分组 | `backend/ent/schema/user_allowed_group.go` | ⬜ |
| 11 | 支付相关表 — payment_order / payment_provider_instance / payment_audit_log | `backend/ent/schema/payment_*.go` | ⬜ |
| 12 | 认证相关表 — auth_identity / auth_identity_channel / pending_auth_session | `backend/ent/schema/auth_*.go` | ⬜ |
| 13 | Mixin — TimeMixin（created_at/updated_at）/ SoftDeleteMixin（deleted_at） | `backend/ent/schema/mixins/*.go` | ⬜ |
| 14 | Ent 代码生成机制 — `go generate ./ent`，改 schema 后重新生成 | `backend/Makefile` | ⬜ |

**核心数据关系图**：
```
User ──1:N──> APIKey ──N:1──> Group ──M:N──> Account
  │                              │                │
  └──1:N──> UserSubscription ──N:1──> SubscriptionPlan ──N:1──> Group
                                        │
  User ──1:N──> PaymentOrder            └──> 定义定价规则
```

**为什么先学数据模型**：后端 Wire 注入的 25+ 个 Service、前端所有页面的 CRUD 操作、Gateway 的调度逻辑，全部围绕这些表展开。不理解数据结构，后面每一步都会卡住。

**动手建议**：启动后连上 PostgreSQL，用 `\d` 查看实际表结构，对照 schema 代码理解字段含义。

---

## 阶段 3：后端骨架 — 启动流程与架构 ⬜

**目标**：理解后端的启动流程、依赖注入、路由注册

| # | 内容 | 关键文件 | 状态 |
|---|------|----------|------|
| 1 | 入口 main.go — 三种模式（-version / -setup / normal）及 graceful shutdown | `backend/cmd/server/main.go` | ⬜ |
| 2 | Wire 依赖注入总图 — 6 大 ProviderSet 如何串起整个应用 | `backend/cmd/server/wire.go` | ⬜ |
| 3 | Wire 生成的初始化代码与 cleanup 逻辑（25+ 个后台服务） | `backend/cmd/server/wire_gen.go` | ⬜ |
| 4 | 配置加载 — Viper + config.yaml，25+ 子配置项 | `backend/internal/config/config.go` | ⬜ |
| 5 | 路由注册 — 5 个模块（auth / user / admin / gateway / payment） | `backend/internal/server/router.go` | ⬜ |
| 6 | 网关路由的自动分发逻辑（Anthropic / OpenAI 平台切换） | `backend/internal/server/routes/gateway.go` | ⬜ |
| 7 | 全局中间件链 — RequestLogger / CORS / SecurityHeaders / Recovery | `backend/internal/server/router.go` (SetupRouter) | ⬜ |

**核心认知**：请求链路 = `main.go` → `initializeApplication` (Wire) → `SetupRouter` → Middleware → Handler → Service → Repository → DB

**有了阶段 2 的基础**：现在看 `wire_gen.go` 里的 25+ 个 Service 不再是一堆陌生名字 — 你知道 `AccountService` 操作 `accounts` 表，`BillingCacheService` 依赖 `User` 的 `balance` 字段和 `UserSubscription` 的配额窗口。

---

## 阶段 4：前端全貌 ⬜

**目标**：理解前端架构、页面结构和数据流转方式，建立完整的系统直觉

| # | 内容 | 关键文件 | 状态 |
|---|------|----------|------|
| 1 | 启动流程 — Pinia → AppConfig → i18n → Router → Mount | `frontend/src/main.ts` | ⬜ |
| 2 | 根组件 — 路由守卫 / Toast / 公告弹窗 | `frontend/src/App.vue` | ⬜ |
| 3 | 路由体系 — 4 类路由（public / user / admin / setup）+ 守卫 + 路由预取 | `frontend/src/router/index.ts` | ⬜ |
| 4 | API 层 — Axios 封装 / 自动刷新 token / 401 重试队列 / 标准响应解包 | `frontend/src/api/client.ts` | ⬜ |
| 5 | Pinia Store — auth / app / adminSettings / subscriptions / onboarding / announcements / payment | `frontend/src/stores/*.ts` | ⬜ |
| 6 | 管理后台页面（Dashboard / Users / Groups / Accounts / Channels / Settings 等） | `frontend/src/views/admin/` | ⬜ |
| 7 | 用户端页面（Dashboard / Keys / Usage / Subscriptions / Purchase） | `frontend/src/views/user/` | ⬜ |
| 8 | 组件体系 — 按域组织（account / admin / auth / channels / keys / layout / payment） | `frontend/src/components/` | ⬜ |
| 9 | Composables — 共享响应式逻辑（OAuth 流程 / 表格加载 / 路由预取） | `frontend/src/composables/` | ⬜ |
| 10 | 国际化 — vue-i18n JIT 编译 / 中英双语 | `frontend/src/i18n/` | ⬜ |
| 11 | 构建配置 — Vite 插件 / chunk 拆分 / 代理 / 输出到后端 embed 目录 | `frontend/vite.config.ts` | ⬜ |

**为什么前端放在后端业务逻辑之前**：
- 前端页面就是系统的"使用说明书" — 看完之后你就知道 Group 管理页面有哪些字段、APIKey 创建时能配置什么参数
- 前端 API 模块和后端路由是一一对应的，先看前端能快速理解"哪些 API 做了什么事"
- 对二次开发来说，很多时候改动是从 UI 需求倒推后端改动的

**动手建议**：`pnpm dev` 启动前端，对照管理后台每个页面操作，同时观察 Network 面板里的 API 调用。

---

## 阶段 5：核心业务 — 网关转发引擎 ⬜

**目标**：搞透项目最核心的"请求转发 + 智能调度"机制

| # | 内容 | 关键文件 | 状态 |
|---|------|----------|------|
| 1 | API Key 认证中间件 — 鉴权 + 配额校验 + IP 限制 + 未分组拦截 | `backend/internal/server/middleware/api_key_auth.go` | ⬜ |
| 2 | GatewayService — 调度 + 转发引擎（核心中的核心） | `backend/internal/service/gateway_service.go` | ⬜ |
| 3 | 账号调度器 — 优先级 / 粘性会话 / 负载因子 / 调度快照 | `gateway_service.go` 调度逻辑 | ⬜ |
| 4 | 流式响应处理 — SSE + 实时 token 计数 + 实时计费 | `gateway_service.go` stream 处理 | ⬜ |
| 5 | 并发控制 — Redis 槽位管理（per-account / per-user） | `backend/internal/service/concurrency_service.go` | ⬜ |
| 6 | 限流服务 — 429/529 冷却 / 临时不可调度 / RPM 控制 | `backend/internal/service/rate_limit_service.go` | ⬜ |
| 7 | 计费服务 — 余额检查 / 订阅配额扣减 / Redis 缓存 | `backend/internal/service/billing_cache_service.go` | ⬜ |
| 8 | 使用记录异步写入 — usage_log + 溢出策略 | `backend/internal/service/usage_service.go` | ⬜ |
| 9 | 错误透传规则 — 哪些上游错误直接返回 vs 触发账号切换 | `gateway_service.go` error passthrough 逻辑 | ⬜ |
| 10 | 模型映射 — Claude→Antigravity / Claude→Bedrock 等跨平台路由 | `gateway_service.go` model mapping 逻辑 | ⬜ |
| 11 | 系统提示注入 — Claude Code 模拟 / MCP XML / 网页搜索 | `gateway_service.go` prompt injection 逻辑 | ⬜ |
| 12 | 用户消息队列 UMQ — serialize / throttle 模式 | `backend/internal/service/user_msg_queue_service.go` | ⬜ |

**有了前面阶段的基础**：
- 你知道 Account 表有哪些状态字段（schedulable/rate_limited/overloaded/temp_unschedulable），调度逻辑不再抽象
- 你知道 Group 表有 platform 字段和模型路由配置，模型映射逻辑有上下文
- 你知道 APIKey 表有 5h/1d/7d 限流窗口，限流服务的逻辑自然连贯

**动手建议**：在 `gateway_service.go` 中加 log，跟踪一次完整请求的 调度 → 转发 → 计费 → 记录 流程

---

## 阶段 6：认证与授权体系 ⬜

**目标**：掌握用户认证、OAuth、多身份合并等机制

| # | 内容 | 关键文件 | 状态 |
|---|------|----------|------|
| 1 | JWT 认证中间件 — Access/Refresh Token 管理 | `backend/internal/server/middleware/jwt_auth.go` | ⬜ |
| 2 | 管理员鉴权中间件 | `backend/internal/server/middleware/admin_auth.go` | ⬜ |
| 3 | 用户注册 / 登录 / 密码重置 | `backend/internal/service/auth_service.go` | ⬜ |
| 4 | TOTP 双因素认证 | `backend/internal/service/totp_service.go` | ⬜ |
| 5 | 多 OAuth 平台登录 — LinuxDo / GitHub / Google / WeChat / DingTalk / OIDC | `backend/internal/service/*oauth*.go` | ⬜ |
| 6 | 身份合并决策 — 新 OAuth 与已有用户匹配时的处理 | `backend/ent/schema/identity_adoption_decision.go` | ⬜ |
| 7 | Token 刷新服务 — 自动刷新上游 OAuth token | `backend/internal/service/token_refresh_service.go` | ⬜ |
| 8 | 前端 OAuth 回调页面 | `frontend/src/views/auth/` | ⬜ |

---

## 阶段 7：支付系统 ⬜

**目标**：掌握内置支付系统的运作方式

| # | 内容 | 关键文件 | 状态 |
|---|------|----------|------|
| 1 | PaymentService — 订单创建 / 充值码兑换 / 退款 | `backend/internal/service/payment_service.go` | ⬜ |
| 2 | Payment Registry — 动态注册支付提供商 | `backend/internal/payment/registry.go` | ⬜ |
| 3 | LoadBalancer — 支付实例负载均衡（轮询 / 最小金额） | `backend/internal/payment/load_balancer.go` | ⬜ |
| 4 | Stripe 集成 | `backend/internal/payment/provider/stripe/` | ⬜ |
| 5 | 支付宝集成 | `backend/internal/payment/provider/alipay/` | ⬜ |
| 6 | 微信支付集成 | `backend/internal/payment/provider/wechat/` | ⬜ |
| 7 | EasyPay 集成 | `backend/internal/payment/provider/easypay/` | ⬜ |
| 8 | Airwallex 集成 | `backend/internal/payment/provider/airwallex/` | ⬜ |
| 9 | 支付审计日志 | `backend/ent/schema/payment_audit_log.go` | ⬜ |
| 10 | 前端支付流程 | `frontend/src/views/user/` 支付相关页面 | ⬜ |

---

## 阶段 8：运维与监控 ⬜

**目标**：掌握运维监控相关的后台服务

| # | 内容 | 关键文件 | 状态 |
|---|------|----------|------|
| 1 | OpsService — 集中运维服务 | `backend/internal/service/ops_service.go` | ⬜ |
| 2 | OpsMetricsCollector — 周期指标采集（并发 / 可用性 / 流量） | `backend/internal/service/ops_metrics_collector.go` | ⬜ |
| 3 | OpsAggregationService — 小时/日聚合 | `backend/internal/service/ops_aggregation_service.go` | ⬜ |
| 4 | OpsAlertEvaluatorService — 告警规则评估 | `backend/internal/service/ops_alert_evaluator_service.go` | ⬜ |
| 5 | ChannelMonitor — 渠道健康监控 / 定时检测 | `backend/internal/service/channel_monitor_service.go` | ⬜ |
| 6 | 调度快照服务 — 账号可用性快照到 Redis | `backend/internal/service/scheduler_snapshot_service.go` | ⬜ |
| 7 | 定时任务 — 订阅过期 / 账号过期 / 订单过期 / 数据清理 | `backend/internal/service/*expiry_service.go`、`usage_cleanup_service.go` | ⬜ |

---

## 阶段 9：扩展领域（按需深入） ⬜

### 9.1 OAuth 接入新平台 ⬜

| 内容 | 关键文件 | 状态 |
|------|----------|------|
| Claude OAuth | `backend/internal/service/claude_oauth_service.go` | ⬜ |
| OpenAI OAuth | `backend/internal/service/openai_oauth_service.go` | ⬜ |
| Gemini OAuth | `backend/internal/service/gemini_oauth_service.go` | ⬜ |
| Antigravity OAuth | `backend/internal/service/antigravity_oauth_service.go` | ⬜ |
| Kiro OAuth | `backend/internal/service/kiro_oauth_service.go` | ⬜ |
| Token Provider 模式 | `backend/internal/repository/*token_provider*.go` | ⬜ |
| Token Refresher | `backend/internal/service/token_refresh_service.go` | ⬜ |

**改造场景**：接入新的 AI 服务商

### 9.2 网关协议扩展 ⬜

| 内容 | 关键文件 | 状态 |
|------|----------|------|
| Anthropic 协议 | `backend/internal/handler/gateway_handler.go`, `backend/internal/pkg/claude/` | ⬜ |
| OpenAI 兼容协议 | `backend/internal/handler/openai_gateway_handler.go`, `backend/internal/pkg/openai/` | ⬜ |
| Gemini 原生协议 | `backend/internal/handler/gemini_gateway_handler.go`, `backend/internal/pkg/gemini/` | ⬜ |
| Antigravity 协议 | `backend/internal/handler/antigravity_gateway_handler.go`, `backend/internal/pkg/antigravity/` | ⬜ |
| Kiro 协议 | `backend/internal/pkg/kiro/` | ⬜ |
| OpenAI WebSocket v2 | `backend/internal/service/openai_ws_v2/` | ⬜ |
| 错误透传规则 | `backend/ent/schema/error_passthrough_rule.go` | ⬜ |

**改造场景**：支持新的 API 格式或平台

### 9.3 计费模式定制 ⬜

| 内容 | 关键文件 | 状态 |
|------|----------|------|
| BillingCacheService | `backend/internal/service/billing_cache_service.go` | ⬜ |
| PricingService | `backend/internal/service/pricing_service.go` | ⬜ |
| SubscriptionService | `backend/internal/service/subscription_service.go` | ⬜ |
| 模型定价数据 | `backend/data/model_pricing.json` | ⬜ |
| Channel 定价 | `backend/internal/service/channel_service.go` | ⬜ |

**改造场景**：调整计费策略、新增定价模型

### 9.4 前端页面定制 ⬜

| 内容 | 关键文件 | 状态 |
|------|----------|------|
| 管理后台 | `frontend/src/views/admin/` | ⬜ |
| 用户端 | `frontend/src/views/user/` | ⬜ |
| 公共页面 | `frontend/src/views/public/` | ⬜ |
| 布局组件 | `frontend/src/components/layout/` | ⬜ |
| 通用组件 | `frontend/src/components/common/` | ⬜ |

**改造场景**：修改 UI、添加新页面、自定义主题

---

## 学习顺序总结

```
阶段 1  跑通系统，建立直觉
   ↓
阶段 2  数据模型 ← 根基！所有代码围绕这些表展开
   ↓
阶段 3  后端骨架 ← 启动流程、DI、路由（有了数据模型基础，看懂 wire_gen 不再困难）
   ↓
阶段 4  前端全貌 ← 先看 UI，建立"哪些功能做什么事"的完整认知
   ↓
阶段 5  核心业务 ← 网关引擎（此时数据+骨架+UI 都已理解，串联起来自然顺畅）
   ↓
阶段 6  认证授权 ← 独立模块，按需深入
阶段 7  支付系统 ← 独立模块，按需深入
阶段 8  运维监控 ← 独立模块，按需深入
阶段 9  扩展领域 ← 根据你的二次开发方向选择性深入
```

---

## 关键概念速查表

| 概念 | 含义 |
|------|------|
| **Account** | 上游 AI 账号（API Key / OAuth），实际调用 AI 服务的凭证 |
| **Group** | Account 的分组，定义计费规则、模型路由、限流策略 |
| **Channel** | Group 下的计费通道，定义每个模型的价格 |
| **API Key** | 分发给用户的密钥，关联到某个 Group |
| **Gateway** | 请求转发引擎，将用户请求路由到合适的 Account |
| **Simple Mode** | 简化模式，关闭 SaaS 功能（注册/支付/订阅），适合个人使用 |
| **Sticky Session** | 粘性会话，同一会话优先使用同一 Account |
| **UMQ** | 用户消息队列（User Message Queue），serialize / throttle 两种模式 |
| **Wire** | Google 编译时依赖注入框架，`wire.go` 声明，`wire_gen.go` 自动生成 |
| **Ent** | Go ORM 框架，schema 定义在 `ent/schema/`，通过 `go generate` 生成 CRUD |

---

## 二次开发备忘

1. **先跑通再改** — Docker Compose 完整运行，走通所有功能
2. **改 Schema 要跑 generate** — 修改 `ent/schema/` 后必须 `go generate ./ent`
3. **前端构建输出到后端** — `pnpm build` 输出到 `backend/internal/web/dist`，通过 Go embed 嵌入二进制
4. **配置优先看 .env.example** — 20KB+ 环境变量模板，几乎所有行为都可配置
5. **核心逻辑在 Service 层** — Handler 只做参数解析，Service 才是业务核心
6. **Redis 是性能关键** — 并发 / 计费缓存 / 调度快照 / 限流 / UMQ 都依赖 Redis
7. **迁移文件递增编号** — 新增迁移放在 `backend/migrations/`，编号递增
8. **后端启动会注册 25+ 个后台定时服务** — 都在 cleanup 中统一 Stop
9. **Gateway 路由会根据 group platform 自动切换 handler** — `/v1/messages` 可能走 Anthropic 或 OpenAI
10. **前端 i18n 使用 JIT 编译** — CSP 安全，运行时按需加载语言包
