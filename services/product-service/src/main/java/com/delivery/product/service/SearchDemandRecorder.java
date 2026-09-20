package com.delivery.product.service;

import java.security.SecureRandom;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.Executor;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.DisposableBean;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.support.TransactionTemplate;

import com.delivery.product.domain.GeoPoint;
import com.delivery.product.domain.SearchDemandLog;
import com.delivery.product.domain.SearchDemandLogRepository;

/**
 * Writes down what a street looked for, without ever writing down who looked.
 *
 * <p><strong>Never on the search's thread, never in its transaction, never able to fail it.</strong>
 * A search answers the customer and then hands this class a small value object; everything after that
 * — resolving the pin to a neighbourhood, judging whether an answering shop was in it, opening a
 * transaction, inserting — happens on this class's own thread. {@link #record} does no I/O and throws
 * nothing: a full queue drops the row, a database that is down drops the row, and in both cases the
 * customer has already had their answer. A demand feature is worth exactly nothing if it can slow or
 * break the search it watches, so it is built so that it cannot.
 *
 * <p><strong>Its own small pool, deliberately not a Spring {@code Executor} bean</strong>, for the
 * reason {@link CatalogScanAnalyzer} gives: declaring one would make Spring Boot's auto-configured
 * application task executor back off for the whole service. One thread — the work is an insert —
 * and a bounded queue, so a slow database makes the log lossy rather than making the service a
 * queue of pending writes.
 *
 * <p><strong>The account id stops here.</strong> It is taken only to answer one question — "has this
 * person already asked for this, in this neighbourhood, in the last
 * {@code delivery.demand.search-log.repeat-window}" — so that one shopper typing a word letter by
 * letter, or searching again after changing their mind, is one signal rather than nine. That question
 * is answered in memory, in a bounded map this process alone holds and a restart empties, and the
 * answer is a yes or a no. No account id is passed to {@link SearchDemandLog}, and there is no column
 * on it that could hold one.
 *
 * <p><strong>Rows are buffered and each flush is written in a shuffled order.</strong> A random
 * primary key does not hide the order rows were written in: this is an insert-only table, so
 * {@code ORDER BY ctid} reads the heap in physical order, which is the order the single writer
 * inserted in. Left alone that would hand back the minute-by-minute sequence that truncating
 * {@code searched_at} to the hour exists to remove, and consecutive rows from one area would read as
 * one shopper's basket — which says far more about a household than any single word does. So rows
 * wait here until there are enough of them to be written together, and the flush is shuffled
 * ({@link #flush}) before it is inserted:
 *
 * <ul>
 *   <li><strong>{@value #DEFAULT_FLUSH_ROWS} rows</strong> ({@code flush-rows}) write at once. At any
 *       real traffic that is a handful of minutes of searches from every area at once, and one
 *       shopper's burst is a few rows lost among them;</li>
 *   <li><strong>{@value #HOLD_MINUTES} minutes</strong> ({@code flush-after}) is how long the oldest
 *       row waits for company before the buffer goes anyway. A shopper's burst — typing a word,
 *       trying a synonym, then a photo — happens inside a couple of minutes, so a burst lands inside
 *       one flush and its order does not survive it;</li>
 *   <li><strong>never fewer than {@value #MIN_FLUSH_ROWS}</strong> on that timer. A flush of one row
 *       is exactly the sequence this is meant to hide, and a flush smaller than the digest's floor of
 *       five could be one household on its own. A quiet area's rows therefore wait for neighbours
 *       rather than being written alone;</li>
 *   <li><strong>and never longer than {@value #MAX_HOLD_MINUTES} minutes</strong>, however few rows
 *       there are. After an hour the rows in the buffer are spread across the hour that
 *       {@code searched_at} already names, so writing them in whatever order can say nothing about
 *       the sequence that the row itself does not already say — and holding them longer would only
 *       mean losing more of them to a restart.</li>
 * </ul>
 *
 * <p>The cost of the buffer is what an unclean stop loses: at most one flush, at most an hour old. A
 * clean shutdown writes what it holds ({@link #destroy}). That is the right side of the trade — the
 * numbers this feeds are counts over a week, and a handful of missing rows moves a band by nothing.
 *
 * <p>Paging is handled by the caller rather than here: only the first page of an answer is a search
 * (see {@code ItemSearchController}), so scrolling through shops is not a second signal.
 */
