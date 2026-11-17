# AGENTS.md — AI 编码助手项目指令

campus-run · 校园跑腿平台（Java 主服务 + Python Agent + 三端 Vue 前端）。
施工按 `build/S00~S16` 顺序进行，每一步先读对应施工图再动工；分层顺序与自检清单见 `docs/14-AI辅助开发工作流.md`。

## 编码铁律（AI 必须遵守）

1. JSON/HTTP/DB 字段一律 snake_case；Java 内部类用大驼峰。
2. 金额一律 int（分）；禁止 double/BigDecimal 参与计算。
3. 费用必须拆成 fee/urgent_fee/night_fee/raise_fee/urgency_fee/total_fee 六字段。
4. 订单状态只能走 OrderStateMachine.requireTransit(...)；禁止直接 UPDATE status。
5. Redis 写操作必须带 TTL，key 必须在 docs/05 的 key 表里。
6. 事务方法内禁止 Redis/HTTP/Stream 调用（放 afterCommit）。
7. 写接口必须支持 Idempotency-Key；key 按"用户动作"生成。
8. Agent 工具不注册 refund_order / update_order_status；工具用户身份从 X-Session-Id 派生。
9. 错误码只能来自 ErrorCode 枚举（docs/03 §9），禁止硬编码数字。
10. 每次改动必须同步 docs/02、docs/03、SQL、测试四处中的相关项。

## 交付基线

- 分层顺序：L0 契约 → L1 领域（纯函数）→ L2 持久 → L3 编排 → L4 接入 → L5 前端，不要跳层。
- 每层完成标准见 docs/14 §3（L0 是 `mvn compile` + SQL 38 条 PASS，L1 是 domain 测试全绿，依次类推）。
- 三个 TDD 契约测试（`backend-java/src/test/java/com/campusrun/domain/`）未全绿不得进入下一层。
- 演示与评测时钟：评测集固定 `now=2026-11-17T12:00:00+08:00`（见 `agent-python/eval/README.md` §4）。
- 真实密钥只放 `deploy/.env`（已 gitignore）；示例变量见 `deploy/.env.example`。
