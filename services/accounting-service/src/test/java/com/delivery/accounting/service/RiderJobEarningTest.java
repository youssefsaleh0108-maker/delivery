package com.delivery.accounting.service;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import com.delivery.accounting.domain.AccountingTransaction;
import com.delivery.accounting.domain.AccountingTransaction.Leg;
import com.delivery.accounting.domain.AccountingTransactionRepository;
import com.delivery.accounting.domain.CashFloatRepository;
import com.delivery.accounting.domain.RiderLedgerEntry;
import com.delivery.accounting.domain.RiderLedgerEntry.PayableBy;
import com.delivery.accounting.domain.RiderLedgerRepository;

/**
 * What a rider earns for carrying one order.
 *
 * <p>Two properties are worth more than the rest. <strong>The legs still sum to the total</strong>:
 * paying a rider out of the delivery fee is a re-split of money the customer already handed over,
 * not a new charge, so the platform's share has to fall by exactly what the rider's rises by.
 * <strong>And a rider is paid once</strong>: this bus is at-least-once, so a delivered order will
 * arrive twice, and the second copy must move no money at all.
 */
@ExtendWith(MockitoExtension.class)
@DisplayName("what a rider earns for a job")
class RiderJobEarningTest {

    private static final String CUSTOMER = "ACC-CUSTOMER";
    private static final String MERCHANT = "ACC-MERCHANT";
    private static final String PLATFORM = "ACC-PLATFORM";
    private static final String CARRIER_ACCOUNT = "ACC-CARRIER";

    private static final SettlementService.Rider RIDER = new SettlementService.Rider(
            "rider-1", "ACC-RIDER", null, "customer-1");
    private static final SettlementService.Rider COMPANY_RIDER = new SettlementService.Rider(
            "rider-2", "ACC-RIDER-2", "carrier-9", "customer-1");

    @Mock
    private AccountingTransactionRepository transactions;
    @Mock
    private CashFloatRepository floatEntries;
    @Mock
    private RiderLedgerRepository riderLedger;
    @Mock
    private BankPostingPublisher postings;

    private UUID orderId;

    @BeforeEach
    void setUp() {
        orderId = UUID.randomUUID();
    }

    /**
     * @param riderFeeShare blank to mirror the carrier arrangement, which is the shipped default
     */
    private SettlementService serviceWith(String riderFeeShare) {
        return new SettlementService(transactions, floatEntries, riderLedger, postings,
                new BigDecimal("12.5"), new BigDecimal("10"), riderFeeShare, PLATFORM, "USD",
                // LEDGER_ONLY, which is what the platform actually runs: there is no bank, and
                // these cases are about the split rather than about the posting sequence.
                SettlementService.SettlementMode.LEDGER_ONLY);
    }

    /** A 40.00 basket with a 2.50 delivery fee, carried by whoever the caller says. */
    private List<AccountingTransaction> deliver(SettlementService.Rider rider,
                                                String carrierAccount) {
        return serviceWith("").settle(orderId, new BigDecimal("42.50"), new BigDecimal("40.00"),
                CUSTOMER, MERCHANT, carrierAccount, null, "corr-1",
                new SettlementService.Waivers(new BigDecimal("2.50"), false, false, false),
                rider, Instant.parse("2026-08-20T10:00:00Z"));
    }

    private static BigDecimal amountOf(List<AccountingTransaction> legs, Leg which) {
        return legs.stream()
                .filter(t -> t.getLeg() == which)
                .map(AccountingTransaction::getAmount)
                .findFirst()
                .orElse(null);
    }

    private RiderLedgerEntry savedRow() {
        ArgumentCaptor<RiderLedgerEntry> captor = ArgumentCaptor.forClass(RiderLedgerEntry.class);
        verify(riderLedger).saveAndFlush(captor.capture());
        return captor.getValue();
    }

    @Nested
    @DisplayName("a rider on the platform's own fleet")
    class OwnFleet {

        @Test
        void is_paid_out_of_the_delivery_fee_rather_than_the_platform_keeping_all_of_it() {
            List<AccountingTransaction> legs = deliver(RIDER, null);

            // 2.50 fee less the platform's 10% cut of it.
            assertThat(amountOf(legs, Leg.RIDER_CREDIT)).isEqualByComparingTo("2.25");
        }

