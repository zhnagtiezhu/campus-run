# 12 · 开发排期 WBS

> 按 **8 周课余**（每周 12–15 小时）排，总工时约 120h。每周有明确交付物和验收标准，做完打勾。
> 如果时间被压缩，按 §6 的裁剪顺序砍，不要平均分配时间。
> v1.2：W1 拆成 W1a/W1b（原 12h 明显低估）；补自动确认、改派、退款流水、消息、压测造数；每步对应 `build/` 施工图编号。

---

## W0 · 准备（3 天，不写业务代码）

- [ ] 装齐环境（JDK17 / Maven / Node / Python3.11 / Docker / JMeter）
- [ ] 申请 LLM API Key、高德 JS Key + 安全密钥，写入 `.env`
- [ ] 下载 `bge-small-zh-v1.5` 到本地
- [x] 建仓库 `campus-run`（remote: github.com/zhnagtiezhu/campus-run），目录：`docs/ build/ backend-java/ agent-python/ frontend/ deploy/ tests/`
- [x] 本套文档（00–14 + 附件 + 评审）入库，tag `v1.2-docs`
- [x] `deploy/mysql/init/01-schema.sql`（**22 张表**）+ `02-demo-data.sql`（**7 单 / 4 工单 / 14 账号**）
- [ ] `docker compose` 起 MySQL/Redis/MinIO，灌数据，`tests/sql/verify-demo-data.sql` 跑出 **38 个 PASS**
- [x] 建 5 学生 / 8 骑手 / 1 运营账号（密码 `123456`，运营 `admin/Admin@123`）
- [x] 测试先于实现入库：3 个 JUnit（TDD 契约）+ 60 条评测样本 + Postman（36 请求）+ 38 条断言 + 压测造数
- [ ] 按 `14` 建仓库根 `AGENTS.md`（10 条铁律），并在 IDE 里配好格式化

**验收**：`docker compose up -d` 后能看到 22 张表 + 演示数据，校验脚本全 PASS。
**坑位提醒**：MySQL 初始化脚本只在数据卷为空时执行，改脚本要 `down -v`；Docker Desktop 内存建议 ≥6GB（六个容器 + Chroma 与本地模型）。
**施工图**：`build/S00-环境与仓库.md`

---

## W1a · Java 骨架与鉴权（12h）

- [ ] 单模块工程 + pom 依赖锁定（按 `04` §5）
- [ ] 统一 `Result` / `PageResult` / `ErrorCode`（31 个）/ `BizException`
- [ ] `JacksonConfig` 全局 `SNAKE_CASE`
- [ ] `TraceIdFilter` + MDC + `LoginContext`（ThreadLocal）
- [ ] `GlobalExceptionHandler`
- [ ] 三端 JWT 拦截器 + `JwtUtil`（含 `aud` 校验）
- [ ] MyBatis-Plus 分页插件 + `MetaObjectHandler` 自动填充
- [ ] C-01~C-07 公共接口（登录/校区/上传/健康）
- [ ] `domain/OrderStateMachine`（含改派/重派）+ `PriceCalculator` + `RefundRuleEngine` —— **让 3 个测试跑绿**
- [ ] Knife4j 可访问

**验收**：三端能登录拿到 token；计价/状态机/退款单测全绿；Knife4j 能调通登录。
**施工图**：`S01-骨架与公共层.md`、`S02-领域层三件套.md`、`S03-鉴权与公共接口.md`

## W1b · 前端脚手架（8h）

- [ ] pnpm workspace + 三端脚手架（Vite + TS + Router + Pinia）
- [ ] `shared/api/http.ts`（统一响应、错误码、trace、**幂等键按动作**）
- [ ] `useWebSocket`（CONNECT 头 token、`/topic` 订阅）
- [ ] 三端登录页 + 路由守卫 + 布局骨架
- [ ] Mock 数据跑通登录 → 首页

