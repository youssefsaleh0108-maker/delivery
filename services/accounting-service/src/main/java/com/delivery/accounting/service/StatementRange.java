package com.delivery.accounting.service;

import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.time.temporal.ChronoUnit;

/**
 * The period a statement covers: two inclusive dates, resolved once into one half-open window.
 *
 * <p><strong>A range is a calendar question and a query is not.</strong> "August" is 31 days in
 * somebody's timezone, and the instants that bound it depend on where they are standing. Resolving
 * that in one place means the ledger query, the cash-float query and the rider-ledger query cannot
 * disagree about where a leg written at 23:50 belongs — which they would, eventually, if each of
 * them did the conversion.
 *
 * <p>Half-open: {@code from} is the first instant of the first day and {@code toExclusive} is the
 * first instant of the day AFTER the last. The obvious alternative — end-of-day inclusive — needs a
 * "last representable instant" that differs by database and silently drops the final millisecond.
 */
public record StatementRange(LocalDate from, LocalDate to, ZoneId zone) {

    /**
     * The longest period anybody may ask for in one request.
     *
     * <p>366 rather than 365 so a whole leap year is expressible: a limit that refuses "the year
     * 2028" is a limit somebody will work around by asking for two half-years and adding them up by
     * hand, which is worse than the load it was protecting against.
     */
    public static final long MAX_DAYS = 366;

    /**
     * Validates the two dates a caller supplied.
     *
     * @throws IllegalArgumentException either date is missing, the range is inverted, or it is
     *                                  longer than {@link #MAX_DAYS}. Inverted is called out
     *                                  separately from too-long because the two are different
     *                                  mistakes: one is transposed parameters and the other is
     *                                  asking for too much, and a single message sends whoever hit
     *                                  it looking in the wrong place
     */
    public static StatementRange of(LocalDate from, LocalDate to, ZoneId zone) {
        if (from == null || to == null) {
            throw new IllegalArgumentException("Both from and to are required, as ISO dates");
        }
        if (to.isBefore(from)) {
            throw new IllegalArgumentException(
                    "The range ends before it starts: " + from + " to " + to);
        }
        // Inclusive on both ends, so a single day is one day and not zero.
        long days = ChronoUnit.DAYS.between(from, to) + 1;
        if (days > MAX_DAYS) {
            throw new IllegalArgumentException(
                    "That range covers " + days + " days; the most in one request is " + MAX_DAYS);
        }
        return new StatementRange(from, to, zone);
    }

    /** The first instant of the first day, in the platform's timezone. */
    public Instant fromInstant() {
        return from.atStartOfDay(zone).toInstant();
    }

    /** The first instant of the day after the last, so nothing on the final day is lost. */
    public Instant toExclusive() {
        return to.plusDays(1).atStartOfDay(zone).toInstant();
    }

    /** Whether an instant falls inside the window. The same half-open rule the queries use. */
    public boolean contains(Instant at) {
        return at != null && !at.isBefore(fromInstant()) && at.isBefore(toExclusive());
    }
}
