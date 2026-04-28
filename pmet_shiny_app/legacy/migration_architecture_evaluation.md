# PMET Shiny → 现代架构迁移评估

## 1. 当前系统执行链与问题点

### 1.1 执行链梳理

```
app.R
  └── R/app.R
      └── R/global.R (加载所有依赖、配置、source所有模块)
          └── R/server/tab_start.R (核心任务入口)
              ├── R/module/promoters.R (UI + 文件上传处理)
              ├── R/module/promoters_precomputed.R
              ├── R/module/intervals.R
              │   └── 文件上传 → reactiveVal 状态 → future_promise 异步
              │       └── R/utils/command_call_pmet.R
              │           └── system("nohup scripts/pmet/*.sh ... &")
              │               ├── scripts/pmet/promoters_only_pair.sh
              │               ├── scripts/pmet/promoters_index_pair_new_fimo.sh
              │               └── scripts/pmet/intervals_index_pair.sh
              │                   ├── 外部二进制 (pair_parallel, index_fimo_fused)
              │                   ├── Python 脚本
              │                   └── R/utils/send_mail.R (通过 Rscript 调用)
              └── 结果下载: nginx 静态文件服务
```

### 1.2 关键文件职责

| 文件 | 职责 | 问题 |
|------|------|------|
| `R/server/tab_start.R` | 任务提交入口，UI状态控制，future异步 | 逻辑耦合严重，~400行代码混杂UI和业务 |
| `R/utils/command_call_pmet.R` | 构建并执行PMET命令 | `paste()` 拼接shell命令，命令注入风险 |
| `R/utils/send_mail.R` | 邮件通知 | 可独立，但通过 Rscript CLI 调用，不够优雅 |
| `scripts/pmet/*.sh` | 实际执行PMET流程 | 与R层强耦合，难以独立测试 |
| `R/module/promoters.R` | UI组件 + 文件验证 + 状态反馈 | UI与validation逻辑混在一起 |

### 1.3 核心问题点

1. **会话绑定**: `future_promise` 结果回调依赖Shiny会话，会话断开后无法通知用户
2. **命令拼接**: `system(paste(...))` 风格存在安全隐患且难以测试
3. **状态存储**: 任务状态仅存于内存（RDS文件形同虚设），缺乏持久化
4. **并发限制**: `future::plan("multisession", workers = 2)` 硬编码，无法水平扩展
5. **文件上传**: Shiny原生上传机制在大文件时体验差
6. **错误处理**: shell脚本失败时，用户只能通过邮件或超时得知

---

## 2. 逻辑分层分析

### 2.1 UI相关逻辑（应保留在前端）

| 逻辑 | 当前列置 | 说明 |
|------|----------|------|
| 表单渲染 | Shiny UI | 模式选择、参数输入、文件上传 |
| 实时验证反馈 | Shiny reactive | 邮箱格式、文件格式校验 |
| 进度展示 | shinybusy/toast | spinner、通知消息 |
| 结果可视化 | Shiny plots | motif热图、直方图等 |
| 结果下载 | downloadHandler | ZIP文件下载 |

### 2.2 应该是后端API的逻辑

| 逻辑 | 当前置 | 应置 |
|------|--------|------|
| 任务提交 | `ComdRunPmet()` inside future | POST /api/tasks |
| 任务状态查询 | 无独立接口 | GET /api/tasks/{id} |
| 文件上传处理 | Shiny fileInput | POST /api/files (multipart) |
| 参数验证 | `CheckGeneFile()` | API层validation |
| 结果列表 | 无 | GET /api/tasks?email=xxx |

### 2.3 应该下沉为 Worker 的逻辑

| 逻辑 | 当前方式 | 问题 |
|------|----------|------|
| PMET indexing | nohup shell后台运行 | 无状态追踪，无法重试 |
| PMET pairing | 同上 | 同上 |
| 结果打包 | shell内zip | 同上 |
| 邮件发送 | 脚本内同步调用 | 失败无重试，延迟用户等待 |

### 2.4 应该持久化的状态

| 状态 | 当前方式 | 问题 |
|------|----------|------|
| 任务ID | 文件夹名（email_time） | 无结构化索引 |
| 任务状态 | RDS文件（不更新） | 实际状态靠文件存在推断 |
| 输入参数 | 散落在各目录 | 无审计日志 |
| 用户信息 | 仅在结果目录名 | 无用户管理 |
| 执行日志 | stdout/stderr | 无集中存储 |

