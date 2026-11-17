# S12 · Agent 底座与工具层

## 1. 目标
Python 服务可起、trace 贯通、会话锁与预算生效；Java 侧 14 个内部工具可调，带会话身份派生与全量审计。

## 2. 前置
S11 完成；`AGENT_TOKEN` 两端一致。

## 3. 产出文件

```
agent-python/app/
├── main.py
├── core/{config,logging,limiter,budget,fallback,session_lock}.py
├── api/{health,policy}.py
├── tools/{java_client,registry,redact,schemas}.py
└── pyproject.toml

backend-java/src/main/java/com/campusrun/
├── controller/internal/AgentToolController.java
├── interceptor/AgentToolInterceptor.java
├── service/AgentSessionService.java
├── service/internal/{AgentToolService,PolicyService}.java
└── model/dto/agent/*.java
```

## 4. 契约

**Java 内部接口**（统一前缀 `/internal/agent`）
| 工具 | 方法/路径 | 写 | 说明 |
|---|---|---|---|
| get_campus_config | GET `/campus-config` | 读 | 半径/时段/关键词/默认起点/clause 列表 |
| quote_price | POST `/quote-price` | 读 | 复用 S05 `QuoteService` |
| get_order | GET `/orders/{no}` | 读 | 仅会话用户 |
| list_my_orders | GET `/me/orders` | 读 | 分页 ≤20 |
| create_order_draft | POST `/order-drafts` | 低危 | `cr:draft:{id}` 15min |
| create_ticket | POST `/tickets` | 写 | 复用 S10 |
| get_ticket | GET `/tickets/{no}` | 读 | 仅会话用户 |
| update_ticket_assessment | POST `/tickets/{no}/assessment` | 写 | 只写 agent_* |
| nearby_riders | GET `/riders/nearby` | 读 | 聚合信息 |
| query_rider_status | GET `/riders/{id}/status` | 读 | |
| reassign_order | POST `/orders/{no}/reassign` | 中危 | 复用 S08 |
| add_urgency_fee | POST `/orders/{no}/raise-fee` | 中危 | 复用 S08 |
| notify_user | POST `/notify` | 低危 | 模板 |
| list_policy_docs | GET `/policy-docs` | 读 | 10 条 + 版本 |

**安全契约**
- Header：`X-Agent-Token`（必填）、`X-Session-Id`（必填）、`X-Trace-Id`。
- 用户身份：`AgentSessionService.userIdOf(sessionId)`；**工具入参不含 `user_id`**。
- 白名单：未注册/禁止工具（`refund_order`、`update_order_status`）→ 40302。
- 审计：`finally` 写 `agent_tool_log`（tool/args/result/latency/success）。
- 限流：`cr:limit:tool:{sessionId}` 10/10s。

**Python 契约**
- `java_client.py`：httpx.AsyncClient，统一注入三个头，超时 3s，读重试 1 次。
- `registry.py`：14 个工具 + `read/write_low/write_mid/danger` 标记；`danger` 不注册。
- `redact.py`：手机号、姓名、门牌、订单号脱敏。
- `main.py` 中间件：trace_id、budget 检查（50005）、会话锁（`cr:lock:chat`）。
- `P-05 /agent/health`：model 可用、vector_count、budget_left。

## 5. 实现要点
1. `AgentToolInterceptor` 先校验 token/白名单/限流，再放行；`finally` 审计（即使 403 也记）。
2. `create_order_draft` 校验 `draft.user_id == session.userId`。
3. `update_ticket_assessment` 只允许更新 `agent_category/agent_liable_party/agent_suggested_refund/agent_clauses/agent_reply_draft/agent_confidence/agent_trace_id/damage_level`，且 `clause_no` 必须在 `policy_doc` 存在。
4. 工具返回统一 `Result` 结构（Java 内部仍用统一信封，Python 只取 `data`）。
5. Python 侧不装任何 MySQL 驱动。

## 6. 禁止
- 不要让工具接受 `user_id` 入参。
- 不要在 registry 注册退款/改状态工具。
- 不要在 Python 里 `import pymysql/sqlalchemy`。
- 不要把 `X-Session-Id` 当可选（缺 → 40001）。

## 7. 验收
```bash
# 直调（带 session）：
curl -H "X-Agent-Token: $T" -H "X-Session-Id: s_13800000005_20261117" \
     localhost:8080/internal/agent/policy-docs        # 10 条
# 缺 session → 40001
# refund_order → 40302
# 工具日志：select count(*) from agent_tool_log where trace_id='...'  >=1
```

## 8. 可复制 Prompt
```text
按 build/S12 实现 Agent 底座与 14 个内部工具。
要求：
1) Java /internal/agent/** 拦截器：token + X-Session-Id + 白名单 + 限流，finally 写 agent_tool_log；
2) 用户身份从 agent_session 派生，任何工具入参不得含 user_id；
3) 14 个工具严格按 docs/03 §6 路径与出入参，复用已有 Service；
4) Python：FastAPI + structlog + httpx 客户端 + registry（read/写分级，danger 不注册）+ PII 脱敏 + 会话锁 + 预算 key；
5) P-05 health 返回 model/vector_count/budget_left。
禁止：注册 refund_order/update_order_status、Python 连 MySQL、缺 session 放行。
验收：policy-docs 返回 10 条；缺 session 40001；refund_order 40302；审计有记录。
```

## 9. 进度
- [ ] Java 内部接口 14 个
- [ ] 拦截器（白名单/身份/审计/限流）
- [ ] Python 骨架 + 中间件
- [ ] registry + redact + budget
- [ ] 安全用例 S-04/S-05
