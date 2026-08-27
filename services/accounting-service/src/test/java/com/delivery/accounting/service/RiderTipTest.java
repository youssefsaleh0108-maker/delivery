package com.delivery.accounting.service;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import com.delivery.accounting.domain.CashFloatRepository;
import com.delivery.accounting.domain.RiderCashOutRepository;
import com.delivery.accounting.domain.RiderLedgerEntry;
import com.delivery.accounting.domain.RiderLedgerEntry.EntryType;
import com.delivery.accounting.domain.RiderLedgerEntry.Fleet;
import com.delivery.accounting.domain.RiderLedgerEntry.PayableBy;
import com.delivery.accounting.domain.RiderLedgerRepository;
import com.delivery.accounting.payout.ManualPayoutProvider;
import com.delivery.accounting.payout.RiderPayoutProviders;

/**
 * Tipping the rider who turned up.
 *
 * <p>The guarantee this file exists for: <strong>a tip is the rider's and the platform takes none
 * of it</strong>. It is not enforced by a rule saying so — it is enforced by there being no path
 * from a tip to the commission arithmetic at all. A tip is never part of an order total, so
 * {@link SettlementService}, which computes every commission this platform charges from that total,
 * cannot see one.
 */
@ExtendWith(MockitoExtension.class)
@DisplayName("a tip belongs to the rider")
class RiderTipTest {

    private static final String CUSTOMER = "customer-1";
    private static final String RIDER = "rider-1";

    @Mock
    private RiderLedgerRepository ledger;
    @Mock
    private RiderCashOutRepository cashOuts;
    @Mock
    private CashFloatRepository floatEntries;

    private RiderEarningsService service;
    private UUID orderId;

    @BeforeEach
    void setUp() {
        orderId = UUID.randomUUID();
        service = new RiderEarningsService(ledger, cashOuts, floatEntries,
                new RiderPayoutProviders(List.of(new ManualPayoutProvider()), "MANUAL"),
                new BigDecimal("5.00"), new BigDecimal("100.00"), true, "UTC", "USD");
    }

    /** The job earning written when the order was delivered, which is what a tip attaches to. */
    private void delivered(Fleet fleet, String carrierRef, String customerRef) {
        when(ledger.findFirstByOrderIdAndEntryType(orderId, EntryType.JOB_EARNING))
                .thenReturn(Optional.of(RiderLedgerEntry.jobEarning(
                        RIDER, orderId, new BigDecimal("2.25"), "USD", fleet, carrierRef,
                        customerRef, Instant.now())));
    }

    private RiderLedgerEntry savedRow() {
        ArgumentCaptor<RiderLedgerEntry> captor = ArgumentCaptor.forClass(RiderLedgerEntry.class);
        verify(ledger).saveAndFlush(captor.capture());
        return captor.getValue();
    }

    @Test
    void the_whole_tip_reaches_the_rider_with_no_commission_taken() {
        delivered(Fleet.PLATFORM, null, CUSTOMER);

        service.tip(orderId, CUSTOMER, new BigDecimal("3.00"), RiderEarningsService.TipMethod.CASH);

        // Three pounds tipped, three pounds recorded. Not 2.63, which is what 12.5% commission on
        // it would leave, and not 2.70, which is what the delivery cut would.
        assertThat(savedRow().getAmount()).isEqualByComparingTo("3.00");
    }

    @Test
    void it_is_recorded_as_a_tip_rather_than_folded_into_what_the_job_paid() {
        // Its own entry type so a statement can separate the platform paying from people being
        // kind — and so no future change to job earnings can ever sweep a tip along with it.
        delivered(Fleet.PLATFORM, null, CUSTOMER);

        service.tip(orderId, CUSTOMER, new BigDecimal("3.00"), RiderEarningsService.TipMethod.CASH);

        assertThat(savedRow().getEntryType()).isEqualTo(EntryType.TIP);
    }

