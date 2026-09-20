package com.delivery.accounting.service;

import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.LinkedHashMap;
import java.util.Map;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

/**
 * The one calendar every day, period and report boundary in this service is read in (RECON-08).
 *
 * <p><strong>Why one.</strong> A day is a local-calendar question, and four readers answering it
 * differently report the same money in different months. They did: statements and the carrier cash
 * page ran on UTC while pay periods — and every Order Manager dashboard, and every date a client
 * sends — ran on Asia/Beirut. So an order delivered at 00:16 Beirut landed on the previous day's
 * statement, a month's statement ran from 03:00 to 03:00, and for three hours a night the carrier
 * cash page's "today" was yesterday. Three of the 36 orders delivered on dev fell on a different day
 * in the two calendars.
 *
 * <p><strong>One place resolves it.</strong> The zone comes from {@code delivery.calendar.zone} and
 * every reader takes it from here, so there is no second default to drift: the {@code :UTC} that
 * used to sit beside each reader's own property was exactly how the calendar split in the first
 * place. The per-reader keys are still honoured — a deployment that sets one is not silently
 * ignored — but they must agree with it, and this refuses to start when they do not. A calendar
 * that disagrees with itself is not a state this service should run in: it misreports money quietly,
 * which is the failure that cost the most to find.
 *
 * <p>Order Manager's dashboards and order-tracking's duty-session day are the same zone, set in
 * their own services; payroll's key additionally has to match order-tracking's, which is why the
 * attendance read refuses an answer in another zone.
 */
@Component
public class PlatformCalendar {

    /** Where the platform operates. Lebanon, on one calendar. */
    public static final String DEFAULT_ZONE = "Asia/Beirut";

    private final ZoneId zone;
    private final Clock clock;

    public PlatformCalendar(
            @Value("${delivery.calendar.zone:" + DEFAULT_ZONE + "}") String zone,
            // The keys each reader has always used. Aliases of the one above in the shipped
            // configuration; named here so an environment that still sets one is either honoured
            // (it agrees) or refused (it does not), never quietly overridden.
            @Value("${delivery.accounting.statements.zone:}") String statements,
            @Value("${delivery.rider-earnings.zone:}") String riderEarnings,
            @Value("${delivery.accounting.payroll.zone:}") String payroll) {
        this(zone, statements, riderEarnings, payroll, Clock.systemUTC());
    }

    /** For tests, which need "now" to hold still while they ask what day it is. */
    PlatformCalendar(String zone, String statements, String riderEarnings, String payroll,
                     Clock clock) {
        this.zone = parse(zone, "delivery.calendar.zone");
        Map<String, String> readers = new LinkedHashMap<>();
        readers.put("delivery.accounting.statements.zone", statements);
        readers.put("delivery.rider-earnings.zone", riderEarnings);
        readers.put("delivery.accounting.payroll.zone", payroll);
        readers.forEach((key, value) -> {
            if (value == null || value.isBlank()) {
                return;
            }
            ZoneId theirs = parse(value, key);
            if (!theirs.equals(this.zone)) {
                throw new IllegalStateException(
                        "The platform has one calendar and this configuration has two: "
                                + "delivery.calendar.zone is " + this.zone + " and " + key + " is "
                                + theirs + ". Statements, the carrier cash page, rider earnings and "
                                + "pay periods must count days in the same zone, or the same money "
                                + "lands in different months on different pages.");
            }
        });
        this.clock = clock.withZone(this.zone);
    }

    private static ZoneId parse(String value, String key) {
        try {
            return ZoneId.of(value.trim());
        } catch (java.time.DateTimeException e) {
            throw new IllegalStateException(key + " is not a timezone this server knows: " + value);
        }
    }

    /** The zone every range, period and "today" in this service is resolved in. */
    public ZoneId zone() {
        return zone;
    }

    /** The clock the same readers ask what "now" is, already in {@link #zone()}. */
    public Clock clock() {
        return clock;
    }

    /** Today, in the platform's calendar. */
    public LocalDate today() {
        return LocalDate.now(clock);
    }

    /** The first instant of a local day. */
    public Instant startOf(LocalDate day) {
        return day.atStartOfDay(zone).toInstant();
    }

    /** The day a moment falls on. */
    public LocalDate dayOf(Instant at) {
        return LocalDate.ofInstant(at, zone);
    }
}
