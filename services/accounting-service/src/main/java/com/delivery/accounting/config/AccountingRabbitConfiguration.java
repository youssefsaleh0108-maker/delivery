package com.delivery.accounting.config;

import org.springframework.amqp.core.Binding;
import org.springframework.amqp.core.BindingBuilder;
import org.springframework.amqp.core.Queue;
import org.springframework.amqp.core.QueueBuilder;
import org.springframework.amqp.core.TopicExchange;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * This service's queues off the shared domain-event exchange.
 *
 * <p>Its own, not shared with Order Tracking's or the notification layer's. The exchange fans out,
 * so all three bind {@code order.#} and each gets a full copy; competing consumers on one queue
 * would mean some orders were tracked, some were notified about, and some were settled.
 */
@Configuration(proxyBeanMethods = false)
public class AccountingRabbitConfiguration {

    @Bean
    public TopicExchange deliveryEventsExchange(
            @Value("${delivery.outbox.exchange:delivery.events}") String exchange) {
        return new TopicExchange(exchange, true, false);
    }

    @Bean
    public Queue accountingOrderEventsQueue(
            @Value("${delivery.accounting.order-events-queue:accounting.order-events}") String name) {
        return QueueBuilder.durable(name)
                .deadLetterExchange("")
                .deadLetterRoutingKey(name + ".dlq")
                .build();
    }

    @Bean
    public Queue accountingOrderEventsDlq(
            @Value("${delivery.accounting.order-events-queue:accounting.order-events}") String name) {
        return QueueBuilder.durable(name + ".dlq").build();
    }

    /**
     * Bound to {@code order.#} rather than only {@code order.delivered}.
     *
     * <p>The listener filters. Binding the wildcard means a future event that ought to settle
     * something — a partial refund, a dispute resolution — reaches this service without a broker
     * change, at the cost of a few ignored messages.
     */
    @Bean
    public Binding accountingOrderEventsBinding(Queue accountingOrderEventsQueue,
                                                TopicExchange deliveryEventsExchange) {
        return BindingBuilder.bind(accountingOrderEventsQueue)
                .to(deliveryEventsExchange)
                .with("order.#");
    }

    @Bean
    public Queue accountingResultsQueue(
            @Value("${delivery.accounting.results-queue:accounting.posting-results}") String name) {
        return QueueBuilder.durable(name)
                .deadLetterExchange("")
                .deadLetterRoutingKey(name + ".dlq")
                .build();
    }

    @Bean
    public Queue accountingResultsDlq(
            @Value("${delivery.accounting.results-queue:accounting.posting-results}") String name) {
        return QueueBuilder.durable(name + ".dlq").build();
    }

    @Bean
    public Binding accountingResultsBinding(Queue accountingResultsQueue,
                                            TopicExchange deliveryEventsExchange) {
        return BindingBuilder.bind(accountingResultsQueue)
                .to(deliveryEventsExchange)
                .with("accounting.posting.result");
    }
}
