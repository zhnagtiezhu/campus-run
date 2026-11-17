# 05 · Redis 设计

> Redis 7.2 ｜ 单实例（简历项目不做集群，`§13` 写清"上集群要改什么"）
> 定位：**闸门 + 加速 + 消息 + 状态**。所有 Redis 数据都可从 MySQL 重建，绝不作为唯一事实源。
> 版本 v1.2：删掉重复的 `cr:order:expire` 设计、补 10 个被引用但未定义的 key、抢单 Lua 增加"同骑手幂等"、限流改称固定窗口、补热 key 治理。

---

## 1. Key 命名规范

- 统一前缀 `cr:`（campus-run）
- 格式：`cr:{域}:{对象}:{维度/标识}`
- 全部**必须带 TTL**（GEO、状态镜像、Stream 等长驻数据除外，但必须有清理/重建任务）
- 不用 `KEYS`，线上禁用 `FLUSHALL`
- 单 key 上限 10KB；`cr:order:detail` 是唯一允许到 3KB 的缓存

---

## 2. Key 全表（32 个，按用途分组）

### 2.1 缓存（4）

| Key | 类型 | TTL | 写入方 | 读方 | 技术点 |
|---|---|---|---|---|---|
| `cr:order:detail:{order_no}` | String(JSON) | 30min + rand(0,300s) | 详情读回填 | 学生/骑手/运营 | 雪崩（随机 TTL） |
| `cr:order:null:{order_no}` | String | 2min | 查空时写 | 同上 | 穿透（空值）；建单后必须 DEL |
| `cr:order:lock:{order_no}` | String(NX) | 3s | 缓存重建 | 重建线程 | 击穿（互斥重建） |
| `cr:bloom:order_no` | Redisson RBloomFilter | 常驻 | 建单写 | 查单前 | 穿透（布隆）；误判率 1%，容量 10 万，启动重建 |

### 2.2 状态与闸门（4）

| Key | 类型 | TTL | 写入方 | 读方 | 技术点 |
|---|---|---|---|---|---|
| `cr:order:status:{order_no}` | Hash（status/rider_id/version/paused） | 常驻 | 状态机每次变更 | 抢单 Lua、巡检 | **Lua 只能读 Redis，必须有状态镜像**；丢失由巡检从 MySQL 重建 |
| `cr:rider:state:{rider_id}` | Hash（online/busy_order_count/credit_score） | 1h，**心跳续期** | 上线/抢单/送达/心跳 | 抢单 Lua、派单 | 抢单前置校验；v1.2 明确心跳刷新 TTL |
| `cr:geo:rider` | GEO | 常驻 | 上线/心跳 | 派单、大厅 | GEO 附近检索；下线 ZREM |
| `cr:order:grab:{order_no}` | String（rider_id） | 5min | 抢单 Lua | 抢单 Lua、一致性巡检 | 抢单占位（原子） |

### 2.3 消息与延迟（4）

| Key | 类型 | TTL | 写入方 | 读方 | 技术点 |
|---|---|---|---|---|---|
| `cr:stream:dispatch` | Stream | 7d | 订单/抢单/派单服务 | 消费组 `cg:dispatch` | 通知类副作用 + `grab_record` 批量落库 |
| `cr:stream:ticket` | Stream | 7d | 工单服务 | 消费组 `cg:ticket` | 工单初判（10s 模型调用） |
| `cr:stream:dlq` | Stream | 30d | 消费失败 | 巡检/运营 | 死信 |
| `cr:zset:timeout` | ZSet | — | 建单/重派 | `DispatchTimeoutTask` | 延迟队列；`dispatch_paused=1` 后必须 ZREM |

### 2.4 统计（4）

| Key | 类型 | TTL | 说明 |
|---|---|---|---|
| `cr:zset:rank:daily:{yyyymmdd}` | ZSet | 32d | 骑手当日完成单榜（A-01 展示），抢单成功/送达结算时 ZINCRBY |
| `cr:bitmap:online:{yyyymmdd}` | BitMap | 3d | 上线打卡，统计日活骑手 |
| `cr:bitmap:pickup:{yyyymmdd}` | BitMap | 3d | 取件成功，算取件率 |
| `cr:hll:uv:{yyyymmdd}` | HyperLogLog | 7d | 登录/详情页访问 UV |