        @Test
        void earns_exactly_what_an_outside_carrier_would_have_been_paid_for_the_same_job() {
            // The whole justification for the default. The platform has decided what it charges to
            // find a delivery job a rider; nobody has decided that its own riders are worth less,
            // so the unconfigured answer is the one split that HAS been decided, applied again.
            BigDecimal ownFleet = amountOf(deliver(RIDER, null), Leg.RIDER_CREDIT);

            orderId = UUID.randomUUID();
            BigDecimal outsideCarrier =
                    amountOf(deliver(COMPANY_RIDER, CARRIER_ACCOUNT), Leg.PROVIDER_CREDIT);

            assertThat(ownFleet).isEqualByComparingTo(outsideCarrier);
        }

        @Test
        void the_platform_keeps_only_its_commission_and_its_cut_of_the_fee() {
            List<AccountingTransaction> legs = deliver(RIDER, null);

            // 5.00 commission on the goods plus 0.25, the 10% cut of the 2.50 fee. Before riders
            // earned per job this leg was 7.50 — the whole fee stayed with the platform.
            assertThat(amountOf(legs, Leg.PLATFORM_COMMISSION)).isEqualByComparingTo("5.25");
        }

        @Test
        void the_legs_still_sum_to_what_the_customer_paid() {
            // The invariant the whole table rests on. Paying a rider is a re-split of money already
            // collected, so nothing may go missing and nothing may be conjured.
            List<AccountingTransaction> legs = deliver(RIDER, null);

            BigDecimal credited = legs.stream()
                    .filter(t -> t.getLeg() != Leg.CUSTOMER_DEBIT)
                    .map(AccountingTransaction::getAmount)
                    .reduce(BigDecimal.ZERO, BigDecimal::add);

            assertThat(credited).isEqualByComparingTo("42.50");
        }

        @Test
        void the_ledger_row_says_the_platform_owes_it() {
            deliver(RIDER, null);

            RiderLedgerEntry row = savedRow();
            assertThat(row.getRiderRef()).isEqualTo("rider-1");
            assertThat(row.getAmount()).isEqualByComparingTo("2.25");
            assertThat(row.getPayableBy()).isEqualTo(PayableBy.PLATFORM);
            assertThat(row.getFleet()).isEqualTo(RiderLedgerEntry.Fleet.PLATFORM);
        }

        @Test
        void the_row_is_dated_when_the_order_was_delivered_not_when_the_event_arrived() {
            // A slow or redelivered event must not move a day's work into the wrong week.
            deliver(RIDER, null);

            assertThat(savedRow().getEarnedAt()).isEqualTo(Instant.parse("2026-08-20T10:00:00Z"));
        }

        @Test
        void a_configured_share_overrides_the_mirrored_default() {
            serviceWith("60").settle(orderId, new BigDecimal("42.50"), new BigDecimal("40.00"),
                    CUSTOMER, MERCHANT, null, null, "corr-1",
                    new SettlementService.Waivers(new BigDecimal("2.50"), false, false, false),
                    RIDER, null);

            // 60% of the 2.50 fee.
            assertThat(savedRow().getAmount()).isEqualByComparingTo("1.50");
        }
    }

    @Nested
    @DisplayName("a rider employed by a delivery company")
    class CompanyFleet {

        @Test
        void is_not_paid_by_the_platform_a_second_time() {
            // The company was paid through PROVIDER_CREDIT. A RIDER_CREDIT beside it would pay for
            // one delivery twice, which is the mistake this distinction exists to make impossible.
            List<AccountingTransaction> legs = deliver(COMPANY_RIDER, CARRIER_ACCOUNT);

            assertThat(legs).noneMatch(t -> t.getLeg() == Leg.RIDER_CREDIT);
            assertThat(amountOf(legs, Leg.PROVIDER_CREDIT)).isEqualByComparingTo("2.25");
        }

        @Test
        void still_gets_a_row_so_their_own_app_can_show_the_work_they_did() {
            deliver(COMPANY_RIDER, CARRIER_ACCOUNT);

            RiderLedgerEntry row = savedRow();
            assertThat(row.getRiderRef()).isEqualTo("rider-2");
            assertThat(row.getCarrierRef()).isEqualTo("carrier-9");
            assertThat(row.getFleet()).isEqualTo(RiderLedgerEntry.Fleet.CARRIER);
        }