@Component
public class SearchDemandRecorder implements DisposableBean {

    private static final Logger log = LoggerFactory.getLogger(SearchDemandRecorder.class);

    /** One thread: the work is a single-row insert, and ordering between rows means nothing. */
    private static final int THREADS = 1;

    /**
     * How many recordings may wait. Short on purpose: a backlog longer than this means the database
     * is struggling, and the right thing to do then is to drop demand rows, not to hold memory for
     * them while the storefront it shares a database with is already in trouble.
     */
    private static final int QUEUE = 500;

    /** How many repeats the dedupe map remembers before the oldest are forgotten. */
    static final int REPEATS_REMEMBERED = 20_000;

    /** The bounds the repeat window is held to, applied to the setting. */
    static final Duration MIN_REPEAT_WINDOW = Duration.ZERO;
    static final Duration MAX_REPEAT_WINDOW = Duration.ofHours(6);

    /** How many rows are written in one shuffled flush, unless the timer comes first. */
    static final int DEFAULT_FLUSH_ROWS = 50;

    /** The bounds the flush size is held to. One row per flush is no shuffle at all. */
    static final int MIN_FLUSH_ROWS_SETTING = 1;
    static final int MAX_FLUSH_ROWS_SETTING = 500;

    /** How long the oldest buffered row waits for company. See the class comment. */
    static final int HOLD_MINUTES = 10;
    static final Duration DEFAULT_HOLD = Duration.ofMinutes(HOLD_MINUTES);

    /**
     * The fewest rows the timer will write. Anything smaller waits for neighbours until
     * {@link #MAX_HOLD}: the digest's floor is five people, and a flush under it could be one.
     */
    static final int MIN_FLUSH_ROWS = 5;

    /**
     * The longest a row waits, whatever the buffer holds — the same hour {@code searched_at} is
     * truncated to, so a late flush discloses nothing the row does not already carry.
     */
    static final int MAX_HOLD_MINUTES = 60;
    static final Duration MAX_HOLD = Duration.ofMinutes(MAX_HOLD_MINUTES);

    /** How often the buffer is asked whether it has waited long enough. */
    static final Duration TICK = Duration.ofMinutes(1);

    /** How long a clean shutdown waits for the last flush before giving up on it. */
    private static final Duration SHUTDOWN_GRACE = Duration.ofSeconds(5);

    private final SearchDemandLogRepository logs;
    private final CoarseAreas areas;
    private final Clock clock;
    private final Executor executor;
    private final ScheduledExecutorService ticker;
    private final TransactionTemplate transaction;
    private final Duration repeatWindow;
    private final int flushRows;
    private final Duration holdFor;

    /** Dropped because the queue was full, and dropped because the write failed. For tests and logs. */
    private final AtomicLong refused = new AtomicLong();
    private final AtomicLong failed = new AtomicLong();
    private final AtomicLong written = new AtomicLong();
    private final AtomicLong repeats = new AtomicLong();

    /**
     * Rows waiting for a flush, and when the oldest of them arrived.
     *
     * <p>Touched only on the recorder's own thread: {@link #record} hands the work to the executor,
     * and the timer submits its check to the same executor rather than reaching in from another
     * thread. One writer means the buffer needs no lock and the shuffle needs no copy.
     */
    private final List<SearchDemandLog> buffer = new ArrayList<>();
    private Instant bufferedSince;

    /** The shuffle itself. Seeded by the platform, so the permutation is not one anybody can replay. */
    private final SecureRandom shuffle = new SecureRandom();

