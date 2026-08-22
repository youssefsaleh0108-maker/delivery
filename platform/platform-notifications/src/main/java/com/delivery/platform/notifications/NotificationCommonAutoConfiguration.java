package com.delivery.platform.notifications;

import org.springframework.amqp.core.Queue;
import org.springframework.amqp.core.QueueBuilder;
import org.springframework.amqp.core.TopicExchange;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.AutoConfiguration;
import org.springframework.boot.autoconfigure.condition.AnyNestedCondition;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Conditional;

import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * The three beans a worker and a connector both need, in one place so that one process can be both.
 *
 * <p>{@link WorkerAutoConfiguration} and {@link ConnectorAutoConfiguration} each used to declare
 * {@code deliveryEventsExchange}, {@code notificationDeadLetterQueue} and {@code deadLetterPublisher}
 * for themselves. That was harmless while no service ever set both {@code delivery.worker.channel}
 * and {@code delivery.connector.type} — and it is exactly what stopped a service from doing so.
 * Bean definition overriding is off by default, so a process activating both auto-configurations
 * failed at startup with {@code BeanDefinitionOverrideException} naming a bean neither file
 * appeared to define twice.
 *
 * <p>Merging the channel workers into their connectors is what made that a real case. The
 * definitions were identical in both, so nothing here changes behaviour for a service that plays
 * only one of the two roles.
 */
@AutoConfiguration
@Conditional(NotificationCommonAutoConfiguration.WorkerOrConnectorCondition.class)
public class NotificationCommonAutoConfiguration {

    /**
     * Active for a worker, a connector, or one process being both — but not for a service that
     * merely has this library on the classpath. Notifications Manager publishes commands and
     * consumes neither of these queues; declaring a dead-letter queue there would be infrastructure
     * owned by nobody.
     *
     * <p>{@code @ConditionalOnProperty} cannot express OR across two different property names,
     * which is what {@link AnyNestedCondition} is for.
     */
    static class WorkerOrConnectorCondition extends AnyNestedCondition {

        WorkerOrConnectorCondition() {
            super(ConfigurationPhase.REGISTER_BEAN);
        }

        @ConditionalOnProperty(prefix = "delivery.worker", name = "channel")
        static class IsWorker {
        }

        @ConditionalOnProperty(prefix = "delivery.connector", name = "type")
        static class IsConnector {
        }
    }

    /**
     * The domain event exchange. Durable and non-auto-delete, matching the outbox relay that
     * publishes to it.
     */
    @Bean
    public TopicExchange deliveryEventsExchange(
            @Value("${delivery.outbox.exchange:delivery.events}") String exchange) {
        return new TopicExchange(exchange, true, false);
    }

    /**
     * Durable and unconsumed on purpose — this is the operator's inbox, not a retry path.
     *
     * <p>The nested placeholder keeps every existing configuration file working untouched: a
     * connector sets {@code delivery.connector.dead-letter-queue}, a worker sets
     * {@code delivery.worker.dead-letter-queue}, and a merged service sets both. The connector's
     * value wins when both are present, which is only reachable when they already agree.
     */
    @Bean
    public Queue notificationDeadLetterQueue(
            @Value("${delivery.connector.dead-letter-queue:${delivery.worker.dead-letter-queue:notification.dlq}}")
            String deadLetterQueue) {
        return QueueBuilder.durable(deadLetterQueue).build();
    }

    @Bean
    public DeadLetterPublisher deadLetterPublisher(
            RabbitTemplate rabbit,
            ObjectMapper objectMapper,
            @Value("${delivery.connector.dead-letter-queue:${delivery.worker.dead-letter-queue:notification.dlq}}")
            String deadLetterQueue) {
        return new DeadLetterPublisher(rabbit, objectMapper, deadLetterQueue);
    }
}