**验收**：三端能登录、刷新不丢状态、mock 首页可点。
**施工图**：`S04-前端骨架与登录.md`

---

## W2 · 订单主流程（15h）

- [ ] U-07 报价（`quote_token`、六项费用、时段/范围/申报价值校验）
- [ ] U-08 下单（`DRAFT` + `idempotency_key` + `draft_id` 二选一）
- [ ] 模拟支付网关 + 回调（SYSTEM → WAITING）
- [ ] U-09 支付 → 状态机 → ZADD 延迟队列
- [ ] U-10/U-11/U-12 列表/详情/时间线（缓存基础版）
- [ ] U-13 取消（DRAFT/WAITING）、U-14 确认送达、U-16 评价
- [ ] 费用六字段拆分落库 + 抽佣计算
- [ ] 前端：下单页（地图选点）+ 收银台 + 订单列表/详情 + 费用明细组件

**验收**：学生端走完"下单→支付→等待接单→取消"；T-01/T-04/T-05/T-07/T-08/T-09 通过。
**施工图**：`S05-计价下单与支付.md`、`S06-订单查询与缓存.md`

---

## W3 · 骑手端与抢单（15h）

- [ ] R-01~R-03 登录/资质/上线（BitMap + GEO + Hash + 心跳续 TTL）
- [ ] R-05 任务大厅（GEO 圈选 + 二次过滤 + 打分）
- [ ] R-07 骑手订单分页（本人订单，MP 分页插件）
- [ ] 先做 DB 版抢单（条件 UPDATE），跑通 R-06
- [ ] 改成 Lua 抢单（`grab.lua` 7 步 + 同骑手幂等）+ **同步落库**
- [ ] 失败回滚（grab key + 在手数）与 `grab_record` 异步落库
- [ ] 状态镜像 `cr:order:status` 写入与重建任务
- [ ] WebSocket：`/topic/rider/{id}/task`、`/topic/order/{id}`、订阅鉴权
- [ ] R-09 取件（40005/40905）、R-10 送达、R-11 异常上报、R-15 弃单申请
- [ ] 前端：骑手工作台、大厅（倒计时）、任务详情

**验收**：两个骑手抢同一单只有一个成功，且**成功瞬间取件可用**（T-10/T-11/T-12/T-13/T-14/T-15/T-17/T-18~T-22）。
**施工图**：`S07-骑手与抢单.md`

---

## W4 · 派单升级、结算、运营端（15h）

- [ ] `cr:zset:timeout` + `DispatchTimeoutTask`（5s 轮询）
- [ ] 首轮超时 → 扩圈 + `raise_fee+100`（`dispatch_round=2`）
- [ ] 第二轮 → 预留 Agent 调用位（先写死 `ESCALATE_CS`）
- [ ] 终止条件：`dispatch_paused=1` + ZREM
- [ ] `SettlementService`（唯一索引 + 锁）
- [ ] `RefundService` + `refund_record`（部分赔付、幂等、CAS）
- [ ] 信用分 `rider_credit_log` + 日上限 + 低于 60 拒绝抢单
- [ ] R-12/R-13/R-14 骑手收益汇总/结算明细/信用分页
- [ ] `AutoConfirmTask`（30 分钟自动确认）
- [ ] `PayTimeoutTask`（15 分钟关闭未支付）
- [ ] A-01 大盘、A-02/A-03 订单、A-04 强制取消、A-05 改派
- [ ] 工单表 + `ticket_event` + 学生端 U-17~U-19（先不接 Agent）
- [ ] 前端：运营端登录/大盘/订单列表 + 学生端售后页

**验收**：无人抢能看到扩圈加价；订单完成有结算；部分赔付不改支付状态；改派后旧骑手在手数正确（T-23~T-35）。
**施工图**：`S08-派单升级与改派.md`、`S09-结算退款与信用分.md`、`S10-工单与售后.md`

---

## W5 · 压测与打磨（12h）

