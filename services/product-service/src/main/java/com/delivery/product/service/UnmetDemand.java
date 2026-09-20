package com.delivery.product.service;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.product.domain.SearchDemandDigestRepository;
import com.delivery.product.domain.SearchDemandLogRepository;
import com.delivery.product.domain.SearchDemandWeek;
import com.delivery.product.domain.SearchDemandWeekRepository;

/**
 * What a neighbourhood asked for and did not find: the week's roll-up, and the rule that decides
 * whether a term may be spoken of at all.
 *
 * <p>Two questions, per area, over one week:
 * <ul>
 *   <li><strong>NONE</strong> — terms whose searches answered with no shop at all. "Nine people near
 *       you looked for nappies and nothing came back";
 *   <li><strong>FAR</strong> — terms that answered, but only with shops further than
 *       {@code delivery.demand.digest.far-metres}. "Somebody sells it, two kilometres away".
 * </ul>
 *
 * <p><strong>The floor is {@value #MIN_SEARCHES} distinct searches, and it is a constant.</strong>
 * Not a setting, for the reason Order Manager's demand radar gives about its own floor: a number that
 * decides whether a handful of people's searches can be shown to their neighbours must not be
 * lowerable by a typo in a values file. Under the floor a term is one person's shopping list — and
 * reporting it would be telling a shop what somebody on their street wants, which is the difference
 * between a market signal and surveillance. A term under the floor is not written, so no reader can
 * be built that forgets it.
 *
 * <p>Distinct searches, not repeats: the log already holds one row per search, because one person
 * typing a word letter by letter or paging through shops is collapsed before a row exists
 * ({@link SearchDemandRecorder}). So the count here is a plain {@code COUNT(*)} over rows, and every
 * row it counts is a separate search.
 *
 * <p>Computed rather than queried on demand, and the reason is the merchant's screen: the Demand
 * Radar polls, and an aggregate over a quarter of a million searches on every poll would be the
 * demand feature making the platform slower. The roll-up runs on a schedule
 * ({@code SearchDemandMaintenance}) and refreshes both the week that has finished and the week in
 * progress, so "this week and last" costs a merchant one indexed read of a small table.
 */
@Service
public class UnmetDemand {

    private static final Logger log = LoggerFactory.getLogger(UnmetDemand.class);

    /**
     * The fewest distinct searches a term needs in one area in one week before anybody is told about
     * it. A constant on purpose — see the class comment.
     */
    public static final int MIN_SEARCHES = 5;

    /** The widest and narrowest "too far" may be set to. */
    static final int MIN_FAR_METRES = 500;
    static final int MAX_FAR_METRES = 20_000;

    /** The fewest and most days of searches that may be kept. */
    static final int MIN_RETENTION_DAYS = 7;
    static final int MAX_RETENTION_DAYS = 400;

    private final SearchDemandLogRepository logs;
    private final SearchDemandWeekRepository weeks;
    private final SearchDemandDigestRepository digests;
    private final DemandWeeks calendar;
    private final Clock clock;
    private final int farMetres;
    private final int termsPerArea;
    private final int retentionDays;

    public UnmetDemand(SearchDemandLogRepository logs, SearchDemandWeekRepository weeks,
                       SearchDemandDigestRepository digests, DemandWeeks calendar, Clock clock,
                       @Value("${delivery.demand.digest.far-metres:2000}") int farMetres,
                       @Value("${delivery.demand.digest.terms-per-area:10}") int termsPerArea,
                       @Value("${delivery.demand.search-log.retention-days:90}") int retentionDays) {
        if (farMetres < MIN_FAR_METRES || farMetres > MAX_FAR_METRES) {
            throw new IllegalArgumentException("delivery.demand.digest.far-metres must be between "
                    + MIN_FAR_METRES + " and " + MAX_FAR_METRES + ", not " + farMetres);
        }
        if (retentionDays < MIN_RETENTION_DAYS || retentionDays > MAX_RETENTION_DAYS) {
            // Refused rather than clamped: a value that quietly kept a year of searches would be a
            // privacy decision made by a typo.
            throw new IllegalArgumentException("delivery.demand.search-log.retention-days must be "
                    + "between " + MIN_RETENTION_DAYS + " and " + MAX_RETENTION_DAYS + ", not "
                    + retentionDays);
        }
        this.logs = logs;
        this.weeks = weeks;
        this.digests = digests;
        this.calendar = calendar;
        this.clock = clock;
        this.farMetres = farMetres;
        this.termsPerArea = Math.min(Math.max(termsPerArea, 1), 50);
        this.retentionDays = retentionDays;
    }

