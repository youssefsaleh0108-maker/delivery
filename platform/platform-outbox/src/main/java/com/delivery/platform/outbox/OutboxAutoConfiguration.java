package com.delivery.platform.outbox;

import org.springframework.amqp.core.TopicExchange;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.boot.autoconfigure.AutoConfiguration;
import org.springframework.boot.autoconfigure.amqp.RabbitAutoConfiguration;
import org.springframework.boot.autoconfigure.condition.ConditionalOnBean;
import org.springframework.boot.autoconfigure.condition.ConditionalOnClass;
import org.springframework.boot.autoconfigure.condition.ConditionalOnMissingBean;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.boot.autoconfigure.orm.jpa.HibernateJpaAutoConfiguration;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.orm.jpa.LocalContainerEntityManagerFactoryBean;
import org.springframework.scheduling.annotation.EnableScheduling;

import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * Wires the outbox into any service that puts {@code platform-outbox} on its classpath.
 *
 * <p><strong>The consuming service must scan this package for JPA entities and repositories.</strong>
 * Annotate its application class with:
 *
 * <pre>
 * &#64;EntityScan(basePackages = "com.delivery")
 * &#64;EnableJpaRepositories(basePackages = "com.delivery")
 * </pre>
 *
 * <p>This class deliberately does NOT declare those annotations itself. Declaring
 * {@code @EnableJpaRepositories} anywhere makes Spring Boot's own repository auto-configuration
 * back off entirely — so a library that "helpfully" enables its own repositories silently stops the
 * application's repositories from being found, and the service fails at startup with
 * "No qualifying bean of type ...Repository available".
 */
@AutoConfiguration(after = {RabbitAutoConfiguration.class, HibernateJpaAutoConfiguration.class})
@ConditionalOnClass({RabbitTemplate.class, LocalContainerEntityManagerFactoryBean.class})
@EnableConfigurationProperties(OutboxProperties.class)
public class OutboxAutoConfiguration {

    @Bean
    @ConditionalOnMissingBean
    public OutboxRecorder outboxRecorder(OutboxEventRepository repository, ObjectMapper objectMapper) {
        return new OutboxRecorder(repository, objectMapper);
    }

    /**
     * Declared so the exchange exists on first boot regardless of which service starts first —
     * with 14 services publishing, none of them should have to assume another one created it.
     */
    @Bean
    @ConditionalOnMissingBean(name = "deliveryEventsExchange")
    public TopicExchange deliveryEventsExchange(OutboxProperties properties) {
        return new TopicExchange(properties.getExchange(), true, false);
    }

    /**
     * The outbox gauges, bound wherever a meter registry exists.
     *
     * <p>Separate inner configuration so a service without Micrometer on its classpath still gets a
     * working outbox — the alternative, a hard dependency, would make the metrics the reason a
     * service could not start.
     */
    @org.springframework.context.annotation.Configuration(proxyBeanMethods = false)
    @ConditionalOnClass(io.micrometer.core.instrument.MeterRegistry.class)
    static class MetricsConfiguration {

        @Bean
        @ConditionalOnMissingBean
        public OutboxMetrics outboxMetrics(OutboxEventRepository repository) {
            return new OutboxMetrics(repository);
        }
    }

    @org.springframework.context.annotation.Configuration(proxyBeanMethods = false)
    @ConditionalOnProperty(prefix = "delivery.outbox", name = "relay-enabled",
            havingValue = "true", matchIfMissing = true)
    @EnableScheduling
    static class RelayConfiguration {

        @Bean
        @ConditionalOnBean(RabbitTemplate.class)
        @ConditionalOnMissingBean
        public OutboxRelay outboxRelay(OutboxEventRepository repository,
                                       RabbitTemplate rabbitTemplate,
                                       OutboxProperties properties) {
            return new OutboxRelay(repository, rabbitTemplate, properties);
        }
    }
}
