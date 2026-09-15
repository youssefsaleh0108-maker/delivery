package com.delivery.accounting.service;

import java.time.Instant;
import java.time.LocalDate;
import java.time.YearMonth;
import java.time.ZoneId;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.Optional;

import com.delivery.accounting.domain.CarrierPayPolicy;
import com.delivery.accounting.domain.CarrierPayPolicy.PayCycle;

/**
 * How a delivery company's calendar is cut into pay periods.
 *
 * <p><strong>Calendar-aligned, never rolling.</strong> A semi-monthly period is the 1st to the 15th or
 * the 16th to the month's end; a monthly one is the month. Any two periods that overlap therefore
 * share a first or a last day — across a change of calendar too, because a change of calendar can
 * only start on the 1st — which is what lets two unique keys on the run table make paying one day
 * twice impossible.
 *
 * <p>Dates are local days in the payroll zone, the same calendar order-tracking judges attendance
 * in, so "the 15th" means the same 24 hours to the deliveries and to the hours.
 */
public final class PayPeriods {

    private PayPeriods() {
    }

    /** An inclusive run of local days. */
    public record Period(LocalDate from, LocalDate to) {

        public Period {
            if (from == null || to == null || to.isBefore(from)) {
                throw new IllegalArgumentException("A period ends on or after the day it starts");
            }
        }

        public int days() {
            return (int) ChronoUnit.DAYS.between(from, to) + 1;
        }

        public boolean contains(LocalDate day) {
            return !day.isBefore(from) && !day.isAfter(to);
        }

        /** The first instant of the period in {@code zone}. */
        public Instant startIn(ZoneId zone) {
            return from.atStartOfDay(zone).toInstant();
        }

        /**
         * The first instant after it: midnight starting the next day, so a delivery at 23:59:59 on
         * the last day is in, and the query reads {@code earnedAt < end}.
         */
        public Instant endIn(ZoneId zone) {
            return to.plusDays(1).atStartOfDay(zone).toInstant();
        }
    }

    /** The period of {@code cycle} containing {@code day}. */
    public static Period containing(LocalDate day, PayCycle cycle) {
        YearMonth month = YearMonth.from(day);
        return switch (cycle) {
            case MONTHLY -> new Period(month.atDay(1), month.atEndOfMonth());
            case SEMI_MONTHLY -> day.getDayOfMonth() <= 15
                    ? new Period(month.atDay(1), month.atDay(15))
                    : new Period(month.atDay(16), month.atEndOfMonth());
        };
    }

    /** Whether a period of {@code cycle} starts on {@code day}. */
    public static boolean isStart(LocalDate day, PayCycle cycle) {
        return containing(day, cycle).from().equals(day);
    }

    /**
     * The version of a company's rules in force on a day: the latest to have started by then and, of
     * two starting the same day, the later saved.
     *
     * @param newestFirst every version, as {@code findByCarrierRefOrderByEffectiveFromDescCreatedAtDesc}
     *                    returns them
     */
    public static Optional<CarrierPayPolicy> inForce(List<CarrierPayPolicy> newestFirst,
                                                     LocalDate day) {
        return newestFirst.stream()
                .filter(policy -> !policy.getEffectiveFrom().isAfter(day))
                .findFirst();
    }

    /**
     * The pay period containing a day under the rules in force that day, or empty before the company
     * had any rules.
     */
    public static Optional<Period> periodOf(List<CarrierPayPolicy> newestFirst, LocalDate day) {
        return inForce(newestFirst, day).map(policy -> containing(day, policy.getPayCycle()));
    }
}
