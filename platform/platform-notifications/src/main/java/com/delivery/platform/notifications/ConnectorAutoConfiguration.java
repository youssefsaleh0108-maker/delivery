package com.delivery.platform.notifications;

import java.time.Duration;
import java.util.List;

import org.springframework.amqp.core.Binding;
import org.springframework.amqp.core.BindingBuilder;
import org.springframework.amqp.core.Queue;
import org.springframework.amqp.core.QueueBuilder;
import org.springframework.amqp.core.TopicExchange;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.AutoConfiguration;
import org.springframework.boot.autoconfigure.condition.ConditionalOnBean;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.boot.autoconfigure.condition.ConditionalOnWebApplication;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.scheduling.concurrent.ThreadPoolTaskScheduler;
import org.springframework.web.client.RestClient;

import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * Turns a service into a provider connector once it sets {@code delivery.connector.type}.
 *
 * <p>Three connectors need the same six pieces of plumbing — active-provider registry, its own
 * settings queue and binding, the bus listener, a TTL refresh, a resilience wrapper and a dead
 * letter target. Contributing them from one place is what keeps the SMS connector's resilience
 * behaviour identical to the email connector's; three hand-written copies would drift, and the
 * drift would only show up during an outage.
 *
 * <p>What each connector still writes for itself is the part that is genuinely different: its
 * provider clients and how it classifies their failures.
 */
@AutoConfiguration
@ConditionalOnProperty(prefix = "delivery.connector", name = "type")
@EnableConfigurationProperties(ConnectorProperties.class)
public class ConnectorAutoConfiguration {

    @Bean
    public ActiveProviderRegistry activeProviderRegistry(ConnectorProperties properties) {
        return new ActiveProviderRegistry(
                properties.getType(), properties.getDefaultProvider(), properties.getCacheTtl());
    }

    // deliveryEventsExchange, notificationDeadLetterQueue and deadLetterPublisher moved to
    // NotificationCommonAutoConfiguration — a worker declares the same three, and one process being
    // both a worker and a connector could not start while they were defined in both.

    @Bean
    public Queue connectorSettingsQueue(ConnectorProperties properties) {
        return QueueBuilder.durable(properties.getSettingsQueue()).build();
    }

    @Bean
    public Binding connectorSettingsBinding(Queue connectorSettingsQueue,
                                            TopicExchange deliveryEventsExchange) {
        return BindingBuilder.bind(connectorSettingsQueue)
                .to(deliveryEventsExchange)
                .with(SettingsChangedEvent.ROUTING_KEY);
    }

    @Bean
    public ConnectorSettingsListener connectorSettingsListener(ConnectorProperties properties,
                                                               ActiveProviderRegistry registry,
                                                               ObjectMapper objectMapper) {
        return new ConnectorSettingsListener(properties.getType(), registry, objectMapper);
    }

    @Bean
    public ResilientDispatcher connectorDispatcher(ConnectorProperties properties) {
        return new ResilientDispatcher(
                properties.getType().toLowerCase(java.util.Locale.ROOT) + "-provider",
                properties.getMaxAttempts(),
                properties.getInitialBackoff(),
                properties.getFailureRateThreshold(),
                properties.getOpenStateDuration());
    }

    /**
     * Contributed here rather than component-scanned so the three connectors cannot end up with
     * subtly different send endpoints. A connector supplies only its {@link ProviderClient}s.
     */
    @Bean
    @ConditionalOnWebApplication(type = ConditionalOnWebApplication.Type.SERVLET)
    public ConnectorSendController connectorSendController(List<ProviderClient> providerClients,
                                                           ActiveProviderRegistry registry,
                                                           ResilientDispatcher connectorDispatcher,
                                                           DeadLetterPublisher deadLetterPublisher,
                                                           ConnectorProperties properties) {
        return new ConnectorSendController(providerClients, registry, connectorDispatcher,
                deadLetterPublisher, properties);
    }

    /**
     * Only stood up when the connector actually contributes translators.
     *
     * <p>Without the condition, EMAIL and PUSH — which have no carrier-receipt concept and supply
     * none — would each expose a public webhook path that answers 404 to everything. An endpoint
     * that exists but can never succeed is a thing to probe, not a feature.
     */
    @Bean
    @ConditionalOnWebApplication(type = ConditionalOnWebApplication.Type.SERVLET)
    @ConditionalOnBean(DeliveryReceiptTranslator.class)
    public DlrWebhookController dlrWebhookController(List<DeliveryReceiptTranslator> translators,
                                                     RabbitTemplate rabbitTemplate,
                                                     ObjectMapper objectMapper,
                                                     @Value("${delivery.outbox.exchange:delivery.events}")
                                                     String exchange) {
        return new DlrWebhookController(translators, rabbitTemplate, objectMapper, exchange);
    }

    @Bean
    public ProviderSettingsRefresher providerSettingsRefresher(ConnectorProperties properties,
                                                               ActiveProviderRegistry registry,
                                                               RestClient.Builder builder) {
        return new ProviderSettingsRefresher(
                builder.baseUrl(properties.getSettingsUrl()).build(),
                properties.getType(),
                registry);
    }

    /**
     * Drives the refresh.
     *
     * <p>An owned single-thread scheduler rather than {@code @EnableScheduling}, so this library
     * cannot silently switch on scheduling for whatever else the host service is doing.
     *
     * <p>The first run is offset by a few seconds rather than fired at construction: a connector
     * must come up healthy even when Connector Settings is down, and blocking startup on an HTTP
     * call to another service would make the two boot-order dependent.
     */
    @Bean(destroyMethod = "shutdown")
    public ThreadPoolTaskScheduler connectorSettingsRefreshScheduler(
            ProviderSettingsRefresher refresher, ConnectorProperties properties) {

        ThreadPoolTaskScheduler scheduler = new ThreadPoolTaskScheduler();
        scheduler.setPoolSize(1);
        scheduler.setThreadNamePrefix("connector-settings-refresh-");
        scheduler.setWaitForTasksToCompleteOnShutdown(false);
        scheduler.initialize();

        // Checked more often than the TTL, so a value is never much staler than the TTL itself.
        Duration interval = properties.getCacheTtl().dividedBy(2);
        scheduler.scheduleWithFixedDelay(
                refresher::refreshIfStale,
                java.time.Instant.now().plusSeconds(FIRST_REFRESH_DELAY_SECONDS),
                interval);
        return scheduler;
    }

    /** Long enough for the context to finish starting, short enough to correct a stale boot value. */
    private static final long FIRST_REFRESH_DELAY_SECONDS = 5;
}
