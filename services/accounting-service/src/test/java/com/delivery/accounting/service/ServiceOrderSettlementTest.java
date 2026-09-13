package com.delivery.accounting.service;

import java.math.BigDecimal;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.argThat;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.atLeastOnce;
import static org.mockito.Mockito.clearInvocations;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.ArgumentMatcher;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import com.delivery.accounting.domain.AccountingTransaction;
import com.delivery.accounting.domain.AccountingTransactionRepository;
import com.delivery.accounting.domain.CashFloatEntry;
import com.delivery.accounting.domain.CashFloatRepository;
import com.delivery.accounting.domain.RiderLedgerRepository;
import com.delivery.accounting.event.OrderEventListener;
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * Service orders, from the event Order Manager publishes to the legs they settle to.
 *
 * <p>Order Manager's contract for a service order: kind {@code SERVICE}, fulfilment
 * {@code DELIVERY} or {@code PICKUP}, a {@code service} object on each line, and on a pickup no
 * address, no pins, no rider, no carrier and no fee. Every event published before it carries no
 * fulfilment at all. The real listener runs into the real settlement here, with only the
 * repositories mocked, because what is worth pinning is what reaches the ledger from that exact
 * payload: a pickup's cash is the shop's, a delivered service order is a basket to settlement, and
 * nothing older moved.
 */
@ExtendWith(MockitoExtension.class)
@DisplayName("a service order's order.delivered event")
class ServiceOrderSettlementTest {

    private static final String ORDER = "7f000001-0000-4000-8000-00000000c0de";

    /** A print run collected at the shop and paid there, exactly as OrderSnapshot serialises it. */
    private static final String PICKUP = """
            {"orderId":"%s","kind":"SERVICE","customerId":"customer-1","merchantId":"merchant-1",
             "riderId":null,"deliveryProviderId":null,"deliveryProviderAccount":null,
             "status":"DELIVERED","totalAmount":40.00,"subtotal":40.00,"deliveryFee":0,
             "deliveryTier":"STANDARD","expressSurcharge":0,"gift":false,"giftWrapFee":0,
             "deliveryFeeWaived":false,"merchantFeeWaived":false,"carrierFeeWaived":false,
             "discountAmount":0,"promoCode":null,"storeId":"5e000000-0000-4000-8000-000000000001",
             "storeName":"Hamra Print House","checkoutId":null,"paymentMethod":"CASH",
             "paymentStatus":"COLLECTED","deliveryAddress":null,"cancelReason":null,
             "fulfilment":"PICKUP","serviceCategory":"PRINTING",
             "customerDisplayName":"Jean-Pierre D.","estimatedReadyAt":"2026-09-14T15:00:00Z",
             "items":[{"productId":"9d000000-0000-4000-8000-000000000001",
                       "productName":"Business cards","unitPrice":40.00,"qty":1,
                       "service":{"pricingType":"FIXED","unitLabel":"cards","unitSize":500,
                                  "turnaroundMinHours":24,"turnaroundMaxHours":48,
                                  "attachmentPolicy":"OPTIONAL"}}],
             "placedAt":"2026-09-13T09:00:00Z","occurredAt":"2026-09-14T16:30:00Z"}
            """.formatted(ORDER);

    private static final String GOODS_LINE = """
            [{"productId":"9d000000-0000-4000-8000-000000000002","productName":"Sourdough",
              "unitPrice":40.00,"qty":1,"service":null}]""";

    private static final String SERVICE_LINE = """
            [{"productId":"9d000000-0000-4000-8000-000000000001","productName":"Business cards",
              "unitPrice":40.00,"qty":1,
              "service":{"pricingType":"FIXED","unitLabel":"cards","unitSize":500,
                         "turnaroundMinHours":24,"turnaroundMaxHours":48,
                         "attachmentPolicy":"OPTIONAL"}}]""";

    @Mock
    private AccountingTransactionRepository transactions;
    @Mock
    private CashFloatRepository floatEntries;
    @Mock
    private RiderLedgerRepository riderLedger;
    @Mock
    private BankPostingPublisher postings;
    @Mock
    private AccountDirectory accounts;
    @Mock
    private PointsService points;
    @Mock
    private RiderEarningsService riderEarnings;

    private OrderEventListener listener;

