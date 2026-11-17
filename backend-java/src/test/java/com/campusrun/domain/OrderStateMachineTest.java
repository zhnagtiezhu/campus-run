package com.campusrun.domain;

import com.campusrun.common.BizException;
import com.campusrun.domain.OrderStateMachine.OperatorType;
import com.campusrun.domain.OrderStateMachine.OrderStatus;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.Arguments;
import org.junit.jupiter.params.provider.MethodSource;

import java.util.stream.Stream;

import static org.junit.jupiter.api.Assertions.*;

/**
 * 订单状态机验收测试 —— 对应文档 docs/02-数据库设计.md §3.1 / §5（v1.2）
 *
 * 【W1 实现契约】
 *
 *   public final class OrderStateMachine {
 *       public enum OrderStatus { DRAFT, WAITING, ACCEPTED, PICKED, DELIVERED, COMPLETED, EXCEPTION, CANCELLED }
 *       public enum OperatorType { USER, RIDER, ADMIN, AGENT, SYSTEM }
 *
 *       public static boolean canTransit(OrderStatus from, OrderStatus to, OperatorType op);
 *       public static void requireTransit(OrderStatus from, OrderStatus to, OperatorType op)
 *               throws BizException;   // 非法迁移抛 BizException(ErrorCode.ORDER_STATUS_CONFLICT = 40901)
 *       public static boolean isTerminal(OrderStatus status);
 *   }
 *
 * 设计要点（测试即规则）：
 *   1. 只有状态机允许的迁移才能落库，任何"跳状态"都必须在单测里被拦住；
 *   2. 支付回调 DRAFT→WAITING 的操作者是 SYSTEM；
 *   3. 改派/重派：ACCEPTED→WAITING、EXCEPTION→WAITING 仅 ADMIN/AGENT；
 *   4. ACCEPTED/PICKED 的取消只允许 ADMIN；骑手只能异常上报；
 *   5. 同状态 → 同状态 仅 SYSTEM/AGENT 可"记一条事件"（重派、Agent 加价）；
 *   6. COMPLETED / CANCELLED 为终态。
 */
class OrderStateMachineTest {

    static Stream<Arguments> legalTransitions() {
        return Stream.of(
                // 支付回调（SYSTEM）与未支付关闭
                Arguments.of(OrderStatus.DRAFT, OrderStatus.WAITING, OperatorType.SYSTEM),
                Arguments.of(OrderStatus.DRAFT, OrderStatus.CANCELLED, OperatorType.USER),
                Arguments.of(OrderStatus.DRAFT, OrderStatus.CANCELLED, OperatorType.SYSTEM),
                // 抢单 / 用户取消
                Arguments.of(OrderStatus.WAITING, OrderStatus.ACCEPTED, OperatorType.RIDER),
                Arguments.of(OrderStatus.WAITING, OrderStatus.CANCELLED, OperatorType.USER),
                Arguments.of(OrderStatus.WAITING, OrderStatus.CANCELLED, OperatorType.ADMIN),
                // 取件 / 异常 / 改派 / 运营取消
                Arguments.of(OrderStatus.ACCEPTED, OrderStatus.PICKED, OperatorType.RIDER),
                Arguments.of(OrderStatus.ACCEPTED, OrderStatus.EXCEPTION, OperatorType.RIDER),
                Arguments.of(OrderStatus.ACCEPTED, OrderStatus.EXCEPTION, OperatorType.ADMIN),
                Arguments.of(OrderStatus.ACCEPTED, OrderStatus.CANCELLED, OperatorType.ADMIN),
                Arguments.of(OrderStatus.ACCEPTED, OrderStatus.WAITING, OperatorType.ADMIN),
                Arguments.of(OrderStatus.ACCEPTED, OrderStatus.WAITING, OperatorType.AGENT),
                // 送达 / 破损 / 运营取消
                Arguments.of(OrderStatus.PICKED, OrderStatus.DELIVERED, OperatorType.RIDER),
                Arguments.of(OrderStatus.PICKED, OrderStatus.EXCEPTION, OperatorType.RIDER),
                Arguments.of(OrderStatus.PICKED, OrderStatus.EXCEPTION, OperatorType.ADMIN),
                Arguments.of(OrderStatus.PICKED, OrderStatus.CANCELLED, OperatorType.ADMIN),
                // 确认 / 自动确认 / 售后异常
                Arguments.of(OrderStatus.DELIVERED, OrderStatus.COMPLETED, OperatorType.USER),
                Arguments.of(OrderStatus.DELIVERED, OrderStatus.COMPLETED, OperatorType.SYSTEM),
                Arguments.of(OrderStatus.DELIVERED, OrderStatus.EXCEPTION, OperatorType.USER),
                Arguments.of(OrderStatus.DELIVERED, OrderStatus.EXCEPTION, OperatorType.SYSTEM),
                // 异常处理：重派 / 完成 / 取消
                Arguments.of(OrderStatus.EXCEPTION, OrderStatus.WAITING, OperatorType.ADMIN),
                Arguments.of(OrderStatus.EXCEPTION, OrderStatus.WAITING, OperatorType.AGENT),
                Arguments.of(OrderStatus.EXCEPTION, OrderStatus.COMPLETED, OperatorType.ADMIN),
                Arguments.of(OrderStatus.EXCEPTION, OrderStatus.CANCELLED, OperatorType.ADMIN)
        );
    }

    @ParameterizedTest(name = "{0} → {1}（{2}）应允许")
    @MethodSource("legalTransitions")
    void shouldAllow(OrderStatus from, OrderStatus to, OperatorType op) {
        assertTrue(OrderStateMachine.canTransit(from, to, op));
        assertDoesNotThrow(() -> OrderStateMachine.requireTransit(from, to, op));
    }

