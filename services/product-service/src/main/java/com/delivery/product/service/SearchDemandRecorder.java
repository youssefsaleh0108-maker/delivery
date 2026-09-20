package com.delivery.product.service;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.Executor;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.RejectedExecutionException;
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

    private final SearchDemandLogRepository logs;
    private final CoarseAreas areas;
    private final Clock clock;
    private final Executor executor;
    private final TransactionTemplate transaction;
    private final Duration repeatWindow;

    /** Dropped because the queue was full, and dropped because the write failed. For tests and logs. */
    private final AtomicLong refused = new AtomicLong();
    private final AtomicLong failed = new AtomicLong();
    private final AtomicLong written = new AtomicLong();
    private final AtomicLong repeats = new AtomicLong();

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
                                Duration repeatWindow) {
        this(logs, areas, clock, transactionManager, newPool(), repeatWindow);
    }

    /**
     * A caller-supplied executor, usually one that runs inline. For tests, as {@code PhotoQuota}'s
     * second constructor is: the pool is the only part of this class a test cannot assert against
     * directly, and the thing worth asserting about it — that {@link #record} returns before the
     * write happens — needs an executor that does not run inline.
     */
    public SearchDemandRecorder(SearchDemandLogRepository logs, CoarseAreas areas, Clock clock,
                                PlatformTransactionManager transactionManager, Executor executor,
                                Duration repeatWindow) {
        this.logs = logs;
        this.areas = areas;
        this.clock = clock;
        this.executor = executor;
        // A transaction of its own, started on the background thread: the search's own transaction
        // is read-only and, by the time this runs, closed. REQUIRES_NEW says so out loud.
        this.transaction = new TransactionTemplate(transactionManager);
        this.transaction.setPropagationBehavior(TransactionDefinition.PROPAGATION_REQUIRES_NEW);
        Duration window = repeatWindow == null ? Duration.ofMinutes(30) : repeatWindow;
        this.repeatWindow = window.compareTo(MIN_REPEAT_WINDOW) < 0 ? MIN_REPEAT_WINDOW
                : window.compareTo(MAX_REPEAT_WINDOW) > 0 ? MAX_REPEAT_WINDOW : window;
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
            transaction.executeWithoutResult(status -> logs.save(row));
            written.incrementAndGet();
        } catch (Throwable e) {
            // Including Errors: this thread is the platform's, and letting one die would stop every
            // later recording without a word. The search it describes was answered long ago.
            failed.incrementAndGet();
            log.debug("Could not record a search for the demand digest", e);
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
        String key = accountId + ' ' + area + ' ' + term;
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

    @Override
    public void destroy() {
        if (executor instanceof ExecutorService pool) {
            // Not waited on. A recording lost to a rolling update is one search missing from one
            // week's count, and holding the shutdown open for it would be the wrong trade.
            pool.shutdownNow();
        }
    }

    /** How many recordings were written, dropped for a full queue, dropped on failure, or collapsed. */
    public record Counts(long written, long refused, long failed, long repeats) {
    }

    public Counts counts() {
        return new Counts(written.get(), refused.get(), failed.get(), repeats.get());
    }

    Duration repeatWindow() {
        return repeatWindow;
    }
}
