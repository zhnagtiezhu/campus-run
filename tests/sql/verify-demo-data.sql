-- ============================================================
-- campus-run 演示数据一致性校验（v1.2 · 38 条断言）
-- 用法：mysql -uroot -p campus_run < verify-demo-data.sql
-- 输出：每条检查一行，result 为 PASS 表示通过
-- 依赖：01-schema.sql（22 表）+ 02-demo-data.sql
-- ============================================================

USE `campus_run`;

-- ------------------------------------------------------------
-- 1. 结构：22 张表
-- ------------------------------------------------------------
SELECT 'C01 表数量=22' AS check_item,
       IF(COUNT(*) = 22, 'PASS', CONCAT('FAIL(', COUNT(*), ')')) AS result
FROM information_schema.tables
WHERE table_schema = 'campus_run' AND table_name IN (
    'user','rider','admin','campus','address','task_order','order_status_log','grab_record',
    'pay_record','settlement','ticket','ticket_event','review','policy_doc','agent_session',
    'agent_tool_log','dispatch_decision','refund_record','rider_credit_log','agent_message',
    'agent_turn_log','notify_message');

-- ------------------------------------------------------------
-- 2. 数据量
-- ------------------------------------------------------------
SELECT 'C02 学生=5'  AS check_item, IF(COUNT(*) = 5,  'PASS', CONCAT('FAIL(', COUNT(*), ')')) AS result FROM `user`;
SELECT 'C03 骑手=8'  AS check_item, IF(COUNT(*) = 8,  'PASS', CONCAT('FAIL(', COUNT(*), ')')) AS result FROM `rider`;
SELECT 'C04 运营=1'  AS check_item, IF(COUNT(*) = 1,  'PASS', CONCAT('FAIL(', COUNT(*), ')')) AS result FROM `admin`;
SELECT 'C05 订单=7'  AS check_item, IF(COUNT(*) = 7,  'PASS', CONCAT('FAIL(', COUNT(*), ')')) AS result FROM `task_order`;
SELECT 'C06 工单=4'  AS check_item, IF(COUNT(*) = 4,  'PASS', CONCAT('FAIL(', COUNT(*), ')')) AS result FROM `ticket`;
SELECT 'C07 条款=10' AS check_item, IF(COUNT(*) = 10, 'PASS', CONCAT('FAIL(', COUNT(*), ')')) AS result FROM `policy_doc`;

-- 状态覆盖：COMPLETED / WAITING / ACCEPTED / DELIVERED / CANCELLED / EXCEPTION
SELECT 'C08 状态覆盖=6 种' AS check_item,
       IF(COUNT(DISTINCT status) = 6, 'PASS', CONCAT('FAIL(', COUNT(DISTINCT status), ')')) AS result
FROM `task_order`;

-- ------------------------------------------------------------
-- 3. 金额一致性
-- ------------------------------------------------------------
SELECT 'C09 total_fee = fee + urgency_fee' AS check_item,
       IF(COUNT(*) = 0, 'PASS', CONCAT('FAIL(', COUNT(*), ')')) AS result
FROM `task_order` WHERE total_fee <> fee + urgency_fee;

SELECT 'C10 urgency_fee = urgent+night+raise' AS check_item,
       IF(COUNT(*) = 0, 'PASS', CONCAT('FAIL(', COUNT(*), ')')) AS result
FROM `task_order` WHERE urgency_fee <> urgent_fee + night_fee + raise_fee;

SELECT 'C11 支付金额=订单总额' AS check_item,
       IF(COUNT(*) = 0, 'PASS', CONCAT('FAIL(', COUNT(*), ')')) AS result
FROM `pay_record` p JOIN `task_order` o ON o.id = p.order_id
WHERE p.amount <> o.total_fee;

SELECT 'C12 已支付订单 pay_status<>0 且有支付记录' AS check_item,
       IF(COUNT(*) = 0, 'PASS', CONCAT('FAIL(', COUNT(*), ')')) AS result
