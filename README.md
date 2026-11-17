# campus-run · 校园跑腿平台（AI 调度客服中台）

面向校园场景的跑腿平台：学生下单 → 骑手抢单 → 超时派单升级（加价/改派/转人工）→ 结算与售后工单，叠加 AI Agent（下单对话、客服工单定性、派单决策）。

项目定位为实习简历项目：后端用苍穹外卖技术栈（Spring Boot 3.5 + MyBatis-Plus + MySQL 8），Redis 用黑马点评技术栈（Lua 原子抢单 / Stream / ZSet / GEO / BitMap / 布隆过滤器），Agent 用 Python（FastAPI + LangGraph + Chroma 检索）。

## 当前状态

- ✅ 设计文档 v1.2：`docs/00–14` + 附件 + 历史评审记录
- ✅ 数据层：`deploy/mysql/init/`（22 张表 DDL + 7 单/4 工单/14 账号演示数据）
- ✅ 测试资产：3 个 TDD 契约 JUnit、60 条 Agent 评测样本、36 请求 Postman 冒烟集、38 条一致性断言、压测造数脚本
- ✅ 施工图：`build/S00–S16`（每步含契约/要点/验收/可复制 Prompt）
- ⏳ 后端 / Agent / 前端代码：按 `build/` 施工图从 S00 开始逐步实现

## 目录结构

```
campus-run/
├── AGENTS.md               # AI 编码助手项目指令（10 条铁律）
├── docs/                   # 00–14 设计文档 + 附件（规则库/接口文档样例）
├── build/                  # S00–S16 施工图（AI 投喂用）
├── backend-java/           # Java 主服务（当前仅 3 个 TDD 契约测试，pom 随 S00 建）
├── agent-python/           # Agent 服务与评测（当前 eval/ 数据集已就绪）
├── frontend/               # student-web / rider-web / admin-web / shared（待 W5+）
├── deploy/                 # docker-compose / .env.example / mysql init 脚本
└── tests/                  # Postman 冒烟集 + SQL 断言 + 压测造数
```

## 快速开始

环境：JDK 17 · Maven · Node 18+ · Python 3.11 · Docker · JMeter 5.6

```bash
cp deploy/.env.example deploy/.env     # 填 LLM Key、高德 Key（不入库）
docker compose -f deploy/docker-compose.yml up -d   # W0 建 compose 后可用
mysql -h127.0.0.1 -uroot -p123456 campus_run < tests/sql/verify-demo-data.sql   # 38 PASS
```

开发顺序：读 `docs/README.md` → 按 `build/00-使用说明与总索引.md` 从 S00 逐步施工。

## 文档索引

| 文档 | 内容 |
|---|---|
| `docs/00-项目总览与裁剪决策.md` | 需求边界、裁剪理由、亮点清单 |
| `docs/04-系统架构设计.md` | 模块拆分、技术选型 |
| `docs/05-Redis设计.md` | 32 个 `cr:` key、抢单 Lua、缓存三件套 |
| `docs/06-Agent设计.md` | 路由/槽位/工具/检索与评测指标 |
| `docs/09-测试与压测方案.md` | T-01~T-51 + S-01~S-06、压测场景 A–D |
| `docs/10-部署与运行手册.md` | 环境、启动、排错表 |
| `docs/12-开发排期WBS.md` | W0–W8 排期与验收 |

## 质量基线（目标，见 docs/09）

抢单并发正确性（200 并发恰 1 成功）· 订单详情缓存 QPS ≥3 倍 · Agent 条款引用准确率 100%。