---

## 3. 候选架构对比

### 3.1 方案A: Next.js + FastAPI + Celery + Redis + PostgreSQL + Nginx

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Next.js   │────▶│   FastAPI   │────▶│  PostgreSQL │
│   (前端)    │     │   (API)     │     │ (任务元数据)│
└─────────────┘     └──────┬──────┘     └─────────────┘
                           │
                    ┌──────▼──────┐
                    │    Redis    │
                    │ (消息队列)  │
                    └──────┬──────┘
                           │
              ┌────────────┼────────────┐
              ▼            ▼            ▼
        ┌──────────┐ ┌──────────┐ ┌──────────┐
        │  Celery  │ │  Celery  │ │  Celery  │
        │ Worker 1 │ │ Worker 2 │ │ Worker N │
        └────┬─────┘ └────┬─────┘ └────┬─────┘
             │            │            │
             └────────────┼────────────┘
                          ▼
              ┌───────────────────────┐
              │ PMET binaries/scripts │
              └───────────────────────┘
```

**优点**:
- 业界成熟方案，社区资源丰富
- FastAPI 原生支持 async，适合 I/O 密集操作
- Celery 支持任务重试、优先级、定时任务
- PostgreSQL 提供可靠的任务持久化
- Next.js 提供优秀的开发体验和SEO

**缺点**:
- 技术栈较重，需要维护多个组件
- 团队需要学习新语言栈（TypeScript + Python）
- 部署复杂度较高

**适配分析**:
- 多文件上传: ✅ FastAPI multipart + 前端chunk upload
- 长任务: ✅ Celery + Redis 完美适配
- shell/二进制: ✅ Python subprocess 管理成熟
- 任务状态: ✅ Celery + PostgreSQL
- 结果下载: ✅ Nginx static / FastAPI stream
- 邮件: ✅ Celery task with retry
- 部署: ⚠️ 需要维护5+组件

### 3.2 方案B: 前端框架 + Plumber API + 任务队列

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  React/Vue  │────▶│   Plumber   │────▶│   SQLite    │
│   (前端)    │     │  (R API)    │     │ (元数据)    │
└─────────────┘     └──────┬──────┘     └─────────────┘
                           │
                    ┌──────▼──────┐
                    │  自己实现   │
                    │ 队列/进程池 │
                    └──────┬──────┘
                           │
                          ...
```

**优点**:
- 保留R栈，现有代码可复用
- 学习曲线平缓
- Plumber API 简单易用

**缺点**:
- R 的并发模型不如 Python 成熟
- 缺乏现成的任务队列方案（需要自己实现）
- 调试和生产监控工具较少
- 社区资源有限

**适配分析**:
- 多文件上传: ⚠️ Plumber 支持，但需自己处理
- 长任务: ⚠️ 需自己实现队列和状态管理
- shell/二进制: ✅ 与现有方案一致
- 任务状态: ⚠️ 需自己实现
- 结果下载: ✅ Plumber static files
- 邮件: ✅ 现有代码可复用
- 部署: ⚠️ 中等复杂度，但工具链不成熟

### 3.3 方案C: Dash + Celery/Redis

```
┌─────────────────────────────┐
│         Dash (Python)       │
│    (前端 + API 一体)        │
└──────────────┬──────────────┘
               │
        ┌──────▼──────┐
        │    Redis    │
        └──────┬──────┘
               │
        ┌──────▼──────┐
        │   Celery    │
        │   Workers   │
        └─────────────┘
```

**优点**:
- 保持 Python 单栈
- Dash 提供类似 Shiny 的开发体验
- 可以复用 PMET Python 脚本

**缺点**:
- Dash 仍是一个状态化的框架，长任务问题未根本解决
- 并非真正的 REST API 分离
- 生产级部署案例较少

**适配分析**:
- 多文件上传: ⚠️ Dash 上传组件能力有限
- 长任务: ⚠️ 仍需 Celery 等外部方案
- shell/二进制: ✅ Python subprocess
- 任务状态: ✅ Celery
- 结果下载: ⚠️ Dash 内置能力
- 邮件: ✅ Python smtplib
- 部署: ⚠️ 中等

### 3.4 方案D: Streamlit

```
┌─────────────────────────────┐
│        Streamlit            │
│  (脚本式应用，热重载)       │
└─────────────────────────────┘
```

**优点**:
- 快速原型开发
- 学习曲线极低
- 适合数据科学团队

