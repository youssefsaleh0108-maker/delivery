package com.delivery.product.service;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.time.ZonedDateTime;
import java.time.temporal.ChronoUnit;
import java.util.HashMap;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.DisposableBean;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.support.TransactionTemplate;

import com.delivery.product.domain.MenuViewDay;
import com.delivery.product.domain.MenuViewDayRepository;
import com.delivery.product.domain.Store;
import com.delivery.product.domain.StoreRepository;

/**
 * Counting the opens of a shop's public menu, without ever writing down an open.
 *
 * <p>The public page is the busiest surface the platform has and the cheapest: it is memoised in
 * process, cached for five minutes by everything downstream, and reads nothing about its caller. A
 * counter that cost a row and a write per reader would undo all three. So nothing is written per
 * view. Views are added up in memory, in buckets, and a flush turns a period of traffic into a
 * handful of {@code +=} statements.
 *
 * <p><strong>The buffer holds no readers either.</strong> Its key is
 * {@code (slug, the hour, how they arrived)} and its value is a number. That is already the shape
 * the table has; the flush only coarsens it further, resolving the shop's own zone so that an hour
 * becomes one of four parts of that shop's day, and then dropping the hour. Nothing about a person
 * is in scope at any point — unlike {@code SearchDemandRecorder}, which has to hold an account id
 * in memory to collapse one person's repeats and spends a long comment on the fact. Here there is
 * nothing to collapse, because two opens by one reader were never two of anything.
 *
 * <p><strong>What it cannot see.</strong> A reader served by their own browser's cache or by a CDN
 * never reaches this service and is not counted. A link preview and a crawler are each counted once,
 * the same as a person. The merchant-facing read is responsible for never calling the result
 * "visitors"; see {@link MenuInsights}.
 */
@Service
public class MenuViewRecorder implements DisposableBean {

    private static final Logger log = LoggerFactory.getLogger(MenuViewRecorder.class);

    /** How often the ticker asks whether the buffer is due. */
    private static final Duration TICK = Duration.ofSeconds(30);

    /**
     * The most buckets held before a flush is forced.
     *
     * <p>A bound rather than a tuning knob: a bucket is a shop, an hour and a way in, so this is
     * thousands of shops before it bites. It exists so that a service that somehow stopped
     * flushing grows a bounded map instead of a heap dump.
     */
    private static final int MAX_BUCKETS = 20_000;

    /** The fewest and most days of counters that may be kept. */
    static final int MIN_RETENTION_DAYS = 7;
    static final int MAX_RETENTION_DAYS = 400;

    /** One bucket of the in-memory tally: a shop's slug, the hour it was, and how they arrived. */
    private record Bucket(String slug, Instant hour, MenuViewDay.Source source) {
    }

    /** What a bucket becomes once the shop's zone is known and the hour has been given up. */
    private record Coarse(UUID storeId, LocalDate day, MenuViewDay.Part part,
                          MenuViewDay.Source source) {
    }

    private final MenuViewDayRepository days;
    private final StoreRepository stores;
    private final Clock clock;
    private final TransactionTemplate transaction;
    private final ScheduledExecutorService ticker;
    private final Duration flushAfter;
    private final int retentionDays;

    private final Map<Bucket, Integer> tally = new ConcurrentHashMap<>();
    private volatile Instant oldest;

    /**
     * {@code @Autowired} because there are two constructors and Spring will not guess between
     * them: without it, container startup falls back to a no-arg constructor that does not exist
     * and the service crash-loops while every unit test passes. That is the failure
     * {@code ApplicationContextBootTest} was written for after {@code DemandWeeks} did it, and it
     * caught this one too.
     */
    @Autowired
    public MenuViewRecorder(MenuViewDayRepository days, StoreRepository stores, Clock clock,
                            PlatformTransactionManager transactionManager,
                            @Value("${delivery.menu-views.flush-after:5m}") Duration flushAfter,
                            @Value("${delivery.menu-views.retention-days:90}") int retentionDays) {
        this(days, stores, clock, transactionManager, newTicker(), flushAfter, retentionDays);
        // Started here and not in the shared constructor, so nothing schedules a task that reads a
        // half-built object. Its own ticker rather than @Scheduled, for the reason
        // SearchDemandRecorder gives about its own: a buffer that only emptied when somebody else's
        // configuration switched scheduling on would hold counts for ever.
        this.ticker.scheduleWithFixedDelay(this::flushIfDue,
                TICK.toMillis(), TICK.toMillis(), TimeUnit.MILLISECONDS);
    }

    /**
     * The shared constructor, and the one a test uses with a {@code null} ticker: a test moves its
     * own clock and calls {@link #flushIfDue} when it means to, rather than waiting on a thread.
     *
     * <p>Not a second convenience overload without the ticker, because the annotations on the
     * public constructor above erase and the two would collide.
     */
    MenuViewRecorder(MenuViewDayRepository days, StoreRepository stores, Clock clock,
                     PlatformTransactionManager transactionManager,
                     ScheduledExecutorService ticker, Duration flushAfter, int retentionDays) {
        if (retentionDays < MIN_RETENTION_DAYS || retentionDays > MAX_RETENTION_DAYS) {
            // Refused rather than clamped, as the search log's is: a value that quietly kept a
            // year of a shop's traffic would be a decision made by a typo in a values file.
            throw new IllegalArgumentException("delivery.menu-views.retention-days must be between "
                    + MIN_RETENTION_DAYS + " and " + MAX_RETENTION_DAYS + ", not " + retentionDays);
        }
        this.days = days;
        this.stores = stores;
        this.clock = clock;
        this.ticker = ticker;
        this.flushAfter = flushAfter;
        this.retentionDays = retentionDays;
        TransactionTemplate template = new TransactionTemplate(transactionManager);
        // Its own transaction on its own thread: the page's read-only one is closed by the time
        // this runs.
        template.setPropagationBehavior(TransactionDefinition.PROPAGATION_REQUIRES_NEW);
        this.transaction = template;
    }

