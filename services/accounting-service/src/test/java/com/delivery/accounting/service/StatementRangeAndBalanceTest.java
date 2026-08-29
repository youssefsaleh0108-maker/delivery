package com.delivery.accounting.service;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import com.delivery.accounting.domain.CounterpartyKind;

/**
 * The two rules a statement must obey before anybody looks at a figure on it.
 *
 * <p>A period has to be a period somebody could have meant, and the lines have to explain the total.
 * Both are enforced where they cannot be skipped rather than checked at the edge — a validation that
 * lives only in a controller is one the next caller does not run.
 */
@DisplayName("what a statement refuses")
class StatementRangeAndBalanceTest {

    private static final ZoneId UTC = ZoneId.of("UTC");

    @Nested
    @DisplayName("the period")
    class Range {

        @Test
        @DisplayName("refuses a range that ends before it starts")
        void invertedIsRefused() {
            assertThatThrownBy(() -> StatementRange.of(
                    LocalDate.parse("2026-08-29"), LocalDate.parse("2026-08-01"), UTC))
                    .isInstanceOf(IllegalArgumentException.class)
                    // Called out as its own mistake: transposed parameters and "too much data" are
                    // different problems, and one message would send whoever hit it to the wrong
                    // place.
                    .hasMessageContaining("ends before it starts");
        }

        @Test
        @DisplayName("refuses more than 366 days")
        void oversizedIsRefused() {
            assertThatThrownBy(() -> StatementRange.of(
                    LocalDate.parse("2026-01-01"), LocalDate.parse("2027-01-02"), UTC))
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessageContaining("367 days");
        }

        @Test
        @DisplayName("allows a whole leap year, because 365 would be worked around")
        void aLeapYearFits() {
            assertThatCode(() -> StatementRange.of(
                    LocalDate.parse("2028-01-01"), LocalDate.parse("2028-12-31"), UTC))
                    .doesNotThrowAnyException();
        }

        @Test
        @DisplayName("refuses a missing date rather than defaulting one")
        void missingIsRefused() {
            assertThatThrownBy(() -> StatementRange.of(null, LocalDate.parse("2026-08-01"), UTC))
                    .isInstanceOf(IllegalArgumentException.class);
        }

        @Test
        @DisplayName("includes both ends of the period")
        void bothEndsAreInclusive() {
            StatementRange one = StatementRange.of(
                    LocalDate.parse("2026-08-10"), LocalDate.parse("2026-08-10"), UTC);

            assertThat(one.fromInstant().toString()).isEqualTo("2026-08-10T00:00:00Z");
            // Half-open at the top: the exclusive start of the next day, so nothing written at
            // 23:59:59.999 falls out of the day it belongs to.
            assertThat(one.toExclusive().toString()).isEqualTo("2026-08-11T00:00:00Z");
            assertThat(one.contains(java.time.Instant.parse("2026-08-10T23:59:59.999Z"))).isTrue();
            assertThat(one.contains(java.time.Instant.parse("2026-08-11T00:00:00Z"))).isFalse();
        }

        @Test
        @DisplayName("resolves the same dates differently in a different calendar")
        void theZoneDecidesWhereADayStarts() {
            StatementRange beirut = StatementRange.of(
                    LocalDate.parse("2026-08-10"), LocalDate.parse("2026-08-10"),
                    ZoneId.of("Asia/Beirut"));

            // A drop at 22:00 UTC on the 10th is already the 11th in Beirut, and a range that
            // ignored the zone would put it in the wrong month at a month boundary.
            assertThat(beirut.fromInstant().toString()).isEqualTo("2026-08-09T21:00:00Z");
        }
    }

    @Nested
    @DisplayName("the balance property")
    class Balance {

        private final StatementRange august = StatementRange.of(
                LocalDate.parse("2026-08-01"), LocalDate.parse("2026-08-29"), UTC);

        @Test
        @DisplayName("derives the net from the lines rather than accepting one")
        void netIsAlwaysTheSumOfTheLines() {
            Statement statement = Statement.of(CounterpartyKind.MERCHANT, "shop", "A Shop",
                    august, "USD",
                    List.of(Statement.Line.credit("Goods sold", new BigDecimal("119.50"), null),
                            Statement.Line.debit("Commission", new BigDecimal("14.94"), null)),
                    new BigDecimal("104.56"), List.of(), 2, null);

            assertThat(statement.net().amount()).isEqualByComparingTo("104.56");
            assertThat(statement.net().direction()).isEqualTo(Statement.Direction.WE_OWE);
        }

        @Test
        @DisplayName("refuses to exist when its lines disagree with the ledger")
        void aMismatchThrows() {
            // The defect this makes impossible: a net read straight from the ledger beside lines
            // computed for display, drifting apart the first time somebody adds a line and forgets
            // the total. It is invisible until a merchant adds the column up by hand.
            assertThatThrownBy(() -> Statement.of(CounterpartyKind.MERCHANT, "shop", "A Shop",
                    august, "USD",
                    List.of(Statement.Line.credit("Goods sold", new BigDecimal("119.50"), null)),
                    new BigDecimal("104.56"), List.of(), 2, null))
                    .isInstanceOf(IllegalStateException.class)
                    .hasMessageContaining("does not balance");
        }

        @Test
        @DisplayName("calls a zero net settled rather than owed either way")
        void zeroIsSettled() {
            Statement statement = Statement.of(CounterpartyKind.RIDER, "rider", "Rida",
                    august, "USD",
                    List.of(Statement.Line.credit("Earnings", new BigDecimal("10.00"), null),
                            Statement.Line.debit("Cash held", new BigDecimal("10.00"), null)),
                    BigDecimal.ZERO, List.of(), 1, null);

            assertThat(statement.net().direction()).isEqualTo(Statement.Direction.SETTLED);
            assertThat(statement.net().amount()).isEqualByComparingTo("0.00");
        }

        @Test
        @DisplayName("keeps the net non-negative and puts the sign in the direction")
        void theDirectionCarriesTheSign() {
            Statement statement = Statement.of(CounterpartyKind.RIDER, "rider", "Rida",
                    august, "USD",
                    List.of(Statement.Line.credit("Earnings", new BigDecimal("4.50"), null),
                            Statement.Line.debit("Cash collected", new BigDecimal("200.00"), null)),
                    new BigDecimal("-195.50"), List.of(), 2, null);

            // A negative amount beside a direction that also means "the other way" is how a report
            // ends up saying the opposite of what it means.
            assertThat(statement.net().amount()).isEqualByComparingTo("195.50");
            assertThat(statement.net().direction()).isEqualTo(Statement.Direction.THEY_OWE);
        }
    }
}
