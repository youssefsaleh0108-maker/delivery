package com.delivery.product.service;

import java.sql.SQLException;
import java.time.Clock;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.platform.outbox.OutboxRecorder;
import com.delivery.product.domain.SearchDemandDigest;
import com.delivery.product.domain.SearchDemandDigestRepository;
import com.delivery.product.domain.Store;
import com.delivery.product.event.DemandEvents;
import com.delivery.product.service.MerchantUnmetDemand.Term;

/**
 * Takes one merchant's week, or finds that somebody already took it.
 *
 * <p>A bean of its own rather than a method on {@link DemandDigestService}, because a scheduled loop
 * calling a transactional method on itself bypasses the proxy and would run the whole run in one
 * transaction — which is exactly the shape that makes a single unique-constraint violation roll back
 * every merchant that came before it.
 *
 * <p>The ledger row and the outbox event share one commit, and the unique key on (week, merchant) is
 * what makes the send idempotent: whoever inserts first sends, everybody else finds the row and does
 * nothing. Neither half can happen without the other, so there is no window where a merchant is
 * recorded as told and never told, or told and never recorded.
 */
@Service
public class DemandDigestClaim {

    private static final Logger log = LoggerFactory.getLogger(DemandDigestClaim.class);

    private final SearchDemandDigestRepository digests;
    private final OutboxRecorder outbox;
    private final Clock clock;

    public DemandDigestClaim(SearchDemandDigestRepository digests, OutboxRecorder outbox,
                             Clock clock) {
        this.digests = digests;
        this.outbox = outbox;
        this.clock = clock;
    }

    /** PostgreSQL's unique_violation: somebody else has this merchant's week. */
    private static final String UNIQUE_VIOLATION = "23505";

    /**
     * @return true when this run is the one that told them
     */
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public boolean claimAndRaise(Instant weekStart, String merchantId, Store shop, List<Term> terms) {
        try {
            digests.saveAndFlush(
                    new SearchDemandDigest(weekStart, merchantId, terms.size(), clock.instant()));
            outbox.record(DemandEvents.AGGREGATE_TYPE, merchantId, DemandEvents.DIGEST_WEEKLY,
                    payload(weekStart, merchantId, shop, terms));
            return true;
        } catch (RuntimeException e) {
            if (!alreadyTaken(e)) {
                throw e;
            }
            // Another replica claimed this merchant's week between the check and the insert. That is
            // the constraint doing its job, not a failure.
            log.debug("The week of {} was already claimed for merchant {}", weekStart, merchantId);
            return false;
        }
    }

    /**
     * Whether {@code e} is the unique key refusing a second claim.
     *
     * <p>Read off the driver's own SQLState rather than off an exception type, the way
     * {@code ItemSearchService} reads a cancelled statement: which wrapper arrives depends on
     * whether Spring's exception translation is in the way, and the fact worth branching on is the
     * database's, not the wrapper's. Bounded, in case a chain of causes loops.
     */
    static boolean alreadyTaken(Throwable e) {
        Throwable cause = e;
        for (int depth = 0; cause != null && depth < 32; depth++, cause = cause.getCause()) {
            if (cause instanceof DataIntegrityViolationException
                    || cause instanceof SQLException sql && UNIQUE_VIOLATION.equals(sql.getSQLState())) {
                return true;
            }
        }
        return false;
    }

    private static DemandEvents.WeeklyDigest payload(Instant weekStart, String merchantId, Store shop,
                                                     List<Term> terms) {
        List<DemandEvents.UnmetTerm> lines = new ArrayList<>();
        String region = null;
        for (Term term : terms) {
            lines.add(new DemandEvents.UnmetTerm(term.term(), term.about(), term.areaName(),
                    term.kind().name()));
            if (region == null) {
                region = term.region();
            }
        }
        return new DemandEvents.WeeklyDigest(merchantId, shop.getId(), weekStart, region, lines);
    }
}