FROM `task_order` o
LEFT JOIN `pay_record` p ON p.order_id = o.id AND p.status IN (1, 3)
WHERE o.pay_status <> 0 AND p.id IS NULL;

-- ------------------------------------------------------------
-- 4. 结算与抽佣
-- ------------------------------------------------------------
SELECT 'C13 已完成订单均有结算单' AS check_item,
       IF(COUNT(*) = 0, 'PASS', CONCAT('FAIL(', COUNT(*), ')')) AS result
FROM `task_order` o LEFT JOIN `settlement` s ON s.order_id = o.id
WHERE o.status = 'COMPLETED' AND s.id IS NULL;

SELECT 'C14 未完成订单无结算单' AS check_item,
       IF(COUNT(*) = 0, 'PASS', CONCAT('FAIL(', COUNT(*), ')')) AS result
FROM `settlement` s JOIN `task_order` o ON o.id = s.order_id
WHERE o.status <> 'COMPLETED';

SELECT 'C15 抽佣=max(floor(10%),30)' AS check_item,
       IF(COUNT(*) = 0, 'PASS', CONCAT('FAIL(', COUNT(*), ')')) AS result
FROM `settlement`
WHERE platform_fee <> GREATEST(FLOOR(order_amount * 0.10), 30)
   OR rider_income <> order_amount - platform_fee;

-- ------------------------------------------------------------
-- 5. 骑手与订单绑定
-- ------------------------------------------------------------
SELECT 'C16 ACCEPTED 及之后必须有骑手' AS check_item,
       IF(COUNT(*) = 0, 'PASS', CONCAT('FAIL(', COUNT(*), ')')) AS result
FROM `task_order`
WHERE status IN ('ACCEPTED','PICKED','DELIVERED','COMPLETED','EXCEPTION') AND rider_id IS NULL;

SELECT 'C17 SUCCESS 记录数=已绑定骑手订单数' AS check_item,
       IF((SELECT COUNT(*) FROM `grab_record` WHERE result = 'SUCCESS')
        = (SELECT COUNT(DISTINCT order_id) FROM `task_order` WHERE rider_id IS NOT NULL),
        'PASS', 'FAIL') AS result;

SELECT 'C18 同一订单只有 1 条 SUCCESS' AS check_item,
       IF(COUNT(*) = 0, 'PASS', CONCAT('FAIL(', COUNT(*), ')')) AS result
FROM (SELECT order_id FROM `grab_record` WHERE result = 'SUCCESS'
      GROUP BY order_id HAVING COUNT(*) > 1) t;

-- ------------------------------------------------------------
-- 6. 时间线与状态流水
-- ------------------------------------------------------------
SELECT 'C19 时间字段顺序合法' AS check_item,
       IF(COUNT(*) = 0, 'PASS', CONCAT('FAIL(', COUNT(*), ')')) AS result
FROM `task_order`
WHERE (accepted_at IS NOT NULL AND accepted_at < created_at)
   OR (picked_at IS NOT NULL AND picked_at < accepted_at)
   OR (delivered_at IS NOT NULL AND delivered_at < picked_at)
   OR (completed_at IS NOT NULL AND completed_at < delivered_at);

SELECT 'C20 每单首条流水为 DRAFT' AS check_item,
       IF(COUNT(*) = 0, 'PASS', CONCAT('FAIL(', COUNT(*), ')')) AS result
FROM (
    SELECT l.order_id, l.from_status
    FROM `order_status_log` l
    JOIN (SELECT order_id, MIN(id) AS min_id FROM `order_status_log` GROUP BY order_id) f
      ON f.order_id = l.order_id AND f.min_id = l.id
) t WHERE t.from_status <> 'DRAFT';

