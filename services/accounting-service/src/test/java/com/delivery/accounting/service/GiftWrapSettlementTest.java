package com.delivery.accounting.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.rabbit.core.RabbitTemplate;

import com.delivery.accounting.domain.AccountingTransaction;
import com.delivery.accounting.domain.AccountingTransaction.Direction;
import com.delivery.accounting.domain.AccountingTransaction.Leg;
import com.delivery.accounting.domain.AccountingTransactionRepository;
import com.delivery.accounting.domain.CashFloatRepository;
import com.delivery.accounting.domain.CounterpartyKind;
import com.delivery.accounting.domain.RiderLedgerRepository;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * A gift's wrapping at settlement: paid to the shop that wrapped it, on a leg of its own, with no
 * commission taken on it.
 *
 * <p>Before this nothing read the event's {@code giftWrapFee}. The fee sat inside the total and
 * outside every credit, so it landed in the platform's residue — posted as commission and reported as
 * "Commission earned" — while the shop that did the wrapping was paid nothing for it, although its
 * receipt lists the wrap inside the order total.
 *
 * <p>Three properties carry it: the shop is paid the wrap in full; the legs still sum to what was
 * collected; and an order with no wrap — an ordinary order, an unwrapped gift, an order carried by
 * the platform's own rider — settles exactly as it always did.
 */
@ExtendWith(MockitoExtension.class)
@DisplayName("a gift's wrapping at settlement")
class GiftWrapSettlementTest {

    private static final String CUSTOMER = "ACC-CUSTOMER";
    private static final String MERCHANT = "ACC-MERCHANT";
    private static final String PLATFORM = "ACC-PLATFORM";
    private static final String SHOP = "merchant-sub-1";
    private static final Instant DELIVERED = Instant.parse("2026-09-01T10:00:00Z");

    /** One of the platform's own riders: the in-house fleet. */
    private static final SettlementService.Rider OWN_RIDER =
            new SettlementService.Rider("rider-1", "ACC-RIDER", null, "customer-1");

    @Mock
    private AccountingTransactionRepository transactions;
    @Mock
    private CashFloatRepository floatEntries;
    @Mock
    private BankPostingPublisher postings;
    @Mock
    private RiderLedgerRepository riderLedger;

    private UUID orderId;

    @BeforeEach
    void setUp() {
        orderId = UUID.randomUUID();
    }

    private SettlementService service() {
        // 12.5% on goods, 10% of the delivery fee — the platform's real rates. BANK, so the legs
        // are asserted as they reach the bank path.
        return new SettlementService(transactions, floatEntries, riderLedger, postings,
                new BigDecimal("12.5"), new BigDecimal("10"), "", PLATFORM, "USD",
                SettlementService.SettlementMode.BANK);
    }

    /**
     * A card order of 45.00 of goods and a 2.50 delivery fee, settled the way the listener settles
     * it.
     *
     * @param total    what the customer paid: goods, delivery and any wrap, less any discount
     * @param wrap     the event's {@code giftWrapFee}; null for an event from before gifting
     * @param discount what a promo code took off, or null
     * @param rider    the platform's own rider who carried it, or null when the event names none
     */
    private List<AccountingTransaction> settle(String total, String wrap, String discount,
                                               SettlementService.Rider rider) {
        return service().settle(orderId, new BigDecimal(total), new BigDecimal("45.00"),
                CUSTOMER, MERCHANT, null, null, "corr-1",
                new SettlementService.Waivers(new BigDecimal("2.50"), false, false, false,
                        discount == null ? null : new BigDecimal(discount)),
                rider, DELIVERED, new SettlementService.Parties(SHOP, null),
                wrap == null ? null : new BigDecimal(wrap));
    }

    private static AccountingTransaction legOf(List<AccountingTransaction> legs, Leg which) {
        return legs.stream().filter(t -> t.getLeg() == which).findFirst().orElse(null);
    }

    private static BigDecimal amountOf(List<AccountingTransaction> legs, Leg which) {
        AccountingTransaction leg = legOf(legs, which);
        return leg == null ? null : leg.getAmount();
    }

    /** Each leg as "LEG amount", in the order written: enough to compare two settlements. */
    private static List<String> shapeOf(List<AccountingTransaction> legs) {
        return legs.stream()
                .map(t -> t.getLeg() + " " + t.getAmount().setScale(2, RoundingMode.HALF_UP))
                .toList();
    }

