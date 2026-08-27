package com.delivery.notifications.config;

import org.springframework.amqp.core.Binding;
import org.springframework.amqp.core.BindingBuilder;
import org.springframework.amqp.core.Queue;
import org.springframework.amqp.core.QueueBuilder;
import org.springframework.amqp.core.TopicExchange;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import com.delivery.platform.notifications.DeliveryReceipt;
import com.delivery.platform.notifications.ProviderDeliveryReceipt;

/**
 * The manager's two queues off the shared domain-event exchange.
 *
 * <p>Its own queues, not shared with Order Tracking's: a topic exchange fans out, so both services
 * bind {@code order.#} and each gets a full copy. Sharing one queue would make them competing
 * consumers, and roughly half of every order's notifications would silently never be sent.
 */
@Configuration(proxyBeanMethods = false)
public class NotificationsRabbitConfiguration {

    @Bean
    public TopicExchange deliveryEventsExchange(
            @Value("${delivery.outbox.exchange:delivery.events}") String exchange) {
        return new TopicExchange(exchange, true, false);
    }

    @Bean
    public Queue notificationsOrderEventsQueue(
            @Value("${delivery.notifications.order-events-queue:notifications.order-events}") String name) {
        return QueueBuilder.durable(name)
                .deadLetterExchange("")
                .deadLetterRoutingKey(name + ".dlq")
                .build();
    }

    @Bean
    public Queue notificationsOrderEventsDlq(
            @Value("${delivery.notifications.order-events-queue:notifications.order-events}") String name) {
        return QueueBuilder.durable(name + ".dlq").build();
    }

    /**
     * {@code order.#} — every order event, including types that do not exist yet. A new event type
     * in Order Manager reaches the notification layer without a change here; whether it produces a
     * message is decided by whether a template row exists for it.
     */
    @Bean
    public Binding notificationsOrderEventsBinding(Queue notificationsOrderEventsQueue,
                                                   TopicExchange deliveryEventsExchange) {
        return BindingBuilder.bind(notificationsOrderEventsQueue)
                .to(deliveryEventsExchange)
                .with("order.#");
    }

    /**
     * Chat events, on their own queue rather than the order one.
     *
     * <p>A chat event carries no order snapshot, so sharing the queue above would mean
     * {@code OrderEventListener} recognising and discarding it on every delivery — and one
     * unparseable chat message queued in front of a backlog of order notifications would delay the
     * ones a customer is actually waiting on.
     */
    @Bean
    public Queue notificationsChatEventsQueue(
            @Value("${delivery.notifications.chat-events-queue:notifications.chat-events}") String name) {
        return QueueBuilder.durable(name)
                .deadLetterExchange("")
                .deadLetterRoutingKey(name + ".dlq")
                .build();
    }

    @Bean
    public Queue notificationsChatEventsDlq(
            @Value("${delivery.notifications.chat-events-queue:notifications.chat-events}") String name) {
        return QueueBuilder.durable(name + ".dlq").build();
    }

    /**
     * {@code chat.#} — the same opt-in shape as {@code order.#}. App Notification publishes
     * {@code chat.message_missed} today; a second chat event reaches this service without a change
     * here, and whether it produces a message is decided by whether a template row exists for it.
     */
    @Bean
    public Binding notificationsChatEventsBinding(Queue notificationsChatEventsQueue,
                                                  TopicExchange deliveryEventsExchange) {
        return BindingBuilder.bind(notificationsChatEventsQueue)
                .to(deliveryEventsExchange)
                .with("chat.#");
    }

    @Bean
    public Queue notificationReceiptsQueue(
            @Value("${delivery.notifications.receipts-queue:notifications.receipts}") String name) {
        return QueueBuilder.durable(name)
                .deadLetterExchange("")
                .deadLetterRoutingKey(name + ".dlq")
                .build();
    }

    @Bean
    public Queue notificationReceiptsDlq(
            @Value("${delivery.notifications.receipts-queue:notifications.receipts}") String name) {
        return QueueBuilder.durable(name + ".dlq").build();
    }

    @Bean
    public Binding notificationReceiptsBinding(Queue notificationReceiptsQueue,
                                               TopicExchange deliveryEventsExchange) {
        return BindingBuilder.bind(notificationReceiptsQueue)
                .to(deliveryEventsExchange)
                .with(DeliveryReceipt.ROUTING_KEY);
    }

    /**
     * Carrier receipts get their own queue rather than sharing the worker-receipt one.
     *
     * <p>They arrive from a different source (a vendor's webhook, not our worker), on a different
     * timescale (up to hours later), and in bursts a carrier decides the size of. Sharing a queue
     * would let a vendor's retry storm delay the worker receipts that move messages out of PENDING —
     * the ones an operator is watching during an incident.
     */
    @Bean
    public Queue notificationDlrQueue(
            @Value("${delivery.notifications.dlr-queue:notifications.dlr}") String name) {
        return QueueBuilder.durable(name)
                .deadLetterExchange("")
                .deadLetterRoutingKey(name + ".dlq")
                .build();
    }

    @Bean
    public Queue notificationDlrDlq(
            @Value("${delivery.notifications.dlr-queue:notifications.dlr}") String name) {
        return QueueBuilder.durable(name + ".dlq").build();
    }

    @Bean
    public Binding notificationDlrBinding(Queue notificationDlrQueue,
                                          TopicExchange deliveryEventsExchange) {
        return BindingBuilder.bind(notificationDlrQueue)
                .to(deliveryEventsExchange)
                .with(ProviderDeliveryReceipt.ROUTING_KEY);
    }
}
