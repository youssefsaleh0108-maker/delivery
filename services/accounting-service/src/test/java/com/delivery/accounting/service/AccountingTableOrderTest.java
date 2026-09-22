package com.delivery.accounting.service;

import java.math.BigDecimal;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.verifyNoInteractions;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import com.delivery.accounting.domain.AccountingTransactionRepository;
import com.delivery.accounting.domain.CashFloatRepository;
import com.delivery.accounting.domain.RiderLedgerRepository;
import com.delivery.accounting.event.OrderEventListener;
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * A table order settles to nothing, and this is the test that says why it would not have.
 *
 * <p>A diner sat down in a restaurant, scanned the code on the table, chose from the shop's own
 * menu and sent it to the kitchen. They paid the restaurant, at the table, the way they always
 * have. The platform lent the restaurant an order pad — it did not sell the meal, carry it,
 * collect for it or take a cut of it. <strong>There is nothing here for a ledger to record.</strong>
 *
 * <p>Without the gate this would not merely settle; it would settle <em>plausibly</em>, which is
 * worse. A table order is {@code CASH}, has no rider and is not carried: that is the exact shape
 * of the pickup branch written for service orders, so it would take the merchant-holder path and
 * write a {@code CASH_COLLECTED} leg against the restaurant for notes the platform never saw, a
 * {@code MERCHANT_CREDIT}, a {@code PLATFORM_COMMISSION} on a meal the platform had no part in, a
 * {@code cash_float} obligation the restaurant would then be chased for, and points on top. Every
 * one of those is a real row somebody would eventually have to explain.
 *
 * <p>The first two tests here are the shape of the rule. The third is the one that matters most:
 * it takes the pickup event that <em>does</em> settle, changes one field, and shows the ledger
 * empty — so this test fails the day the gate is removed, rather than the day somebody reconciles
 * a restaurant's books.
 *
 * <p>{@code AccountingTableOrderDatabaseTest} then asserts the same thing against a real database,
 * counting rows rather than mock interactions, because that is the assertion a careless change
 * cannot argue with.
 */
@ExtendWith(MockitoExtension.class)
@DisplayName("a table order's order.delivered event")
class AccountingTableOrderTest {

    private static final String ORDER = "7f000001-0000-4000-8000-0000000000aa";

    /**
     * Four mezze at a table, as {@code OrderSnapshot} would serialise them.
     *
     * <p>Everything that would tempt settlement is here and true: cash, collected, a merchant, a
     * customer, a total, no rider. The only thing saying otherwise is {@code "kind":"TABLE"}.
     */
    private static final String TABLE_ORDER = """
            {"orderId":"%s","kind":"TABLE","customerId":"table:5e000000-7:9f3a",
             "merchantId":"merchant-1","riderId":null,"deliveryProviderId":null,
             "deliveryProviderAccount":null,"status":"DELIVERED","totalAmount":9.25,
             "subtotal":9.25,"deliveryFee":0,"deliveryTier":"STANDARD","expressSurcharge":0,
             "gift":false,"giftWrapFee":0,"deliveryFeeWaived":false,"merchantFeeWaived":false,
             "carrierFeeWaived":false,"discountAmount":0,"promoCode":null,
             "storeId":"5e000000-0000-4000-8000-000000000001","storeName":"Beirut Grill",
             "checkoutId":null,"paymentMethod":"CASH","paymentStatus":"COLLECTED",
             "deliveryAddress":null,"cancelReason":null,"fulfilment":"DINE_IN","tableLabel":"7",
             "items":[{"productId":"9d000000-0000-4000-8000-000000000001",
                       "productName":"Hummus","unitPrice":1.50,"qty":2,"service":null},
                      {"productId":"9d000000-0000-4000-8000-000000000002",
                       "productName":"Fattoush","unitPrice":2.25,"qty":1,"service":null}],
             "placedAt":"2026-09-22T19:10:00Z","occurredAt":"2026-09-22T19:40:00Z"}
            """.formatted(ORDER);

    /**
     * The same meal, at a shop counter instead: a service order collected and paid there.
     *
     * <p>Identical in every way settlement looks at — cash, collected, no rider, not carried — and
     * it settles, because it should. It is here so that the test below can change one field and
     * show that the field is what decides.
     */
    private static final String PICKUP = TABLE_ORDER
            .replace("\"kind\":\"TABLE\"", "\"kind\":\"SERVICE\"")
            .replace("\"fulfilment\":\"DINE_IN\"", "\"fulfilment\":\"PICKUP\"");

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

    @Test
    @DisplayName("books nothing at all: no leg, no cash float, no rider ledger, no points")
    void booksNothing() {
        listener.onOrderEvent(TABLE_ORDER, "order.delivered", null, "corr-1");

        verifyNoInteractions(transactions, floatEntries, riderLedger, points, riderEarnings,
                postings);
    }

    /**
     * Settling to nothing is the right answer, not a failure.
     *
     * <p>{@code settleDelivered} returning refused would put every table order in
     * {@code SettlementFailureLog} for the Back Office to look at — a queue of things that are
     * exactly as they should be, which is how a queue of real problems stops being read.
     */
    @Test
    @DisplayName("is settled, not refused: nothing went wrong, so nothing is filed as a failure")
    void isNotAFailure() throws Exception {
        OrderEventListener.Outcome outcome = listener.settleDelivered(
                new ObjectMapper().readTree(TABLE_ORDER), "corr-1");

        assertThat(outcome.settled()).isTrue();
        assertThat(outcome.reason()).isNull();
    }

    /**
     * The one field that decides, shown by changing only it.
     *
     * <p>Both payloads are cash, collected, merchant-held and uncarried. The pickup settles to
     * three legs and a float row; the table order settles to nothing. If the gate is ever removed,
     * this is the assertion that goes red — and it goes red pointing at the three legs a
     * restaurant would otherwise have been billed for.
     */
    @Test
    @DisplayName("the same meal at a counter settles: it is the kind, and nothing else, that decides")
    void onlyTheKindDecides() {
        listener.onOrderEvent(PICKUP, "order.delivered", null, "corr-1");
        org.mockito.Mockito.verify(transactions, org.mockito.Mockito.atLeastOnce())
                .saveAll(org.mockito.ArgumentMatchers.anyList());
        org.mockito.Mockito.verify(floatEntries)
                .save(org.mockito.ArgumentMatchers.any());

        org.mockito.Mockito.clearInvocations(transactions, floatEntries);
        listener.onOrderEvent(TABLE_ORDER, "order.delivered", null, "corr-1");
        verifyNoInteractions(transactions, floatEntries);
    }

    /**
     * A cancelled table order books nothing either.
     *
     * <p>Unreachable today — nobody picks a table order up, and a database CHECK in another service
     * forbids the status that would be needed. That is a good reason and it belongs to somebody
     * else, so this service holds the rule on its own terms at every door into it.
     */
    @Test
    @DisplayName("a cancellation compensates nobody, even one that claims it was picked up")
    void compensatesNobodyOnCancellation() {
        String cancelled = TABLE_ORDER
                .replace("\"status\":\"DELIVERED\"", "\"status\":\"CANCELLED\",\"stage\":"
                        + "\"AFTER_PICKUP\",\"compensateMerchant\":true,\"compensateCarrier\":true");

        listener.onOrderEvent(cancelled, "order.cancelled", null, "corr-1");

        verifyNoInteractions(transactions, floatEntries, riderLedger, points);
    }
}
