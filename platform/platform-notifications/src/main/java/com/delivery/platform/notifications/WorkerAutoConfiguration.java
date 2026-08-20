package com.delivery.platform.notifications;

import java.time.Duration;

import org.springframework.amqp.core.Binding;
import org.springframework.amqp.core.BindingBuilder;
import org.springframework.amqp.core.Queue;
import org.springframework.amqp.core.QueueBuilder;
import org.springframework.amqp.core.TopicExchange;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.AutoConfiguration;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.web.client.RestClient;

import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * Turns a service into a channel worker once it sets {@code delivery.worker.channel}.
 *
 * <p>Same rationale as {@link ConnectorAutoConfiguration}: the three workers are identical except
 * for their {@link ChannelPreparer}, and hand-copying the queue declaration, resilience settings
 * and receipt publishing into each would let them drift apart in exactly the ways that only show
 * up under load.
 *
 * <p>A worker supplies one bean of its own — a {@code ChannelPreparer} — and a listener that
 * forwards to {@link WorkerDispatchService}.
 */
@AutoConfiguration
@ConditionalOnProperty(prefix = "delivery.worker", name = "channel")
@EnableConfigurationProperties(WorkerProperties.class)
public class WorkerAutoConfiguration {

    @Bean
    public TopicExchange deliveryEventsExchange(
            @Value("${delivery.outbox.exchange:delivery.events}") String exchange) {
        return new TopicExchange(exchange, true, false);
    }

    /**
     * This worker's own channel queue.
     *
     * <p>One queue per channel is the point of the design: a shared {@code notification.requested}
     * queue would let one wedged channel hold up the others behind it.
     */
    @Bean
    public Queue workerChannelQueue(WorkerProperties properties) {
        return QueueBuilder.durable(properties.queueName()).build();
    }

    @Bean
    public Binding workerChannelBinding(Queue workerChannelQueue, TopicExchange deliveryEventsExchange,
                                        WorkerProperties properties) {
        return BindingBuilder.bind(workerChannelQueue)
                .to(deliveryEventsExchange)
                .with(properties.queueName());
    }

    @Bean
    public Queue notificationDeadLetterQueue(WorkerProperties properties) {
        return QueueBuilder.durable(properties.getDeadLetterQueue()).build();
    }

    @Bean
    public DeadLetterPublisher deadLetterPublisher(RabbitTemplate rabbit, ObjectMapper objectMapper,
                                                   WorkerProperties properties) {
        return new DeadLetterPublisher(rabbit, objectMapper, properties.getDeadLetterQueue());
    }

    @Bean
    public ConnectorClient connectorClient(WorkerProperties properties, RestClient.Builder builder) {
        // An explicit timeout, because the default is none: a connector that accepts the connection
        // and then never answers would otherwise hold a worker thread indefinitely, and enough of
        // those is the channel going down without a single error being logged.
        SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
        factory.setConnectTimeout(Duration.ofSeconds(2));
        factory.setReadTimeout(properties.getConnectorTimeout());

        return new ConnectorClient(
                builder.baseUrl(properties.getConnectorUrl()).requestFactory(factory).build(),
                properties.getChannel());
    }

    @Bean
    public ResilientDispatcher workerDispatcher(WorkerProperties properties) {
        return new ResilientDispatcher(
                properties.getChannel().toLowerCase(java.util.Locale.ROOT) + "-connector",
                properties.getMaxAttempts(),
                properties.getInitialBackoff(),
                properties.getFailureRateThreshold(),
                properties.getOpenStateDuration());
    }

    /**
     * The consumer itself.
     *
     * <p>Contributed here so all three workers consume identically. The queue name comes from the
     * queue bean rather than a second property, so a worker cannot end up declaring one queue and
     * listening on another — a mistake that looks like "this channel silently stopped working".
     */
    @Bean
    public NotificationCommandListener notificationCommandListener(WorkerDispatchService dispatch) {
        return new NotificationCommandListener(dispatch);
    }

    @Bean
    public WorkerDispatchService workerDispatchService(WorkerProperties properties,
                                                       ChannelPreparer preparer,
                                                       ConnectorClient connectorClient,
                                                       ResilientDispatcher workerDispatcher,
                                                       DeadLetterPublisher deadLetterPublisher,
                                                       RabbitTemplate rabbit,
                                                       ObjectMapper objectMapper,
                                                       @Value("${delivery.outbox.exchange:delivery.events}")
                                                       String exchange) {
        return new WorkerDispatchService(properties.getChannel(), preparer, connectorClient,
                workerDispatcher, deadLetterPublisher, rabbit, objectMapper, exchange);
    }
}