- [ ] JMeter 场景 A（200 并发抢单，先跑 `seed-pressure-test.sql`）
- [ ] 场景 B（缓存前后）+ 场景 C（改 `expire_at` 制造逻辑过期）
- [ ] 输出 `docs/压测报告.md`（三张表 + 结论）
- [ ] 修 P0/P1 缺陷（记 `docs/bug-list.md`）
- [ ] `ConsistencyCheckTask`（8 项巡检，见 `09` §4）
- [ ] 限流拦截器（6 个场景，固定窗口 Lua）
- [ ] 消息中心 C-08/C-09 + `notify_message`
- [ ] 空状态 / loading / 异常页统一
- [ ] tag `v0.2-redis`

**验收**：三组数据拿到手；M2 里程碑达成，此时已可投简历。
**施工图**：`S11-压测巡检与消息.md`

---

## W6 · Agent 底座与下单 Agent（15h）

- [ ] FastAPI 骨架 + `trace_id` 中间件 + structlog + 会话锁
- [ ] `java_client.py`（httpx + 超时 + 重试 + trace + **X-Session-Id**）
- [ ] `tools/registry.py`（**14 个工具** + 权限标记；不注册退款/改状态）
- [ ] `redact.py`（PII 脱敏）
- [ ] Java 侧 `/internal/agent/**` 统一入口 + 白名单 + `agent_session` 派生用户 + 审计
- [ ] `agent/chat` P-01 + 意图路由（规则优先）
- [ ] OrderAgent（LangGraph）+ 槽位抽取 + 一次一问 + 3 轮兜底 + 类目默认起点
- [ ] 报价卡 + `create_order_draft` + 前端确认走 U-08（`draft_id`）
- [ ] ProgressAgent（进度/取消/FAQ，规则优先）+ `faq.json`
- [ ] 前端：`AgentChatPanel` + `CardRenderer` + 进度卡
- [ ] 降级开关 `app.agent.enabled=false` 全链路验证

**验收**：T-43~T-51 通过；关掉 Agent 后学生端能用表单正常下单。
**施工图**：`S12-Agent底座与工具层.md`、`S13-下单与进度Agent.md`

---

## W7 · 售后 Agent 与派单 Agent（15h）

- [ ] 规则库 10 条入 `policy_doc`（version 1.1）
- [ ] `ingest.py` 灌 Chroma（按条款切 + cosine + metadata）+ `reload-vector` 接口
- [ ] ServiceAgent：查询改写 → 检索 → 白名单校验 → `TicketAssessment`（含 `damage_level`）
- [ ] `TicketStreamConsumer` 异步调 P-03 + 回写 `agent_*`
- [ ] Java 侧 `RefundRuleEngine` 金额复算 + 差异标记
- [ ] 运营端工单台 A-11~A-14（条款原文、高额标记、role 校验、复算对比）
- [ ] DispatchAgent P-02（输入带 `raise_fee`）+ 阈值校验 + `dispatch_decision` 落库
- [ ] A-19 决策回放页（`TraceTimeline`）

**验收**：T-36~T-42、T-28~T-33 通过。
**施工图**：`S14-RAG与ServiceAgent.md`、`S15-DispatchAgent与回放.md`

---

## W8 · 评测、收尾、可讲（12h）

- [ ] 4 个样本集跑评测 → `docs/评测报告.md`（含路由/检索指标）
- [ ] 回填 `11` 文档 §2 所有 `<待填>`
- [ ] 8 页答辩 PPT
- [ ] 3 分钟录屏
- [ ] 演示路线预演 3 遍（`10` §7）
- [ ] 更新 README（架构图 + 快速开始 + 数据）
- [ ] `verify-demo-data.sql` 38 条全 PASS
- [ ] tag `v1.0-demo`
- [ ] 简历条目定稿（`11` §1 选一版）

**验收**：M4 达成。陌生人照 README 能起环境。
**施工图**：`S16-评测收尾与部署.md`

---

## 1. 甘特图（文字版）

