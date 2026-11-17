# S13 · 下单与进度 Agent

## 1. 目标
`/agent/chat` 可用：规则路由 + OrderAgent（槽位/报价/草稿）+ ProgressAgent（进度/取消/FAQ）；前端对话页与卡片渲染。

## 2. 前置
S12 工具层与 `X-Session-Id` 可用。

## 3. 产出文件

```
agent-python/app/
├── api/chat.py
├── agents/{base,router,order_agent,progress_agent}.py
├── agents/prompts/{order_system,progress_system}.py
├── schemas/{chat,slots,card}.py
├── data/faq.json                         # 30 条
└── tools/registry.py                     # 补 OrderAgent 可见工具

backend-java/src/main/java/com/campusrun/
├── controller/user/AgentChatController.java     # U-20/U-21/U-22
├── service/AgentChatService.java                # 转发 + 持久化 + 降级
├── service/AgentDraftService.java               # cr:draft
└── mapper/{AgentSessionMapper,AgentMessageMapper}.java

frontend/student-web/src/views/AgentChat.vue
frontend/shared/components/{AgentChatPanel,CardRenderer}.vue
```

## 4. 契约

**U-20 POST /api/user/agent/chat** → Java `AgentChatService`：
1. 入参 `session_id?/message`；无 session 则建 `agent_session(ref_type=CHAT,user_id)`，生成 `s_...`；
2. 取 `cr:ctx`（或从 `agent_message` 恢复最近 6 轮）；
3. 转发 `POST /agent/chat`（`session_id,user_id,message,context`），timeout 8s；
4. 成功：持久化 user/assistant 消息 + 更新 session.slots/intent/turn_count + 写 `cr:ctx`；
5. 失败/超时：返回降级文本 + `need_form_fallback=true`，不抛 500；
6. 出参：`session_id, reply, intent, state, slots, missing[], cards[], need_form_fallback`。

**P-01 Python 出参**：`reply, intent, state, slots, missing[], cards[], trace_id`（裸 JSON，不套 Result）。
card：`quote{quote_token,draft_id,fee_detail}`、`clarify{question}`、`progress{order_no,status}`、`ticket{ticket_no,status}`、`text{content}`。

**路由（规则优先）**
| 关键词 | intent | Agent |
|---|---|---|
| 单号/到哪/进度/多久/谁在送 | order_progress | ProgressAgent |
| 取消/不要了/退款 | order_cancel | ProgressAgent |
| 投诉/破损/丢了/超时/赔/态度 | complaint | ServiceAgent（S14） |
| 能不能送/收费/规则/几点/禁运/怎么算 | consult | FAQ → ProgressAgent |
| 帮我取/买/送到/打印/还书 | order_create | OrderAgent |
| 其他 | 模型分类（≤200 token） | 六类 |
| 置信度 <0.7 | clarify | 连续 2 次转人工 |

意图锁定：进入 `order_create` 后默认续接，除非"算了/不下了/查订单/我要投诉"。

**OrderAgent 图**：`extract_slots → check_complete → ask_next | call_quote → call_create_draft → render_quote`。
- 一次只问一个；from→to→deadline→category；
- 默认起点：`campus.default_origins`（快递/代买/打印），回复说明"默认从 XX 取"；
- `declared_value>50000` → 拒单 P-02；
- 3 轮缺必填 → `need_form_fallback=true`；
- 用户改条件后旧 draft 作废，重新 quote+draft。

**ProgressAgent**：`order_progress` 用 `list_my_orders/get_order` + 模板；`order_cancel` 返回按钮卡（WAITING）或"申请取消"卡（ACCEPTED+）；`consult` 先 `cr:faq` 再 `faq.json`；`chitchat` 固定话术。**不调用写工具**。

**U-21 history**：从 `agent_message` 取最近 10 轮（Redis 过期也能看）。
**U-22 draft**：`POST /api/user/agent/draft`，入参 `session_id,slots`，调 `create_order_draft`，返回 `draft_id/expires_at`。

## 5. 实现要点
1. Python 不落业务库；会话消息由 Java 持久化。
2. 工具循环上限：下单 5 次；超限直接 fallback。
3. 报价卡必须同时带 `quote_token` 与 `draft_id`；前端确认走 U-08（`draft_id`）。
4. `need_form_fallback` 时前端展示"切到表单"按钮。
5. FAQ 缓存 key `cr:faq:{md5(question)}`；30 条随代码发布。

## 6. 禁止
- 不要在 OrderAgent 里调 `confirm_order`/`cancel_order`（不存在）。
- 不要让模型自报价（必须 `quote_price`）。
- 不要把完整会话塞进 prompt（只 6 轮 + 摘要）。
- 不要在 Python 里新增数据库依赖。

## 7. 验收
```bash
python -m compileall agent-python/app                     # 语法自检（W7 验收门）
# Postman：U-20 对话主链路 + N-07/N-08（注入不执行/工具白名单）
# 手工抽查 order_samples 3 条（T-43/T-44/T-46）：一次成型 / 只追问 1 个槽位 / 改口覆盖
# U-21 返回最近 10 轮；U-22 生成草稿返回 draft_id
# app.agent.enabled=false 后表单下单仍可用（主流程回归）
# T-43~T-51 全过；评测脚本跑 order_samples 20 条（eval/README §4）
```

## 8. 可复制 Prompt
```text
按 build/S13 实现路由 + OrderAgent + ProgressAgent + U-20/21/22 + 前端对话页。
要求：
1) 规则优先路由，意图锁定；置信度<0.7 澄清；
2) OrderAgent 一次一问、默认起点需说明、3 轮兜底、必须调 quote_price 后出卡（quote_token+draft_id）；
3) ProgressAgent 只读工具 + FAQ，不调写工具；
4) Java 负责会话创建/消息持久化/cr:ctx/降级；Python 无状态；
5) U-22 生成草稿，确认走 U-08（draft_id）。
禁止：模型自报价、调不存在工具、Python 连库。
验收：T-43~T-51；关 Agent 后主流程可用。
```

## 9. 进度
- [ ] 路由 + 槽位抽取
- [ ] 报价卡 + draft
- [ ] ProgressAgent + FAQ
- [ ] U-20/21/22 + 持久化
- [ ] 前端对话页
- [ ] T-43~T-51
