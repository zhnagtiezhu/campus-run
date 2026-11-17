package com.campusrun.domain;

import com.campusrun.domain.RefundRuleEngine.DamageLevel;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;

import static org.junit.jupiter.api.Assertions.*;

/**
 * 赔付规则引擎验收测试 —— 对应规则库 P-04 / P-05 / P-06 / P-10
 * （docs/附件/跑腿服务规则库-v1.md）
 *
 * 【W1 实现契约】
 *
 *   public final class RefundRuleEngine {
 *       public enum DamageLevel { LIGHT, MEDIUM, SEVERE }
 *
 *       public static int delayRefund(int totalFee, int delayMinutes);
 *       public static int damageRefund(int totalFee, DamageLevel level);
 *       public static int lostRefund(int declaredValueCent);
 *       public static boolean needsSupervisorApproval(int refundAmount);
 *       public static boolean withinComplaintWindow(long minutesSinceSigned, String ticketType);
 *   }
 *
 * 为什么金额由这个类算而不是模型算：
 *   Agent 只输出"定性 + 引用条款"，金额一律走本引擎复算；模型建议值与复算值
 *   偏差超过 20% 时以复算值为准并标记 review_flag（见 docs/06 §5.1）。
 *   这条约束让"模型幻觉"不可能变成资金损失。
 *
 * 取整约定：一律向下取整（Math.floorDiv），避免多赔。
 */
class RefundRuleEngineTest {

    @ParameterizedTest(name = "订单 {0} 分、超时 {1} 分钟 → 赔付 {2} 分")
    @CsvSource({
            // totalFee, delayMinutes, expected
            "350,  0,    0",
            "350,  15,   0",     // 15 分钟以内（含）不赔
            "350,  16,   70",    // 20%（超出 15 分钟）
            "350,  30,   70",    // 30 分钟（含）仍按 20%
            "350,  31,   175",   // 超过 30 分钟按 50%
            "350,  45,   175",   // 演示工单 TK20261117000001 的场景
            "500,  40,   250",
            "300,  20,   60"
    })
    void delayRefund(int totalFee, int delayMinutes, int expected) {
        assertEquals(expected, RefundRuleEngine.delayRefund(totalFee, delayMinutes));
    }

    @Test
    @DisplayName("超时赔付封顶：50% 且不超过 1000 分（10 元）")
    void delayRefundCap() {
        // 订单封顶 2000 分时，50% = 1000，正好等于上限
        assertEquals(1000, RefundRuleEngine.delayRefund(2000, 60));
        // 极端金额（不应出现，但引擎要兜住）仍不超 1000
        assertEquals(1000, RefundRuleEngine.delayRefund(5000, 60));
    }

    @ParameterizedTest(name = "订单 {0} 分、破损程度 {1} → 赔付 {2} 分")
    @CsvSource({
            "350,  LIGHT,  105",   // 30%
            "350,  MEDIUM, 210",   // 60%
            "350,  SEVERE, 350",   // 100%
            "500,  LIGHT,  150",
            "800,  MEDIUM, 480"
    })
    void damageRefund(int totalFee, String level, int expected) {
        assertEquals(expected, RefundRuleEngine.damageRefund(totalFee, DamageLevel.valueOf(level.trim())));
    }

    @Test
    @DisplayName("破损赔付封顶 20000 分（200 元）")
    void damageRefundCap() {
        assertEquals(20000, RefundRuleEngine.damageRefund(30000, DamageLevel.SEVERE));
    }

    @ParameterizedTest(name = "声明价值 {0} 分 → 丢件赔付 {1} 分")
    @CsvSource({
            "0,      0",
            "5000,   5000",
            "19999,  19999",
            "20000,  20000",
            "25000,  20000"   // 超过 200 元部分因违反 P-02 贵重物品申报限制不予赔付
    })
    void lostRefund(int declaredValue, int expected) {
        assertEquals(expected, RefundRuleEngine.lostRefund(declaredValue));
    }

    @Test
    @DisplayName("高额赔付需主管复核：>1000 分必须为 true（P-10）")
    void supervisorApprovalThreshold() {
        assertFalse(RefundRuleEngine.needsSupervisorApproval(0));
        assertFalse(RefundRuleEngine.needsSupervisorApproval(1000));
        assertTrue(RefundRuleEngine.needsSupervisorApproval(1001));
        assertTrue(RefundRuleEngine.needsSupervisorApproval(20000));
    }

    @Test
    @DisplayName("受理时限：破损必须在签收后 2 小时内提交（P-05）")
    void damageComplaintWindow() {
        assertTrue(RefundRuleEngine.withinComplaintWindow(30, "damage"));
        assertTrue(RefundRuleEngine.withinComplaintWindow(120, "damage"));
        assertFalse(RefundRuleEngine.withinComplaintWindow(121, "damage"));
        assertFalse(RefundRuleEngine.withinComplaintWindow(600, "damage"));
    }

    @Test
    @DisplayName("丢件无 2 小时限制，但需立即提交；超时类以送达时间判定，不受此窗口约束")
    void otherComplaintWindows() {
        assertTrue(RefundRuleEngine.withinComplaintWindow(600, "lost"));
        assertTrue(RefundRuleEngine.withinComplaintWindow(600, "delay"));
    }

    @Test
    @DisplayName("与演示数据对齐：工单 TK20261117000002 破损轻微，350 分订单 → 105 分建议赔付")
    void matchDemoTicket2() {
        assertEquals(105, RefundRuleEngine.damageRefund(350, DamageLevel.LIGHT));
        assertFalse(RefundRuleEngine.needsSupervisorApproval(105));
    }

    @Test
    @DisplayName("与演示数据对齐：工单 TK20261117000001 超时 45 分钟，350 分订单 → 175 分")
    void matchDemoTicket1() {
        assertEquals(175, RefundRuleEngine.delayRefund(350, 45));
        assertFalse(RefundRuleEngine.needsSupervisorApproval(175));
    }
}