    /**
     * When each (account, area, term) was last recorded. Access-ordered and capped, so it is an LRU
     * rather than a leak, and synchronized because one thread reads it and request threads write it.
     */
    private final Map<String, Instant> lastSeen = Collections.synchronizedMap(
            new LinkedHashMap<>(1_024, 0.75f, true) {
                @Override
                protected boolean removeEldestEntry(Map.Entry<String, Instant> eldest) {
                    return size() > REPEATS_REMEMBERED;
                }
            });

    @Autowired
    public SearchDemandRecorder(SearchDemandLogRepository logs, CoarseAreas areas, Clock clock,
                                PlatformTransactionManager transactionManager,
                                @Value("${delivery.demand.search-log.repeat-window:30m}")
                                Duration repeatWindow,
                                @Value("${delivery.demand.search-log.flush-rows:50}") int flushRows,
                                @Value("${delivery.demand.search-log.flush-after:10m}")
                                Duration flushAfter) {
        this(logs, areas, clock, transactionManager, newPool(), newTicker(), repeatWindow, flushRows,
                flushAfter);
        // Started here rather than in the shared constructor, so nothing schedules a task that reads
        // a half-built object. Its own ticker rather than @Scheduled: scheduling reaches this service
        // through the outbox library's configuration, and a buffer that only emptied when somebody
        // else's feature was switched on would hold rows for ever. One daemon thread, one periodic
        // task, and all it does is ask the recorder's own thread whether the buffer has waited long
        // enough.
        this.ticker.scheduleWithFixedDelay(this::askForAFlush,
                TICK.toMillis(), TICK.toMillis(), TimeUnit.MILLISECONDS);
    }

    /**
     * A caller-supplied executor, usually one that runs inline. For tests, as {@code PhotoQuota}'s
     * second constructor is: the pool is the only part of this class a test cannot assert against
     * directly, and the thing worth asserting about it — that {@link #record} returns before the
     * write happens — needs an executor that does not run inline.
     *
     * <p>No ticker: a test moves its own clock and calls {@link #flushIfDue} when it means to.
     */
    public SearchDemandRecorder(SearchDemandLogRepository logs, CoarseAreas areas, Clock clock,
                                PlatformTransactionManager transactionManager, Executor executor,
                                Duration repeatWindow, int flushRows, Duration flushAfter) {
        this(logs, areas, clock, transactionManager, executor, null, repeatWindow, flushRows,
                flushAfter);
    }

    private SearchDemandRecorder(SearchDemandLogRepository logs, CoarseAreas areas, Clock clock,
                                 PlatformTransactionManager transactionManager, Executor executor,
                                 ScheduledExecutorService ticker, Duration repeatWindow,
                                 int flushRows, Duration flushAfter) {
        this.logs = logs;
        this.areas = areas;
        this.clock = clock;
        this.executor = executor;
        this.ticker = ticker;
        // A transaction of its own, started on the background thread: the search's own transaction
        // is read-only and, by the time this runs, closed. REQUIRES_NEW says so out loud.
        this.transaction = new TransactionTemplate(transactionManager);
        this.transaction.setPropagationBehavior(TransactionDefinition.PROPAGATION_REQUIRES_NEW);
        Duration window = repeatWindow == null ? Duration.ofMinutes(30) : repeatWindow;
        this.repeatWindow = window.compareTo(MIN_REPEAT_WINDOW) < 0 ? MIN_REPEAT_WINDOW
                : window.compareTo(MAX_REPEAT_WINDOW) > 0 ? MAX_REPEAT_WINDOW : window;
        // Clamped rather than refused: neither end of this can leak anything or lose anything that a
        // restart would not, so a mistyped value should not stop the service from starting.
        this.flushRows = Math.min(Math.max(flushRows, MIN_FLUSH_ROWS_SETTING), MAX_FLUSH_ROWS_SETTING);
        Duration hold = flushAfter == null ? DEFAULT_HOLD : flushAfter;
        this.holdFor = hold.isNegative() ? Duration.ZERO
                : hold.compareTo(MAX_HOLD) > 0 ? MAX_HOLD : hold;
    }