    public int farMetres() {
        return farMetres;
    }

    public Duration retention() {
        return Duration.ofDays(retentionDays);
    }

    /**
     * Recomputes one week, replacing whatever was there.
     *
     * <p>Idempotent by deletion: the week's rows go and are written again from the log, so running
     * this twice — two replicas, a re-run after a fix, a catch-up on boot — leaves exactly one set of
     * rows. That is the same bargain {@code TrackingPartitionMaintenance} makes: make every step
     * repeatable instead of adding a lock to coordinate a job that runs once a day.
     *
     * @param weekStart Monday 00:00 in the platform's zone
     * @return how many terms the week has, across every area and both kinds
     */
    @Transactional
    public int rollUp(Instant weekStart) {
        Instant until = calendar.weekAfter(weekStart);
        Instant now = clock.instant();
        weeks.deleteWeek(weekStart);
        int written = 0;
        for (SearchDemandWeek.Kind kind : SearchDemandWeek.Kind.values()) {
            written += rollUp(weekStart, until, kind, now);
        }
        log.debug("Rolled up {} unmet terms for the week of {}", written, weekStart);
        return written;
    }

    private int rollUp(Instant weekStart, Instant until, SearchDemandWeek.Kind kind, Instant now) {
        List<Object[]> rows = logs.unmetRows(weekStart, until, kind.name(), farMetres, MIN_SEARCHES);
        List<SearchDemandWeek> batch = new ArrayList<>();
        UUID area = null;
        int rank = 0;
        for (Object[] row : rows) {
            UUID rowArea = (UUID) row[0];
            if (!rowArea.equals(area)) {
                area = rowArea;
                rank = 0;
            }
            // The query returns an area's terms best first, so the rank is the position in that run.
            if (++rank > termsPerArea) {
                continue;
            }
            batch.add(new SearchDemandWeek(weekStart, rowArea, (String) row[1], kind,
                    ((Number) row[2]).intValue(), rank, now));
        }
        weeks.saveAll(batch);
        return batch.size();
    }

    /**
     * Recomputes the week that has finished and the week in progress — what a merchant is shown.
     *
     * @return how many terms the two weeks hold
     */
    @Transactional
    public int rollUpRecentWeeks() {
        Instant now = clock.instant();
        Instant thisWeek = calendar.weekOf(now);
        return rollUp(calendar.weekBefore(thisWeek)) + rollUp(thisWeek);
    }

    /**
     * Forgets searches, roll-ups and digest records past their retention.
     *
     * <p>The log is the one that matters: ninety days is what the platform promised to keep, and a
     * row that outlives it is a privacy commitment quietly broken. The cutoff is computed from the
     * service's clock and bound as a parameter, never written as SQL interval arithmetic, so a test
     * with a fixed clock deletes exactly what it means to.
     *
     * <p>The roll-up and the digest ledger are kept one retention longer than the log they came from:
     * they are aggregates over a floor of five and hold nothing about anybody, but keeping them
     * for ever would be keeping a derivative of deleted data with no reason to.
     *
     * @return how many rows went, from all three tables
     */
    @Transactional
    public int forgetOldSearches() {
        Instant cutoff = clock.instant().minus(retention());
        int searches = logs.deleteOlderThan(cutoff);
        int rolled = weeks.deleteOlderThan(cutoff);
        int sent = digests.deleteOlderThan(cutoff);
        if (searches + rolled + sent > 0) {
            log.info("Forgot {} searches, {} rolled-up terms and {} digest records older than {}",
                    searches, rolled, sent, cutoff);
        }
        return searches + rolled + sent;
    }

    /**
     * How a count is said out loud: rounded down to a round number, never the number itself.
     *
     * <p>"About ten people looked for this" is everything a shop needs to decide whether to stock it.
     * The exact figure is not, and it invites arithmetic — a merchant watching a term week by week
     * could otherwise read changes small enough to be one household. Rounded <em>down</em>, so the
     * platform never says more people wanted something than really did.
     *
     * <p>Five is the smallest band there is, because five is the floor: a term that reached this
     * function was asked for at least that many times.
     */
    public static int band(int searches) {
        if (searches < MIN_SEARCHES) {
            return MIN_SEARCHES;
        }
        if (searches < 20) {
            return searches / 5 * 5;
        }
        if (searches < 100) {
            return searches / 10 * 10;
        }
        return searches / 50 * 50;
    }
}
