package com.delivery.platform.outbox;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.boot.autoconfigure.AutoConfigurations;
import org.springframework.boot.test.context.FilteredClassLoader;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import io.micrometer.core.instrument.MeterRegistry;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;

/**
 * Whether the outbox beans actually appear in a service that depends on this library.
 *
 * <p>Everything else about the metrics is unit-tested, and none of it matters if the bean is never
 * created. That is the specific way a monitoring change fails quietly: the code is right, the tests
 * pass, and the gauge is simply absent from {@code /actuator/prometheus} because a condition did not
 * match — so the alert never fires and the absence looks exactly like health.
 */
class OutboxAutoConfigurationTest {

    private final ApplicationContextRunner runner = new ApplicationContextRunner()
            .withConfiguration(AutoConfigurations.of(OutboxAutoConfiguration.class))
            .withUserConfiguration(StubDependencies.class);

    /**
     * Stands in for what a real service brings — the repository and a rabbit template. Enough for
     * the conditions to resolve without a database or a broker.
     */
    @Configuration(proxyBeanMethods = false)
    static class StubDependencies {

        @Bean
        OutboxEventRepository outboxEventRepository() {
            return mock(OutboxEventRepository.class);
        }

        @Bean
        org.springframework.amqp.rabbit.core.RabbitTemplate rabbitTemplate() {
            return mock(org.springframework.amqp.rabbit.core.RabbitTemplate.class);
        }

        @Bean
        com.fasterxml.jackson.databind.ObjectMapper objectMapper() {
            return new com.fasterxml.jackson.databind.ObjectMapper();
        }
    }

    @Nested
    @DisplayName("in an ordinary service")
    class Standard {

        @Test
        void the_metrics_binder_is_registered() {
            runner.run(context -> assertThat(context).hasSingleBean(OutboxMetrics.class));
        }

        @Test
        void the_recorder_and_relay_are_registered() {
            runner.run(context -> {
                assertThat(context).hasSingleBean(OutboxRecorder.class);
                assertThat(context).hasSingleBean(OutboxRelay.class);
            });
        }

        /** Spring Boot binds any MeterBinder bean to the registry, which is how the gauge appears. */
        @Test
        void the_binder_is_a_meter_binder_so_boot_picks_it_up() {
            runner.run(context -> assertThat(context.getBean(OutboxMetrics.class))
                    .isInstanceOf(io.micrometer.core.instrument.binder.MeterBinder.class));
        }
    }

    @Nested
    @DisplayName("when the relay is switched off")
    class RelayDisabled {

        /**
         * A read replica or a test turns the relay off. The metrics must survive that — an instance
         * that is not publishing is precisely one where a growing backlog matters.
         */
        @Test
        void the_metrics_are_still_registered() {
            runner.withPropertyValues("delivery.outbox.relay-enabled=false")
                    .run(context -> {
                        assertThat(context).doesNotHaveBean(OutboxRelay.class);
                        assertThat(context).hasSingleBean(OutboxMetrics.class);
                    });
        }
    }

    @Nested
    @DisplayName("in a service without Micrometer")
    class WithoutMicrometer {

        /**
         * The metrics are optional on purpose. A service that does not carry Micrometer should get
         * a working outbox rather than a failure to start — the monitoring must never be the reason
         * something cannot run.
         */
        @Test
        void the_outbox_still_works_and_the_metrics_are_simply_absent() {
            runner.withClassLoader(new FilteredClassLoader(MeterRegistry.class))
                    .run(context -> {
                        assertThat(context).hasNotFailed();
                        assertThat(context).hasSingleBean(OutboxRecorder.class);
                        assertThat(context).doesNotHaveBean(OutboxMetrics.class);
                    });
        }
    }
}