    @BeforeEach
    void wire() {
        SettlementService settlements = new SettlementService(transactions, floatEntries,
                riderLedger, postings, new BigDecimal("12.5"), new BigDecimal("10"), "",
                "ACC-PLATFORM", "USD", SettlementService.SettlementMode.LEDGER_ONLY);
        lenient().when(accounts.forUser(anyString())).thenAnswer(i -> "ACC-" + i.getArgument(0));
        listener = new OrderEventListener(settlements, accounts, points, riderEarnings,
                new ObjectMapper());
    }

    /**
     * 40.00 of goods carried to the door by one of the platform's own riders for a 2.50 fee and
     * paid in cash, with an address and a pin — plus whatever {@code extra} says about kind and
     * fulfilment.
     */
    private static String deliveredToTheDoor(String extra, String items) {
        return """
                {"orderId":"%s","customerId":"customer-1","merchantId":"merchant-1",
                 "riderId":"rider-1","status":"DELIVERED","totalAmount":42.50,"subtotal":40.00,
                 "deliveryFee":2.50,"paymentMethod":"CASH","paymentStatus":"COLLECTED",
                 "deliveryAddress":"Hamra, Beirut","dropoffLat":33.8959,"dropoffLng":35.4787,
                 "occurredAt":"2026-09-14T16:30:00Z","items":%s%s}
                """.formatted(ORDER, items, extra);
    }

    /** The same order with nobody on it, as an event that names no rider arrives. */
    private static String withNoRider(String payload) {
        return payload.replace("\"riderId\":\"rider-1\",", "");
    }

    /**
     * Every leg one event settled to, one readable line each, in the order they were written — so
     * two settlements compare as exactly as the ledger would.
     */
    @SuppressWarnings({"unchecked", "rawtypes"})
    private List<String> settle(String payload) {
        clearInvocations(transactions, floatEntries, riderLedger, points);
        listener.onOrderEvent(payload, "order.delivered", null, "corr-1");

        ArgumentCaptor<List> saved = ArgumentCaptor.forClass(List.class);
        verify(transactions, atLeastOnce()).saveAll(saved.capture());
        return ((List<AccountingTransaction>) saved.getAllValues().get(0)).stream()
                .map(t -> t.getLeg() + " " + Statement.money(t.getAmount()) + " "
                        + t.getDirection() + " " + t.getAccountRef() + " "
                        + t.getCounterpartyKind() + "/" + t.getCounterpartyRef() + " "
                        + t.getStatus())
                .toList();
    }

    private CashFloatEntry floatRowWritten() {
        ArgumentCaptor<CashFloatEntry> saved = ArgumentCaptor.forClass(CashFloatEntry.class);
        verify(floatEntries).save(saved.capture());
        return saved.getValue();
    }

    private static ArgumentMatcher<BigDecimal> money(String expected) {
        return actual -> actual != null && actual.compareTo(new BigDecimal(expected)) == 0;
    }

    @Nested
    @DisplayName("collected at the shop")
    class Pickup {

        @Test
        @DisplayName("pays the shop on its goods at 12.5%, with no carrier or rider leg")
        void settlesLikeABasketWithNobodyCarrying() {
            assertThat(settle(PICKUP)).containsExactly(
                    "CASH_COLLECTED 40.00 DEBIT merchant-1 MERCHANT/merchant-1 SETTLED_IN_CASH",
                    "MERCHANT_CREDIT 35.00 CREDIT ACC-merchant-1 MERCHANT/merchant-1 SETTLED_IN_CASH",
                    "PLATFORM_COMMISSION 5.00 CREDIT ACC-PLATFORM PLATFORM/PLATFORM SETTLED_IN_CASH");
            verifyNoInteractions(riderLedger);
        }

        @Test
        @DisplayName("records the shop, and never the customer, as holding the cash")
        void theShopHoldsTheCash() {
            settle(PICKUP);

            CashFloatEntry row = floatRowWritten();
            assertThat(row.getHolderKind()).isEqualTo(CashFloatEntry.HolderKind.MERCHANT);
            assertThat(row.getHolderRef()).isEqualTo("merchant-1");
            assertThat(row.getAmount()).isEqualByComparingTo("40.00");
            assertThat(row.getCarrierRef()).isNull();
        }