    static Stream<Arguments> illegalTransitions() {
        return Stream.of(
                // 跳状态
                Arguments.of(OrderStatus.DRAFT, OrderStatus.ACCEPTED, OperatorType.RIDER),
                Arguments.of(OrderStatus.WAITING, OrderStatus.DELIVERED, OperatorType.RIDER),
                Arguments.of(OrderStatus.ACCEPTED, OrderStatus.COMPLETED, OperatorType.USER),
                // 支付回调不能由 USER 触发（v1.1 的错误，已修正）
                Arguments.of(OrderStatus.DRAFT, OrderStatus.WAITING, OperatorType.USER),
                // 越权取消
                Arguments.of(OrderStatus.ACCEPTED, OrderStatus.CANCELLED, OperatorType.RIDER),
                Arguments.of(OrderStatus.ACCEPTED, OrderStatus.CANCELLED, OperatorType.USER),
                Arguments.of(OrderStatus.PICKED, OrderStatus.CANCELLED, OperatorType.RIDER),
                // 改派只能 ADMIN/AGENT
                Arguments.of(OrderStatus.ACCEPTED, OrderStatus.WAITING, OperatorType.RIDER),
                Arguments.of(OrderStatus.ACCEPTED, OrderStatus.WAITING, OperatorType.USER),
                // 跨级/回退
                Arguments.of(OrderStatus.PICKED, OrderStatus.COMPLETED, OperatorType.RIDER),
                Arguments.of(OrderStatus.DELIVERED, OrderStatus.ACCEPTED, OperatorType.RIDER),
                Arguments.of(OrderStatus.DELIVERED, OrderStatus.PICKED, OperatorType.ADMIN),
                // 终态不可再动
                Arguments.of(OrderStatus.COMPLETED, OrderStatus.CANCELLED, OperatorType.ADMIN),
                Arguments.of(OrderStatus.COMPLETED, OrderStatus.EXCEPTION, OperatorType.ADMIN),
                Arguments.of(OrderStatus.CANCELLED, OrderStatus.WAITING, OperatorType.ADMIN),
                Arguments.of(OrderStatus.CANCELLED, OrderStatus.COMPLETED, OperatorType.SYSTEM),
                // 同状态由用户/骑手发起，属于伪造状态变更
                Arguments.of(OrderStatus.WAITING, OrderStatus.WAITING, OperatorType.USER),
                Arguments.of(OrderStatus.PICKED, OrderStatus.PICKED, OperatorType.RIDER)
        );
    }

    @ParameterizedTest(name = "{0} → {1}（{2}）应拒绝")
    @MethodSource("illegalTransitions")
    void shouldReject(OrderStatus from, OrderStatus to, OperatorType op) {
        assertFalse(OrderStateMachine.canTransit(from, to, op));
        BizException ex = assertThrows(BizException.class,
                () -> OrderStateMachine.requireTransit(from, to, op));
        assertEquals(40901, ex.getCode(), "非法迁移必须返回 40901（订单状态不允许该操作）");
    }

    @Test
    @DisplayName("同状态仅允许 SYSTEM / AGENT 记录事件（重派、Agent 加价）")
    void sameStatusOnlyForSystemOrAgent() {
        assertTrue(OrderStateMachine.canTransit(OrderStatus.WAITING, OrderStatus.WAITING, OperatorType.SYSTEM));
        assertTrue(OrderStateMachine.canTransit(OrderStatus.WAITING, OrderStatus.WAITING, OperatorType.AGENT));
        assertFalse(OrderStateMachine.canTransit(OrderStatus.WAITING, OrderStatus.WAITING, OperatorType.USER));
        assertFalse(OrderStateMachine.canTransit(OrderStatus.WAITING, OrderStatus.WAITING, OperatorType.RIDER));
    }

    @Test
    @DisplayName("终态判定：COMPLETED / CANCELLED 不可再迁出")
    void terminalStates() {
        assertTrue(OrderStateMachine.isTerminal(OrderStatus.COMPLETED));
        assertTrue(OrderStateMachine.isTerminal(OrderStatus.CANCELLED));
        assertFalse(OrderStateMachine.isTerminal(OrderStatus.EXCEPTION));
        assertFalse(OrderStateMachine.isTerminal(OrderStatus.DELIVERED));
    }

    @Test
    @DisplayName("主链路顺序：DRAFT → WAITING → ACCEPTED → PICKED → DELIVERED → COMPLETED")
    void happyPath() {
        assertTrue(OrderStateMachine.canTransit(OrderStatus.DRAFT, OrderStatus.WAITING, OperatorType.SYSTEM));
        assertTrue(OrderStateMachine.canTransit(OrderStatus.WAITING, OrderStatus.ACCEPTED, OperatorType.RIDER));
        assertTrue(OrderStateMachine.canTransit(OrderStatus.ACCEPTED, OrderStatus.PICKED, OperatorType.RIDER));
        assertTrue(OrderStateMachine.canTransit(OrderStatus.PICKED, OrderStatus.DELIVERED, OperatorType.RIDER));
        assertTrue(OrderStateMachine.canTransit(OrderStatus.DELIVERED, OrderStatus.COMPLETED, OperatorType.USER));
        assertTrue(OrderStateMachine.canTransit(OrderStatus.DELIVERED, OrderStatus.COMPLETED, OperatorType.SYSTEM));
        assertTrue(OrderStateMachine.isTerminal(OrderStatus.COMPLETED));
    }
}
