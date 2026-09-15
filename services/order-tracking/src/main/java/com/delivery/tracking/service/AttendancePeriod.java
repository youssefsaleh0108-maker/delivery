package com.delivery.tracking.service;

import java.time.LocalDate;
import java.time.YearMonth;
import java.time.format.DateTimeParseException;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.List;
import java.util.Objects;

import com.delivery.tracking.service.AttendanceService.InvalidRequestException;

/**
 * The days an attendance or sessions read covers — inclusive dates in the platform's day zone.
 *
 * <p>Asked for either as a calendar month ({@code month=2026-10}), which is what the console's
 * calendar wants, or as an explicit range ({@code from}/{@code to}), which is what a pay run that
 * is not monthly wants. Never more than {@value #MAX_DAYS} days: the read walks every session and
 * every day in it, and a longer window belongs in a loop of months, not one request.
 */
public record AttendancePeriod(LocalDate from, LocalDate to) {

    public static final int MAX_DAYS = 31;

    public AttendancePeriod {
        Objects.requireNonNull(from, "from");
        Objects.requireNonNull(to, "to");
        if (to.isBefore(from)) {
            throw new InvalidRequestException("The period ends before it starts.");
        }
        if (ChronoUnit.DAYS.between(from, to) + 1 > MAX_DAYS) {
            throw new InvalidRequestException(
                    "A period can cover at most " + MAX_DAYS + " days. Ask for one month at a time.");
        }
    }

    /**
     * Exactly one of a month or a range; anything else is refused with a sentence that says which.
     */
    public static AttendancePeriod parse(String month, String from, String to) {
        boolean hasMonth = month != null && !month.isBlank();
        boolean hasRange = (from != null && !from.isBlank()) || (to != null && !to.isBlank());
        if (hasMonth == hasRange) {
            throw new InvalidRequestException(
                    "Ask for either a month (month=YYYY-MM) or a range (from and to), not both.");
        }
        if (hasMonth) {
            try {
                YearMonth ym = YearMonth.parse(month.trim());
                return new AttendancePeriod(ym.atDay(1), ym.atEndOfMonth());
            } catch (DateTimeParseException e) {
                throw new InvalidRequestException("month must look like 2026-10.");
            }
        }
        if (from == null || from.isBlank() || to == null || to.isBlank()) {
            throw new InvalidRequestException("A range needs both from and to (YYYY-MM-DD).");
        }
        return new AttendancePeriod(date(from, "from"), date(to, "to"));
    }

    static LocalDate date(String value, String field) {
        try {
            return LocalDate.parse(value.trim());
        } catch (DateTimeParseException e) {
            throw new InvalidRequestException(field + " must be an ISO date such as 2026-10-01.");
        }
    }

    /** Every date in the period, in order. */
    public List<LocalDate> dates() {
        List<LocalDate> dates = new ArrayList<>();
        for (LocalDate d = from; !d.isAfter(to); d = d.plusDays(1)) {
            dates.add(d);
        }
        return dates;
    }

    public boolean contains(LocalDate day) {
        return !day.isBefore(from) && !day.isAfter(to);
    }
}
