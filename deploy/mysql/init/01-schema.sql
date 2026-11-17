-- ============================================================
-- campus-run 校园跑腿平台 · 建表脚本
-- 对应文档：docs/02-数据库设计.md（22 张表，v1.2）
-- MySQL 8.0+ / InnoDB / utf8mb4
-- 执行方式：docker compose 启动时由 mysql 容器自动执行
--           或手动：mysql -uroot -p < 01-schema.sql
-- ============================================================

CREATE DATABASE IF NOT EXISTS `campus_run`
    DEFAULT CHARACTER SET utf8mb4
    DEFAULT COLLATE utf8mb4_general_ci;

USE `campus_run`;

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

-- ------------------------------------------------------------
-- 1. user 学生账号
-- ------------------------------------------------------------
CREATE TABLE `user` (
    `id`           bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键',
    `open_id`      varchar(64)     DEFAULT NULL COMMENT '预留小程序标识，H5 登录时为空',
    `phone`        varchar(128)    NOT NULL COMMENT '手机号（AES 加密；dev noop 为明文占位）',
    `phone_masked` varchar(20)     NOT NULL COMMENT '脱敏展示用，如 138****0001',
    `phone_hash`   char(64)        NOT NULL COMMENT '手机号 SHA256，登录等值查询走此列',
    `nickname`     varchar(32)     NOT NULL DEFAULT '' COMMENT '昵称',
    `avatar_url`   varchar(255)    NOT NULL DEFAULT '' COMMENT 'MinIO 私有地址（预签名访问）',
    `credit_score` int             NOT NULL DEFAULT 100 COMMENT '学生信用分（P2 爽约扣分）',
    `status`       tinyint         NOT NULL DEFAULT 1 COMMENT '1 正常 / 0 禁用',
    `created_at`   datetime        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at`   datetime        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    `delete_flag`  tinyint(1)      NOT NULL DEFAULT 0 COMMENT '逻辑删除',
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_user_open_id` (`open_id`),
    UNIQUE KEY `uk_user_phone_hash` (`phone_hash`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT ='学生账号';

-- ------------------------------------------------------------
-- 2. rider 骑手
-- ------------------------------------------------------------
CREATE TABLE `rider` (
    `id`                 bigint unsigned NOT NULL AUTO_INCREMENT,
    `phone`              varchar(128)    NOT NULL COMMENT '手机号（AES 加密）',
    `phone_masked`       varchar(20)     NOT NULL COMMENT '脱敏展示用',
    `phone_hash`         char(64)        NOT NULL COMMENT '手机号 SHA256',
    `password`           varchar(64)     NOT NULL COMMENT 'BCrypt',
    `real_name`          varchar(32)     NOT NULL DEFAULT '' COMMENT '真实姓名，资质审核后填写',
    `id_card_no`         varchar(128)    NOT NULL DEFAULT '' COMMENT '身份证号（AES 加密）',
    `student_no`         varchar(32)     NOT NULL DEFAULT '' COMMENT '学号（P-09 要求加密；dev 明文占位）',
    `campus_id`          bigint unsigned NOT NULL DEFAULT 1,
    `credit_score`       int             NOT NULL DEFAULT 100 COMMENT '信用分；<60 抢单拒绝',
    `online_status`      tinyint         NOT NULL DEFAULT 0 COMMENT '在线状态落库快照，实时以 Redis 为准',
    `active_order_count` int             NOT NULL DEFAULT 0 COMMENT '在手单数落库快照',
    `total_orders`       int             NOT NULL DEFAULT 0 COMMENT '累计完成单',
    `audit_status`       tinyint         NOT NULL DEFAULT 0 COMMENT '0 待审核 / 1 通过 / 2 驳回',
    `status`             tinyint         NOT NULL DEFAULT 1 COMMENT '1 正常 / 0 封禁',
    `created_at`         datetime        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at`         datetime        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    `delete_flag`        tinyint(1)      NOT NULL DEFAULT 0,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_rider_phone_hash` (`phone_hash`),
    KEY `idx_rider_campus` (`campus_id`),
    KEY `idx_rider_audit` (`audit_status`, `status`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT ='骑手';

-- ------------------------------------------------------------
-- 3. admin 运营账号
-- ------------------------------------------------------------
CREATE TABLE `admin` (
    `id`          bigint unsigned NOT NULL AUTO_INCREMENT,
    `username`    varchar(32)     NOT NULL COMMENT '登录名',
    `password`    varchar(64)     NOT NULL COMMENT 'BCrypt',
    `name`        varchar(32)     NOT NULL DEFAULT '' COMMENT '显示名',
    `role`        tinyint         NOT NULL DEFAULT 1 COMMENT '1 客服 / 2 主管（可退超额）',
    `created_at`  datetime        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at`  datetime        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    `delete_flag` tinyint(1)      NOT NULL DEFAULT 0,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_admin_username` (`username`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT ='运营账号';

-- ------------------------------------------------------------
-- 4. campus 校区（单校区，仅 1 条；配置表无 delete_flag）
-- ------------------------------------------------------------
CREATE TABLE `campus` (
    `id`                 bigint unsigned NOT NULL AUTO_INCREMENT,
    `name`               varchar(64)     NOT NULL,
    `center_lng`         decimal(10,7)   NOT NULL COMMENT '中心点经度',
    `center_lat`         decimal(10,7)   NOT NULL COMMENT '中心点纬度',
    `radius_m`           int             NOT NULL DEFAULT 2000 COMMENT '服务半径（米）',
    `open_time`          time            NOT NULL DEFAULT '07:00:00',
    `close_time`         time            NOT NULL DEFAULT '23:00:00',
    `forbidden_keywords` json            DEFAULT NULL COMMENT '禁运关键词数组，P-02 的检索缓存',
    `default_origins`    json            DEFAULT NULL COMMENT '类目默认起点，如 {"1":"菜鸟驿站（东门）","2":"一食堂","3":"打印店（南门）"}',
    `status`             tinyint         NOT NULL DEFAULT 1,
    `created_at`         datetime        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at`         datetime        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT ='校区';

-- ------------------------------------------------------------
-- 5. address 常用地址
-- ------------------------------------------------------------
CREATE TABLE `address` (
    `id`          bigint unsigned NOT NULL AUTO_INCREMENT,
    `user_id`     bigint unsigned NOT NULL,
    `alias`       varchar(32)     NOT NULL COMMENT '如 5号楼302',
    `detail`      varchar(128)    NOT NULL DEFAULT '',
    `lng`         decimal(10,7)   NOT NULL,
    `lat`         decimal(10,7)   NOT NULL,
    `is_default`  tinyint         NOT NULL DEFAULT 0,
    `created_at`  datetime        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at`  datetime        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    `delete_flag` tinyint(1)      NOT NULL DEFAULT 0,
    PRIMARY KEY (`id`),
    KEY `idx_address_user` (`user_id`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT ='常用地址';

-- ------------------------------------------------------------
-- 6. task_order 订单核心表
-- ------------------------------------------------------------
CREATE TABLE `task_order` (
    `id`              bigint unsigned NOT NULL AUTO_INCREMENT,
    `order_no`        varchar(32)     NOT NULL COMMENT 'CR + yyyyMMdd + 6 位序列',
    `user_id`         bigint unsigned NOT NULL,
    `rider_id`        bigint unsigned DEFAULT NULL COMMENT '抢单后写入',
    `campus_id`       bigint unsigned NOT NULL DEFAULT 1,
    `category`        tinyint         NOT NULL COMMENT '1快递 2代买 3打印 4还书 5其他',
    `title`           varchar(64)     NOT NULL DEFAULT '',
    `item_desc`       varchar(255)    NOT NULL DEFAULT '',
    `declared_value`  int             NOT NULL DEFAULT 0 COMMENT '申报价值（分），>50000 拒单；0=未申报',
    `from_addr`       varchar(128)    NOT NULL,
    `from_lng`        decimal(10,7)   NOT NULL,
    `from_lat`        decimal(10,7)   NOT NULL,
    `to_addr`         varchar(128)    NOT NULL,
    `to_lng`          decimal(10,7)   NOT NULL,
    `to_lat`          decimal(10,7)   NOT NULL,
    `distance_m`      int             NOT NULL DEFAULT 0 COMMENT '服务端按坐标算的直线距离',
    `weight_kg`       decimal(5,2)    NOT NULL DEFAULT 1.00,
    `expect_deadline` datetime        NOT NULL,
    `fee`             int             NOT NULL DEFAULT 0 COMMENT 'base+distance+weight（分）',
    `urgent_fee`      int             NOT NULL DEFAULT 0 COMMENT '加急费（分）',
    `night_fee`       int             NOT NULL DEFAULT 0 COMMENT '夜间费（分）',
    `raise_fee`       int             NOT NULL DEFAULT 0 COMMENT '系统/Agent 加价累计（分，≤500）',
    `urgency_fee`     int             NOT NULL DEFAULT 0 COMMENT '冗余：urgent+night+raise',
    `total_fee`       int             NOT NULL DEFAULT 0 COMMENT 'fee + urgency_fee',
    `pay_status`      tinyint         NOT NULL DEFAULT 0 COMMENT '0未支付 1已支付(可含部分退) 2全额退款 3已关闭',
    `status`          varchar(20)     NOT NULL DEFAULT 'DRAFT' COMMENT '见 02 文档状态机',
    `version`         int             NOT NULL DEFAULT 0 COMMENT '乐观锁',
    `dispatch_round`  tinyint         NOT NULL DEFAULT 1 COMMENT '1首轮 2扩圈 3Agent决策',
    `dispatch_paused` tinyint         NOT NULL DEFAULT 0 COMMENT '1=已转人工/终止自动派单',
    `source`          tinyint         NOT NULL DEFAULT 0 COMMENT '0表单 1Agent对话',
    `remark`          varchar(255)    NOT NULL DEFAULT '',
    `pickup_code`     char(4)         NOT NULL DEFAULT '' COMMENT '取件码，仅下单人与接单骑手可见',
    `idem_key`        varchar(64)     DEFAULT NULL COMMENT '下单幂等键（DB 兜底）',
    `accepted_at`     datetime        DEFAULT NULL,
    `picked_at`       datetime        DEFAULT NULL,
    `delivered_at`    datetime        DEFAULT NULL,
    `completed_at`    datetime        DEFAULT NULL,
    `cancelled_at`    datetime        DEFAULT NULL,
    `cancel_reason`   varchar(255)    DEFAULT NULL,
    `created_at`      datetime        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at`      datetime        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    `delete_flag`     tinyint(1)      NOT NULL DEFAULT 0 COMMENT '财务留痕，禁止逻辑删除（保留列兼容）',
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_order_no` (`order_no`),
    UNIQUE KEY `uk_order_idem` (`user_id`, `idem_key`),
    KEY `idx_order_user_status` (`user_id`, `status`),
    KEY `idx_order_rider_status` (`rider_id`, `status`),
    KEY `idx_order_status_deadline` (`status`, `expect_deadline`),
    KEY `idx_order_status_created` (`status`, `created_at`),
    KEY `idx_order_created` (`created_at`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT ='跑腿订单';

-- ------------------------------------------------------------
-- 7. order_status_log 状态流水
-- ------------------------------------------------------------
CREATE TABLE `order_status_log` (
    `id`            bigint unsigned NOT NULL AUTO_INCREMENT,
    `order_id`      bigint unsigned NOT NULL,
    `from_status`   varchar(20)     NOT NULL,
    `to_status`     varchar(20)     NOT NULL,
    `operator_type` varchar(10)     NOT NULL COMMENT 'USER/RIDER/ADMIN/AGENT/SYSTEM',
    `operator_id`   bigint unsigned NOT NULL DEFAULT 0,
    `trace_id`      varchar(36)     NOT NULL DEFAULT '',
    `remark`        varchar(255)    NOT NULL DEFAULT '' COMMENT '同状态事件带动作码，如 RAISE_FEE:100',
    `created_at`    datetime        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_osl_order` (`order_id`),
    KEY `idx_osl_trace` (`trace_id`),
    KEY `idx_osl_created` (`created_at`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT ='订单状态流水';

-- ------------------------------------------------------------
-- 8. grab_record 抢单记录
-- ------------------------------------------------------------
CREATE TABLE `grab_record` (
    `id`             bigint unsigned NOT NULL AUTO_INCREMENT,
    `order_id`       bigint unsigned NOT NULL,
    `rider_id`       bigint unsigned NOT NULL,
    `result`         varchar(16)     NOT NULL COMMENT 'SUCCESS/FAIL_GONE/FAIL_BUSY/FAIL_OFFLINE/FAIL_STATUS/FAIL_CREDIT/FAIL_DUPLICATE',
    `cost_ms`        int             NOT NULL DEFAULT 0 COMMENT '推送至点击耗时',
    `dispatch_round` tinyint         NOT NULL DEFAULT 1,
    `created_at`     datetime        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_grab_order` (`order_id`, `result`),
    KEY `idx_grab_rider` (`rider_id`, `created_at`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT ='抢单记录';

-- ------------------------------------------------------------
-- 9. pay_record 模拟支付（一单一条；部分退款靠 refund_record）
-- ------------------------------------------------------------
CREATE TABLE `pay_record` (
    `id`            bigint unsigned NOT NULL AUTO_INCREMENT,
    `pay_no`        varchar(32)     NOT NULL,
    `order_id`      bigint unsigned NOT NULL,
    `amount`        int             NOT NULL COMMENT '分',
    `channel`       varchar(16)     NOT NULL DEFAULT 'MOCK',
    `status`        tinyint         NOT NULL DEFAULT 0 COMMENT '0待支付 1成功 2失败 3全额已退',
    `paid_at`       datetime        DEFAULT NULL,
    `refunded_at`   datetime        DEFAULT NULL,
    `callback_json` json            DEFAULT NULL,
    `created_at`    datetime        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at`    datetime        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_pay_no` (`pay_no`),
    UNIQUE KEY `uk_pay_order` (`order_id`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT ='支付记录';

-- ------------------------------------------------------------
-- 10. settlement 结算单（财务表，无 delete_flag）
-- ------------------------------------------------------------
CREATE TABLE `settlement` (
    `id`            bigint unsigned NOT NULL AUTO_INCREMENT,
    `order_id`      bigint unsigned NOT NULL,
    `rider_id`      bigint unsigned NOT NULL,
    `order_amount`  int             NOT NULL COMMENT 'total_fee（分）',
    `platform_fee`  int             NOT NULL COMMENT 'max(floor(total*10%),30)',
    `rider_income`  int             NOT NULL COMMENT 'order_amount - platform_fee',
    `status`        tinyint         NOT NULL DEFAULT 0 COMMENT '0待结算 1已结算',
    `settled_at`    datetime        DEFAULT NULL,
    `created_at`    datetime        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_settlement_order` (`order_id`),
    KEY `idx_settlement_rider` (`rider_id`, `settled_at`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT ='结算单';

-- ------------------------------------------------------------
-- 11. ticket 工单
-- ------------------------------------------------------------
CREATE TABLE `ticket` (
    `id`                    bigint unsigned NOT NULL AUTO_INCREMENT,
    `ticket_no`             varchar(32)     NOT NULL,
    `order_id`              bigint unsigned DEFAULT NULL COMMENT '可无订单的纯咨询工单',
    `type`                  tinyint         NOT NULL COMMENT '1超时 2破损 3丢件 4态度 5其他',
    `source`                varchar(10)     NOT NULL DEFAULT 'USER' COMMENT 'USER/RIDER/SYSTEM/AGENT',
    `title`                 varchar(64)     NOT NULL DEFAULT '',
    `description`           varchar(1000)   NOT NULL DEFAULT '',
    `evidence_urls`         json            DEFAULT NULL,
    `evidence_count`        int             NOT NULL DEFAULT 0 COMMENT '凭证数量（Agent 判定用）',
    `signed_at`             datetime        DEFAULT NULL COMMENT '签收时间',
    `within_window`         tinyint         NOT NULL DEFAULT 1 COMMENT 'Java 按 P-05/P-06 预计算',
    `damage_level`          varchar(8)      DEFAULT NULL COMMENT 'LIGHT/MEDIUM/SEVERE',
    `agent_category`        varchar(16)     DEFAULT NULL COMMENT 'delay/damage/lost/attitude/other',
    `agent_liable_party`    varchar(16)     DEFAULT NULL COMMENT 'rider/platform/user/unknown',
    `agent_suggested_refund` int            DEFAULT NULL COMMENT '建议赔付（分）',
    `agent_clauses`         json            DEFAULT NULL COMMENT '引用条款号数组',
    `agent_reply_draft`     text            DEFAULT NULL COMMENT '给用户的话术',
    `agent_confidence`      decimal(3,2)    DEFAULT NULL COMMENT '0.00-1.00',
    `agent_trace_id`        varchar(36)     DEFAULT NULL COMMENT '可回放到工具日志',
    `agent_failed`          tinyint         NOT NULL DEFAULT 0 COMMENT 'Agent 初判失败标记',
    `status`                varchar(16)     NOT NULL DEFAULT 'PENDING' COMMENT 'PENDING/REVIEWING/RESOLVED/REJECTED',
    `handler_id`            bigint unsigned DEFAULT NULL,
    `refund_amount`         int             DEFAULT NULL COMMENT '实际赔付（冗余，权威在 refund_record）',
    `handle_remark`         varchar(255)    DEFAULT NULL,
    `created_at`            datetime        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `resolved_at`           datetime        DEFAULT NULL,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_ticket_no` (`ticket_no`),
    KEY `idx_ticket_order` (`order_id`),
    KEY `idx_ticket_status` (`status`, `created_at`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT ='售后工单';

-- ------------------------------------------------------------
-- 12. ticket_event 工单事件流
-- ------------------------------------------------------------
CREATE TABLE `ticket_event` (
    `id`            bigint unsigned NOT NULL AUTO_INCREMENT,
    `ticket_id`     bigint unsigned NOT NULL,
    `action`        varchar(24)     NOT NULL COMMENT 'CREATE/AGENT_ASSESS/ASSIGN/RESOLVE/REJECT/REFUND',
    `operator_type` varchar(10)     NOT NULL COMMENT 'USER/RIDER/ADMIN/AGENT/SYSTEM',
    `operator_id`   bigint unsigned NOT NULL DEFAULT 0,
    `payload`       json            DEFAULT NULL,
    `created_at`    datetime        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_te_ticket` (`ticket_id`, `created_at`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT ='工单事件流';

-- ------------------------------------------------------------
-- 13. review 评价
-- ------------------------------------------------------------
CREATE TABLE `review` (
    `id`          bigint unsigned NOT NULL AUTO_INCREMENT,
    `order_id`    bigint unsigned NOT NULL,
    `user_id`     bigint unsigned NOT NULL,
    `rider_id`    bigint unsigned NOT NULL,
    `score`       tinyint         NOT NULL COMMENT '1-5',
    `tags`        json            DEFAULT NULL,
    `content`     varchar(500)    NOT NULL DEFAULT '',
    `created_at`  datetime        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at`  datetime        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    `delete_flag` tinyint(1)      NOT NULL DEFAULT 0,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_review_order` (`order_id`),
    KEY `idx_review_rider` (`rider_id`, `created_at`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT ='订单评价';

-- ------------------------------------------------------------
-- 14. policy_doc 规则库源表（唯一事实源）
-- ------------------------------------------------------------
CREATE TABLE `policy_doc` (
    `id`           bigint unsigned NOT NULL AUTO_INCREMENT,
    `doc_code`     varchar(32)     NOT NULL DEFAULT 'CR-POLICY-v1',
    `clause_no`    varchar(8)      NOT NULL COMMENT 'P-01 ~ P-10',
    `title`        varchar(64)     NOT NULL,
    `content`      text            NOT NULL COMMENT '条款原文（RAG 切块单位）',
    `version`      varchar(16)     NOT NULL DEFAULT '1.1',
    `effective_at` datetime        NOT NULL,
    `status`       tinyint         NOT NULL DEFAULT 1 COMMENT '1生效 0停用',
    `created_at`   datetime        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at`   datetime        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_policy_clause` (`doc_code`, `clause_no`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT ='规则库源表（Chroma 只是索引）';

-- ------------------------------------------------------------
-- 15. agent_session 会话
-- ------------------------------------------------------------
CREATE TABLE `agent_session` (
    `id`             bigint unsigned NOT NULL AUTO_INCREMENT,
    `session_id`     varchar(36)     NOT NULL,
    `user_id`        bigint unsigned NOT NULL,
    `ref_type`       varchar(16)     NOT NULL DEFAULT 'CHAT' COMMENT 'CHAT/TICKET',
    `ref_id`         varchar(32)     DEFAULT NULL COMMENT '如 ticket_no',
    `intent`         varchar(24)     NOT NULL DEFAULT '',
    `slots`          json            DEFAULT NULL,
    `turn_count`     int             NOT NULL DEFAULT 0,
    `status`         varchar(16)     NOT NULL DEFAULT 'ACTIVE' COMMENT 'ACTIVE/DONE/ABANDONED',
    `last_active_at` datetime        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `created_at`     datetime        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_session_id` (`session_id`),
    KEY `idx_session_user` (`user_id`, `last_active_at`),
    KEY `idx_session_ref` (`ref_type`, `ref_id`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT ='Agent 会话';

-- ------------------------------------------------------------
-- 16. agent_tool_log 工具调用审计
-- ------------------------------------------------------------
CREATE TABLE `agent_tool_log` (
    `id`          bigint unsigned NOT NULL AUTO_INCREMENT,
    `trace_id`    varchar(36)     NOT NULL DEFAULT '',
    `session_id`  varchar(36)     NOT NULL DEFAULT '',
    `tool_name`   varchar(48)     NOT NULL,
    `args_json`   json            DEFAULT NULL,
    `result_json` json            DEFAULT NULL,
    `success`     tinyint         NOT NULL DEFAULT 1,
    `error_code`  varchar(32)     DEFAULT NULL,
    `latency_ms`  int             NOT NULL DEFAULT 0,
    `token_cost`  int             NOT NULL DEFAULT 0 COMMENT '已废弃，模型 token 见 agent_turn_log',
    `created_at`  datetime        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_atl_trace` (`trace_id`),
    KEY `idx_atl_session` (`session_id`),
    KEY `idx_atl_created` (`created_at`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT ='Agent 工具调用审计';

-- ------------------------------------------------------------
-- 17. dispatch_decision 派单决策留痕
-- ------------------------------------------------------------
CREATE TABLE `dispatch_decision` (
    `id`         bigint unsigned NOT NULL AUTO_INCREMENT,
    `order_id`   bigint unsigned NOT NULL,
    `round`      tinyint         NOT NULL COMMENT '决策发生在第几轮（1/2/3）',
    `action`     varchar(16)     NOT NULL COMMENT 'REASSIGN/RAISE_FEE/ESCALATE_CS',
    `rider_id`   bigint unsigned DEFAULT NULL,
    `fee_delta`  int             NOT NULL DEFAULT 0 COMMENT '分',
    `reason`     varchar(255)    NOT NULL DEFAULT '',
    `confidence` decimal(3,2)    NOT NULL DEFAULT 0.00,
    `applied`    tinyint         NOT NULL DEFAULT 0,
    `trace_id`   varchar(36)     NOT NULL DEFAULT '',
    `created_at` datetime        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_dd_order_round` (`order_id`, `round`),
    KEY `idx_dd_created` (`created_at`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT ='派单决策留痕';

-- ------------------------------------------------------------
-- 18. refund_record 退款/赔付流水（v1.2 新增）
-- ------------------------------------------------------------
CREATE TABLE `refund_record` (
    `id`            bigint unsigned NOT NULL AUTO_INCREMENT,
    `refund_no`     varchar(32)     NOT NULL,
    `order_id`      bigint unsigned NOT NULL,
    `ticket_id`     bigint unsigned DEFAULT NULL COMMENT '赔付时关联工单',
    `settlement_id` bigint unsigned DEFAULT NULL COMMENT '结算后赔付的冲回依据',
    `type`          varchar(16)     NOT NULL COMMENT 'ORDER_REFUND 退单款 / COMPENSATION 平台赔付',
    `amount`        int             NOT NULL COMMENT '分',
    `bear_party`    varchar(16)     NOT NULL DEFAULT 'platform' COMMENT 'platform/rider',
    `status`        tinyint         NOT NULL DEFAULT 0 COMMENT '0待执行 1成功 2失败',
    `idem_key`      varchar(64)     NOT NULL COMMENT '退款幂等键',
    `operator_type` varchar(10)     NOT NULL DEFAULT 'ADMIN',
    `operator_id`   bigint unsigned NOT NULL DEFAULT 0,
    `remark`        varchar(255)    NOT NULL DEFAULT '',
    `created_at`    datetime        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `refunded_at`   datetime        DEFAULT NULL,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_refund_no` (`refund_no`),
    UNIQUE KEY `uk_refund_idem` (`idem_key`),
    KEY `idx_refund_order` (`order_id`, `created_at`),
    KEY `idx_refund_ticket` (`ticket_id`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT ='退款与赔付流水';

-- ------------------------------------------------------------
-- 19. rider_credit_log 信用分变动（v1.2 新增）
-- ------------------------------------------------------------
CREATE TABLE `rider_credit_log` (
    `id`            bigint unsigned NOT NULL AUTO_INCREMENT,
    `rider_id`      bigint unsigned NOT NULL,
    `delta`         int             NOT NULL,
    `score_after`   int             NOT NULL,
    `reason_code`   varchar(32)     NOT NULL COMMENT 'ON_TIME/TIMEOUT/COMPLAINT/ADMIN_ADJUST',
    `ref_type`      varchar(16)     NOT NULL DEFAULT '' COMMENT 'ORDER/TICKET/ADMIN',
    `ref_id`        bigint unsigned DEFAULT NULL,
    `operator_type` varchar(10)     NOT NULL DEFAULT 'SYSTEM',
    `operator_id`   bigint unsigned NOT NULL DEFAULT 0,
    `created_at`    datetime        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_credit_rider` (`rider_id`, `created_at`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT ='骑手信用分变动';

-- ------------------------------------------------------------
-- 20. agent_message 会话消息（v1.2 新增，U-21 数据源）
-- ------------------------------------------------------------
CREATE TABLE `agent_message` (
    `id`         bigint unsigned NOT NULL AUTO_INCREMENT,
    `session_id` varchar(36)     NOT NULL,
    `turn_no`    int             NOT NULL,
    `role`       varchar(16)     NOT NULL COMMENT 'user/assistant/tool',
    `content`    text,
    `tool_calls` json            DEFAULT NULL,
    `created_at` datetime        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_msg_session` (`session_id`, `turn_no`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT ='Agent 会话消息';

-- ------------------------------------------------------------
-- 21. agent_turn_log 模型调用流水（v1.2 新增）
-- ------------------------------------------------------------
CREATE TABLE `agent_turn_log` (
    `id`             bigint unsigned NOT NULL AUTO_INCREMENT,
    `trace_id`       varchar(36)     NOT NULL DEFAULT '',
    `session_id`     varchar(36)     NOT NULL DEFAULT '',
    `agent`          varchar(24)     NOT NULL COMMENT 'order/progress/service/dispatch',
    `model`          varchar(48)     NOT NULL,
    `prompt_version` varchar(16)     NOT NULL DEFAULT '',
    `input_tokens`   int             NOT NULL DEFAULT 0,
    `output_tokens`  int             NOT NULL DEFAULT 0,
    `latency_ms`     int             NOT NULL DEFAULT 0,
    `finish_reason`  varchar(24)     NOT NULL DEFAULT '',
    `created_at`     datetime        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_turn_trace` (`trace_id`),
    KEY `idx_turn_created` (`created_at`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT ='Agent 模型调用流水';

-- ------------------------------------------------------------
-- 22. notify_message 站内消息（v1.2 新增）
-- ------------------------------------------------------------
CREATE TABLE `notify_message` (
    `id`          bigint unsigned NOT NULL AUTO_INCREMENT,
    `to_type`     varchar(10)     NOT NULL COMMENT 'USER/RIDER/ADMIN',
    `to_id`       bigint unsigned NOT NULL,
    `template_id` varchar(32)     NOT NULL DEFAULT '',
    `title`       varchar(64)     NOT NULL DEFAULT '',
    `content`     varchar(500)    NOT NULL DEFAULT '',
    `params`      json            DEFAULT NULL,
    `biz_type`    varchar(16)     NOT NULL DEFAULT '' COMMENT 'ORDER/TICKET/SYSTEM',
    `biz_id`      bigint unsigned DEFAULT NULL,
    `read_flag`   tinyint         NOT NULL DEFAULT 0,
    `created_at`  datetime        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `read_at`     datetime        DEFAULT NULL,
    PRIMARY KEY (`id`),
    KEY `idx_msg_to` (`to_type`, `to_id`, `read_flag`),
    KEY `idx_msg_created` (`created_at`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT ='站内消息';

SET FOREIGN_KEY_CHECKS = 1;

-- ============================================================
-- 表清单核对：22 张
-- 1 user / 2 rider / 3 admin / 4 campus / 5 address / 6 task_order
-- 7 order_status_log / 8 grab_record / 9 pay_record / 10 settlement
-- 11 ticket / 12 ticket_event / 13 review / 14 policy_doc
-- 15 agent_session / 16 agent_tool_log / 17 dispatch_decision
-- 18 refund_record / 19 rider_credit_log / 20 agent_message
-- 21 agent_turn_log / 22 notify_message
-- ============================================================
