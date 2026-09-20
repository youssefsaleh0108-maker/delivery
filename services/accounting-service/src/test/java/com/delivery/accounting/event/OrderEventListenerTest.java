package com.delivery.accounting.event;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.argThat;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
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

    /**
     * RECON-04: what cannot be settled is acknowledged — a bad message that comes back for ever
     * blocks every good one behind it — and written down first, because an order that settles
     * nowhere leaves no trace in a service whose every view reads legs that exist.
     */
    @Nested
    @DisplayName("a message that will never settle")
    class Recorded {

        private final List<String> recorded = new ArrayList<>();

        private final com.delivery.accounting.service.SettlementFailureLog log =
                (orderId, eventType, reason, payload, correlationId) ->
                        recorded.add(orderId + " " + eventType + ": " + reason);

        private void receive(String payload) {
            new OrderEventListener(settlements, accounts, points, riderEarnings,
                    new ObjectMapper(), log)
                    .onOrderEvent(payload, "order.delivered", null, "corr-1");
        }

        @Test
        @DisplayName("an event naming no shop is recorded against its order")
        void namesNobody() {
            receive("""
                    {"orderId":"%s","customerId":"customer-1","kind":"CATALOG",
                     "status":"DELIVERED","totalAmount":48.00}
                    """.formatted(ORDER));

            assertThat(recorded).singleElement().asString()
                    .contains(ORDER.toString()).contains("order.delivered").contains("no shop");
            verifyNoInteractions(settlements);
        }

        @Test
        @DisplayName("an order delivered but never paid for is recorded with what the payment is")
        void nobodyCollectedTheMoney() {
            receive("""
                    {"orderId":"%s","customerId":"customer-1","merchantId":"merchant-1",
                     "kind":"CATALOG","status":"DELIVERED","totalAmount":48.00,"subtotal":45.00,
                     "paymentMethod":"CARD","paymentStatus":"AUTHORIZATION_PENDING"}
                    """.formatted(ORDER));

            assertThat(recorded).singleElement().asString()
                    .contains("AUTHORIZATION_PENDING").contains("nobody can be paid");
            verifyNoInteractions(settlements);
        }

        @Test
        @DisplayName("a message that is not even JSON is recorded without an order")
        void notEvenJson() {
            receive("{\"orderId\": oops");

            assertThat(recorded).singleElement().asString()
                    .startsWith("null order.delivered: The event could not be read");
        }
    }
}