        @Test
        @DisplayName("awards the shop its points and nobody any for a delivery")
        void noDeliveryPoints() {
            settle(PICKUP);

            // No rider, no company and no fee: PointsService pays delivery points to nobody.
            verify(points).awardForDelivery(eq(UUID.fromString(ORDER)), eq("merchant-1"),
                    argThat(money("40.00")), isNull(), isNull(), argThat(money("0")),
                    eq("customer-1"), argThat(money("40.00")));
        }

        @Test
        @DisplayName("reads a null address, no pins and a line's service terms without complaint")
        void theNewShapeParses() {
            // Stripped to the fields settlement reads: the extra ones cannot be what made it pass.
            String bare = """
                    {"orderId":"%s","kind":"SERVICE","customerId":"customer-1",
                     "merchantId":"merchant-1","totalAmount":40.00,"subtotal":40.00,
                     "deliveryFee":0,"paymentMethod":"CASH","paymentStatus":"COLLECTED",
                     "fulfilment":"PICKUP"}
                    """.formatted(ORDER);

            assertThat(settle(PICKUP)).isEqualTo(settle(bare));
        }
    }

    @Nested
    @DisplayName("carried to the door")
    class Delivery {

        @Test
        @DisplayName("settles exactly as a basket from a shop does")
        void identicalToACatalogOrder() {
            List<String> basket = settle(deliveredToTheDoor(
                    ",\"kind\":\"CATALOG\",\"fulfilment\":\"DELIVERY\"", GOODS_LINE));
            List<String> service = settle(deliveredToTheDoor(
                    ",\"kind\":\"SERVICE\",\"fulfilment\":\"DELIVERY\","
                            + "\"serviceCategory\":\"PRINTING\"", SERVICE_LINE));

            assertThat(service).isEqualTo(basket);
            assertThat(floatRowWritten().getHolderKind())
                    .isEqualTo(CashFloatEntry.HolderKind.RIDER);
        }

        @Test
        @DisplayName("naming no rider, is never charged to the shop")
        void aRiderlessDeliveryIsNotAPickup() {
            List<String> legs = settle(withNoRider(deliveredToTheDoor(
                    ",\"kind\":\"SERVICE\",\"fulfilment\":\"DELIVERY\"", SERVICE_LINE)));

            // The old approximation, unchanged: only a pickup makes the shop the holder.
            assertThat(legs).first().asString().startsWith("CUSTOMER_DEBIT 42.50 DEBIT");
            verify(floatEntries, never()).save(any());
        }
    }

    @Nested
    @DisplayName("published before service orders")
    class OlderEvents {

        /** No kind, no fulfilment and no service terms: every basket event before this release. */
        private final String older = deliveredToTheDoor("", """
                [{"productId":"9d000000-0000-4000-8000-000000000002","productName":"Sourdough",
                  "unitPrice":40.00,"qty":1}]""");

        @Test
        @DisplayName("settles to the same legs as it did before fulfilment existed")
        void settlesAsBefore() {
            List<String> legs = settle(older);

            assertThat(legs).containsExactly(
                    "CASH_COLLECTED 42.50 DEBIT rider-1 RIDER/rider-1 SETTLED_IN_CASH",
                    "MERCHANT_CREDIT 35.00 CREDIT ACC-merchant-1 MERCHANT/merchant-1 SETTLED_IN_CASH",
                    "RIDER_CREDIT 2.25 CREDIT ACC-rider-1 RIDER/rider-1 SETTLED_IN_CASH",
                    "PLATFORM_COMMISSION 5.25 CREDIT ACC-PLATFORM PLATFORM/PLATFORM SETTLED_IN_CASH");
            assertThat(legs).isEqualTo(settle(deliveredToTheDoor(
                    ",\"kind\":\"CATALOG\",\"fulfilment\":\"DELIVERY\"", GOODS_LINE)));
        }

        @Test
        @DisplayName("naming no rider, still falls back to the customer rather than the shop")
        void aRiderlessOlderEventIsUnchanged() {
            List<String> legs = settle(withNoRider(older));

            assertThat(legs).first().asString()
                    .isEqualTo("CUSTOMER_DEBIT 42.50 DEBIT ACC-customer-1 null/null SETTLED_IN_CASH");
            verify(floatEntries, never()).save(any());
        }
    }
}
