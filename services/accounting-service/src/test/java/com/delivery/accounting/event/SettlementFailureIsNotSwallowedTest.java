package com.delivery.accounting.event;

import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;

import java.util.UUID;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;
import org.springframework.dao.QueryTimeoutException;

import com.delivery.accounting.service.AccountDirectory;
import com.delivery.accounting.service.PointsService;
import com.delivery.accounting.service.RiderEarningsService;
import com.delivery.accounting.service.SettlementService;
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * RECON-04: a settlement that fails is acknowledged and lost.
 *
 * <p>{@link OrderEventListener#onOrderEvent} catches every exception and returns (lines 249-251), so
 * a database blip while settling an {@code order.delivered} acknowledges the message: the listener's
 * own retry (three attempts) and the {@code accounting.order-events.dlq} never see it, and nothing
 * re-drives it later. The order stays delivered in Order Manager and absent from the ledger — the
 * shop, the carrier and the rider are never credited, and no screen lists it, because every
 * reconciliation view reads only legs that exist.
 *
 * <p>Dev already holds two such orders (9576be97, dcb4f889; delivered 2026-09-08, discounted to
 * 0.00 by a code): refused by the settlement code of the day, acknowledged, never settled since. The
 * shop is still owed 13.11 and the delivery company 4.72 on them.
 *
 * <p>A malformed event is rightly acknowledged — it would loop for ever. A transient failure is not
 * malformed. Fails until one reaches the container's retry and dead-letter queue.
 */
@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
@DisplayName("RECON-04: a settlement that fails on the database is retried, not dropped")
class SettlementFailureIsNotSwallowedTest {

    @Mock
    private SettlementService settlements;
    @Mock
    private AccountDirectory accounts;
    @Mock
    private PointsService points;
    @Mock
    private RiderEarningsService riderEarnings;

    @Test
    @DisplayName("a transient database failure reaches the listener container")
    void aTransientFailureIsRethrown() {
        when(settlements.settle(any(), any(), any(), any(), any(), any(), any(), any(), any(),
                any(), any(), any(), any()))
                .thenThrow(new QueryTimeoutException("canceling statement due to statement timeout"));
        String payload = """
                {"orderId":"%s","customerId":"customer-1","merchantId":"merchant-1",
                 "riderId":"rider-1","kind":"CATALOG","status":"DELIVERED","totalAmount":19.50,
                 "subtotal":19.50,"deliveryFee":0.00,"paymentMethod":"CASH",
                 "paymentStatus":"COLLECTED","fulfilment":"DELIVERY"}
                """.formatted(UUID.randomUUID());
        OrderEventListener listener = new OrderEventListener(settlements, accounts, points,
                riderEarnings, new ObjectMapper());

        assertThatThrownBy(() -> listener.onOrderEvent(payload, "order.delivered", null, "corr-1"))
                .as("the failure must reach the container, which retries and then dead-letters it")
                .isInstanceOf(QueryTimeoutException.class);
    }
}