    /**
     * One open of one shop's menu.
     *
     * <p>Called from the page's request thread, so it does two things and neither of them touches
     * the database: it adds one to a map, and it returns. It also cannot throw — a shop's page
     * must not fail to render because its counter did.
     *
     * @param slug      the shop whose page was served, already known to exist
     * @param fromTable whether the address carried a table card's parameter. Not "was this a QR
     *                  scan": see {@link MenuViewDay.Source}
     */
    public void record(String slug, boolean fromTable) {
        try {
            Instant hour = clock.instant().truncatedTo(ChronoUnit.HOURS);
            Bucket bucket = new Bucket(slug,
                    hour, fromTable ? MenuViewDay.Source.TABLE : MenuViewDay.Source.LINK);
            tally.merge(bucket, 1, Integer::sum);
            if (oldest == null) {
                oldest = clock.instant();
            }
            if (tally.size() >= MAX_BUCKETS) {
                flush();
            }
        } catch (RuntimeException failed) {
            log.warn("Could not count a menu view for {}", slug, failed);
        }
    }

    /** Flushes when the buffer has waited long enough. Called by the ticker, and by tests. */
    void flushIfDue() {
        Instant since = oldest;
        if (since == null || tally.isEmpty()) {
            return;
        }
        if (Duration.between(since, clock.instant()).compareTo(flushAfter) < 0) {
            return;
        }
        flush();
    }

    /**
     * Turn what is held into {@code +=} statements, one per shop per day per part per way in.
     *
     * <p>The buffer is taken first and emptied, so a request counted while this runs lands in the
     * next flush rather than being lost or written twice.
     */
    void flush() {
        Map<Bucket, Integer> held = new HashMap<>();
        // drainTo, by hand: remove returns what was there, so a concurrent merge either happened
        // before the remove (and is in `held`) or after it (and starts the next bucket).
        for (Bucket bucket : Map.copyOf(tally).keySet()) {
            Integer count = tally.remove(bucket);
            if (count != null) {
                held.put(bucket, count);
            }
        }
        oldest = null;
        if (held.isEmpty()) {
            return;
        }

        // Resolved once per shop per flush, not once per bucket: a busy shop has a bucket an hour
        // and they all want the same zone.
        Map<String, Optional<Store>> resolved = new HashMap<>();
        Map<Coarse, Integer> coarse = new HashMap<>();
        for (Map.Entry<Bucket, Integer> entry : held.entrySet()) {
            Bucket bucket = entry.getKey();
            Optional<Store> shop = resolved.computeIfAbsent(bucket.slug(), stores::findBySlug);
            if (shop.isEmpty()) {
                // The shop went away between the page being served and this flush. Nothing to
                // attribute the count to, and inventing a row for a shop that is gone would only
                // be a foreign key violation a moment later.
                continue;
            }
            ZonedDateTime local = bucket.hour().atZone(shop.get().zone());
            // The hour is given up here and never reaches the database. Every part boundary is on
            // the hour, so a whole buffered hour belongs to one part of the shop's day.
            coarse.merge(new Coarse(shop.get().getId(), local.toLocalDate(),
                            MenuViewDay.partOf(local.toLocalTime()), bucket.source()),
                    entry.getValue(), Integer::sum);
        }
        if (coarse.isEmpty()) {
            return;
        }

        try {
            transaction.executeWithoutResult(status -> coarse.forEach((key, views) ->
                    days.add(key.storeId(), key.day(), key.part().name(), key.source().name(),
                            views)));
        } catch (RuntimeException failed) {
            // A flush that cannot be written is a lost count, not a lost page. Said once, and the
            // buffer is already empty so the next flush is not made worse by this one.
            log.warn("Could not write {} menu-view buckets", coarse.size(), failed);
        }
    }

    /**
     * Forget counters past the retention window.
     *
     * <p>{@code @Scheduled}, unlike the flush above, and the difference is what each one costs if
     * scheduling is off: a flush that never runs loses counts, while a retention pass that never
     * runs leaves old counters lying about. Neither is good; only one of them is urgent.
     */
    @Scheduled(cron = "${delivery.menu-views.retention-cron:0 40 3 * * *}",
            zone = "${delivery.platform.zone:UTC}")
    public int forgetOldDays() {
        LocalDate cutoff = LocalDate.ofInstant(clock.instant(), ZoneId.of("UTC"))
                .minusDays(retentionDays);
        int gone = transaction.execute(status -> days.deleteOlderThan(cutoff));
        if (gone > 0) {
            log.info("Forgot {} menu-view counters older than {}", gone, cutoff);
        }
        return gone;
    }

    private static ScheduledExecutorService newTicker() {
        AtomicInteger counter = new AtomicInteger();
        return Executors.newSingleThreadScheduledExecutor(runnable -> {
            Thread thread = new Thread(runnable, "menu-views-flush-" + counter.incrementAndGet());
            thread.setDaemon(true);
            return thread;
        });
    }

    @Override
    public void destroy() {
        if (ticker != null) {
            ticker.shutdownNow();
        }
        // A clean stop writes what is held. What a kill -9 loses is one window of counts on one
        // pod, which is a number that was never exact and is documented as not being exact.
        try {
            flush();
        } catch (RuntimeException failed) {
            log.warn("Could not flush menu views on shutdown", failed);
        }
    }
}
