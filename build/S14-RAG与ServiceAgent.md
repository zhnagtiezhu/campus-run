# S14 · RAG 与 ServiceAgent

## 1. 目标
工单提交后 10s 内出 Agent 初判：检索条款（Chroma/cosine）→ 定性 + 责任方 + 损坏等级 + 引用条款 + 话术；Java 复算金额并回写。

## 2. 前置
S10 工单流可用；S12 `list_policy_docs` 可用。

## 3. 产出文件

```
agent-python/app/
├── api/{ticket,policy}.py
├── rag/{ingest,retriever,chunker,prompts}.py
├── agents/service_agent.py
└── schemas/ticket.py

backend-java/src/main/java/com/campusrun/
├── mq/TicketStreamConsumer.java        # 补：调用 P-03 + 回写
├── service/AgentClient.java            # 补 assessTicket
└── service/TicketService.java          # 补 applyAssessment
```

## 4. 契约

**灌库 P-04**：Java `POST /agent/policy/reload`，body `docs[]`（来自 `list_policy_docs`）→ Python：
- 按 `clause_no` 一条一个 chunk（>400 字按段落再切，保留 part）；
- metadata：`doc_code/clause_no/title/version/effective_at`；
- collection：`campus_policy_v1`，`hnsw:space=cosine`；重灌前 delete collection；
- 返回 `chunks, cost_ms`。

**检索**：
- 查询改写（口语→检索语句）；
- top_k=4，相似度阈值 0.35（若召回率不达标在 0.30–0.45 之间标定）；
- 过滤 `status=生效`（由 Java 传入的 docs 保证）；
- 返回 `[{clause_no,title,content,score}]`，空则 `[]`。

**P-03 `/agent/ticket/assess`**
入参：`ticket{type,description,evidence_count,within_window,signed_at}`、`order{total_fee,delay_minutes,declared_value}`、`user_message`。
出参：`category,liable_party,damage_level?,suggested_refund,cited_clauses[],reply_draft,confidence`。
Prompt 硬约束：
- 只输出 JSON；`cited_clauses ⊆ 检索结果`；
- `within_window=0` → 不得建议赔付（refund=0 或仅退基础费）；
- `P-02` 违规（申报>500 元）→ 必须引用 P-02 且 `needs_human` 由 Java 判定；
- 话术 ≤150 字、先结论后依据、不承诺"一定赔"。

**Java 回写**：
1. `TicketStreamConsumer` 收到 `ticket_no`：建/取 `agent_session(ref_type=TICKET, ref_id=ticket_no)`；
2. 组装入参（金额/时长/申报价值都来自 DB）；
3. `POST /agent/ticket/assess`（10s）；
4. 成功：白名单校验（clause 存在于 policy_doc 且 status=1）→ 写 `agent_*` + `damage_level` → `PENDING→REVIEWING`；写 `agent_tool_log`/`agent_turn_log`；WS 推运营；
5. 失败：`agent_failed=1`，状态保持 PENDING；
6. 金额复算：`RefundRuleEngine` + `min(实付, 申报或50000, 20000)`，与建议差 >20% 以复算为准并标 review_flag。

## 5. 实现要点
1. 先灌库再测检索：`/agent/health` 的 `vector_count` 应为 10。
2. 白名单校验在 Python 与 Java 各做一次（双保险）。
3. `damage_level` 只允许 LIGHT/MEDIUM/SEVERE；`category` 只允许 delay/damage/lost/attitude/other。
4. `within_window` 与 `evidence_count` 由 Java 算，模型只读。
5. 运营详情 A-12 展示"模型建议 vs 规则复算"。

## 6. 禁止
- 不要让模型输出百分比/自算金额。
- 不要让模型引用检索结果之外的条款。
- 不要在 Python 里直连 DB 或直接改 ticket 状态。
- 不要绕过 `within_window` 给赔付。

## 7. 验收
```bash
# T-36 提交 200ms 返回，10s 内 REVIEWING 且有 agent_*
# T-37/T-38 条款引用 ⊆ 检索结果；>1000 分需 role=2
# T-39/T-40/T-41/T-42 赔付/幂等/驳回/并发
# 工单 1：应命中 P-04，175 分；工单 2：P-05，105→实际 100
```

## 8. 可复制 Prompt
```text
按 build/S14 实现 RAG + ServiceAgent + 异步回写。
要求：
1) 灌库：按条款切、cosine、metadata 五字段；
2) 检索：改写 + top_k=4 + 阈值 0.35 + 空数组；
3) 模型只输出定性/责任方/damage_level/条款/话术，不输出金额百分比；
4) Java 复算金额并在 A-12 展示对比；白名单校验 Python + Java 各一次；
5) 失败只标 agent_failed，不改工单状态。
禁止：模型算钱、引用未检索条款、Python 连库。
验收：T-36~T-42；条款准确率 100%；检索召回≥95%。
```

## 9. 进度
- [ ] 灌库 10 chunk + cosine
- [ ] 检索 + 改写
- [ ] ServiceAgent + Prompt
- [ ] 异步回写 + 白名单
- [ ] 复算对比 + A-12
- [ ] T-36~T-42
