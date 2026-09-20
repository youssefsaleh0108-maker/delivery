package com.delivery.product.service;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.Optional;
import java.util.concurrent.atomic.AtomicReference;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.product.domain.PhotoSearchUse;
import com.delivery.product.domain.PhotoSearchUse.Kind;
import com.delivery.product.domain.PhotoSearchUseRepository;
import com.delivery.product.service.PhotoSearchException.Scope;

/**
 * How many photos an account may have read: the cost guard in front of a paid vision call.
 *
 * <p>Once real recognition is on, every photo read is a call to Claude of a few cents
 * ({@code application.yml}, {@code delivery.catalog.photo-search}). So each use is counted before the
 * call is made, and refused past:
 * <ul>
 *   <li>{@code per-customer-per-day} (10) customer searches per account over a rolling day, or
 *       {@code merchant-per-day} (30) finds by photo for a merchant;
 *   <li>{@code per-account-per-minute} (3) of either kind in a minute, so a stuck button or a script
 *       cannot spend the day's allowance in one burst;
 *   <li>{@code platform-per-day} (1,000) customer searches across the whole platform over a rolling day,
 *       and {@code merchant-platform-per-day} (500) finds by photo across it, which together bound the
 *       whole bill however many accounts there are. Each kind has its own platform day, so a run of
 *       merchants' finds can neither be spent by customers nor spend what customers are allowed.
 * </ul>
 * Rolling rather than per calendar day, as Blitz's quota is, so a burst cannot straddle midnight to
 * double it.
 *
 * <p><strong>One short transaction</strong> ({@link #take}), under a transaction-scoped advisory lock on
 * the account ({@link PhotoSearchUseRepository#lockAccount}, the pattern of
 * {@code CatalogScanRepository#lockMerchant}), so three photos sent at once cannot all see room for
 * one more; the platform's lock is then taken, after the account's and in that order for both kinds,
 * for the platform count. Every {@link #SWEEP_EVERY}, and before the lock rather than under it, the
 * same transaction also deletes the uses no window counts any more, so the table never holds much
 * more than two days of them. The caller makes the paid call afterwards, outside it: a pooled
 * connection held across a 25-second call is one taken from every storefront.
 *
 * <p>A use is counted just before the reader is asked — after the photo was accepted and decoded, and
 * after a slot to read it was found — so a refusal for size, type or a busy reader costs the account
 * nothing. A read that then fails still counts: the call was made.
 */
@Component
public class PhotoQuota {

    private static final Logger log = LoggerFactory.getLogger(PhotoQuota.class);

    /** The longest window a limit counts over. */
    static final Duration DAY = Duration.ofHours(24);

    /** The burst window. */
    static final Duration MINUTE = Duration.ofMinutes(1);

    /** Uses older than this answer no limit and are deleted. Twice the longest window, for slack. */
    public static final Duration KEEP = Duration.ofHours(48);

    /**
     * How often one instance sweeps rows no window counts any more.
     *
     * <p>Not once per photo, which is what it was: {@link #sweep} is a delete across the whole table,
     * and running it under an account's lock made every photo pay for every other account's old rows,
     * and made two accounts' photos contend on rows neither of them owns. Not {@code @Scheduled}
     * either, for the reason {@code GeocodeCache#evictStale} gives — several replicas, no scheduler
     * lock. Ten minutes leaves the table at most a few rows past two days deep, since a row is only
     * written when a photo is really read.
     */
    public static final Duration SWEEP_EVERY = Duration.ofMinutes(10);

    /** The limits, clamped to at least one each: a zero in the configuration must not refuse everything. */
    public record Limits(int perCustomerPerDay, int perAccountPerMinute, int platformPerDay,
                         int merchantPerDay, int merchantPlatformPerDay) {

        public Limits {
            perCustomerPerDay = Math.max(perCustomerPerDay, 1);
            perAccountPerMinute = Math.max(perAccountPerMinute, 1);
            platformPerDay = Math.max(platformPerDay, 1);
            merchantPerDay = Math.max(merchantPerDay, 1);
            merchantPlatformPerDay = Math.max(merchantPlatformPerDay, 1);
        }

        /** The whole platform's day for this kind of use. */
        int platformPerDay(Kind kind) {
            return kind == Kind.MERCHANT_FIND ? merchantPlatformPerDay : platformPerDay;
        }
    }

    private final PhotoSearchUseRepository uses;
    private final Clock clock;
    private final Limits limits;

    /** When this instance last swept. Epoch, so the first photo after a start sweeps once. */
    private final AtomicReference<Instant> sweptAt = new AtomicReference<>(Instant.EPOCH);

    @Autowired
    public PhotoQuota(PhotoSearchUseRepository uses, Clock clock,
                      @Value("${delivery.catalog.photo-search.per-customer-per-day:10}") int perCustomerPerDay,
                      @Value("${delivery.catalog.photo-search.per-account-per-minute:3}") int perAccountPerMinute,
                      @Value("${delivery.catalog.photo-search.platform-per-day:1000}") int platformPerDay,
                      @Value("${delivery.catalog.photo-search.merchant-per-day:30}") int merchantPerDay,
                      @Value("${delivery.catalog.photo-search.merchant-platform-per-day:500}")
                      int merchantPlatformPerDay) {
        this(uses, clock, new Limits(perCustomerPerDay, perAccountPerMinute, platformPerDay,
                merchantPerDay, merchantPlatformPerDay));
    }