### 2.5 Agent 与预算（6）

| Key | 类型 | TTL | 说明 |
|---|---|---|---|
| `cr:ctx:{session_id}` | Hash（turns/summary/slots/intent/tool_calls） | 30min，每轮刷新 | 会话上下文 |
| `cr:quote:{quote_token}` | String(JSON) | 15min | 报价防篡改（**按 token 存，不按 session**） |
| `cr:draft:{draft_id}` | String(JSON：slots/quote_token/user_id) | 15min | 确认下单的草稿；归属校验 |
| `cr:faq:{md5(question)}` | String | 7d | FAQ 直答缓存（内容来自 `app/data/faq.json`） |
| `cr:budget:{yyyymmdd}` | Hash（total/used） | 2d | 日 token 预算，INCRBY 后判上限 |
| `cr:lock:chat:{session_id}` | String(NX) | 5s | 同会话串行处理，防双击并发覆盖槽位 |

### 2.6 幂等、限流、锁（8）

| Key | 类型 | TTL | 说明 |
|---|---|---|---|
| `cr:idem:{scene}:{user_id}:{key}` | String | 10min | 写接口幂等（值存首次结果摘要） |
| `cr:idem:event:{message_id}` | String | 1h | Stream 消费幂等（**用 message id，不用 order version**） |
| `cr:limit:{scene}:{id}` | String(计数) | 60s（grab 为 600s） | 固定窗口计数限流 |
| `cr:lock:settle:{order_no}` | String(Redisson) | 10s | 结算锁 |
| `cr:lock:raise:{order_no}` | String(Redisson) | 5s | 加价并发锁（DB 条件更新仍兜底） |
| `cr:lock:refund:{order_no}` | String(Redisson) | 10s | 退款/赔付锁 |
| `cr:alert:grab:{rider_id}` | String | 10min | 防脚本抢单告警标记 |
| `cr:urge:{order_no}:{user_id}` | String | 15min | 催单频控 |

### 2.7 其他（2）

| Key | 类型 | TTL | 说明 |
|---|---|---|---|
| `cr:pickup:fail:{order_no}:{rider_id}` | String | 10min | 取件码连续错误计数（3 次锁定） |
| `cr:credit:daily:{rider_id}:{yyyymmdd}` | String | 1d | 信用分当日加分累计（上限 +10） |

---

## 3. 缓存三件套

### 3.1 缓存什么（只缓存读多写少的）

| 对象 | 缓存 | 理由 |
|---|---|---|
| 订单详情（`task_order` + 展示字段） | ✅ | 详情页高频读、低频改 |
| 校区配置 / 计价规则 / 禁运词 | ✅（Spring Cache，1h） | 几乎不变 |
| 骑手列表 / 任务大厅 | ❌ | GEO 已承担，且实时性强 |
| 订单列表分页 | ❌ | 组合条件多、命中率低 |

> 缓存价值 = 命中率 × 省下的 DB 时间 − 一致性维护成本。**不要无脑缓存。**

### 3.2 穿透

1. 参数层：`order_no` 格式校验（`CR` + 14 位）
2. 布隆：建单写、查单前过；误判率 1%、容量 10 万；**Redis 重启后由 `ConsistencyCheckTask` 全量重建**（扫描近 30 天订单）
3. 空值缓存：查库为空写 `cr:order:null:{no}`，TTL 2min；**建单成功后必须 DEL**（否则新单 2 分钟内查不到）

### 3.3 击穿：逻辑过期 + 异步互斥重建（唯一方案）

| 步骤 | 动作 |
|---|---|
| 1 | 写缓存时在 JSON 内塞 `expire_at`（业务过期时间），真实 TTL 30min 兜底 |
| 2 | 读命中 → 判断 `expire_at` |
| 3 | 未过期 → 直接返回 |
| 4 | 已过期 → **仍返回旧值**，同时 `SET NX cr:order:lock:{no} 3s` |
| 5 | 拿到锁 → 异步线程池重建；拿不到 → 返回旧值 |
| 6 | 重建失败 → 保留旧值 + 日志，60s 后由巡检重试 |

> v1.1 的 `cr:order:expire` 独立 key 已删除（与 JSON 内 `expire_at` 重复）。**读永远不阻塞**，代价是可能返回几秒旧值。

### 3.4 雪崩