```
周次   W0  W1  W2  W3  W4  W5  W6  W7  W8
骨架       ██
前端       ██
订单           ████
骑手/抢单           ████
派单/结算              ████
压测/巡检                  ████
Agent底座                      ████
售后/派单                          ████
评测/收尾                              ████
```

---

## 2. 每周固定节奏（建议）

| 时点 | 动作 |
|---|---|
| 周一开始 | 从 WBS 勾本周任务，先做"验收标准最硬"的那条，并打开对应 `build/Sxx` 施工图 |
| 周三 | 中断检查：本周完成 <50% 立刻按 §6 砍范围 |
| 周五 | 跑本周验收用例，不过的不带进下周 |
| 周日 | 写 3 行周记：做完了什么 / 卡在哪 / 下周第一件事 |

**周记不是形式**：收尾时 `bug-list` 的"根因"和面试答"难点在哪"都从这里来。

---

## 3. 进度风险与应对

| 信号 | 说明 | 动作 |
|---|---|---|
| W2 结束还跑不通下单 | 地基有问题 | 砍地图选点，先用预置地址下拉 |
| W3 抢单 Lua 反复出错 | 复杂度超预期 | 回退 DB 条件更新，文档里讲"两种方案都实现了，压测对比后选 Lua"，反而加分 |
| W5 压测数据不理想 | 环境问题居多 | 先查索引、Redis 与压测机是否同机（同机会互相干扰） |
| W6 Agent 底座拖到 10 天 | 通常是 LangGraph 学习成本 | 改用自研 while-loop 工具调用，不迷信框架 |
| W7 条款引用总错 | 切块/检索问题 | 检查 chunk 是否按条款切、metadata 是否带 `clause_no`、距离是否是 cosine |

---

## 4. 时间不足时的裁剪顺序（从后往前砍）

| 顺序 | 砍掉 | 影响 | 保留什么 |
|---|---|---|---|
| 1 | 运营端结算导出、决策回放页 | 演示少一页 | 工单台必须留 |
| 2 | 地图打点大厅（改纯列表） | 视觉弱一点 | GEO 接口保留 |
| 3 | DispatchAgent（保留规则升级） | 少一个 Agent 亮点 | 设计仍可讲"评估过，阈值内规则更稳" |
| 4 | 评价与信用分 | 少一条闭环 | 结算必须有 |
| 5 | 消息中心（保留 WS 推送） | 少一个页面 | `notify_message` 表保留 |
| 6 | **绝不砍**：Lua 抢单 + 同步落库、缓存三件套、Agent 下单、工单初判、退款/赔付、压测报告 | 砍了就成普通 CRUD | — |

**判断标准**：能砍的都是"锦上添花"，不能砍的都是"简历上那一行字"。

---

## 5. 每阶段可展示的产物（给自己正反馈）

| 阶段 | 能截图的 |
|---|---|
| W2 | 支付成功 + 等待接单的订单详情（费用六项） |
| W3 | 两个骑手抢单，一个成功一个"手慢了"；成功瞬间能取件 |
| W4 | 无人接单 → 自动加价 100 分的系统消息；部分赔付的工单 |
| W5 | 三张压测柱状图 |
| W6 | 一段 Agent 对话，从口语到报价卡 |
| W7 | 一张工单：定性 + 引用 P-04 + 复算对比；一次改派回放 |
| W8 | 完整 3 分钟录屏 |

---

## 6. 变更记录

| 版本 | 日期 | 变更 |
|---|---|---|
| v1.0 | 2026-11-17 | 8 周初版 |
| v1.2 | 2026-11-17 | ① W1 拆 W1a/W1b；② 每阶段挂 `build/Sxx` 施工图；③ 补同步落库、状态镜像、自动确认、改派、退款流水、信用分、消息、压测造数；④ 验收用例编号对齐 v1.2；⑤ 裁剪顺序把地图大厅提前；⑥ 总工时 120h |
