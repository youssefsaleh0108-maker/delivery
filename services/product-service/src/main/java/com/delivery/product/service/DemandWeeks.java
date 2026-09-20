package com.delivery.product.service;

import java.time.DayOfWeek;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.time.format.DateTimeParseException;
import java.time.temporal.TemporalAdjusters;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

/**
 * The platform's week: Monday 00:00 in {@code delivery.platform.zone}, wherever the server is.
 *
 * <p>A week has to be somebody's week. A merchant in Beirut reading "this week" means the week their
 * shop just traded, and a roll-up cut at midnight UTC would put Sunday evening — Lebanon's busiest
 * shopping hours — in the following week for half the year. So every boundary this feature uses is
 * computed here, in the platform's own calendar, and nowhere else.
 *
 * <p>Through {@link LocalDate} rather than by subtracting seven days from an instant: Lebanon changes
 * its clocks, and a week measured in fixed hours would drift an hour twice a year until "Monday
 * midnight" was Sunday at eleven.
 */
@Component
public class DemandWeeks {

    private final ZoneId zone;

    public DemandWeeks(@Value("${delivery.platform.zone:Asia/Beirut}") String platformZone) {
        this.zone = parse(platformZone);
    }

    public DemandWeeks(ZoneId zone) {
        this.zone = zone;
    }

    /**
     * Refused at start-up rather than defaulted, the way {@code StoreService} refuses the same
     * setting: a zone nobody can read would silently move every merchant's week.
     */
    private static ZoneId parse(String platformZone) {
        try {
            return ZoneId.of(platformZone);
        } catch (DateTimeParseException | java.time.zone.ZoneRulesException e) {
            throw new IllegalArgumentException("delivery.platform.zone is '" + platformZone
                    + "', which is not a time zone. The demand digest cuts its weeks in it.", e);
        }
    }

    public ZoneId zone() {
        return zone;
    }

    /** Monday 00:00, in the platform's zone, of the week {@code at} falls in. */
    public Instant weekOf(Instant at) {
        return at.atZone(zone).toLocalDate()
                .with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
                .atStartOfDay(zone)
                .toInstant();
    }

    /** The Monday before {@code weekStart}'s. */
    public Instant weekBefore(Instant weekStart) {
        return weekStart.atZone(zone).toLocalDate().minusWeeks(1).atStartOfDay(zone).toInstant();
    }

    /** The Monday after {@code weekStart}'s, which is the end of that week. */
    public Instant weekAfter(Instant weekStart) {
        return weekStart.atZone(zone).toLocalDate().plusWeeks(1).atStartOfDay(zone).toInstant();
    }

    /** The last week that has finished, as of {@code now}: what a Monday digest reports on. */
    public Instant lastCompleteWeek(Instant now) {
        return weekBefore(weekOf(now));
    }
}