    /**
     * What one search asked for and what came back, as the recorder needs it.
     *
     * <p>Built on the request thread, where the pin and the caller are still in hand, and read on the
     * recorder's. Neither the pin nor the account survives the recording.
     *
     * @param accountId  the caller, used only to collapse their own repeats and never stored
     * @param term       the folded term, several joined by a space in slot order
     * @param pin        where the customer was, or null. Resolved to an area and discarded
     * @param shops      how many shops answered, across every page
     * @param nearest    metres to the nearest answering shop, or null
     * @param answering  the pins of the shops that answered, for "was one of them in my own area"
     * @param vertical   the scope the search was narrowed to, or null when it was not
     */
    public record Recording(String accountId, String term, GeoPoint pin, int shops, Double nearest,
                            List<GeoPoint> answering, String vertical) {

        public Recording {
            answering = answering == null ? List.of() : List.copyOf(answering);
        }
    }

    /**
     * Records one search, off this thread.
     *
     * <p>Returns at once and never throws — not for a full queue, not for a rejected executor, not
     * for anything the recording holds.
     */
    public void record(Recording recording) {
        try {
            if (recording == null || recording.term() == null || recording.term().isBlank()) {
                return;
            }
            Instant now = clock.instant();
            executor.execute(() -> write(recording, now));
        } catch (RejectedExecutionException e) {
            // The queue is full, which means the database is behind. A dropped demand row costs a
            // fraction of one week's count; a blocked request thread costs a customer their search.
            refused.incrementAndGet();
        } catch (RuntimeException e) {
            // Nothing here may reach the caller. Whatever it was, the search has already answered.
            refused.incrementAndGet();
            log.debug("Could not hand a search to the demand recorder", e);
        }
    }

    void write(Recording recording, Instant now) {
        try {
            UUID area = areas.areaOf(recording.pin()).orElse(null);
            if (isRepeat(recording.accountId(), area, recording.term(), now)) {
                repeats.incrementAndGet();
                return;
            }
            boolean inOwnArea = recording.shops() > 0 && areas.anyIn(recording.answering(), area);
            SearchDemandLog row = new SearchDemandLog(now, area, recording.term(),
                    recording.shops(), inOwnArea, recording.nearest(), recording.vertical());
            buffer.add(row);
            if (bufferedSince == null) {
                bufferedSince = now;
            }
            if (buffer.size() >= flushRows) {
                flush();
            }
        } catch (Throwable e) {
            // Including Errors: this thread is the platform's, and letting one die would stop every
            // later recording without a word. The search it describes was answered long ago.
            failed.incrementAndGet();
            log.debug("Could not record a search for the demand digest", e);
        }
    }

    /**
     * Writes the buffer if it has waited long enough, on the recorder's own thread.
     *
     * <p>Three states: not yet waited {@code flush-after}, so nothing happens; waited, and holding at
     * least {@value #MIN_FLUSH_ROWS} rows, so it goes; waited {@value #MAX_HOLD_MINUTES} minutes with
     * fewer than that, so it goes anyway — by then the rows span the hour their own timestamps name.
     */
    void flushIfDue() {
        if (buffer.isEmpty() || bufferedSince == null) {
            return;
        }
        Instant now = clock.instant();
        if (bufferedSince.plus(holdFor).isAfter(now)) {
            return;
        }
        if (buffer.size() < MIN_FLUSH_ROWS && bufferedSince.plus(MAX_HOLD).isAfter(now)) {
            return;
        }
        flush();
    }

