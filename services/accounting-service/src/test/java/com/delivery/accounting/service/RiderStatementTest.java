package com.delivery.accounting.service;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.when;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import com.delivery.accounting.domain.CashFloatRepository;
import com.delivery.accounting.domain.RiderCashOutRepository;
import com.delivery.accounting.domain.RiderLedgerEntry;
import com.delivery.accounting.domain.RiderLedgerEntry.Fleet;
import com.delivery.accounting.domain.RiderLedgerRepository;
import com.delivery.accounting.payout.ManualPayoutProvider;
import com.delivery.accounting.payout.RiderPayoutProviders;

/**
 * The figures on the Earnings screen.
 *
 * <p>What a rider EARNED and what the platform OWES them are different numbers, and this file is
 * mostly about keeping them apart. A cash tip is earned and already in their pocket; a job done for
 * a delivery company is earned and owed by that company. Both belong in a day's total and neither
 * belongs in a balance.
 *
 * <p>The other property here is that a day is a day in the RIDER'S calendar. A drop at 23:40 UTC
 * belongs to a different day depending on where the rider is standing, and a total that moves when
 * the server's timezone does is one nobody can check against their own memory of the shift.
 */
@ExtendWith(MockitoExtension.class)
@DisplayName("what the Earnings screen shows")
class RiderStatementTest {

    private static final String RIDER = "rider-1";
    private static final ZoneId BEIRUT = ZoneId.of("Asia/Beirut");

    @Mock
    private RiderLedgerRepository ledger;
    @Mock
    private RiderCashOutRepository cashOuts;
    @Mock
    private CashFloatRepository floatEntries;

    private RiderEarningsService service;

    @BeforeEach
    void setUp() {
        service = new RiderEarningsService(ledger, cashOuts, floatEntries,
                new RiderPayoutProviders(List.of(new ManualPayoutProvider()), "MANUAL"),
                new BigDecimal("5.00"), new BigDecimal("100.00"), true, "UTC", "USD");
    }

    private RiderLedgerEntry job(String amount, Instant at) {
        return RiderLedgerEntry.jobEarning(RIDER, UUID.randomUUID(), new BigDecimal(amount), "USD",
                Fleet.PLATFORM, null, "customer-1", at);
    }

    private RiderLedgerEntry cashTip(String amount, Instant at) {
        return RiderLedgerEntry.tip(RIDER, UUID.randomUUID(), new BigDecimal(amount), "USD",
                Fleet.PLATFORM, null, true, at);
    }

    private void rowsAre(RiderLedgerEntry... rows) {
        when(ledger.between(anyString(), any(Instant.class), any(Instant.class)))
                .thenReturn(List.of(rows));
    }

    /** Today, in whichever zone the caller asked about, at a time no bucket boundary is near. */
    private Instant todayAt(ZoneId zone, int hour) {
        return LocalDate.now(zone).atTime(hour, 0).atZone(zone).toInstant();
    }

    @Test
    void todays_earnings_and_todays_tips_are_reported_separately() {
        // A rider judging whether a shift was worth doing needs to know how much of it was the
        // platform paying and how much was people being kind. One combined figure hides that.
        rowsAre(job("2.25", todayAt(BEIRUT, 12)),
                job("3.10", todayAt(BEIRUT, 14)),
                cashTip("1.50", todayAt(BEIRUT, 14)));

        RiderEarningsService.Statement statement = service.statement(RIDER, BEIRUT, 7);

        assertThat(statement.today().earnings()).isEqualByComparingTo("5.35");
        assertThat(statement.today().tips()).isEqualByComparingTo("1.50");
        assertThat(statement.today().total()).isEqualByComparingTo("6.85");
        // Two jobs. The tip is not a third one.
        assertThat(statement.today().jobs()).isEqualTo(2);
    }

    @Test
    void the_series_has_a_row_for_every_day_including_the_ones_that_were_days_off() {
        // A series with gaps in it draws a chart that lies about which days the rider was out.
        rowsAre(job("2.25", todayAt(BEIRUT, 12)));

        List<RiderEarningsService.DayTotal> series = service.statement(RIDER, BEIRUT, 7).series();

        assertThat(series).hasSize(7);
        assertThat(series.get(series.size() - 1).day()).isEqualTo(LocalDate.now(BEIRUT));
        assertThat(series).filteredOn(d -> d.total().signum() == 0).hasSize(6);
    }

    @Test
    void a_drop_late_in_the_riders_evening_belongs_to_the_riders_day() {
        // 23:40 in Beirut is already tomorrow in UTC. Bucketing on the server's clock would move
        // this job into a day the rider was not working, and their total would not match what they
        // remember earning.
        Instant lateLocalEvening = LocalDate.now(BEIRUT).atTime(23, 40)
                .atZone(BEIRUT).toInstant();
        rowsAre(job("2.25", lateLocalEvening));

        RiderEarningsService.Statement statement = service.statement(RIDER, BEIRUT, 7);

        assertThat(statement.today().earnings()).isEqualByComparingTo("2.25");
    }

    @Test
    void a_cash_out_moves_the_balance_and_not_a_days_earnings() {
        // Otherwise a rider's Tuesday would show as negative because they took their own money out
        // on it, which is the opposite of what the number means.
        rowsAre(job("2.25", todayAt(BEIRUT, 12)),
                RiderLedgerEntry.cashOutHeld(RIDER, UUID.randomUUID(), new BigDecimal("20.00"),
                        "USD"));

        assertThat(service.statement(RIDER, BEIRUT, 7).today().earnings())
                .isEqualByComparingTo("2.25");
    }

    @Test
    void a_short_series_still_reports_the_whole_week() {
        // A three-day series asked for on a Thursday must not compute "this week" from Tuesday and
        // quietly under-report it. A total that is wrong by an amount depending on the day of the
        // week is the kind nobody reproduces.
        rowsAre(job("2.25", todayAt(BEIRUT, 12)));

        RiderEarningsService.Statement statement = service.statement(RIDER, BEIRUT, 1);

        assertThat(statement.series()).hasSize(1);
        assertThat(statement.thisWeek().earnings()).isEqualByComparingTo("2.25");
    }

    @Test
    void a_cash_tip_counts_as_earned_and_never_as_a_balance() {
        // The rider is already holding the notes. It is in the day's total because they earned it,
        // and out of the balance because paying it out would pay it twice.
        RiderLedgerEntry tip = cashTip("1.50", todayAt(BEIRUT, 14));

        assertThat(tip.isEarning()).isTrue();
        assertThat(tip.isPayableByPlatform()).isFalse();
    }

    @Test
    void a_job_done_for_a_delivery_company_counts_as_earned_and_never_as_a_balance() {
        // The platform paid the company for it. Showing it lets the rider see their work; paying
        // it would pay for one delivery twice.
        RiderLedgerEntry companyJob = RiderLedgerEntry.jobEarning(RIDER, UUID.randomUUID(),
                new BigDecimal("2.25"), "USD", Fleet.CARRIER, "carrier-9", "customer-1",
                Instant.now());

        assertThat(companyJob.isEarning()).isTrue();
        assertThat(companyJob.isPayableByPlatform()).isFalse();
    }
}
