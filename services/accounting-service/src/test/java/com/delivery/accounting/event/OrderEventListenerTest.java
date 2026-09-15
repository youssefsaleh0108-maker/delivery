package com.delivery.accounting.event;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.argThat;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.verify;

import java.math.BigDecimal;
import java.util.UUID;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentMatcher;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import com.delivery.accounting.service.AccountDirectory;
import com.delivery.accounting.service.PointsService;
import com.delivery.accounting.service.RiderEarningsService;
import com.delivery.accounting.service.SettlementService;
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * What the listener reads off {@code order.delivered} for a gift's wrapping.
 *
 * <p>The fee is inside {@code totalAmount} and outside {@code subtotal} and {@code deliveryFee}, so
 * a listener that does not pass it on leaves settlement to hand it to the platform as residue —
 * which is what happened before it was read. That the one field reaches
 * {@link SettlementService#settle} is what is pinned here; what settlement does with it is
 * {@code GiftWrapSettlementTest}'s.
 */
@ExtendWith(MockitoExtension.class)
@DisplayName("an order.delivered event and a gift's wrapping")
class OrderEventListenerTest {

    private static final UUID ORDER = UUID.fromString("7f000001-0000-4000-8000-000000000001");

    @Mock
    private SettlementService settlements;
    @Mock
    private AccountDirectory accounts;
    @Mock
    private PointsService points;
    @Mock
    private RiderEarningsService riderEarnings;

    /** A card basket delivered and captured: 45.00 of goods, and whatever [gift] adds. */
    private void deliver(String gift) {
        String payload = """
                {"orderId":"%s","customerId":"customer-1","merchantId":"merchant-1",
                 "kind":"CATALOG","status":"DELIVERED","totalAmount":48.00,"subtotal":45.00,
                 "deliveryFee":0.00,"paymentMethod":"CARD","paymentStatus":"CAPTURED"%s}
                """.formatted(ORDER, gift);
        new OrderEventListener(settlements, accounts, points, riderEarnings, new ObjectMapper())
                .onOrderEvent(payload, "order.delivered", null, "corr-1");
    }

    private static ArgumentMatcher<BigDecimal> money(String expected) {
        return actual -> actual != null && actual.compareTo(new BigDecimal(expected)) == 0;
    }

    @Test
    @DisplayName("hands the wrap fee to settlement, to be paid to the shop that wrapped it")
    void theWrapFeeReachesSettlement() {
        deliver(",\"gift\":true,\"giftWrapFee\":3.00");

        verify(settlements).settle(eq(ORDER), argThat(money("48.00")), argThat(money("45.00")),
                any(), any(), any(), any(), any(), any(), any(), any(), any(),
                argThat(money("3.00")));
    }

    @Test
    @DisplayName("hands none on an event from before gifting, which settles as it always did")
    void anOlderEventHasNone() {
        deliver("");

        verify(settlements).settle(eq(ORDER), argThat(money("48.00")), argThat(money("45.00")),
                any(), any(), any(), any(), any(), any(), any(), any(), any(), isNull());
    }
}
