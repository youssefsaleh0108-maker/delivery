package com.delivery.tracking.config;

import org.springframework.amqp.core.Binding;
import org.springframework.amqp.core.BindingBuilder;
import org.springframework.amqp.core.Queue;
import org.springframework.amqp.core.QueueBuilder;
import org.springframework.amqp.core.TopicExchange;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * Binds this service's own queue to the shared domain-event exchange.
 *
 * <p>Each consumer declares its own durable queue rather than sharing one: a topic exchange fans
 * out, so Notifications Manager (Phase 3) binding to the same routing keys will get its own copy
 * without competing with tracking for messages.
 */
@Configuration(proxyBeanMethods = false)
public class TrackingRabbitConfiguration {

    @Bean
    public TopicExchange deliveryEventsExchange(
            @Value("${delivery.outbox.exchange:delivery.events}") String exchange) {
        return new TopicExchange(exchange, true, false);
    }

    @Bean
    public Queue trackingOrderEventsQueue(
            @Value("${delivery.tracking.order-events-queue:tracking.order-events}") String name) {
        // Durable, and with a dead-letter target so a message this service genuinely cannot handle
        // is retained for an operator instead of vanishing (Section 10).
        return QueueBuilder.durable(name)
                .deadLetterExchange("")
                .deadLetterRoutingKey(name + ".dlq")
                .build();
    }

    @Bean
    public Queue trackingOrderEventsDlq(
            @Value("${delivery.tracking.order-events-queue:tracking.order-events}") String name) {
        return QueueBuilder.durable(name + ".dlq").build();
    }

    /**
     * {@code order.#} — every order event, including types that do not exist yet. Binding to the
     * wildcard means a new event type in Order Manager reaches this projection without a matching
     * change here.
     */
    @Bean
    public Binding trackingOrderEventsBinding(Queue trackingOrderEventsQueue,
                                              TopicExchange deliveryEventsExchange) {
        return BindingBuilder.bind(trackingOrderEventsQueue)
                .to(deliveryEventsExchange)
                .with("order.#");
    }
}