**缺点**:
- **不适合生产部署**: 会话模型与 Shiny 类似，长任务问题完全相同
- 无真正的并发支持
- 定制化能力弱
- 无 REST API

**适配分析**:
- 多文件上传: ⚠️ 能力有限
- 长任务: ❌ 问题与 Shiny 一模一样
- shell/二进制: ✅ Python subprocess
- 任务状态: ❌ 无解决方案
- 结果下载: ⚠️ 基本支持
- 邮件: ✅ Python
- 部署: ⚠️ 单进程

**结论: 不推荐** - Streamlit 的架构问题与 Shiny 本质相同，无法解决当前痛点。

---

## 4. 推荐方案

### 4.1 长期主方案: 方案A (Next.js + FastAPI + Celery + Redis + PostgreSQL)

**理由**:
1. **彻底解耦**: 前端、API、Worker 各自独立，可独立扩展
2. **成熟生态**: 所有组件都有丰富的生产案例和监控工具
3. **任务可靠性**: Celery 提供重试、超时、死信队列
4. **水平扩展**: 可根据负载增加 Worker 数量
5. **运维友好**: 各组件都有成熟的 Docker/K8s 部署方案

### 4.2 低风险过渡方案: 最小改动版本

如果团队暂时不想引入完整技术栈，可采用**渐进式迁移**:

**Phase 0: 保持 Shiny UI，抽取独立服务**

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Shiny UI  │────▶│  FastAPI    │────▶│  Celery     │
│   (保留)    │     │  (新增)     │     │  (新增)     │
└─────────────┘     └─────────────┘     └─────────────┘
       │                                        │
       │                                   ┌────▼────┐
       └───────────────────────────────────│  Redis  │
                                           │  SQLite │
                                           └─────────┘
```

**改动范围**:
1. 新增 `task_submission_api.py` (FastAPI)
2. 新增 `task_worker.py` (Celery)
3. 修改 `command_call_pmet.R` → 调用 HTTP API 而非直接 system()
4. 保留 Shiny UI 和可视化功能

**好处**: 最大程度保留现有前端，先验证后端架构

---

## 5. 为什么继续绑定 Shiny 不是最优解

1. **会话依赖无法逃避**: Shiny 的 reactive 和 future_promise 都依赖会话，会话断开 = 任务失联
2. **并发模型先天不足**: Shiny 设计用于交互式分析，不适合后台任务密集型应用
3. **扩展性差**: 无法水平扩展，只能垂直升级单机
4. **监控困难**: 缺乏任务状态追踪、告警机制
5. **用户体验**: 用户无法查看历史任务、无法取消任务、无法重试失败任务

---

## 6. 为什么推荐/不推荐各框架

### 推荐迁移，不推荐停留

| 框架 | 推荐度 | 理由 |
|------|--------|------|
| **继续 Shiny** | ⭐ | 不解决任何根本问题 |
| **Streamlit** | ⭐ | 架构问题完全相同，换皮不换骨 |
| **Dash** | ⭐⭐ | Python栈，但仍是状态化框架，长任务未解 |
| **Plumber** | ⭐⭐⭐ | 可保留R栈，但需自己实现整套队列系统 |
| **FastAPI + Celery** | ⭐⭐⭐⭐⭐ | 完美匹配需求，生态成熟，可独立扩展 |

### 核心论点

- **不推荐 Streamlit/Dash**: 它们的会话模型与 Shiny 类似，迁移后问题依旧
- **可选 Plumber**: 如果团队R能力极强且不愿换栈，但需要大量自研工作
- **强烈推荐 FastAPI + Celery**: 这正是为解决此类问题而生的架构

---

## 7. 迁移阶段划分

### Phase 1: 后端服务抽离 (2-3周)

**目标**: 建立独立的任务提交和执行服务，Shiny 仅作为前端

**边界**:
- `task submission api`: FastAPI endpoint
- `task worker`: Celery worker
- `task metadata store`: SQLite (后续可换 PostgreSQL)

**保留**:
- PMET shell/二进制调用语义
- 现有输入参数含义
- 结果目录结构
- 邮件发送逻辑

**产出**:
```
pmet_backend/
├── api/
│   ├── main.py              # FastAPI 入口
│   ├── routes/
│   │   ├── tasks.py         # 任务提交、状态查询
│   │   └── files.py         # 文件上传
│   └── models/
│       └── task.py          # Pydantic 模型
├── worker/
│   ├── celery_app.py        # Celery 配置
│   └── tasks/
│       ├── pmet_index.py    # indexing 任务
│       └── pmet_pair.py     # pairing 任务
├── services/
│   ├── mail.py              # 邮件服务
│   ├── storage.py           # 文件存储
│   └── executor.py          # PMET 执行器
└── config.py
```

**验证方式**:
1. API 可独立启动，/docs 显示 Swagger 文档
2. POST /api/tasks 返回 task_id
3. Worker 完成后状态更新
4. Shiny 通过 HTTP 调用 API 提交任务

### Phase 2: 前端替换 (3-4周)

**目标**: 用 React/Next.js 替换 Shiny UI

**保留**:
- 现有可视化逻辑 (可用 plotly.js / d3 重写)
- 结果下载方式

**产出**:
```
pmet_frontend/
├── app/
│   ├── page.tsx
│   ├── submit/
│   │   └── page.tsx         # 任务提交表单
│   └── results/
│       └── [id]/
│           └── page.tsx     # 结果可视化
├── components/
│   ├── FileUpload.tsx
│   ├── ParameterForm.tsx
│   └── MotifVisualization.tsx
└── lib/
    └── api.ts               # API 客户端
