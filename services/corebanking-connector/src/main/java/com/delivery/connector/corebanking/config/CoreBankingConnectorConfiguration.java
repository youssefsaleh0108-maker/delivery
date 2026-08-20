package com.delivery.connector.corebanking.config;

import java.time.Duration;

import org.springframework.amqp.core.Binding;
import org.springframework.amqp.core.BindingBuilder;
import org.springframework.amqp.core.Queue;
import org.springframework.amqp.core.QueueBuilder;
import org.springframework.amqp.core.TopicExchange;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.scheduling.concurrent.ThreadPoolTaskScheduler;
import org.springframework.web.client.RestClient;

import com.delivery.connector.corebanking.BankPostingCommand;
import com.delivery.platform.notifications.ActiveProviderRegistry;
import com.delivery.platform.notifications.ConnectorSettingsListener;
import com.delivery.platform.notifications.DeadLetterPublisher;
import com.delivery.platform.notifications.ProviderSettingsRefresher;
import com.delivery.platform.notifications.ResilientDispatcher;
import com.delivery.platform.notifications.SettingsChangedEvent;
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * Wires this connector by hand rather than through {@code ConnectorAutoConfiguration}.
 *
 * <p>That auto-configuration is notification-shaped: it contributes a send controller typed to
 * {@code NotificationCommand} and a list of notification {@code ProviderClient}s. A bank posting is
 * a different payload with different provider clients, so activating it here would mean contorting
 * it to serve two unrelated contracts.
 *
 * <p>What IS shared is everything genuinely generic — the active-provider registry, the settings
 * listener and TTL refresh, the resilience wrapper and the dead-letter publisher. Those behave
 * identically for a bank and a vendor, and having one implementation is what keeps the Core Banking
 * connector's outage behaviour the same as the SMS connector's.
 *
 * <p><strong>Consumes off a queue, and is never called synchronously.</strong> Section 10 requires
 * the bank to be an asynchronous saga from the order path, so nothing can hold up an order while a
 * bank is slow. There is deliberately no send endpoint on this service.
 */
@Configuration(proxyBeanMethods = false)
public class CoreBankingConnectorConfiguration {

    /** Matches the CORE_BANKING entry in Connector Settings. */
    public static final String CONNECTOR_TYPE = "CORE_BANKING";

    @Bean
    public TopicExchange deliveryEventsExchange(
            @Value("${delivery.outbox.exchange:delivery.events}") String exchange) {
        return new TopicExchange(exchange, true, false);
    }

    @Bean
    public ActiveProviderRegistry activeProviderRegistry(
            @Value("${delivery.corebanking.default-provider:SIMULATOR}") String defaultProvider,
            @Value("${delivery.corebanking.cache-ttl:5m}") Duration ttl) {
        // SIMULATOR is the safe default for the same reason DEV_PASSTHROUGH is on SMS: a wrong
        // default that moves no real money beats one that does.
        return new ActiveProviderRegistry(CONNECTOR_TYPE, defaultProvider, ttl);
    }

    @Bean
    public Queue connectorSettingsQueue(
            @Value("${delivery.connector.settings-queue}") String name) {
        return QueueBuilder.durable(name).build();
    }

    @Bean
    public Binding connectorSettingsBinding(Queue connectorSettingsQueue,
                                            TopicExchange deliveryEventsExchange) {
        return BindingBuilder.bind(connectorSettingsQueue)
                .to(deliveryEventsExchange)
                .with(SettingsChangedEvent.ROUTING_KEY);
    }

    @Bean
    public ConnectorSettingsListener connectorSettingsListener(ActiveProviderRegistry registry,
                                                               ObjectMapper objectMapper) {
        return new ConnectorSettingsListener(CONNECTOR_TYPE, registry, objectMapper);
    }

    /** The postings queue. Its own, so a bank outage backs up here and nowhere else. */
    @Bean
    public Queue bankPostingQueue() {
        return QueueBuilder.durable(BankPostingCommand.ROUTING_KEY).build();
    }

    @Bean
    public Binding bankPostingBinding(Queue bankPostingQueue, TopicExchange deliveryEventsExchange) {
        return BindingBuilder.bind(bankPostingQueue)
                .to(deliveryEventsExchange)
                .with(BankPostingCommand.ROUTING_KEY);
    }

    @Bean
    public Queue accountingDeadLetterQueue(
            @Value("${delivery.corebanking.dead-letter-queue:accounting.dlq}") String name) {
        // Separate from notification.dlq. A stuck bank posting and a stuck SMS need different
        // people looking at them, and mixing them in one queue guarantees neither gets triaged.
        return QueueBuilder.durable(name).build();
    }

    @Bean
    public DeadLetterPublisher deadLetterPublisher(
            RabbitTemplate rabbit, ObjectMapper objectMapper,
            @Value("${delivery.corebanking.dead-letter-queue:accounting.dlq}") String queue) {
        return new DeadLetterPublisher(rabbit, objectMapper, queue);
    }

    @Bean
    public ResilientDispatcher bankDispatcher(
            @Value("${delivery.corebanking.max-attempts:4}") int maxAttempts,
            @Value("${delivery.corebanking.initial-backoff:1s}") Duration initialBackoff,
            @Value("${delivery.corebanking.failure-rate-threshold:50}") float failureRate,
            @Value("${delivery.corebanking.open-state-duration:60s}") Duration openState) {
        // More attempts and a longer backoff than the notification channels. A late SMS is a poor
        // experience; a lost settlement is a reconciliation problem, so it is worth waiting longer
        // before giving up on a bank that is merely slow.
        return new ResilientDispatcher(
                "corebanking", maxAttempts, initialBackoff, failureRate, openState);
    }

    @Bean
    public ProviderSettingsRefresher providerSettingsRefresher(
            ActiveProviderRegistry registry, RestClient.Builder builder,
            @Value("${delivery.connector.settings-url:http://connector-settings:8109}") String url) {
        return new ProviderSettingsRefresher(builder.baseUrl(url).build(), CONNECTOR_TYPE, registry);
    }

    /** Same pattern as the notification connectors: an owned scheduler, not @EnableScheduling. */
    @Bean(destroyMethod = "shutdown")
    public ThreadPoolTaskScheduler connectorSettingsRefreshScheduler(
            ProviderSettingsRefresher refresher,
            @Value("${delivery.corebanking.cache-ttl:5m}") Duration ttl) {

        ThreadPoolTaskScheduler scheduler = new ThreadPoolTaskScheduler();
        scheduler.setPoolSize(1);
        scheduler.setThreadNamePrefix("corebanking-settings-refresh-");
        scheduler.setWaitForTasksToCompleteOnShutdown(false);
        scheduler.initialize();

        scheduler.scheduleWithFixedDelay(
                refresher::refreshIfStale,
                java.time.Instant.now().plusSeconds(5),
                ttl.dividedBy(2));
        return scheduler;
    }
}