-- ------------------------------------------------------------
-- 7. 工单与 Agent 初判
-- ------------------------------------------------------------
SELECT 'C21 已初判工单引用的条款均存在' AS check_item,
       IF(COUNT(*) = 0, 'PASS', CONCAT('FAIL(', COUNT(*), ')')) AS result
FROM `ticket` t
WHERE t.agent_clauses IS NOT NULL AND JSON_LENGTH(t.agent_clauses) > 0
  AND EXISTS (
      SELECT 1 FROM JSON_TABLE(t.agent_clauses, '$[*]' COLUMNS (clause_no VARCHAR(8) PATH '$')) AS jt
      WHERE NOT EXISTS (SELECT 1 FROM `policy_doc` p WHERE p.clause_no = jt.clause_no AND p.status = 1)
  );

SELECT 'C22 置信度在 0-1' AS check_item,
       IF(COUNT(*) = 0, 'PASS', CONCAT('FAIL(', COUNT(*), ')')) AS result
FROM `ticket` WHERE agent_confidence IS NOT NULL AND (agent_confidence < 0 OR agent_confidence > 1);

SELECT 'C23 REVIEWING/RESOLVED 有 trace_id' AS check_item,
       IF(COUNT(*) = 0, 'PASS', CONCAT('FAIL(', COUNT(*), ')')) AS result
FROM `ticket`
WHERE status IN ('REVIEWING','RESOLVED') AND (agent_trace_id IS NULL OR agent_trace_id = '');

SELECT 'C24 工单事件数与状态匹配' AS check_item,
       IF(COUNT(*) = 0, 'PASS', CONCAT('FAIL(', COUNT(*), ')')) AS result
FROM `ticket` t
WHERE (t.status IN ('REVIEWING','RESOLVED')
        AND (SELECT COUNT(*) FROM `ticket_event` e WHERE e.ticket_id = t.id AND e.action = 'AGENT_ASSESS') <> 1)
   OR (t.status = 'PENDING'
        AND (SELECT COUNT(*) FROM `ticket_event` e WHERE e.ticket_id = t.id AND e.action = 'AGENT_ASSESS') <> 0);

SELECT 'C25 破损工单必须有合法 damage_level' AS check_item,
       IF(COUNT(*) = 0, 'PASS', CONCAT('FAIL(', COUNT(*), ')')) AS result
FROM `ticket`
WHERE type = 2 AND status IN ('REVIEWING','RESOLVED')
  AND (damage_level IS NULL OR damage_level NOT IN ('LIGHT','MEDIUM','SEVERE'));

-- ------------------------------------------------------------
-- 8. 派单决策
-- ------------------------------------------------------------
SELECT 'C26 已执行决策必须有 trace_id' AS check_item,
       IF(COUNT(*) = 0, 'PASS', CONCAT('FAIL(', COUNT(*), ')')) AS result
FROM `dispatch_decision` WHERE applied = 1 AND (trace_id IS NULL OR trace_id = '');

SELECT 'C27 单次加价 ≤300' AS check_item,
       IF(COUNT(*) = 0, 'PASS', CONCAT('FAIL(', COUNT(*), ')')) AS result
FROM `dispatch_decision` WHERE fee_delta > 300 OR fee_delta < 0;

SELECT 'C28 累计加价 ≤500' AS check_item,
       IF(COUNT(*) = 0, 'PASS', CONCAT('FAIL(', COUNT(*), ')')) AS result
FROM `task_order` WHERE raise_fee > 500 OR raise_fee < 0;

-- ------------------------------------------------------------
-- 9. 审计与工具白名单
-- ------------------------------------------------------------
SELECT 'C29 工具审计可按 trace 回放' AS check_item,
       IF(COUNT(*) >= 1, 'PASS', 'FAIL') AS result
FROM `agent_tool_log`
WHERE trace_id = 'a1b2c3d4e5f6' AND session_id = 'ticket_TK20261117000001';

