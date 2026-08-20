package com.delivery.whatsapp.service;

import java.util.UUID;

import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.whatsapp.domain.OrderUpdate;
import com.delivery.whatsapp.repo.OrderUpdateRepository;

/**
 * Which order updates have already been sent.
 *
 * <p><strong>Its own bean on purpose.</strong> {@link OrderUpdateService} calls this, and a
 * {@code REQUIRES_NEW} method called from within its own class goes straight through the object
 * rather than the proxy — the annotation is quietly ignored and the boundary that was supposed to
 * exist does not. Putting the claim behind a separate bean makes the transaction real no matter how
 * its caller later evolves.
 */
@Component
public class OrderUpdateLog {

    private final OrderUpdateRepository updates;

    public OrderUpdateLog(OrderUpdateRepository updates) {
        this.updates = updates;
    }

    /**
     * Records that this order/status pair is ours to send, or reports that somebody already did.
     *
     * <p>Commits before the send is attempted, rather than holding a transaction open across a call
     * to a third party. The composite primary key is the real guarantee — two concurrent
     * redeliveries would both pass a read-then-write check.
     *
     * @return true if this call won the right to send
     */
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public boolean claim(UUID orderId, String status, UUID conversationId) {
        try {
            updates.saveAndFlush(new OrderUpdate(orderId, status, conversationId));
            return true;
        } catch (DataIntegrityViolationException e) {
            // The key did its job. Not an error — this is the mechanism working.
            return false;
        }
    }
}