        @Test
        void and_that_row_is_marked_as_the_companys_debt_not_the_platforms() {
            // The one thing that must never be got wrong: this amount is excluded from the balance
            // by construction, so no display bug can turn it into a payout.
            deliver(COMPANY_RIDER, CARRIER_ACCOUNT);

            assertThat(savedRow().getPayableBy()).isEqualTo(PayableBy.CARRIER);
        }
    }

    @Nested
    @DisplayName("redelivery, which this bus guarantees will happen")
    class Redelivery {

        @Test
        void a_second_copy_of_the_event_credits_the_rider_nothing() {
            when(transactions.existsByOrderId(orderId)).thenReturn(true);

            List<AccountingTransaction> legs = deliver(RIDER, null);

            assertThat(legs).isEmpty();
            verifyNoInteractions(riderLedger);
        }

        @Test
        void and_a_duplicate_that_slips_past_that_guard_is_stopped_by_the_index() {
            // The guard above is a check-then-act and the index behind it is what actually
            // guarantees this. Two events processed at once would both pass the check; the
            // constraint fires on the second, and it has to be the no-op it is rather than an
            // error that fails a settlement which has already been written correctly.
            when(riderLedger.saveAndFlush(any(RiderLedgerEntry.class)))
                    .thenThrow(new org.springframework.dao.DataIntegrityViolationException(
                            "uq_rider_ledger_order_entry"));

            assertThatCode(() -> deliver(RIDER, null)).doesNotThrowAnyException();
        }
    }

    @Nested
    @DisplayName("orders that name nobody")
    class NoRider {

        @Test
        void settle_exactly_as_they_did_before_riders_earned_per_job() {
            // Every event published before the Earnings screen existed looks like this. The fee has
            // to stay where it went, because there is no rider in the model to give it to.
            List<AccountingTransaction> legs = deliver(null, null);

            assertThat(legs).noneMatch(t -> t.getLeg() == Leg.RIDER_CREDIT);
            assertThat(amountOf(legs, Leg.PLATFORM_COMMISSION)).isEqualByComparingTo("7.50");
            verify(riderLedger, never()).saveAndFlush(any());
        }
    }

    @Nested
    @DisplayName("an errand, where most of the credit is the rider's own money coming back")
    class Errand {

        @Test
        void the_goods_are_a_reimbursement_and_only_the_fee_counts_as_earned() {
            // A statement that called the whole credit "earnings" would flatter every Butler shift:
            // the rider is made square on the goods, not better off.
            serviceWith("").settleErrand(orderId, new BigDecimal("30.00"), new BigDecimal("25.00"),
                    CUSTOMER, "ACC-RIDER", null, "corr-1", RIDER, null);

            ArgumentCaptor<RiderLedgerEntry> captor =
                    ArgumentCaptor.forClass(RiderLedgerEntry.class);
            verify(riderLedger, org.mockito.Mockito.times(2)).saveAndFlush(captor.capture());

            List<RiderLedgerEntry> rows = captor.getAllValues();
            assertThat(rows)
                    .filteredOn(r -> r.getEntryType() == RiderLedgerEntry.EntryType.REIMBURSEMENT)
                    .singleElement()
                    .satisfies(r -> assertThat(r.getAmount()).isEqualByComparingTo("25.00"));
            // The 5.00 fee less 0.63, which is 12.5% of it rounded half-up. The remaining cent of
            // the rounding stays with the rider, because the errand credit is derived by
            // subtraction from the total rather than computed as its own percentage.
            assertThat(rows)
                    .filteredOn(r -> r.getEntryType() == RiderLedgerEntry.EntryType.JOB_EARNING)
                    .singleElement()
                    .satisfies(r -> assertThat(r.getAmount()).isEqualByComparingTo("4.37"));
        }

        @Test
        void both_rows_are_the_platforms_debt_whoever_the_rider_rides_for() {
            // The rider fronted the money on the PLATFORM's instruction. A delivery company that
            // never saw that transaction cannot be asked to refund it.
            serviceWith("").settleErrand(orderId, new BigDecimal("30.00"), new BigDecimal("25.00"),
                    CUSTOMER, "ACC-RIDER", null, "corr-1", COMPANY_RIDER, null);

            ArgumentCaptor<RiderLedgerEntry> captor =
                    ArgumentCaptor.forClass(RiderLedgerEntry.class);
            verify(riderLedger, org.mockito.Mockito.times(2)).saveAndFlush(captor.capture());

            assertThat(captor.getAllValues()).allMatch(RiderLedgerEntry::isPayableByPlatform);
        }
    }
}
