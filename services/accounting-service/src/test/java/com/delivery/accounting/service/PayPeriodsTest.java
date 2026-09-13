package com.delivery.accounting.service;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import com.delivery.accounting.domain.CarrierPayPolicy;
import com.delivery.accounting.domain.CarrierPayPolicy.PayCycle;

/**
 * The pay calendar. Every period boundary here decides whose Tuesday lands on which payslip, so the
 * month ends, the leap day and the night the clocks change are each checked, not assumed.
 */
@DisplayName("pay periods")
class PayPeriodsTest {

    private static final ZoneId BEIRUT = ZoneId.of("Asia/Beirut");

    private static LocalDate d(String iso) {
        return LocalDate.parse(iso);
    }

    @Test
    @DisplayName("semi-monthly is the 1st to the 15th and the 16th to the month's real end")
    void semiMonthly() {
        assertThat(PayPeriods.containing(d("2026-10-01"), PayCycle.SEMI_MONTHLY))
                .isEqualTo(new PayPeriods.Period(d("2026-10-01"), d("2026-10-15")));
        assertThat(PayPeriods.containing(d("2026-10-15"), PayCycle.SEMI_MONTHLY).to())
                .isEqualTo(d("2026-10-15"));
        assertThat(PayPeriods.containing(d("2026-10-16"), PayCycle.SEMI_MONTHLY))
                .isEqualTo(new PayPeriods.Period(d("2026-10-16"), d("2026-10-31")));
        assertThat(PayPeriods.containing(d("2027-02-20"), PayCycle.SEMI_MONTHLY).to())
                .isEqualTo(d("2027-02-28"));
        assertThat(PayPeriods.containing(d("2028-02-29"), PayCycle.SEMI_MONTHLY))
                .isEqualTo(new PayPeriods.Period(d("2028-02-16"), d("2028-02-29")));
    }

    @Test
    @DisplayName("monthly is the calendar month, and never longer than attendance answers")
    void monthly() {
        PayPeriods.Period october = PayPeriods.containing(d("2026-10-31"), PayCycle.MONTHLY);
        assertThat(october).isEqualTo(new PayPeriods.Period(d("2026-10-01"), d("2026-10-31")));
        assertThat(october.days()).isEqualTo(31);
        assertThat(PayPeriods.containing(d("2028-02-01"), PayCycle.MONTHLY).days()).isEqualTo(29);
    }

    @Test
    @DisplayName("the 1st starts a period in both calendars and the 16th only in the semi-monthly one")
    void starts() {
        assertThat(PayPeriods.isStart(d("2026-11-01"), PayCycle.MONTHLY)).isTrue();
        assertThat(PayPeriods.isStart(d("2026-11-01"), PayCycle.SEMI_MONTHLY)).isTrue();
        assertThat(PayPeriods.isStart(d("2026-11-16"), PayCycle.SEMI_MONTHLY)).isTrue();
        assertThat(PayPeriods.isStart(d("2026-11-16"), PayCycle.MONTHLY)).isFalse();
        assertThat(PayPeriods.isStart(d("2026-11-02"), PayCycle.SEMI_MONTHLY)).isFalse();
    }

    @Test
    @DisplayName("a period's instants are Beirut midnights, across the night the clocks go back")
    void instantsInTheZone() {
        PayPeriods.Period second = PayPeriods.containing(d("2026-10-20"), PayCycle.SEMI_MONTHLY);

        // Summer time (UTC+3) when it starts; winter time (UTC+2) by the midnight that ends it.
        assertThat(second.startIn(BEIRUT)).isEqualTo(Instant.parse("2026-10-15T21:00:00Z"));
        assertThat(second.endIn(BEIRUT)).isEqualTo(Instant.parse("2026-10-31T22:00:00Z"));
    }

    @Test
    @DisplayName("the rules in force on a day are the latest started by then, the later saved on a tie")
    void rulesInForce() {
        CarrierPayPolicy first = policy("2026-09-01", PayCycle.SEMI_MONTHLY, "2026-08-20T10:00:00Z");
        CarrierPayPolicy retyped = policy("2026-09-01", PayCycle.SEMI_MONTHLY, "2026-08-21T10:00:00Z");
        CarrierPayPolicy monthly = policy("2026-11-01", PayCycle.MONTHLY, "2026-10-02T10:00:00Z");
        List<CarrierPayPolicy> newestFirst = List.of(monthly, retyped, first);

        assertThat(PayPeriods.inForce(newestFirst, d("2026-08-31"))).isEmpty();
        assertThat(PayPeriods.inForce(newestFirst, d("2026-10-31"))).contains(retyped);
        assertThat(PayPeriods.periodOf(newestFirst, d("2026-10-20")))
                .contains(new PayPeriods.Period(d("2026-10-16"), d("2026-10-31")));
        // The change of calendar starts on the 1st, so the two calendars meet without a gap.
        assertThat(PayPeriods.periodOf(newestFirst, d("2026-11-20")))
                .contains(new PayPeriods.Period(d("2026-11-01"), d("2026-11-30")));
    }

    private static CarrierPayPolicy policy(String from, PayCycle cycle, String savedAt) {
        return CarrierPayPolicy.version("provider-77", d(from),
                new CarrierPayPolicy.Terms(cycle, new BigDecimal("2.00"), null, true,
                        new BigDecimal("1.00"), new BigDecimal("0.00"), new BigDecimal("0.00")),
                "USD", "staff", Instant.parse(savedAt));
    }
}