- TTL 加随机抖动 `+ rand(0,300)s`
- 启动预热：最近 1 小时活跃订单 TOP 100 回填
- 兜底：Redis 不可用时 `OrderCacheService.fallbackToDb=true`，直接查库 + 限流

### 3.5 一致性（写路径）

1. 先更新 MySQL（状态机入口，带 `version` 乐观锁）
2. **事务提交后**删除 `cr:order:detail:{no}`（删缓存，不是改缓存），并同步 `HSET cr:order:status` 镜像
3. 延迟 500ms 再删一次（覆盖"读请求在更新前把旧值回填"的窗口）
4. 删失败 → 本地重试队列，`ConsistencyCheckTask` 每分钟兜底

**为什么不走 Canal**：单库单表，延迟双删 + 巡检足够；Canal 引入 binlog 依赖，部署复杂度不划算。这个取舍写进简历。

---

## 4. 抢单 Lua（7 步，v1.2）

| 步骤 | 校验/动作 | 失败返回 |
|---|---|---|
| 1 | `GET cr:order:grab:{order_no}`：已存在 → 比对 `rider_id` | 同人 `5`（幂等成功）/ 不同人 `0`（已被抢） |
| 2 | 读 `cr:rider:state:{rider_id}` 的 `online` | 未上线 `2` |
| 3 | 读 `busy_order_count`，≥3 | `3`（任务已满） |
| 4 | 读 `cr:order:status:{order_no}`，必须 `WAITING` 且 `dispatch_paused=0` | `4`（状态不允许） |
| 5 | 读 `credit_score` <60 | `6`（信用不足） |
| 6 | 全部通过：`SET grab rider_id EX 300`；`HINCRBY busy 1` | — |
| 7 | 返回 `1`（占位成功） | — |

返回值映射：`1` → **同步落库**；`5` → 幂等成功（不再落库，直接返回上次结果）；`0/2/3/4/6` → 回写 `grab_record`（异步）+ 明确 `fail_reason`。

**同步落库与回滚**（v1.2）：

```
rows = UPDATE task_order SET rider_id=?, status='ACCEPTED', accepted_at=NOW(), version=version+1
        WHERE order_no=? AND status='WAITING' AND rider_id IS NULL
if rows == 0:
    DEL cr:order:grab:{no}
    HINCRBY cr:rider:state:{rider_id} busy_order_count -1
    return 40901/40902（按当前状态判断）
else:
    HSET cr:order:status:{no} status ACCEPTED rider_id {rider_id}
    XADD cr:stream:dispatch * type GRABBED order_no ...（异步副作用）
```

**为什么镜像放 Redis**：Lua 不能查 MySQL，必须有一份状态在 Redis；镜像由状态机在每次变更后同步写，丢了对 MySQL 重建。

**为什么同骑手要返回 5**：v1.1 只判断 `EXISTS` 就返回 0，网络重试会让用户看到"手慢了"，实际是自己的单——这是确定性 bug，v1.2 修复。

---

## 5. Stream 消息队列

### 5.1 派单流 `cr:stream:dispatch`

| 项 | 设计 |
|---|---|
| 消费组 | `cg:dispatch`，3 个消费者名（单机实际 1 个） |
| 事件类型 | `ORDER_PAID` / `GRABBED` / `REASSIGN` / `TIMEOUT` / `CANCELLED` / `GRAB_RECORD` |
| 消费语义 | 至少一次；**幂等键 = Stream message id**（不是 order version） |
| 确认 | 处理成功才 `XACK` |
| 失败重试 | 3 次（10s/60s/300s 退避），仍失败 → `XADD cr:stream:dlq` + 告警 |
| pending 恢复 | 每 5 分钟 `XAUTOCLAIM`（min-idle 10min）把 pending 认领回存活消费者；单条重投 >5 次进 DLQ |
| 裁剪 | `XADD MAXLEN ~ 10000` |

> v1.2 修正：v1.1 用 `order_no + event_type + version` 做幂等键，但 `version` 每次状态变都会变，重投会算出不同键 → 重复消费。改为 `cr:idem:event:{message_id}`。

### 5.2 为什么用 Stream

