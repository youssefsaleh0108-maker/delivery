package com.delivery.tracking.service;

import java.time.LocalDate;

import org.junit.jupiter.api.Test;

import com.delivery.tracking.service.AttendanceService.InvalidRequestException;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * The window an attendance read covers: a month, or up to 31 days, and never an ambiguous mixture.
 */
class AttendancePeriodTest {

    @Test
    void a_month_is_its_first_to_its_last_day() {
        AttendancePeriod feb = AttendancePeriod.parse("2028-02", null, null);

        assertThat(feb.from()).isEqualTo(LocalDate.of(2028, 2, 1));
        assertThat(feb.to()).isEqualTo(LocalDate.of(2028, 2, 29));
        assertThat(feb.dates()).hasSize(29);
    }

    @Test
    void a_range_is_inclusive_and_capped_at_thirty_one_days() {
        assertThat(AttendancePeriod.parse(null, "2026-10-01", "2026-10-31").dates()).hasSize(31);

        assertThatThrownBy(() -> AttendancePeriod.parse(null, "2026-10-01", "2026-11-01"))
                .isInstanceOf(InvalidRequestException.class)
                .hasMessageContaining("31");
    }

    @Test
    void a_month_and_a_range_together_or_neither_is_refused() {
        assertThatThrownBy(() -> AttendancePeriod.parse("2026-10", "2026-10-01", "2026-10-02"))
                .isInstanceOf(InvalidRequestException.class);
        assertThatThrownBy(() -> AttendancePeriod.parse(null, null, null))
                .isInstanceOf(InvalidRequestException.class);
        assertThatThrownBy(() -> AttendancePeriod.parse(null, "2026-10-01", null))
                .isInstanceOf(InvalidRequestException.class);
    }

    @Test
    void a_backwards_or_malformed_range_is_refused() {
        assertThatThrownBy(() -> AttendancePeriod.parse(null, "2026-10-05", "2026-10-01"))
                .isInstanceOf(InvalidRequestException.class)
                .hasMessageContaining("ends before it starts");
        assertThatThrownBy(() -> AttendancePeriod.parse("October", null, null))
                .isInstanceOf(InvalidRequestException.class);
        assertThatThrownBy(() -> AttendancePeriod.parse(null, "last monday", "2026-10-01"))
                .isInstanceOf(InvalidRequestException.class);
    }
}