    /** What was collected plus what the platform paid in, against everything credited out. */
    private static void assertBalances(List<AccountingTransaction> legs, String collected) {
        BigDecimal credited = legs.stream()
                .filter(t -> t.getDirection() == Direction.CREDIT)
                .map(AccountingTransaction::getAmount)
                .reduce(BigDecimal.ZERO, BigDecimal::add);
        BigDecimal subsidy = legs.stream()
                .filter(t -> t.getLeg() == Leg.PLATFORM_SUBSIDY)
                .map(AccountingTransaction::getAmount)
                .reduce(BigDecimal.ZERO, BigDecimal::add);

        assertThat(new BigDecimal(collected).add(subsidy))
                .as("what was collected plus what the platform paid in must equal what went out")
                .isEqualByComparingTo(credited);
    }

    @Nested
    @DisplayName("on a wrapped gift")
    class Wrapped {

        @Test
        @DisplayName("pays the shop its wrapping in full, on a leg of its own")
        void theShopIsPaidTheWrap() {
            // 45.00 of goods + 2.50 delivery + 3.00 wrap.
            List<AccountingTransaction> legs = settle("50.50", "3.00", null, null);

            AccountingTransaction wrap = legOf(legs, Leg.GIFT_WRAP_CREDIT);
            assertThat(wrap).isNotNull();
            assertThat(wrap.getAmount()).isEqualByComparingTo("3.00");
            assertThat(wrap.getDirection()).isEqualTo(Direction.CREDIT);
            assertThat(wrap.getAccountRef()).isEqualTo(MERCHANT);
            assertThat(wrap.getCounterpartyKind()).isEqualTo(CounterpartyKind.MERCHANT);
            assertThat(wrap.getCounterpartyRef()).isEqualTo(SHOP);
            // The goods credit is what it would be with no wrap at all: 45.00 less 5.63.
            assertThat(amountOf(legs, Leg.MERCHANT_CREDIT)).isEqualByComparingTo("39.37");
        }

        @Test
        @DisplayName("takes no commission on it, and never counts it as the platform's")
        void noCommissionOnTheWrap() {
            List<AccountingTransaction> legs = settle("50.50", "3.00", null, null);

            // 5.63 of goods commission plus the 2.50 fee the platform's fleet kept. Not 11.13,
            // which is what it posted while the wrap fell into its residue.
            assertThat(amountOf(legs, Leg.PLATFORM_COMMISSION)).isEqualByComparingTo("8.13");
            assertThat(legOf(legs, Leg.PLATFORM_SUBSIDY)).isNull();
            assertBalances(legs, "50.50");
        }

        @Test
        @DisplayName("leaves the platform's own rider paid exactly as without it")
        void theInHouseRiderIsUnchanged() {
            List<AccountingTransaction> wrapped = settle("50.50", "3.00", null, OWN_RIDER);
            orderId = UUID.randomUUID();
            List<AccountingTransaction> ordinary = settle("47.50", null, null, OWN_RIDER);

            // 2.50 less the 10% cut, either way.
            assertThat(amountOf(wrapped, Leg.RIDER_CREDIT)).isEqualByComparingTo("2.25");
            assertThat(amountOf(ordinary, Leg.RIDER_CREDIT)).isEqualByComparingTo("2.25");
            assertThat(amountOf(wrapped, Leg.PLATFORM_COMMISSION))
                    .isEqualByComparingTo(amountOf(ordinary, Leg.PLATFORM_COMMISSION));
            assertBalances(wrapped, "50.50");
        }

        @Test
        @DisplayName("still pays the wrap when a code is worth all of the goods and the delivery")
        void aCodeNeverTouchesTheWrap() {
            // The code takes 47.50 off, and the customer pays the 3.00 wrap alone.
            List<AccountingTransaction> legs = settle("3.00", "3.00", "47.50", null);

            assertThat(amountOf(legs, Leg.CUSTOMER_DEBIT)).isEqualByComparingTo("3.00");
            assertThat(amountOf(legs, Leg.MERCHANT_CREDIT)).isEqualByComparingTo("39.37");
            assertThat(amountOf(legs, Leg.GIFT_WRAP_CREDIT)).isEqualByComparingTo("3.00");
            // The promotion is the platform's to fund — never out of the shop's wrapping.
            assertThat(amountOf(legs, Leg.PLATFORM_SUBSIDY)).isEqualByComparingTo("39.37");
            assertBalances(legs, "3.00");
        }