```

### Phase 3: 完整迁移与优化 (2-3周)

**目标**: 下线 Shiny，完成迁移

**工作**:
- 迁移所有可视化组件
- 添加任务历史页面
- 添加用户通知系统 (WebSocket/SSE)
- 性能优化和监控集成

---

## 8. 第一阶段最小落地改造范围

### 8.1 需要新增的文件

```
pmet_backend/
├── api/main.py                    # FastAPI 入口
├── api/routes/tasks.py            # POST /api/tasks, GET /api/tasks/{id}
├── api/models/task.py             # TaskCreate, TaskResponse
├── worker/celery_app.py           # Celery 实例
├── worker/tasks/pmet.py           # run_pmet_index, run_pmet_pair
├── services/executor.py           # 调用 PMET shell/二进制
├── services/mail.py               # 邮件发送 (复用现有逻辑)
├── services/storage.py            # 文件移动、结果打包
├── config.py                      # 环境变量配置
├── requirements.txt
└── docker-compose.yml             # redis, api, worker
```

### 8.2 需要修改的文件

| 文件 | 改动 |
|------|------|
| `R/server/tab_start.R` | 改为调用 HTTP API |
| `R/utils/command_call_pmet.R` | 废弃或改为 HTTP 客户端 |
| `scripts/pmet/*.sh` | **不动**，保持现有语义 |

### 8.3 需要保留的文件

- `scripts/pmet/*.sh` - 保持不变
- `scripts/pmet/build/*` - 二进制保持不变
- `R/utils/send_mail.R` - 邮件逻辑提取到 Python

---

## 9. 风险与验证方式

### 9.1 风险矩阵

| 风险 | 影响 | 概率 | 缓解措施 |
|------|------|------|----------|
| 并发执行问题 | 高 | 中 | Phase 1 使用单 Worker 验证 |
| 文件路径兼容性 | 高 | 低 | 保持现有目录结构 |
| 邮件发送失败 | 中 | 低 | Celery 自动重试 |
| 前端迁移工作量 | 中 | 中 | Phase 0 先验证后端，再决定前端 |

### 9.2 验证计划

**Phase 1 验证点**:
1. ✅ FastAPI 启动，Swagger 可访问
2. ✅ POST /api/tasks 创建任务，返回 task_id
3. ✅ Celery Worker 执行 PMET 任务
4. ✅ GET /api/tasks/{id} 返回正确状态
5. ✅ 结果文件目录结构与原有一致
6. ✅ 邮件发送成功

**Phase 2 验证点**:
1. ✅ React 表单提交参数正确
2. ✅ 文件上传 multipart 正确处理
3. ✅ 任务状态轮询显示
4. ✅ 结果下载链接可用
5. ✅ 可视化组件正确渲染

---

## 10. 总结

| 项目 | 决策 |
|------|------|
| 长期主方案 | Next.js + FastAPI + Celery + Redis + PostgreSQL |
| 过渡方案 | 保留 Shiny 前端，先迁移后端 |
| 不推荐 | 继续 Shiny、Streamlit、Dash |
| Phase 1 重点 | 后端服务抽离，保留 PMET 执行语义 |
| Phase 2 重点 | 前端替换 |
| 关键验证 | 先验证后端，再迁移前端 |
