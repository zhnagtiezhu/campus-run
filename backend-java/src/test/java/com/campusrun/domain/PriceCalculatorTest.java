package com.campusrun.domain;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;

import java.time.LocalDateTime;

import static org.junit.jupiter.api.Assertions.assertEquals;

/**
 * 计价器验收测试 —— 对应文档 docs/00-项目总览与裁剪决策.md §4.1
 *
 * 【W1 实现契约】本测试锁定 PriceCalculator 的公开签名，实现必须与之一致：
 *
 *   public static FeeDetail calculate(
 *           int distanceM,        // 取送距离（米）
 *           double weightKg,      // 重量（千克）
 *           boolean urgent,       // 是否加急
 *           LocalDateTime orderAt // 下单时间（判定夜间费）
 *   )
 *
 *   public record FeeDetail(int baseFee, int distanceFee, int weightFee,
 *                           int urgentFee, int nightFee, int total, boolean capped)
 *
 * 规则（金额单位一律为分）：
 *   起步价 300，含 ≤1000m 且 ≤2kg
 *   距离：超出 1000m 部分，每满 500m +50（不足 500m 按 500m 计）
 *   重量：超出 2kg 部分，每满 1kg +100（不足 1kg 按 1kg 计）
 *   加急 +200；夜间（21:00–06:00）+100
 *   单笔封顶 2000（触发封顶时 capped=true）
 */
class PriceCalculatorTest {

    private static LocalDateTime day(int hour, int minute) {
        // 2026-11-17 是演示用的基准日期，白天时段
        return LocalDateTime.of(2026, 11, 17, hour, minute);
    }

    @Test
    @DisplayName("起步价内：≤1000m 且 ≤2kg，只收 300 分")
    void baseFeeOnly() {
        FeeDetail d = PriceCalculator.calculate(500, 1.0, false, day(10, 0));
        assertEquals(300, d.baseFee());
        assertEquals(0, d.distanceFee());
        assertEquals(0, d.weightFee());
        assertEquals(0, d.urgentFee());
        assertEquals(0, d.nightFee());
        assertEquals(300, d.total());
    }

    @Test
    @DisplayName("起步价边界：正好 1000m / 2kg 不加价")
    void baseFeeBoundary() {
        FeeDetail d = PriceCalculator.calculate(1000, 2.0, false, day(10, 0));
        assertEquals(300, d.total());
    }

    @ParameterizedTest(name = "距离 {0}m → 距离费 {1} 分")
    @CsvSource({
            // 距离, 期望距离费
            "1001,  50",   // 超 1m，按 500m 计
            "1500,  50",   // 正好一个 500m
            "1501,  100",  // 超一个 500m，进位
            "2000,  100",
            "2500,  150",
            "2501,  200",
            "3000,  200"   // 服务上限
    })
    void distanceFee(int distanceM, int expected) {
        FeeDetail d = PriceCalculator.calculate(distanceM, 1.0, false, day(10, 0));
        assertEquals(expected, d.distanceFee());
        assertEquals(300 + expected, d.total());
    }

    @ParameterizedTest(name = "重量 {0}kg → 重量费 {1} 分")
    @CsvSource({
            "2.0,    0",
            "2.01,   100",  // 超一点，按 1kg 计
            "3.0,    100",
            "3.01,   200",
            "4.5,    300",
            "20.0,   1800"
    })
    void weightFee(double weightKg, int expected) {
        FeeDetail d = PriceCalculator.calculate(800, weightKg, false, day(10, 0));
        assertEquals(expected, d.weightFee());
        assertEquals(300 + expected, d.total());
    }

    @Test
    @DisplayName("距离与重量叠加：2500m + 4kg = 300 + 150 + 200 = 650")
    void distanceAndWeightCombined() {
        FeeDetail d = PriceCalculator.calculate(2500, 4.0, false, day(10, 0));
        assertEquals(650, d.total());
    }

    @Test
    @DisplayName("加急 +200 分")
    void urgentFee() {
        FeeDetail d = PriceCalculator.calculate(800, 1.0, true, day(10, 0));
        assertEquals(200, d.urgentFee());
        assertEquals(500, d.total());
    }

    @ParameterizedTest(name = "下单时间 {0}:{1} → 夜间费 {2} 分")
    @CsvSource({
            // 小时, 分钟, 期望夜间费
            "6,   0,   0",    // 06:00 起不算夜间（左闭右开：夜间为 21:00–05:59）
            "12,  0,   0",
            "20,  59,  0",
            "21,  0,   100",  // 21:00 起算夜间
            "23,  59,  100",
            "0,   30,  100",
            "5,   59,  100"
    })
    void nightFee(int hour, int minute, int expected) {
        FeeDetail d = PriceCalculator.calculate(800, 1.0, false, day(hour, minute));
        assertEquals(expected, d.nightFee());
    }

    @Test
    @DisplayName("加急 + 夜间叠加：800m/1kg = 300 + 200 + 100 = 600")
    void urgentAndNight() {
        FeeDetail d = PriceCalculator.calculate(800, 1.0, true, day(22, 0));
        assertEquals(600, d.total());
    }

    @Test
    @DisplayName("封顶：3000m/20kg/加急/夜间 = 2600 → 2000，且 capped=true")
    void cappedAt2000() {
        FeeDetail d = PriceCalculator.calculate(3000, 20.0, true, day(22, 0));
        assertEquals(2000, d.total());
        assertEquals(true, d.capped());
    }

    @Test
    @DisplayName("封顶不误伤：1200m/3kg/白天 = 300 + 50 + 100 = 450，capped=false")
    void notCapped() {
        FeeDetail d = PriceCalculator.calculate(1200, 3.0, false, day(10, 0));
        assertEquals(450, d.total());
        assertEquals(false, d.capped());
    }

    @Test
    @DisplayName("与演示数据对齐：订单 CR20261117000001 = 1250m / 1kg → 350 分")
    void matchDemoOrder1() {
        assertEquals(350, PriceCalculator.calculate(1250, 1.0, false, day(9, 10)).total());
    }

    @Test
    @DisplayName("与演示数据对齐：订单 CR20261117000002 = 707m + 加价 200 → 基础价 300 分")
    void matchDemoOrder2() {
        FeeDetail d = PriceCalculator.calculate(707, 1.0, false, day(11, 48));
        assertEquals(300, d.total());
        // 加价不进入 fee，只进入 raise_fee/urgency_fee，合计由 OrderService 组装，此处仅断言基础价
    }
}