SELECT 'C30 未出现退款类工具调用' AS check_item,
       IF(COUNT(*) = 0, 'PASS', CONCAT('FAIL(', COUNT(*), ')')) AS result
FROM `agent_tool_log` WHERE tool_name IN ('refund_order', 'update_order_status');

SELECT 'C31 工具调用均能 join 到会话' AS check_item,
       IF(COUNT(*) = 0, 'PASS', CONCAT('FAIL(', COUNT(*), ')')) AS result
FROM `agent_tool_log` l LEFT JOIN `agent_session` s ON s.session_id = l.session_id
WHERE s.id IS NULL;

SELECT 'C32 模型调用有模型与 Prompt 版本' AS check_item,
       IF(COUNT(*) = 0, 'PASS', CONCAT('FAIL(', COUNT(*), ')')) AS result
FROM `agent_turn_log` WHERE model = '' OR prompt_version = '';

-- ------------------------------------------------------------
-- 10. 退款/赔付与信用分
-- ------------------------------------------------------------
SELECT 'C33 退款幂等键唯一且金额>0' AS check_item,
       IF((SELECT COUNT(DISTINCT idem_key) = COUNT(*) FROM `refund_record`) AND
          (SELECT COUNT(*) FROM `refund_record` WHERE amount <= 0) = 0,
          'PASS', 'FAIL') AS result;

SELECT 'C34 部分赔付不改支付状态（订单1）' AS check_item,
       IF((SELECT pay_status FROM `task_order` WHERE id = 1) = 1
          AND (SELECT COUNT(*) FROM `refund_record` WHERE order_id = 1 AND type = 'COMPENSATION') = 1,
          'PASS', 'FAIL') AS result;

SELECT 'C35 全额退款订单状态一致（订单6）' AS check_item,
       IF((SELECT pay_status FROM `task_order` WHERE id = 6) = 2
          AND (SELECT status FROM `pay_record` WHERE order_id = 6) = 3
          AND (SELECT COUNT(*) FROM `refund_record` WHERE order_id = 6 AND type = 'ORDER_REFUND') = 1,
          'PASS', 'FAIL') AS result;

-- ------------------------------------------------------------
-- 11. 信用分与在手单
-- ------------------------------------------------------------
SELECT 'C36 信用分快照与流水一致' AS check_item,
       IF(COUNT(*) = 0, 'PASS', CONCAT('FAIL(', COUNT(*), ')')) AS result
FROM `rider` r
JOIN (SELECT rider_id, score_after,
             ROW_NUMBER() OVER (PARTITION BY rider_id ORDER BY id DESC) AS rn
      FROM `rider_credit_log`) l
  ON l.rider_id = r.id AND l.rn = 1
WHERE r.credit_score <> l.score_after;

SELECT 'C37 在手单数快照与实际一致' AS check_item,
       IF(COUNT(*) = 0, 'PASS', CONCAT('FAIL(', COUNT(*), ')')) AS result
FROM `rider` r
LEFT JOIN (
    SELECT rider_id, COUNT(*) AS cnt FROM `task_order`
    WHERE status IN ('ACCEPTED','PICKED','DELIVERED','EXCEPTION') AND rider_id IS NOT NULL
    GROUP BY rider_id
) o ON o.rider_id = r.id
WHERE r.active_order_count <> COALESCE(o.cnt, 0);

-- ------------------------------------------------------------
-- 12. 规则库版本
-- ------------------------------------------------------------
SELECT 'C38 条款版本=1.1 且全生效' AS check_item,
       IF(COUNT(*) = 10, 'PASS', CONCAT('FAIL(', COUNT(*), ')')) AS result
FROM `policy_doc` WHERE version = '1.1' AND status = 1;

-- ------------------------------------------------------------
-- 汇总
-- ------------------------------------------------------------
SELECT '=== 校验结束：以上每行 result 均应为 PASS（共 38 项，C01~C38） ===' AS summary;
