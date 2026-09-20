package com.delivery.accounting.service;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.accounting.domain.SettlementFailure;
import com.delivery.accounting.domain.SettlementFailureRepository;

/**
 * The settlements this service could not make and will not retry (RECON-04).
 *
 * <p>Writing them down is the whole point: the listener used to catch every exception and return,
 * so a settlement that failed left no trace anywhere — not in the ledger, which is what every
 * reconciliation view reads, and not on any queue. Dev has carried two such orders since
 * 2026-09-08 with nobody able to see them.
 */
@Service
public class SettlementFailures implements SettlementFailureLog {

    private static final Logger log = LoggerFactory.getLogger(SettlementFailures.class);

    /** The most rows one listing returns. A work list, not an archive. */
    private static final int MAX_ROWS = 200;

    private final SettlementFailureRepository failures;

    public SettlementFailures(SettlementFailureRepository failures) {
        this.failures = failures;
    }

    /**
     * Records a settlement that will not happen on its own.
     *
     * <p>In its own transaction: the settlement that failed may have taken its own down with it, and
     * a record that rolls back with the failure it describes is no record at all.
     *
     * <p>A redelivery of the same message updates the order's open row rather than adding another,
     * and a row lost to the race between two of them is not worth failing a listener over — the
     * unsettled-deliveries check finds the order either way.
     */
    @Override
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void record(UUID orderId, String eventType, String reason, String payload,
                       String correlationId) {
        try {
            Optional<SettlementFailure> open = orderId == null
                    ? Optional.empty()
                    : failures.findByOrderIdAndResolvedAtIsNull(orderId);
            if (open.isPresent()) {
                open.get().seenAgain(reason);
                failures.save(open.get());
                return;
            }
            failures.save(new SettlementFailure(orderId, eventType, reason, payload,
                    correlationId));
        } catch (DataIntegrityViolationException e) {
            log.debug("Another delivery of order {} recorded the same failure first", orderId);
        }
    }

    @Transactional(readOnly = true)
    public List<SettlementFailure> open(int limit) {
        return failures.findByResolvedAtIsNullOrderByLastSeenAtDesc(
                PageRequest.of(0, Math.max(1, Math.min(limit, MAX_ROWS))));
    }

    @Transactional(readOnly = true)
    public long openCount() {
        return failures.countByResolvedAtIsNull();
    }

    /**
     * Closes an order's open row, if it has one.
     *
     * <p>Called when the order settles — by hand from the Back Office, or by a later redelivery
     * that worked — so the work list empties itself as the work is done.
     */
    @Transactional
    public void resolve(UUID orderId, String by, String resolution) {
        failures.findByOrderIdAndResolvedAtIsNull(orderId).ifPresent(failure -> {
            failure.resolve(by, resolution);
            failures.save(failure);
            log.info("Settlement failure on order {} resolved by {}: {}", orderId, by, resolution);
        });
    }
}
