package com.delivery.tracking.service;

import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.util.List;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Keeps {@code tracking_events} partitioned ahead of the writers and bounded behind them.
 *
 * <p>Section 10 requires this table to be partitioned by date with a retention policy, because it
 * takes a write per active rider every few seconds and grows without limit otherwise. The
 * partitioning itself is in {@code V11}; this is the part that has to keep running.
 *
 * <p>Three jobs in one, in the order they matter:
 *
 * <ol>
 *   <li><strong>Create ahead.</strong> There is no default partition — see V11 for why — so an
 *       insert past the last partition fails. Keeping a week ahead means maintenance has to be
 *       dead for a week before a rider ping is refused, and the startup run means a service that
 *       has been down over a boundary catches up before it accepts traffic.</li>
 *   <li><strong>Roll up.</strong> Before a day is dropped, reduce it to one row per order. A
 *       delivery dispute arrives weeks late and asks where the rider went; dropping the day
 *       without a summary makes that unanswerable.</li>
 *   <li><strong>Drop.</strong> {@code DROP TABLE} on a partition, not {@code DELETE}. A delete of
 *       a day's pings on this table is millions of rows, a long transaction and a vacuum problem;
 *       dropping the partition is a catalogue update.</li>
 * </ol>
 *
 * <p>Runs on every instance. That is safe rather than coordinated: creation is
 * {@code IF NOT EXISTS}, the roll-up upserts, and the drop is guarded by {@code IF EXISTS}. Two
 * instances doing this simultaneously is wasteful for a few milliseconds a day and cannot corrupt
 * anything, which is a better trade than adding a distributed lock for a daily job.
 */
@Service
public class TrackingPartitionMaintenance {

    private static final Logger log = LoggerFactory.getLogger(TrackingPartitionMaintenance.class);

    private static final DateTimeFormatter SUFFIX = DateTimeFormatter.ofPattern("yyyyMMdd");

    private final JdbcTemplate jdbc;
    private final int retentionDays;
    private final int createAheadDays;

    public TrackingPartitionMaintenance(
            JdbcTemplate jdbc,
            @Value("${delivery.tracking.raw-ping-retention-days:30}") int retentionDays,
            @Value("${delivery.tracking.partition-create-ahead-days:7}") int createAheadDays) {
        this.jdbc = jdbc;
        this.retentionDays = retentionDays;
        this.createAheadDays = createAheadDays;
    }

    /**
     * Catches up before the service takes traffic.
     *
     * <p>Without this, an instance started after a long outage would accept rider pings for a day
     * that has no partition and reject every one of them.
     */
    @EventListener(ApplicationReadyEvent.class)
    public void onStartup() {
        log.info("Tracking partition maintenance: startup run");
        run();
    }

    /** 03:15 — after midnight has rolled over, well clear of any delivery peak. */
    @Scheduled(cron = "${delivery.tracking.partition-maintenance-cron:0 15 3 * * *}")
    public void onSchedule() {
        run();
    }

    void run() {
        try {
            int created = createAhead();
            int rolledUp = rollUpExpired();
            int dropped = dropExpired();

            if (created > 0 || dropped > 0) {
                log.info("Tracking partitions: {} created, {} days rolled up, {} dropped "
                        + "(retention {} days)", created, rolledUp, dropped, retentionDays);
            }
        } catch (Exception e) {
            // Never propagate out of a scheduled method: an exception here cancels all future runs
            // of a fixed-delay schedule, which would turn one bad night into permanently unbounded
            // growth and, eventually, refused rider pings.
            log.error("Tracking partition maintenance failed; will retry on the next run", e);
        }
    }

    private int createAhead() {
        int created = 0;
        for (int offset = 0; offset <= createAheadDays; offset++) {
            LocalDate day = LocalDate.now().plusDays(offset);
            String name = "tracking_events_" + day.format(SUFFIX);

            // IF NOT EXISTS rather than checking first: the check-then-create race between two
            // instances is exactly what this avoids.
            jdbc.execute(String.format(
                    "CREATE TABLE IF NOT EXISTS %s PARTITION OF tracking_events "
                            + "FOR VALUES FROM ('%s') TO ('%s')",
                    name, day, day.plusDays(1)));
            created++;
        }
        return created;
    }

    /**
     * Summarises every partition about to be dropped.
     *
     * <p>Reads from the partition directly rather than the parent, so the scan touches only the day
     * being retired instead of the whole table.
     */
    @Transactional
    int rollUpExpired() {
        int days = 0;
        for (LocalDate day : expiredDays()) {
            String partition = "tracking_events_" + day.format(SUFFIX);

            jdbc.update(String.format("""
                    INSERT INTO tracking_event_rollup (
                        order_id, day, ping_count, first_seen_at, last_seen_at,
                        first_lat, first_lng, last_lat, last_lng, span_metres)
                    SELECT order_id,
                           %2$s::date,
                           count(*),
                           min(recorded_at),
                           max(recorded_at),
                           (array_agg(lat ORDER BY recorded_at))[1],
                           (array_agg(lng ORDER BY recorded_at))[1],
                           (array_agg(lat ORDER BY recorded_at DESC))[1],
                           (array_agg(lng ORDER BY recorded_at DESC))[1],
                           public.ST_Distance(
                               (array_agg(location ORDER BY recorded_at))[1],
                               (array_agg(location ORDER BY recorded_at DESC))[1])
                      FROM %1$s
                     GROUP BY order_id
                    ON CONFLICT (order_id, day) DO NOTHING
                    """, partition, "'" + day + "'"));
            days++;
        }
        return days;
    }

    private int dropExpired() {
        int dropped = 0;
        for (LocalDate day : expiredDays()) {
            // DROP, not DELETE: a day of pings is millions of rows, and a delete would be a long
            // transaction plus a vacuum problem where this is a catalogue update.
            jdbc.execute("DROP TABLE IF EXISTS tracking_events_" + day.format(SUFFIX));
            dropped++;
        }
        return dropped;
    }

    /**
     * Partitions older than the retention window, read from the catalogue rather than assumed.
     *
     * <p>Deriving the list from what actually exists means a gap — a day the service was down and
     * never created — does not stop the days either side of it being retired.
     */
    private List<LocalDate> expiredDays() {
        LocalDate cutoff = LocalDate.now().minusDays(retentionDays);

        return jdbc.query("""
                SELECT c.relname
                  FROM pg_class c
                  JOIN pg_namespace n ON n.oid = c.relnamespace
                 WHERE n.nspname = current_schema()
                   AND c.relkind = 'r'
                   AND c.relname ~ '^tracking_events_[0-9]{8}$'
                 ORDER BY c.relname
                """, (rs, i) -> rs.getString(1)).stream()
                .map(name -> LocalDate.parse(name.substring("tracking_events_".length()), SUFFIX))
                .filter(day -> day.isBefore(cutoff))
                .toList();
    }
}
