package com.delivery.product.config;

import org.springframework.amqp.core.Binding;
import org.springframework.amqp.core.BindingBuilder;
import org.springframework.amqp.core.Queue;
import org.springframework.amqp.core.QueueBuilder;
import org.springframework.amqp.core.TopicExchange;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * This service's queue off the shared domain-event exchange.
 *
 * <p>Product Service was publish-only until reviews needed to know which orders were actually
 * delivered. Its own queue, like every other consumer's — the exchange fans out, so binding
 * {@code order.#} here gives this service a full copy rather than competing with the notification
 * layer or the settlement saga for messages.
 *
 * <p>Bound on the wildcard with the filtering done in the listener, matching the accounting
 * service's reasoning: a future event that ought to affect what is reviewable — an order reversed
 * after a dispute — arrives without a broker change.
 */
@Configuration(proxyBeanMethods = false)
public class ProductRabbitConfiguration {

    @Bean
    public TopicExchange deliveryEventsExchange(
            @Value("${delivery.outbox.exchange:delivery.events}") String exchange) {
        return new TopicExchange(exchange, true, false);
    }

    @Bean
    public Queue productOrderEventsQueue(
            @Value("${delivery.product.order-events-queue:product.order-events}") String name) {
        return QueueBuilder.durable(name)
                .deadLetterExchange("")
                .deadLetterRoutingKey(name + ".dlq")
                .build();
    }

    @Bean
    public Queue productOrderEventsDlq(
            @Value("${delivery.product.order-events-queue:product.order-events}") String name) {
        return QueueBuilder.durable(name + ".dlq").build();
    }

    @Bean
    public Binding productOrderEventsBinding(Queue productOrderEventsQueue,
                                             TopicExchange deliveryEventsExchange) {
        return BindingBuilder.bind(productOrderEventsQueue)
                .to(deliveryEventsExchange)
                .with("order.#");
    }
}
