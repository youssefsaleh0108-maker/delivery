package com.delivery.product.service;

import java.time.Instant;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.event.EventListener;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/**
 * The demand digest's clockwork: roll the week up, forget old searches, send the week's messages.
 *
 * <p><strong>Every step is idempotent instead of locked.</strong> The roll-up deletes a week and
 * writes it again; retention deletes by a cutoff; the send claims each merchant on a unique key. Two
 * replicas running any of them at the same moment waste a few milliseconds and cannot corrupt
 * anything — the same bargain {@code TrackingPartitionMaintenance} makes, and a better one than
 * adding a distributed lock the platform does not otherwise have.
 *
 * <p><strong>Nothing here ever throws.</strong> An exception out of a scheduled method cancels every
 * future run of that schedule, silently: the digest would simply stop one week and nobody would
 * notice until a merchant asked. So each entry point catches everything and logs.
 *
 * <p><strong>In the platform's calendar</strong> ({@link DemandWeeks}). The crons are read in
 * {@code delivery.platform.zone}, so "Monday morning" is Monday morning in Beirut whatever zone the
 * pod's clock is in — the whole point of a weekly digest is that its week is the merchant's week.
 *
 * <p>The roll-up runs daily rather than weekly even though the boundaries are weekly: the merchant's
 * screen shows "this week and last", and a week in progress that only refreshed on Mondays would be
 * six days stale by Sunday. It recomputes the finished week too, which is how a late-arriving row or
 * a fixed bug reaches the numbers without anybody running anything by hand.
 */
@Component
public class SearchDemandMaintenance {

    private static final Logger log = LoggerFactory.getLogger(SearchDemandMaintenance.class);

    private final UnmetDemand unmet;
    private final DemandDigestService digests;

    public SearchDemandMaintenance(UnmetDemand unmet, DemandDigestService digests) {
        this.unmet = unmet;
        this.digests = digests;
    }

    /**
     * Rolls up the week in progress and the week that finished, and forgets searches past retention.
     *
     * <p>Before dawn, when the storefront is quiet: the roll-up is an aggregate over a week of
     * searches and retention is a delete across the table, and neither should compete with a lunchtime
     * rush for the connections the catalogue shares.
     */
    @Scheduled(cron = "${delivery.demand.rollup-cron:0 20 3 * * *}",
            zone = "${delivery.platform.zone:Asia/Beirut}")
    public void rollUp() {
        try {
            int terms = unmet.rollUpRecentWeeks();
            int forgotten = unmet.forgetOldSearches();
            log.debug("Demand roll-up: {} terms over two weeks, {} rows forgotten", terms, forgotten);
        } catch (Exception e) {
            // Never propagate: see the class comment.
            log.error("The demand roll-up failed; the week's numbers will be a day stale", e);
        }
    }

    /**
     * Sends the week's digests, on Monday morning in the platform's zone.
     *
     * <p>After the roll-up's hour, so the week being reported on was recomputed a few hours earlier
     * on the same day. Monday at nine is when a shopkeeper decides what to order, which is the whole
     * point of telling them then.
     */
    @Scheduled(cron = "${delivery.demand.digest-cron:0 0 9 * * MON}",
            zone = "${delivery.platform.zone:Asia/Beirut}")
    public void sendWeeklyDigests() {
        try {
            Instant week = digests.weekToReport();
            // The week is rolled up again first, so a digest never reports numbers that were never
            // computed — a pod that was down on Sunday night would otherwise send an empty week.
            unmet.rollUp(week);
            digests.sendFor(week);
        } catch (Exception e) {
            log.error("The weekly demand digest failed; it will be tried again next week, and a "
                    + "re-run of this week sends nothing to anybody already told", e);
        }
    }

    /**
     * Catches up on a boot: a pod that was down when the roll-up was due brings the numbers forward
     * as soon as it is back, rather than leaving a merchant looking at last Tuesday.
     *
     * <p>Only the roll-up, never the send. Sending on start-up would make a rolling deploy on a
     * Monday morning a second attempt at the week — which the ledger would refuse, but a job that
     * relies on being refused is one bug away from a merchant's phone.
     */
    @EventListener(ApplicationReadyEvent.class)
    public void onStartup() {
        rollUp();
    }
}
