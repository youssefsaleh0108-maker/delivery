package com.delivery.accounting.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import com.delivery.accounting.domain.AccountingTransaction;
import com.delivery.accounting.domain.AccountingTransaction.Leg;
import com.delivery.accounting.domain.AccountingTransactionRepository;
import com.delivery.accounting.domain.CashFloatEntry;
import com.delivery.accounting.domain.CashFloatRepository;
import com.delivery.accounting.domain.RiderLedgerEntry;
import com.delivery.accounting.domain.RiderLedgerRepository;

/**
 * An order the platform discounted all the way to zero.
 *
 * <p>A 100%-off code, or a free delivery on a basket the platform is fully subsidising, produces a
 * delivered order whose <em>total</em> is exactly {@code 0.00}. It is still a real order: a shop
 * packed goods and somebody carried them, and both are owed for it.
 *
 * <p>Settlement used to refuse the whole thing on that total — one guard, taken before the discount
 * was added back, returning an empty list and paying nobody. The order delivered, the customer paid
 * nothing by design, and the merchant, the carrier and the rider were all silently unpaid while a
 * {@code WARN} that read like housekeeping was the only trace.
 *
 * <p>The rule this pins is the one the rest of the method already followed: what there is to
 * <em>distribute</em> is the gross, and a leg is posted only when it is worth something.
 */
@ExtendWith(MockitoExtension.class)
@DisplayName("Settling an order discounted to nothing")
class FullyDiscountedSettlementTest {

    private static final String CUSTOMER = "ACC-CUSTOMER";
    private static final String MERCHANT = "ACC-MERCHANT";
    private static final String CARRIER = "ACC-CARRIER";
    private static final String PLATFORM = "ACC-PLATFORM";
    private static final String RIDER_ACCOUNT = "ACC-RIDER";

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
        // LEDGER_ONLY, which is what is deployed: the subject here is which legs get written, not
        // the bank sequencing SettlementServiceTest covers.
        return new SettlementService(transactions, floatEntries, riderLedger, postings,
                new BigDecimal("12.5"), new BigDecimal("10"), "", PLATFORM, "USD",
                SettlementService.SettlementMode.LEDGER_ONLY);
    }

    /**
     * A 34.00 basket with a 4.00 delivery fee and a 38.00 discount: the customer pays nothing.
     *
     * @param carrierAccount the delivery company, or null for one of the platform's own riders
     */
    private List<AccountingTransaction> settleFullyDiscounted(String carrierAccount) {
        when(transactions.existsByOrderId(any())).thenReturn(false);
        return service().settle(orderId, new BigDecimal("0.00"), new BigDecimal("34.00"),
                CUSTOMER, MERCHANT, carrierAccount, null, "corr-zero",
                new SettlementService.Waivers(
                        new BigDecimal("4.00"), true, false, false, new BigDecimal("38.00")),
                new SettlementService.Rider("rider-1", RIDER_ACCOUNT, null, "cust-1"),
                Instant.parse("2026-09-09T10:00:00Z"),
                new SettlementService.Parties("merchant-1", null));
    }

    private static BigDecimal amountOf(List<AccountingTransaction> legs, Leg which) {
        return legs.stream()
                .filter(t -> t.getLeg() == which)
                .map(AccountingTransaction::getAmount)
                .findFirst()
                .orElse(null);
    }

    @Test
    void the_merchant_is_paid_for_the_goods_they_sold() {
        List<AccountingTransaction> legs = settleFullyDiscounted(CARRIER);

        // 34.00 less the platform's 12.5%. The promotion came off what the CUSTOMER paid; the shop
        // sold 34.00 of goods either way and is owed for them.
        assertThat(amountOf(legs, Leg.MERCHANT_CREDIT)).isEqualByComparingTo("29.75");
    }

    @Test
    void the_carrier_is_paid_for_the_delivery_they_made() {
        List<AccountingTransaction> legs = settleFullyDiscounted(CARRIER);

        // 4.00 less the platform's 10% cut, exactly as on an order the customer paid in full.
        assertThat(amountOf(legs, Leg.PROVIDER_CREDIT)).isEqualByComparingTo("3.60");
    }

    @Test
    void a_platform_rider_is_paid_and_their_ledger_row_is_written() {
        List<AccountingTransaction> legs = settleFullyDiscounted(null);

        assertThat(amountOf(legs, Leg.RIDER_CREDIT)).isEqualByComparingTo("3.60");
        // The balance they cash out, not only the ledger leg beside it.
        verify(riderLedger).saveAndFlush(any(RiderLedgerEntry.class));
    }

    @Test
    void the_platform_carries_the_whole_discount_as_a_subsidy() {
        List<AccountingTransaction> legs = settleFullyDiscounted(CARRIER);

        // Nothing came in; 29.75 + 3.60 went out. The platform funded the offer, which is what the
        // subsidy leg is for — and the books balance rather than showing credits from nowhere.
        assertThat(amountOf(legs, Leg.PLATFORM_COMMISSION))
                .as("nothing was kept, so no commission leg is posted")
                .isNull();
        assertThat(amountOf(legs, Leg.PLATFORM_SUBSIDY)).isEqualByComparingTo("33.35");
    }

    @Test
    void nothing_is_collected_from_a_customer_who_paid_nothing() {
        List<AccountingTransaction> legs = settleFullyDiscounted(CARRIER);

        assertThat(amountOf(legs, Leg.CUSTOMER_DEBIT))
                .as("a zero debit would assert a debt the customer does not owe")
                .isNull();
        assertThat(amountOf(legs, Leg.CASH_COLLECTED)).isNull();
        // And nobody is recorded as holding notes they were never handed.
        verify(floatEntries, never()).save(any(CashFloatEntry.class));
    }

    @Test
    void every_posted_leg_is_worth_something() {
        List<AccountingTransaction> legs = settleFullyDiscounted(CARRIER);

        // chk_txn_amount CHECK (amount > 0), in V40. A zero-value leg does not merely look untidy:
        // it fails on insert and takes every other leg in the settlement down with it.
        assertThat(legs).isNotEmpty();
        assertThat(legs).allSatisfy(leg ->
                assertThat(leg.getAmount().signum())
                        .as("leg %s must be worth more than nothing", leg.getLeg())
                        .isPositive());
    }

    @Test
    void a_negative_total_is_still_refused() {
        when(transactions.existsByOrderId(any())).thenReturn(false);

        List<AccountingTransaction> legs = service().settle(
                orderId, new BigDecimal("-5.00"), new BigDecimal("-5.00"),
                CUSTOMER, MERCHANT, CARRIER, null, "corr-negative",
                SettlementService.Waivers.none());

        // Not a promotion — a nonsensical event. Refusing it is still the right answer.
        assertThat(legs).isEmpty();
    }

    @Test
    void an_order_worth_nothing_at_all_is_refused() {
        when(transactions.existsByOrderId(any())).thenReturn(false);

        List<AccountingTransaction> legs = service().settle(
                orderId, BigDecimal.ZERO, BigDecimal.ZERO,
                CUSTOMER, MERCHANT, CARRIER, null, "corr-empty",
                SettlementService.Waivers.none());

        // Zero total and no discount behind it: there is genuinely nothing to distribute, so there
        // is nothing to post. This is the case the original guard was written for.
        assertThat(legs).isEmpty();
    }
}
