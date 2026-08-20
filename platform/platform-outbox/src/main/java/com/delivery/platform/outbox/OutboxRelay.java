package com.delivery.platform.outbox;

import java.nio.charset.StandardCharsets;
import java.util.Date;
import java.util.List;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.core.MessageDeliveryMode;
import org.springframework.amqp.core.MessageProperties;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.transaction.annotation.Transactional;

/**
 * Moves committed outbox rows onto the message bus.
 *
 * <p>Delivery is <strong>at-least-once</strong>, by design. If the broker accepts a message and this
 * transaction then fails to commit the {@code PUBLISHED} flag, the next tick republishes it. Every
 * consumer must therefore be idempotent — which is why each message carries the outbox row's UUID as
 * its {@code messageId}, giving consumers a natural dedupe key. The alternative (marking published
 * before sending) would trade duplicates for silent loss, and Section 7 asks for the opposite.
 */
public class OutboxRelay {

    private static final Logger log = LoggerFactory.getLogger(OutboxRelay.class);

    private final OutboxEventRepository repository;
    private final RabbitTemplate rabbitTemplate;
    private final OutboxProperties properties;

    public OutboxRelay(OutboxEventRepository repository, RabbitTemplate rabbitTemplate,
                       OutboxProperties properties) {
        this.repository = repository;
        this.rabbitTemplate = rabbitTemplate;
        this.properties = properties;
    }

    @Scheduled(fixedDelayString = "${delivery.outbox.poll-interval:PT2S}")
    @Transactional
    public void publishPending() {
        List<OutboxEvent> batch = repository.claimPendingBatch(properties.getBatchSize());
        if (batch.isEmpty()) {
            return;
        }

        int published = 0;
        for (OutboxEvent event : batch) {
            try {
                rabbitTemplate.send(properties.getExchange(), event.getEventType(), toMessage(event));
                event.markPublished();
                published++;
            } catch (Exception e) {
                // Caught per-event so one poison message cannot stall the whole batch behind it.
                event.markFailed(e.getMessage(), properties.getMaxAttempts(),
                        properties.getRetryBackoff(), properties.getMaxRetryBackoff());
                if (event.getStatus() == OutboxEvent.Status.DEAD_LETTERED) {
                    log.error("Outbox event {} ({}) dead-lettered after {} attempts",
                            event.getId(), event.getEventType(), event.getAttempts(), e);
                } else {
                    log.warn("Outbox event {} ({}) publish attempt {} failed, retrying at {}",
                            event.getId(), event.getEventType(), event.getAttempts(),
                            event.getNextAttemptAt(), e);
                }
            }
        }
        repository.saveAll(batch);
        log.debug("Outbox relay published {}/{} events", published, batch.size());
    }

    private Message toMessage(OutboxEvent event) {
        MessageProperties properties = new MessageProperties();
        properties.setContentType(MessageProperties.CONTENT_TYPE_JSON);
        properties.setContentEncoding(StandardCharsets.UTF_8.name());
        // The outbox row id is the consumer's dedupe key — see the at-least-once note above.
        properties.setMessageId(event.getId().toString());
        properties.setTimestamp(Date.from(event.getCreatedAt()));
        properties.setDeliveryMode(MessageDeliveryMode.PERSISTENT);
        properties.setHeader("eventType", event.getEventType());
        properties.setHeader("aggregateType", event.getAggregateType());
        properties.setHeader("aggregateId", event.getAggregateId());

        if (event.getCorrelationId() != null) {
            properties.setCorrelationId(event.getCorrelationId());
            properties.setHeader(CorrelationId.HEADER, event.getCorrelationId());
        }
        return new Message(event.getPayload().getBytes(StandardCharsets.UTF_8), properties);
    }
}
