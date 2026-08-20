package com.delivery.platform.outbox;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * The only supported way for a domain service to emit an event.
 *
 * <p>Section 7 is explicit that Order Manager, Order Tracking and Product Service never publish
 * directly from application code. Calling this inside an existing {@code @Transactional} method
 * makes the event part of the same commit as the state change: either both land or neither does.
 *
 * <p>{@link Propagation#MANDATORY} enforces that at runtime — recording an event outside a
 * transaction is a programming error, and failing loudly beats silently reintroducing the dual-write
 * gap the outbox exists to close.
 */
public class OutboxRecorder {

    private static final Logger log = LoggerFactory.getLogger(OutboxRecorder.class);

    private final OutboxEventRepository repository;
    private final ObjectMapper objectMapper;

    public OutboxRecorder(OutboxEventRepository repository, ObjectMapper objectMapper) {
        this.repository = repository;
        this.objectMapper = objectMapper;
    }

    /**
     * Records an event to be published after the current transaction commits.
     *
     * @param aggregateType the entity kind, e.g. {@code Order}
     * @param aggregateId   that entity's id
     * @param eventType     the event name, e.g. {@code order.placed} — also the bus routing key
     * @param payload       any Jackson-serialisable object
     */
    @Transactional(propagation = Propagation.MANDATORY)
    public OutboxEvent record(String aggregateType, String aggregateId, String eventType, Object payload) {
        String json;
        try {
            json = objectMapper.writeValueAsString(payload);
        } catch (JsonProcessingException e) {
            // Deliberately fatal: this rolls back the caller's business transaction too. An event
            // we cannot serialise is a bug, and committing the state change without it would leave
            // the rest of the platform permanently out of sync with this service.
            throw new IllegalArgumentException(
                    "Could not serialise outbox payload for event " + eventType, e);
        }

        OutboxEvent event = new OutboxEvent(
                aggregateType, aggregateId, eventType, json, CorrelationId.current());
        log.debug("Recorded outbox event {} for {}:{}", eventType, aggregateType, aggregateId);
        return repository.save(event);
    }
}
