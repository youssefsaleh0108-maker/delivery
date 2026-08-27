package com.delivery.appnotification.config;

import org.springframework.amqp.core.Binding;
import org.springframework.amqp.core.BindingBuilder;
import org.springframework.amqp.core.Queue;
import org.springframework.amqp.core.QueueBuilder;
import org.springframework.amqp.core.TopicExchange;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * This service's own queue for order events, which is what opens and closes chat conversations.
 *
 * <p>Separate from {@link AppNotificationRabbitConfiguration}'s in-app command queue on purpose.
 * That queue carries notification commands the manager addressed to this service; this one carries
 * domain events this service chose to listen to. Sharing a queue would put an order snapshot and a
 * notification command through the same consumer, and one of them would have to be recognised and
 * discarded on every delivery.
 *
 * <p>The exchange bean is declared once, next door, and injected here — declaring a second
 * {@code TopicExchange} bean for the same exchange would be a duplicate bean name and a startup
 * failure.
 */
@Configuration(proxyBeanMethods = false)
public class ChatRabbitConfiguration {

    /**
     * Bound to {@code order.#} rather than to the two keys chat actually uses.
     *
     * <p>The same choice Order Tracking and Notifications Manager made, for the same reason: a new
     * event type in Order Manager reaches this consumer without a matching change here, and the
     * switch in the listener decides what to do with it. The cost is a handful of ignored messages
     * per order, which is cheaper than a deployment to start hearing about a transition.
     */
    @Bean
    public Queue chatOrderEventsQueue(
            @Value("${delivery.chat.order-events-queue:app-notification.order-events}") String name) {
        return QueueBuilder.durable(name)
                // A dead-letter target so an event this service genuinely cannot handle is kept for
                // an operator rather than vanishing.
                .deadLetterExchange("")
                .deadLetterRoutingKey(name + ".dlq")
                .build();
    }

    @Bean
    public Queue chatOrderEventsDlq(
            @Value("${delivery.chat.order-events-queue:app-notification.order-events}") String name) {
        return QueueBuilder.durable(name + ".dlq").build();
    }

    @Bean
    public Binding chatOrderEventsBinding(Queue chatOrderEventsQueue,
                                          TopicExchange deliveryEventsExchange) {
        return BindingBuilder.bind(chatOrderEventsQueue)
                .to(deliveryEventsExchange)
                .with("order.#");
    }
}
