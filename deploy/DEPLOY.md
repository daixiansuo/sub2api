# Sub2API 部署指南（源码构建 + 版本管理）

本文档适用于基于源码二次开发、在服务器上通过 Docker Compose 进行构建部署的场景。

## 前置条件

- Debian 12 x86_64（或其他 Linux 发行版）
- Docker + Docker Compose（v2）
- Git

## 目录结构

```
deploy/
├── .env.example              # 环境变量模板
├── .env                      # 实际环境配置（git 忽略）
├── docker-compose.prod.yml   # 生产部署 compose 文件
├── deploy.sh                 # 部署管理脚本
├── .current_version          # 当前运行版本（自动生成，git 忽略）
├── .pending_version          # 已构建、待部署版本（自动生成，git 忽略）
├── .deploy_history           # 部署历史记录（自动生成，git 忽略）
├── backups/                  # 本地备份目录（自动生成，git 忽略）
├── data/                     # 应用数据目录（运行时生成）
├── postgres_data/            # PostgreSQL 数据目录（运行时生成）
└── redis_data/               # Redis 数据目录（运行时生成）
```

## 核心设计：构建与部署分离

每次构建会生成一个**带版本标签的本地 Docker 镜像**，并记录到 `.pending_version`。
部署成功后才会更新 `.current_version` 和 `.deploy_history`，旧版本镜像保留在本地不会被覆盖。
部署和回滚只是切换使用哪个标签的镜像，无需重新构建。

```
构建（分钟级）：源码 → sub2api:20260522-143052-a1b2c3d → .pending_version
部署（秒级）  ：docker compose 启动指定标签的镜像 → .current_version
回滚（秒级）  ：切换到旧标签，重启容器
```

### 版本标签规则

| 场景 | 标签格式 | 示例 |
|---|---|---|
| 当前 commit 有 git tag | `{git-tag}-{commit}` | `v1.2.0-a1b2c3d` |
| 当前 commit 无 git tag | `{YYYYMMDD-HHMMSS}-{commit}` | `20260522-143052-a1b2c3d` |

每次构建同时会打上 `latest` 标签指向最新版本。

## 首次部署

```bash
# 1. 克隆代码到服务器
git clone <your-repo-url> /opt/sub2api
cd /opt/sub2api

# 2. 创建并编辑环境配置
cp deploy/.env.example deploy/.env
vim deploy/.env
```

`.env` 中必须配置的项：

| 变量 | 说明 |
|---|---|
| `POSTGRES_PASSWORD` | PostgreSQL 密码（必填） |
| `JWT_SECRET` | JWT 签名密钥，建议用 `openssl rand -hex 32` 生成 |
| `TOTP_ENCRYPTION_KEY` | 2FA 加密密钥，建议用 `openssl rand -hex 32` 生成 |

```bash
# 3. 构建镜像并启动服务
./deploy/deploy.sh up

# 4. 查看运行状态
./deploy/deploy.sh status

# 5. 查看日志
./deploy/deploy.sh logs
```

首次启动后访问 `http://<server-ip>:8080`，管理员账号默认为 `admin@sub2api.local`，
密码在首次启动日志中输出（或在 `.env` 中通过 `ADMIN_PASSWORD` 预设）。

## 日常更新

```bash
cd /opt/sub2api
git pull
./deploy/deploy.sh backup
./deploy/deploy.sh preflight
./deploy/deploy.sh up
```

`up` 命令会自动执行：构建新镜像 → 打版本标签 → 重启容器。

如需分步执行：

```bash
./deploy/deploy.sh build     # 只构建，写入 .pending_version，不影响当前运行版本
./deploy/deploy.sh deploy    # 部署 pending 版本，成功后更新 .current_version
```

## 版本回滚

发现问题时可秒级回滚，无需重新构建：

```bash
# 回滚到上一个版本
./deploy/deploy.sh rollback

# 回滚到指定版本
./deploy/deploy.sh rollback 20260520-091530-f3e2a1b
```

查看所有可用版本：

```bash
./deploy/deploy.sh list
```

输出示例：

```
[INFO]  Available sub2api images:

  * 20260522-143052-a1b2c3d   45MB   2026-05-22 14:30:52  <- current
    20260520-091530-f3e2a1b   44MB   2026-05-20 09:15:30
    v1.1.0-d4e5f6a            44MB   2026-05-18 16:20:00

Recent deploy history (last 10):
  2026-05-22 14:31:05 | deploy   | 20260522-143052-a1b2c3d | prev:20260520-091530-f3e2a1b
  2026-05-20 09:16:00 | deploy   | 20260520-091530-f3e2a1b | prev:v1.1.0-d4e5f6a
```

## 全部命令参考

| 命令 | 耗时 | 说明 |
|---|---|---|
| `./deploy.sh build` | 分钟级 | 仅构建镜像，不启动服务 |
| `./deploy.sh deploy` | 秒级 | 用最新构建的镜像启动/更新服务 |
| `./deploy.sh up` | 分钟级 | build + deploy 一步到位 |
| `./deploy.sh preflight` | - | 校验 compose/env/backplane 网络和端口监听 |
| `./deploy.sh backup` | - | 备份配置、版本状态、数据目录，并尽量生成 PostgreSQL dump |
| `./deploy.sh rollback [tag]` | 秒级 | 回滚到上一版本或指定版本 |
| `./deploy.sh list` | - | 列出所有本地镜像版本和部署历史 |
| `./deploy.sh status` | - | 查看当前运行版本和容器状态 |
| `./deploy.sh logs [lines]` | - | 查看应用日志（默认 100 行，持续输出） |
| `./deploy.sh cleanup [N]` | - | 清理旧镜像，保留最近 N 个（默认 5） |
| `./deploy.sh stop` | 秒级 | 停止所有服务 |
| `./deploy.sh restart` | 秒级 | 重启所有服务 |

## 磁盘清理

随着迭代，本地会积累多个版本的镜像。定期清理旧版本释放磁盘空间：

```bash
# 保留最近 5 个版本（默认），删除更早的
./deploy/deploy.sh cleanup

# 保留最近 3 个版本
./deploy/deploy.sh cleanup 3
```

## 其他 compose 文件说明

deploy 目录下还有其他 compose 文件，用途不同，不要混用：

| 文件 | 用途 |
|---|---|
| `docker-compose.prod.yml` | **本方案使用** — 生产部署，配合 deploy.sh |
| `docker-compose.yml` | 拉取 Docker Hub 官方预构建镜像部署（非二次开发） |
| `docker-compose.local.yml` | 同上，但使用本地目录存储数据 |
| `docker-compose.dev.yml` | 本地开发调试（debug 模式） |
| `docker-compose.standalone.yml` | 仅应用容器，PG/Redis 由外部提供 |
