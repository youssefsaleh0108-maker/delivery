package com.delivery.appnotification.config;

import org.springframework.amqp.core.Binding;
import org.springframework.amqp.core.BindingBuilder;
import org.springframework.amqp.core.Queue;
import org.springframework.amqp.core.QueueBuilder;
import org.springframework.amqp.core.TopicExchange;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import com.delivery.platform.notifications.NotificationCommand;

/**
 * The in-app channel's queue.
 *
 * <p>Declared here rather than through the shared worker auto-configuration because this service is
 * not a worker in the sense the other three are: it has no connector to call and no
 * {@code ChannelPreparer}, so wiring in the connector client and its resilience settings would mean
 * configuring a URL that is never used.
 */
@Configuration(proxyBeanMethods = false)
public class AppNotificationRabbitConfiguration {

    @Bean
    public TopicExchange deliveryEventsExchange(
            @Value("${delivery.outbox.exchange:delivery.events}") String exchange) {
        return new TopicExchange(exchange, true, false);
    }

    @Bean
    public Queue inAppCommandQueue() {
        String name = NotificationCommand.routingKeyFor(NotificationCommand.CHANNEL_IN_APP);
        return QueueBuilder.durable(name)
                .deadLetterExchange("")
                .deadLetterRoutingKey(name + ".dlq")
                .build();
    }

    @Bean
    public Queue inAppCommandDlq() {
        return QueueBuilder.durable(
                NotificationCommand.routingKeyFor(NotificationCommand.CHANNEL_IN_APP) + ".dlq")
                .build();
    }

    @Bean
    public Binding inAppCommandBinding(Queue inAppCommandQueue, TopicExchange deliveryEventsExchange) {
        return BindingBuilder.bind(inAppCommandQueue)
                .to(deliveryEventsExchange)
                .with(NotificationCommand.routingKeyFor(NotificationCommand.CHANNEL_IN_APP));
    }
}