    /**
     * Writes what is buffered, in an order that is not the order it happened in.
     *
     * <p>The shuffle is the whole point of the buffer: the rows are inserted in one transaction, in
     * one statement batch, so the heap holds them in the order this list is in — and this list has
     * been permuted. What a reader of {@code ctid} gets back is therefore which flush a row belonged
     * to, never where in it. {@link SecureRandom} rather than a seeded {@link java.util.Random}, so
     * the permutation cannot be recomputed by somebody who knows when the process started.
     *
     * <p>A flush that fails drops its rows rather than keeping them: the buffer is bounded by being
     * emptied, and a database that refused fifty rows will refuse them again.
     */
    private void flush() {
        if (buffer.isEmpty()) {
            return;
        }
        List<SearchDemandLog> rows = new ArrayList<>(buffer);
        buffer.clear();
        bufferedSince = null;
        Collections.shuffle(rows, shuffle);
        try {
            transaction.executeWithoutResult(status -> logs.saveAll(rows));
            written.addAndGet(rows.size());
        } catch (Throwable e) {
            failed.addAndGet(rows.size());
            log.debug("Could not write {} buffered searches for the demand digest", rows.size(), e);
        }
    }

    /** Asks the recorder's thread to consider a flush. Called by the ticker, never by it directly. */
    private void askForAFlush() {
        try {
            executor.execute(this::flushIfDue);
        } catch (RejectedExecutionException e) {
            // Every thread is busy writing; the next tick will ask again.
            log.debug("The demand recorder was too busy to be asked for a flush");
        } catch (RuntimeException e) {
            log.debug("Could not ask the demand recorder for a flush", e);
        }
    }

    /**
     * Whether this account has already had this term, in this neighbourhood, recorded inside the
     * window. Marks it seen when it has not.
     *
     * <p>A zero window turns this off, which is what a test that wants every row wants.
     */
    private boolean isRepeat(String accountId, UUID area, String term, Instant now) {
        if (accountId == null || accountId.isBlank() || repeatWindow.isZero()) {
            return false;
        }
        String key = accountId + ' ' + area + ' ' + term;
        Instant seen = lastSeen.put(key, now);
        return seen != null && seen.plus(repeatWindow).isAfter(now);
    }

    private static ExecutorService newPool() {
        AtomicInteger counter = new AtomicInteger();
        return new ThreadPoolExecutor(THREADS, THREADS, 60, TimeUnit.SECONDS,
                new ArrayBlockingQueue<>(QUEUE),
                runnable -> {
                    Thread thread = new Thread(runnable, "search-demand-" + counter.incrementAndGet());
                    thread.setDaemon(true);
                    return thread;
                },
                new ThreadPoolExecutor.AbortPolicy());
    }

    private static ScheduledExecutorService newTicker() {
        return Executors.newSingleThreadScheduledExecutor(runnable -> {
            Thread thread = new Thread(runnable, "search-demand-flush");
            thread.setDaemon(true);
            return thread;
        });
    }

    @Override
    public void destroy() {
        if (ticker != null) {
            ticker.shutdownNow();
        }
        if (!(executor instanceof ExecutorService pool)) {
            return;
        }
        try {
            // The buffer now holds up to an hour of rows, so a clean stop writes them: submitted
            // before the pool is closed to new work, and waited on briefly. What a kill -9 loses is
            // one flush, which is the price of not writing the sequence down.
            pool.execute(this::flush);
        } catch (RejectedExecutionException e) {
            log.debug("The demand recorder could not be asked for a last flush");
        }
        pool.shutdown();
        try {
            if (!pool.awaitTermination(SHUTDOWN_GRACE.toSeconds(), TimeUnit.SECONDS)) {
                pool.shutdownNow();
            }
        } catch (InterruptedException e) {
            pool.shutdownNow();
            Thread.currentThread().interrupt();
        }
    }

    /**
     * How many recordings were written, dropped for a full queue, dropped on failure, or collapsed,
     * and how many are waiting for a flush.
     */
    public record Counts(long written, long refused, long failed, long repeats, long waiting) {
    }

    public Counts counts() {
        return new Counts(written.get(), refused.get(), failed.get(), repeats.get(), buffer.size());
    }

    Duration repeatWindow() {
        return repeatWindow;
    }

    int flushRows() {
        return flushRows;
    }

    Duration holdFor() {
        return holdFor;
    }
}