| 方案 | 问题 |
|---|---|
| List（LPUSH/BRPOP） | 无消费组、无 ack、不支持多消费者分担 |
| PubSub | 不持久化，消费者离线即丢 |
| **Stream** | 消费组 + ack + pending + 可回溯，最贴近 MQ |

### 5.3 工单流 `cr:stream:ticket`
独立流 + `cg:ticket`：工单初判 5–10s，与派单隔离，避免互相拖慢。

---

## 6. 延迟队列（ZSet）

| 项 | 设计 |
|---|---|
| Key | `cr:zset:timeout` |
| member | `order_no` |
| score | 到期时间戳（秒） |
| 写入 | 支付成功、每次重派后 ZADD |
| 消费 | `ZRANGEBYSCORE 0 <now> LIMIT 0 20` → 逐单处理 → `ZREM` |
| 轮询 | 5s（单机足够；生产可换 Redisson `RDelayedQueue`） |
| 幂等 | 处理前校验 `status=WAITING AND dispatch_paused=0`，否则只 ZREM |
| 终止 | `ESCALATE_CS` 或 `raise_fee` 达上限 → `dispatch_paused=1` + `ZREM`，不再自动重派 |

**为什么不用 key 过期事件**：`notify-keyspace-events` 不可靠（事件丢失无补偿、集群不保证）。
**为什么不用 `@Scheduled` 扫全表**：订单量大时 `WHERE status='WAITING' AND created_at < now-90s` 会锁竞争；ZSet 是 O(log N)。

---

## 7. GEO 设计

| 项 | 设计 |
|---|---|
| Key | `cr:geo:rider`（单校区不分区） |
| member | `rider_id` |
| 更新 | 上线 `GEOADD`；心跳 30s 更新；下线 `ZREM` |
| 查询 | `GEOSEARCH FROMLONLAT lng lat BYRADIUS 1500 m ASC COUNT 10 WITHDIST` |
| 二次过滤 | Pipeline 查 `cr:rider:state`，剔除离线/满单/信用<60 |
| 打分 | `0.5*(1-距离/半径) + 0.3*(信用/100) + 0.2*(1-在手单/3)` |

**为什么打分放 Java 不放 Redis**：权重会调，代码里改一行；Redis 只负责"圈人"。

---

## 8. 限流（固定窗口计数，Lua 原子）

| 场景 | 阈值 | Key |
|---|---|---|
| 登录 | 5 次/分钟/IP | `cr:limit:login:{ip}` |
| 报价 | 10 次/分钟/用户 | `cr:limit:quote:{user_id}` |
| 下单 | 3 次/分钟/用户 | `cr:limit:order:{user_id}` |
| 抢单 | 20 次/10 分钟/骑手 | `cr:limit:grab:{rider_id}` |
| Agent 对话 | 20 轮/10 分钟/会话 | `cr:limit:chat:{session_id}` |
| 内部工具 | 10 次/10 秒/会话 | `cr:limit:tool:{session_id}` |

实现：Lua 内 `INCR` + 首次 `EXPIRE`，超阈值返回剩余秒数。

> **术语诚实**：这是**固定窗口计数**，不是令牌桶；边界会有最多 2 倍突刺，对简历项目可接受。面试被问"为什么不用令牌桶"就答："限流目标只是防刷，不是精确 QPS；固定窗口一个 Lua 就够，令牌桶需要额外状态。生产可换 Redisson `RRateLimiter`。"（v1.1 写"令牌桶"但实现是 INCR，属于口径不一致。）

---

## 9. 幂等

| 场景 | 实现 |
|---|---|
| 下单 / 确认下单 | `cr:idem:order:{user_id}:{key}` 存 `order_no`，命中直接返回首次结果；DB `uk_order_idem` 兜底 |
| 抢单 | Lua 返回 5（同骑手重复）；不同骑手天然失败 |
| 改派 / 加价 | `cr:idem:dispatch:{order_no}:{key}` + `cr:lock:raise` |
| 结算 | `cr:lock:settle` + `settlement.order_id` 唯一 |
| 退款/赔付 | `cr:lock:refund` + `refund_record.idem_key` 唯一 + `pay_record WHERE status=1` |
| Stream 消费 | `cr:idem:event:{message_id}` TTL 1h |
| 工单处理 | `UPDATE ticket SET status='RESOLVED' WHERE id=? AND status='REVIEWING'`（CAS） |

---

## 10. 内存与容量估算

