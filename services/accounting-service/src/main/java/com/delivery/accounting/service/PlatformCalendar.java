package com.delivery.accounting.service;

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
 * <p><strong>One key, and one guard.</strong> The zone comes from {@link #ZONE_PROPERTY}, which
 * every reader resolves by that constant with {@link #DEFAULT_ZONE} behind it, so there is no
 * second default to drift from. The per-reader keys are still honoured — a deployment that sets one
 * is not silently ignored — but they must agree with it, and this bean refuses to start when they
 * do not. A calendar that disagrees with itself is not a state this service should run in: it
 * misreports money quietly, which is the failure that cost the most to find.
 *
 * <p>Order Manager's dashboards and order-tracking's duty-session day are the same zone, set in
 * their own services; payroll's key additionally has to match order-tracking's, which is why the
 * attendance read refuses an answer in another zone.
 */
@Component
public class PlatformCalendar {

    /** Where the platform operates. Lebanon, on one calendar. */
    public static final String DEFAULT_ZONE = "Asia/Beirut";

    /**
     * The one property the zone is configured in.
     *
     * <p>A constant because every reader resolves it by this name and with {@link #DEFAULT_ZONE}
     * behind it — the {@code :UTC} that used to sit beside each reader's own property was exactly
     * how the calendar split. Spelt as {@code @Value("${" + ZONE_PROPERTY + ":" + DEFAULT_ZONE +
     * "}")}, which the compiler folds into one string, so a rename cannot leave one behind.
     */
    public static final String ZONE_PROPERTY = "delivery.calendar.zone";

    private final ZoneId zone;

    public PlatformCalendar(
            @Value("${" + ZONE_PROPERTY + ":" + DEFAULT_ZONE + "}") String zone,
            // The keys each reader has always used. Aliases of the one above in the shipped
            // configuration; named here so an environment that still sets one is either honoured
            // (it agrees) or refused (it does not), never quietly overridden.
            @Value("${delivery.accounting.statements.zone:}") String statements,
            @Value("${delivery.rider-earnings.zone:}") String riderEarnings,
            @Value("${delivery.accounting.payroll.zone:}") String payroll) {
        this.zone = parse(zone, ZONE_PROPERTY);
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
}
