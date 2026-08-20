package com.delivery.platform.outbox;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import io.micrometer.core.instrument.Gauge;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * The gauges that make a dead-lettered event visible to somebody.
 *
 * <p>The relay has always logged when it gives up on an event. That has never been enough: one ERROR
 * line, in one of a dozen containers, at whatever hour the broker had its problem. A dead-lettered
 * event means an order that will never notify, never settle and never project, and until these
 * gauges existed nothing outside the process could tell.
 */
class OutboxMetricsTest {

    private OutboxEventRepository repository;
    private OutboxMetrics metrics;
    private SimpleMeterRegistry registry;

    @BeforeEach
    void setUp() {
        repository = mock(OutboxEventRepository.class);
        metrics = new OutboxMetrics(repository);
        registry = new SimpleMeterRegistry();

        when(repository.countByStatus(OutboxEvent.Status.DEAD_LETTERED)).thenReturn(0L);
        when(repository.countByStatus(OutboxEvent.Status.PENDING)).thenReturn(0L);
    }

    private double gauge(String name) {
        Gauge found = registry.find(name).gauge();
        assertThat(found).as("gauge %s is registered", name).isNotNull();
        return found.value();
    }

    @Nested
    @DisplayName("what is published")
    class Published {

        @Test
        void both_gauges_are_registered() {
            metrics.bindTo(registry);

            assertThat(registry.find("delivery.outbox.dead_lettered").gauge()).isNotNull();
            assertThat(registry.find("delivery.outbox.pending").gauge()).isNotNull();
        }

        @Test
        void the_dead_letter_gauge_reports_the_dead_lettered_count() {
            when(repository.countByStatus(OutboxEvent.Status.DEAD_LETTERED)).thenReturn(3L);
            metrics.bindTo(registry);

            assertThat(gauge("delivery.outbox.dead_lettered")).isEqualTo(3.0);
        }

        @Test
        void the_pending_gauge_reports_the_backlog() {
            when(repository.countByStatus(OutboxEvent.Status.PENDING)).thenReturn(120L);
            metrics.bindTo(registry);

            assertThat(gauge("delivery.outbox.pending")).isEqualTo(120.0);
        }

        /** Published rows are the overwhelming majority over time and are nobody's problem. */
        @Test
        void published_events_are_not_reported() {
            metrics.bindTo(registry);

            assertThat(registry.find("delivery.outbox.published").gauge()).isNull();
        }
    }

    /**
     * The names the alert rules are written against.
     *
     * <p>This is a contract test in the literal sense: {@code infra/prometheus/alerts.yml} matches
     * on these strings, and nothing else connects the two. A rename here, or a stray
     * {@code baseUnit} — which the Prometheus registry appends to the name — leaves the rule
     * matching no series at all. It does not error; it just never fires, which is the one failure
     * mode a monitoring change must not have.
     */
    @Nested
    @DisplayName("the exported metric names")
    class ExportedNames {

        private String scrape() {
            io.micrometer.prometheusmetrics.PrometheusMeterRegistry prometheus =
                    new io.micrometer.prometheusmetrics.PrometheusMeterRegistry(
                            io.micrometer.prometheusmetrics.PrometheusConfig.DEFAULT);
            metrics.bindTo(prometheus);
            return prometheus.scrape();
        }

        @Test
        void are_exactly_what_the_alert_rules_match_on() {
            String scraped = scrape();

            assertThat(scraped).contains("delivery_outbox_dead_lettered");
            assertThat(scraped).contains("delivery_outbox_pending");
        }

        /** The specific way this breaks: a base unit silently suffixed onto the name. */
        @Test
        void carry_no_unit_suffix() {
            String scraped = scrape();

            assertThat(scraped).doesNotContain("delivery_outbox_dead_lettered_events");
            assertThat(scraped).doesNotContain("delivery_outbox_pending_events");
        }
    }

    @Nested
    @DisplayName("how the value is obtained")
    class Freshness {

        /**
         * The value has to be read at scrape time, not captured at bind time. A gauge that latched
         * the count when the service started would report zero for the rest of the process's life,
         * which is worse than no gauge — it would look like an all-clear.
         */
        @Test
        void the_count_is_read_on_every_scrape_rather_than_captured_once() {
            metrics.bindTo(registry);
            assertThat(gauge("delivery.outbox.dead_lettered")).isZero();

            when(repository.countByStatus(OutboxEvent.Status.DEAD_LETTERED)).thenReturn(7L);

            assertThat(gauge("delivery.outbox.dead_lettered")).isEqualTo(7.0);
        }

        /**
         * Counted from the table rather than incremented by the relay. A counter would miss every
         * row dead-lettered by another replica, and would reset on restart — the moment the number
         * matters most.
         */
        @Test
        void the_count_comes_from_the_table() {
            metrics.deadLettered();

            verify(repository).countByStatus(OutboxEvent.Status.DEAD_LETTERED);
        }
    }
}
