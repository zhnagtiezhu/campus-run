# S15 · DispatchAgent 与决策回放

## 1. 目标
第二轮超时由 Agent 决策加价/改派/转人工；Java 严格二次校验；所有决策可按 trace_id 回放。

## 2. 前置
S14 完成；S08 的 `DispatchAgentClient` 占位可替换。

## 3. 产出文件

```
agent-python/app/
├── api/dispatch.py
├── agents/dispatch_agent.py
├── schemas/dispatch.py
└── agents/prompts/dispatch_system.py

backend-java/src/main/java/com/campusrun/
├── agent/DispatchAgentClient.java          # 替换 S08 占位
├── service/DispatchService.java            # 补 applyDecision
├── controller/admin/AdminTraceController.java   # A-19
├── model/vo/TraceReplayVO.java
└── frontend/admin-web/src/views/TraceReplay.vue
```

## 4. 契约

**P-02 入参**
```
order: {order_no,category,from_addr,to_addr,distance_m,fee,urgent_fee,night_fee,
        raise_fee,urgency_fee,total_fee,waited_sec,dispatch_round,minutes_to_deadline}
candidates: [{rider_id,distance_m,credit_score,active_orders,online,
              near7_completed,near7_timeout_rate}]
history_stats: {avg_wait_sec,avg_raise_fee,today_timeout_rate}
```
**出参**：`{action: RAISE_FEE|REASSIGN|ESCALATE_CS, rider_id|null, fee_delta, reason≤80字, confidence}`。

**Prompt 规则**（写进 system，不是硬编码）：
- 有人 0 单且 <800m → REASSIGN；
- 全员 2–3 单 → RAISE_FEE 100–200；
- `raise_fee+150 ≤500` 且仍无人接 → 再加 150–200；
- `raise_fee≥400` 或剩余 <100 → ESCALATE_CS；
- `total_fee<500` 且剩余空间 <100 → ESCALATE_CS；
- 距截止 <15 分钟 → ESCALATE_CS；
- 必须引用输入数字，禁止空话。

**Java 二次校验（不信任模型）**
| 校验 | 失败处理 |
|---|---|
| `action` 在枚举内 | 落 `applied=0` + 建工单 |
| `fee_delta ≤300` 且 `raise_fee+delta ≤500` | 40908 → 落 `applied=0` + 工单 |
| REASSIGN：rider 在线、在手<3、信用≥60、<3km | 拒绝 + 工单 |
| confidence <0.6 | 不执行 + 工单 |
| 订单仍 WAITING 且无 paused | 否则不执行 |

执行成功：写 `dispatch_decision(applied=1)`（`uk_order_round`）→ 加价/改派 → `afterCommit` ZADD(+90)、WS。
**ESCALATE_CS**：建工单 + `paused=1` + ZREM。

**A-19 GET /api/admin/trace/{trace_id}**
返回：
```
{
  "order": {...},
  "status_logs": [...],
  "tool_calls": [...],      // agent_tool_log
  "turns": [...],           // agent_turn_log（model/prompt_version/token）
  "decisions": [...]        // dispatch_decision
}
```
按时间合并成一条时间线（前端 `TraceTimeline`）。

## 5. 实现要点
1. Agent 调用失败（超时/5xx）→ 直接 `ESCALATE_CS`，不要重试超过 1 次。
2. 同一订单同轮只决策一次（唯一索引）；重复时读取已有记录。
3. `reason` 落库截断 255；`confidence` decimal(3,2)。
4. A-19 要能处理"只有工具日志、没有决策"的工单 trace。
5. 决策回放页支持：按 trace 搜索、看输入快照、看阈值校验结果。

## 6. 禁止
- 不要让模型直接改订单或写 DB。
- 不要跳过阈值校验执行 RAISE_FEE/REASSIGN。
- 不要在同一轮重复调用模型（先查 `dispatch_decision`）。
- 不要在回放页暴露完整手机号。

## 7. 验收
```bash
# T-28 首轮扩圈；T-29 第二轮调 Agent 并落 decision；
# T-30 建议加价 800 → applied=0 + 工单；
# T-31 置信度 0.4 → 不执行；
# T-32 Agent 不可用 → 工单，订单不卡死；
# T-33 累计 500 → paused=1 + ZREM
# A-19 按 trace 能串起 状态流水+工具+模型+决策
```

## 8. 可复制 Prompt
```text
按 build/S15 实现 DispatchAgent + Java 二次校验 + A-19 回放。
要求：
1) P-02 入参必须带 raise_fee/urgency_fee，出参严格 action/rider_id/fee_delta/reason/confidence；
2) Prompt 规则见 build/S15 §4，reason 必须引用数字；
3) Java 校验：枚举、单次300、累计500、rider 可用、confidence≥0.6、订单 WAITING；
4) 失败一律 applied=0 + 建工单；成功写 uk_order_round 唯一；
5) A-19 合并 status_logs/tool_calls/turns/decisions 成时间线。
禁止：模型改库、跳过阈值、重复决策。
验收：T-28~T-33；回放可还原一次决策。
```

## 9. 进度
- [ ] P-02 + Prompt
- [ ] Java 校验与执行
- [ ] 决策表唯一
- [ ] A-19 + 前端时间线
- [ ] T-28~T-33