        @Test
        @DisplayName("never pays more wrapping than the customer paid at all")
        void aWrapBeyondTheTotalIsClamped() {
            // An inconsistent event: a 3.00 wrap on an order that collected 2.00.
            List<AccountingTransaction> legs = service().settle(orderId, new BigDecimal("2.00"),
                    BigDecimal.ZERO, CUSTOMER, MERCHANT, null, null, "corr-1",
                    new SettlementService.Waivers(BigDecimal.ZERO, false, false, false),
                    null, DELIVERED, new SettlementService.Parties(SHOP, null),
                    new BigDecimal("3.00"));

            assertThat(amountOf(legs, Leg.GIFT_WRAP_CREDIT)).isEqualByComparingTo("2.00");
            assertBalances(legs, "2.00");
        }
    }

    @Nested
    @DisplayName("on everything else")
    class Unchanged {

        @Test
        @DisplayName("an unwrapped gift settles exactly like an ordinary order")
        void anUnwrappedGift() {
            List<AccountingTransaction> gift = settle("47.50", "0.00", null, null);
            orderId = UUID.randomUUID();
            List<AccountingTransaction> ordinary = settle("47.50", null, null, null);

            assertThat(legOf(gift, Leg.GIFT_WRAP_CREDIT)).isNull();
            assertThat(shapeOf(gift)).isEqualTo(shapeOf(ordinary));
        }

        @Test
        @DisplayName("an ordinary order settles through the pre-gift signature exactly as before")
        void anOrdinaryOrder() {
            List<AccountingTransaction> legs = service().settle(orderId, new BigDecimal("47.50"),
                    new BigDecimal("45.00"), CUSTOMER, MERCHANT, null, null, "corr-1",
                    new SettlementService.Waivers(new BigDecimal("2.50"), false, false, false),
                    null, DELIVERED, new SettlementService.Parties(SHOP, null));

            assertThat(shapeOf(legs)).containsExactly(
                    "CUSTOMER_DEBIT 47.50", "MERCHANT_CREDIT 39.37", "PLATFORM_COMMISSION 8.13");
        }
    }

    @Nested
    @DisplayName("at the bank")
    class AtTheBank {

        private AccountingTransaction leg(Leg which, String account, String amount,
                                          Direction direction) {
            return new AccountingTransaction(
                    orderId, which, account, new BigDecimal(amount), "USD", direction, "corr-1");
        }

        @Test
        @DisplayName("is released straight after the shop's goods credit has posted")
        void releasedAfterTheGoods() {
            List<AccountingTransaction> legs = new ArrayList<>(List.of(
                    leg(Leg.CUSTOMER_DEBIT, CUSTOMER, "48.00", Direction.DEBIT),
                    leg(Leg.MERCHANT_CREDIT, MERCHANT, "39.37", Direction.CREDIT),
                    leg(Leg.GIFT_WRAP_CREDIT, MERCHANT, "3.00", Direction.CREDIT),
                    leg(Leg.PLATFORM_COMMISSION, PLATFORM, "5.63", Direction.CREDIT)));
            legs.get(0).markPosted("debit-ref");
            legs.get(1).markPosted("merchant-ref");
            when(transactions.findByOrderIdOrderByCreatedAt(orderId)).thenReturn(legs);

            service().releaseNextLeg(orderId);

            ArgumentCaptor<AccountingTransaction> published =
                    ArgumentCaptor.forClass(AccountingTransaction.class);
            verify(postings).request(published.capture());
            assertThat(published.getValue().getLeg()).isEqualTo(Leg.GIFT_WRAP_CREDIT);
        }

        @Test
        @DisplayName("is described to the bank as gift wrapping, never as commission")
        void narratedAsGiftWrapping() throws Exception {
            RabbitTemplate rabbit = org.mockito.Mockito.mock(RabbitTemplate.class);
            ObjectMapper json = new ObjectMapper();

            new BankPostingPublisher(rabbit, json, "delivery.events")
                    .request(leg(Leg.GIFT_WRAP_CREDIT, MERCHANT, "3.00", Direction.CREDIT));

            ArgumentCaptor<Message> sent = ArgumentCaptor.forClass(Message.class);
            verify(rabbit).send(eq("delivery.events"), eq(BankPostingPublisher.ROUTING_KEY),
                    sent.capture());
            JsonNode command = json.readTree(sent.getValue().getBody());
            assertThat(command.path("narrative").asText())
                    .startsWith("Gift wrapping for order #")
                    .doesNotContainIgnoringCase("commission");
        }
    }
}