    @Test
    void a_tip_never_reaches_the_settlement_that_decides_commission() {
        // The structural guarantee, stated as a test: tipping touches the rider ledger and nothing
        // else. There is no transaction leg, so there is no order total to take a percentage of.
        delivered(Fleet.PLATFORM, null, CUSTOMER);

        service.tip(orderId, CUSTOMER, new BigDecimal("3.00"), RiderEarningsService.TipMethod.CASH);

        verify(ledger).saveAndFlush(any(RiderLedgerEntry.class));
        org.mockito.Mockito.verifyNoInteractions(cashOuts);
    }

    @Test
    void a_tip_to_a_company_rider_is_still_theirs_and_not_their_employers() {
        // The customer tipped the person who turned up. Routing it through the delivery company
        // would be the platform giving away somebody else's money.
        delivered(Fleet.CARRIER, "carrier-9", CUSTOMER);

        service.tip(orderId, CUSTOMER, new BigDecimal("3.00"), RiderEarningsService.TipMethod.CASH);

        RiderLedgerEntry row = savedRow();
        assertThat(row.getRiderRef()).isEqualTo(RIDER);
        assertThat(row.getEntryType()).isEqualTo(EntryType.TIP);
    }

    @Test
    void notes_handed_over_at_the_door_are_shown_but_never_paid_out_again() {
        // The rider already has them. A balance that offered to pay them would pay them twice.
        delivered(Fleet.PLATFORM, null, CUSTOMER);

        service.tip(orderId, CUSTOMER, new BigDecimal("3.00"), RiderEarningsService.TipMethod.CASH);

        assertThat(savedRow().getPayableBy()).isEqualTo(PayableBy.IN_HAND);
    }

    @Test
    void an_online_tip_is_refused_because_nothing_here_can_charge_a_customer() {
        // The honest failure. Accepting it would credit a rider a balance nobody ever collected,
        // and the platform would pay real money out against it.
        delivered(Fleet.PLATFORM, null, CUSTOMER);

        assertThatThrownBy(() -> service.tip(orderId, CUSTOMER, new BigDecimal("3.00"),
                RiderEarningsService.TipMethod.ONLINE))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("payment processor");

        verify(ledger, never()).saveAndFlush(any());
    }

    @Test
    void somebody_who_did_not_pay_for_the_order_cannot_tip_on_it() {
        // The CUSTOMER role alone would let anybody tip anybody's job — harmless-looking today, and
        // the wrong card charged the moment an online tip is real.
        delivered(Fleet.PLATFORM, null, CUSTOMER);

        assertThatThrownBy(() -> service.tip(orderId, "somebody-else", new BigDecimal("3.00"),
                RiderEarningsService.TipMethod.CASH))
                .isInstanceOf(IllegalArgumentException.class);

        verify(ledger, never()).saveAndFlush(any());
    }

    @Test
    void an_order_nobody_has_delivered_cannot_be_tipped() {
        when(ledger.findFirstByOrderIdAndEntryType(orderId, EntryType.JOB_EARNING))
                .thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.tip(orderId, CUSTOMER, new BigDecimal("3.00"),
                RiderEarningsService.TipMethod.CASH))
                .isInstanceOf(IllegalArgumentException.class);
    }

    @Test
    void a_second_tip_on_one_order_is_refused_by_the_index_rather_than_by_a_read() {
        // Two taps on a phone are the ordinary case, not the exotic one, and a check-then-act would
        // let both through.
        delivered(Fleet.PLATFORM, null, CUSTOMER);
        when(ledger.saveAndFlush(any(RiderLedgerEntry.class)))
                .thenThrow(new org.springframework.dao.DataIntegrityViolationException(
                        "uq_rider_ledger_order_entry"));

        assertThatThrownBy(() -> service.tip(orderId, CUSTOMER, new BigDecimal("3.00"),
                RiderEarningsService.TipMethod.CASH))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("already been tipped");
    }

    @Test
    void a_mistyped_amount_is_refused_rather_than_charged() {
        // The amount arrives from a phone keypad and a misplaced decimal point is the common case.
        delivered(Fleet.PLATFORM, null, CUSTOMER);

        assertThatThrownBy(() -> service.tip(orderId, CUSTOMER, new BigDecimal("300.00"),
                RiderEarningsService.TipMethod.CASH))
                .isInstanceOf(IllegalArgumentException.class);
    }
}