| 数据 | 单条 | 数量 | 占用 |
|---|---|---|---|
| 订单详情缓存 | ~3KB | 500（活跃） | ~1.5MB |
| 状态镜像 | ~100B | 500 | ~50KB |
| GEO 骑手 | ~50B | 50 | 忽略 |
| Stream | ~200B | 1 万 | ~2MB |
| ZSet 超时 | ~60B | 500 | 忽略 |
| 会话上下文 | ~2KB | 50 并发 | ~100KB |
| 其他 | — | — | < 5MB |

**总计 < 20MB**，`maxmemory` 设 256MB，淘汰策略 `volatile-lru`。

> **风险要说清**：`volatile-lru` 只淘汰带 TTL 的 key；如果带 TTL 的缓存很少而写入压力大，可能触发 OOM 写失败。演示环境 256MB 足够，生产应设 `noeviction` + 监控 + 容量规划。另外 `cr:order:grab` 若被误淘汰，会退化为"两个骑手都通过 Lua"，由 DB 条件更新兜底（最终只有一个成功）。

---

## 11. 热 key / 大 key 治理（v1.2 新增）

| 问题 | 表现 | 方案 |
|---|---|---|
| 热 key | 压测时同一 `cr:order:detail` 被打爆，单分片 CPU 高 | 本地 Caffeine 二级缓存（100ms TTL）+ 单 key 限流；生产可做 key 散列副本 |
| 大 key | `cr:ctx` 存 6 轮原文 + 摘要，接近 10KB | 原文截断（每轮 ≤300 字）、超 6 轮压缩为摘要 |
| 大 key | `cr:geo:rider` 单校区 50 人，可忽略 | 多校区时按 campus 分区 |
| 热 key | `cr:bloom:order_no` 每次查单都读 | 本地 Guava 缓存布隆查询结果（可选） |

---

## 12. 上集群要改什么

1. GEO、Stream、状态镜像的 key 需带 `{hash tag}` 保证同槽（否则 `GEOSEARCH`/`XREADGROUP` 跨槽失败）
2. 布隆换 RedisBloom 模块或本地 Guava（集群下不好维护）
3. 分布式锁必须用 Redisson（单机 SETNX 会因主从切换丢锁）
4. 延迟队列的定时任务需选主（`@Scheduled` 会多实例重复执行），改 XXL-Job 或 `SET NX` 抢执行权
5. 本地 Caffeine 二级缓存需要失效广播（Pub/Sub）

---

## 13. 故障降级矩阵

| 故障 | 影响 | 降级 |
|---|---|---|
| Redis 整体不可用 | 缓存/抢单/派单全废 | 开关切"DB 模式"：查库、抢单走 DB 乐观锁、派单走 DB 轮询；接受性能下降，保功能可用 |
| 状态镜像丢失 | Lua 返回 4，抢单全失败 | 巡检从 MySQL 批量重建 `cr:order:status`；抢单接口在 Lua 返回 4 时回查 DB 兜底一次 |
| Stream 消费积压 | 通知/失败记录延迟 | 监控 `XLEN`，超 1000 告警；失败记录改同步写 |
| GEO 数据丢失 | 大厅空 | 心跳重建（骑手端 30s 上报 + 服务端批量回填） |
| 缓存与 DB 不一致 | 展示错 | `ConsistencyCheckTask` 每分钟对比 TOP 50 活跃订单，不一致删缓存 |
| 布隆丢失 | 穿透压力 | 启动/巡检重建；重建期间直接放行 |

---

## 14. 变更记录

| 版本 | 日期 | 变更 |
|---|---|---|
| v1.0 | 2026-11-17 | 22 个 key 初版 |
| v1.2 | 2026-11-17 | ① key 22→32（补状态镜像、draft、faq、budget、chat 锁、raise/refund 锁、urge、pickup fail、credit daily、idem:event、rank 带日期）；② 删 `cr:order:expire`，逻辑过期只保留 JSON `expire_at`；③ Lua 6→7 步，加同骑手幂等与信用分校验；④ 抢单改同步落库与回滚；⑤ Stream 幂等改 message id + XAUTOCLAIM；⑥ 限流正名为固定窗口；⑦ 补热 key/大 key 治理与 volatile-lru 风险；⑧ 降级矩阵补状态镜像与布隆 |
