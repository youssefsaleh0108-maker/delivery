package com.delivery.whatsapp.config;

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
 * <p>Its own durable queue, not a shared one: the exchange is a topic and fans out, so binding here
 * takes nothing away from Order Tracking or Notifications Manager, which bind to the same keys.
 */
@Configuration(proxyBeanMethods = false)
public class WhatsAppRabbitConfiguration {

    @Bean
    public TopicExchange deliveryEventsExchange(
            @Value("${delivery.outbox.exchange:delivery.events}") String exchange) {
        return new TopicExchange(exchange, true, false);
    }

    @Bean
    public Queue whatsappOrderEventsQueue(
            @Value("${delivery.whatsapp.order-events-queue:whatsapp.order-events}") String name) {
        // Durable with a dead-letter target, so an event this service genuinely cannot handle is
        // kept for an operator rather than vanishing.
        return QueueBuilder.durable(name)
                .deadLetterExchange("")
                .deadLetterRoutingKey(name + ".dlq")
                .build();
    }

    @Bean
    public Queue whatsappOrderEventsDlq(
            @Value("${delivery.whatsapp.order-events-queue:whatsapp.order-events}") String name) {
        return QueueBuilder.durable(name + ".dlq").build();
    }

    /**
     * {@code order.#} — every order event, including types that do not exist yet.
     *
     * <p>Wider than what is acted on, deliberately. A narrower binding would need editing every time
     * Order Manager adds an event type, and the filtering it saves is one map lookup against a
     * status — see {@code OrderUpdateService.messageFor}, which returns null for everything the
     * customer does not need to hear about.
     */
    @Bean
    public Binding whatsappOrderEventsBinding(Queue whatsappOrderEventsQueue,
                                              TopicExchange deliveryEventsExchange) {
        return BindingBuilder.bind(whatsappOrderEventsQueue)
                .to(deliveryEventsExchange)
                .with("order.#");
    }
}
