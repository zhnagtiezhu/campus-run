-- ============================================================
-- campus-run 压测造数（可重复执行）
-- 用途：09 §3.1 场景 A（200 并发抢同一单）
-- 生成：200 个已审核在线骑手（id 1001~1200）+ 20 张 WAITING 订单（id 2001~2020）
-- 清理：脚本开头先删旧压测数据，不影响演示数据（id < 1000 / < 2000）
-- 注意：
--   1) 本脚本只写 MySQL；骑手的 Redis 状态（cr:rider:state / cr:geo:rider）
--      需在压测前调一次登录+上线接口（或用 build/S11 里的批量 warmup 脚本）。
--   2) 抢单压测只对其中 1 张订单发起 200 并发，其余订单用于失败重试与缓冲。
-- ============================================================

USE `campus_run`;
SET NAMES utf8mb4;

-- ---------- 1. 清理旧压测数据 ----------
DELETE FROM `grab_record`      WHERE order_id >= 2001;
DELETE FROM `pay_record`       WHERE order_id >= 2001;
DELETE FROM `order_status_log` WHERE order_id >= 2001;
DELETE FROM `task_order`       WHERE id >= 2001;
DELETE FROM `rider`            WHERE id >= 1001;

-- ---------- 2. 200 个压测骑手 ----------
INSERT INTO `rider`
(`id`, `phone`, `phone_masked`, `phone_hash`, `password`, `real_name`, `id_card_no`, `student_no`,
 `campus_id`, `credit_score`, `online_status`, `active_order_count`, `total_orders`, `audit_status`, `status`)
SELECT
    1000 + n,
    CONCAT('139', LPAD(n, 8, '0')),
    CONCAT('139****', LPAD(n, 4, '0')),
    SHA2(CONCAT('139', LPAD(n, 8, '0')), 256),
    '$2a$10$XAoEiUVVl8qdk..NlS.cnuA5dhmd/sIiTUBnWI820JcYBWNOLNvN.',
    CONCAT('压测骑手', n),
    CONCAT('ENC_PRESSURE_', LPAD(n, 3, '0')),
    CONCAT('P', LPAD(n, 4, '0')),
    1, 100, 1, 0, 0, 1, 1
FROM (
    SELECT ROW_NUMBER() OVER (ORDER BY table_name, column_name) AS n
    FROM information_schema.columns
) t
WHERE t.n <= 200;

-- ---------- 3. 20 张 WAITING 订单 ----------
INSERT INTO `task_order`
(`id`, `order_no`, `user_id`, `rider_id`, `campus_id`, `category`, `title`, `item_desc`, `declared_value`,
 `from_addr`, `from_lng`, `from_lat`, `to_addr`, `to_lng`, `to_lat`, `distance_m`, `weight_kg`,
 `expect_deadline`, `fee`, `urgent_fee`, `night_fee`, `raise_fee`, `urgency_fee`, `total_fee`,
 `pay_status`, `status`, `version`, `dispatch_round`, `dispatch_paused`, `source`, `remark`, `pickup_code`, `idem_key`,
 `created_at`)
SELECT
    2000 + n,
    CONCAT('CR20261117', LPAD(900000 + n, 6, '0')),
    1 + (n % 5),
    NULL,
    1,
    1,
    '压测订单',
    '压测用快递',
    0,
    '菜鸟驿站（东门）', 114.3155000, 30.5932000,
    '5号楼302', 114.3035000, 30.5888000,
    1250, 1.00,
    DATE_ADD(NOW(), INTERVAL 2 HOUR),
    350, 0, 0, 0, 0, 350,
    1, 'WAITING', 0, 1, 0, 0, '压测数据', LPAD(n, 4, '0'),
    CONCAT('pressure-idem-', n),
    NOW()
FROM (
    SELECT ROW_NUMBER() OVER (ORDER BY table_name, column_name) AS n
    FROM information_schema.columns
) t
WHERE t.n <= 20;

-- ---------- 4. 支付记录（订单已支付，状态 WAITING） ----------
INSERT INTO `pay_record` (`pay_no`, `order_id`, `amount`, `channel`, `status`, `paid_at`, `callback_json`)
SELECT CONCAT('MOCKP', LPAD(n, 6, '0')), 2000 + n, 350, 'MOCK', 1, NOW(), JSON_OBJECT('simulated', true)
FROM (
    SELECT ROW_NUMBER() OVER (ORDER BY table_name, column_name) AS n
    FROM information_schema.columns
) t
WHERE t.n <= 20;

-- ---------- 5. 状态流水（每单 DRAFT→WAITING） ----------
INSERT INTO `order_status_log` (`order_id`, `from_status`, `to_status`, `operator_type`, `operator_id`, `trace_id`, `remark`, `created_at`)
SELECT 2000 + n, 'DRAFT', 'WAITING', 'SYSTEM', 0, CONCAT('pressure-o-', n), '压测支付成功', NOW()
FROM (
    SELECT ROW_NUMBER() OVER (ORDER BY table_name, column_name) AS n
    FROM information_schema.columns
) t
WHERE t.n <= 20;

-- ---------- 6. 校验 ----------
SELECT '压测骑手=200' AS check_item,
       IF(COUNT(*) = 200, 'PASS', CONCAT('FAIL(', COUNT(*), ')')) AS result
FROM `rider` WHERE id BETWEEN 1001 AND 1200;

SELECT '压测订单=20' AS check_item,
       IF(COUNT(*) = 20, 'PASS', CONCAT('FAIL(', COUNT(*), ')')) AS result
FROM `task_order` WHERE id BETWEEN 2001 AND 2020;

-- 第一个抢单目标：CR20261117900001（id=2001）
SELECT id, order_no, status FROM `task_order` WHERE id BETWEEN 2001 AND 2003 ORDER BY id;

-- ============================================================
-- 清理（压测结束后执行）：
-- DELETE FROM grab_record      WHERE order_id >= 2001;
-- DELETE FROM pay_record       WHERE order_id >= 2001;
-- DELETE FROM order_status_log WHERE order_id >= 2001;
-- DELETE FROM task_order       WHERE id >= 2001;
-- DELETE FROM rider            WHERE id >= 1001;
-- ============================================================