    public PhotoQuota(PhotoSearchUseRepository uses, Clock clock, Limits limits) {
        this.uses = uses;
        this.clock = clock;
        this.limits = limits;
    }

    /** The day's limit for this kind of use. */
    public int perDay(Kind kind) {
        return kind == Kind.MERCHANT_FIND ? limits.merchantPerDay() : limits.perCustomerPerDay();
    }

    /**
     * Counts one use by {@code accountId}, or refuses it.
     *
     * @return how many more uses of this kind the account has over the rolling day, after this one
     * @throws PhotoSearchException a 429 ({@code PHOTO_SEARCH_LIMIT} or {@code PHOTO_FIND_LIMIT}) with
     *                              the limit, which one, and how many seconds until the next use is
     *                              allowed; nothing is counted
     */
    @Transactional
    public int take(String accountId, Kind kind) {
        Instant now = clock.instant();
        // Before the lock is taken, and only when it is due: nothing this deletes is counted by any
        // window below, so its only job is to keep the table small, and it has no business holding an
        // account's lock while it does it.
        sweepIfDue(now);
        uses.lockAccount(accountId);
        boolean merchant = kind == Kind.MERCHANT_FIND;

        int perDay = perDay(kind);
        Instant dayAgo = now.minus(DAY);
        long today = uses.countByAccountIdAndKindAndCreatedAtAfter(accountId, kind, dayAgo);
        if (today >= perDay) {
            throw PhotoSearchException.limit(merchant, perDay, Scope.DAY, secondsUntilFree(
                    uses.findFirstByAccountIdAndKindAndCreatedAtAfterOrderByCreatedAtAsc(accountId, kind,
                            dayAgo), DAY, now));
        }

        Instant minuteAgo = now.minus(MINUTE);
        long lastMinute = uses.countByAccountIdAndKindAndCreatedAtAfter(accountId, kind, minuteAgo);
        if (lastMinute >= limits.perAccountPerMinute()) {
            throw PhotoSearchException.limit(merchant, limits.perAccountPerMinute(), Scope.MINUTE,
                    secondsUntilFree(uses.findFirstByAccountIdAndKindAndCreatedAtAfterOrderByCreatedAtAsc(
                            accountId, kind, minuteAgo), MINUTE, now));
        }

        // Both kinds, each against its own platform day: a merchant's find costs the same call to the
        // same provider as a customer's search, so leaving merchants uncapped would leave the bill
        // bounded only by how many merchants there are.
        int platformPerDay = limits.platformPerDay(kind);
        // After the account's own lock, never before, and in that order for both kinds, so they
        // cannot deadlock.
        uses.lockPlatform();
        long platform = uses.countByKindAndCreatedAtAfter(kind, dayAgo);
        if (platform >= platformPerDay) {
            log.warn("{} has reached the platform's {} photos in 24 hours",
                    merchant ? "Merchant find by photo" : "Customer photo search", platformPerDay);
            throw PhotoSearchException.limit(merchant, platformPerDay, Scope.PLATFORM,
                    secondsUntilFree(uses.findFirstByKindAndCreatedAtAfterOrderByCreatedAtAsc(kind,
                            dayAgo), DAY, now));
        }

        uses.save(new PhotoSearchUse(accountId, kind, now));
        return (int) Math.max(0, perDay - today - 1);
    }

    /**
     * Deletes the uses no window counts any more, if this instance has not done so for
     * {@link #SWEEP_EVERY}. One thread wins the turn; the rest go straight on to their photo.
     */
    private void sweepIfDue(Instant now) {
        Instant last = sweptAt.get();
        if (now.isBefore(last.plus(SWEEP_EVERY)) || !sweptAt.compareAndSet(last, now)) {
            return;
        }
        sweep(now);
    }

    /**
     * Deletes every use older than {@link #KEEP}, whoever's it is.
     *
     * <p>Public so an operator or a future single-runner job can call it, as
     * {@code GeocodeCache#evictStale} is. Joins the caller's transaction when there is one, which is
     * what {@link #take} wants of it.
     */
    @Transactional
    public void sweep(Instant now) {
        uses.deleteOlderThan(now.minus(KEEP));
    }

    /** How many uses of this kind the account has left over the rolling day, without counting one. */
    @Transactional(readOnly = true)
    public int left(String accountId, Kind kind) {
        long today = uses.countByAccountIdAndKindAndCreatedAtAfter(accountId, kind,
                clock.instant().minus(DAY));
        return (int) Math.max(0, perDay(kind) - today);
    }

    /** Whole seconds until the oldest use in the window leaves it; at least one. */
    private static long secondsUntilFree(Optional<PhotoSearchUse> oldest, Duration window, Instant now) {
        if (oldest.isEmpty()) {
            return 1L;
        }
        Duration wait = Duration.between(now, oldest.get().getCreatedAt().plus(window));
        long seconds = wait.getSeconds() + (wait.getNano() > 0 ? 1 : 0);
        return Math.max(1L, seconds);
    }
}
