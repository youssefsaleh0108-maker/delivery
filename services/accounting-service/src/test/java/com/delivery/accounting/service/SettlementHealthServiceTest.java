package com.delivery.accounting.service;

import java.time.Duration;
import java.time.Instant;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

import com.delivery.accounting.config.SettlementMetrics;
import com.delivery.accounting.domain.AccountingTransaction;
import com.delivery.accounting.domain.AccountingTransactionRepository;

import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import io.micrometer.prometheusmetrics.PrometheusConfig;
import io.micrometer.prometheusmetrics.PrometheusMeterRegistry;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * The thresholds, and the metric names the alert rules depend on.
 *
 * <p>What the queries actually return is checked against a real database in
 * {@link com.delivery.accounting.domain.SettlementHealthQueryTest} — no amount of mocking can verify
 * SQL. What is left here is the wiring either side of it: that the clock is applied rather than
 * ignored, and that the gauges reach Prometheus under the names the rules match on.
 */
class SettlementHealthServiceTest {

    private AccountingTransactionRepository transactions;
    private SettlementHealthService health;

    @BeforeEach
    void setUp() {
        transactions = mock(AccountingTransactionRepository.class);
        health = new SettlementHealthService(transactions,
                Duration.ofMinutes(15), Duration.ofMinutes(5));

        when(transactions.countByStatusAndCreatedAtBefore(any(), any())).thenReturn(0L);
        // Stubbed on the default method the service actually calls. Which leg and status sets that
        // default supplies is not this test's business — it is checked against a real database in
        // SettlementHealthQueryTest, where it can be checked properly.
        when(transactions.countDebitedWithoutCounterpartOlderThan(any())).thenReturn(0L);
    }

    @Nested
    @DisplayName("applying the clock")
    class Thresholds {

        /**
         * The whole detector is a clock. Passing {@code now} instead of {@code now - threshold}
         * would count every in-flight settlement as stuck and the alert would be permanently on,
         * which is indistinguishable from having no alert.
         */
        /**
         * Bracketed between two readings of the clock rather than compared to one.
         *
         * <p>The cutoff is {@code now - threshold} taken at some instant during the call, so the
         * only thing that can be asserted without a fake clock is that it lands inside the window
         * the call spanned. An earlier version compared it to a single {@code before - threshold}
         * with {@code isBeforeOrEqualTo}, which is true only if the clock does not tick between the
         * two reads — that holds on Windows, whose granularity is about 15ms, and fails on a Linux
         * runner reading nanoseconds. It passed locally and failed in CI for two years' worth of
         * reasons that had nothing to do with the code under test.
         */
        @Test
        void stuck_legs_looks_back_by_the_configured_threshold() {
            Instant before = Instant.now();

            health.stuckLegs();

            Instant after = Instant.now();
            ArgumentCaptor<Instant> cutoff = ArgumentCaptor.forClass(Instant.class);
            verify(transactions).countByStatusAndCreatedAtBefore(
                    eq(AccountingTransaction.Status.PENDING), cutoff.capture());
            assertThat(cutoff.getValue()).isBetween(
                    before.minus(Duration.ofMinutes(15)), after.minus(Duration.ofMinutes(15)));
        }

        @Test
        void uncredited_orders_use_their_own_tighter_threshold() {
            Instant before = Instant.now();

            health.debitedWithoutCounterpart();

            Instant after = Instant.now();
            ArgumentCaptor<Instant> cutoff = ArgumentCaptor.forClass(Instant.class);
            verify(transactions).countDebitedWithoutCounterpartOlderThan(cutoff.capture());
            assertThat(cutoff.getValue()).isBetween(
                    before.minus(Duration.ofMinutes(5)), after.minus(Duration.ofMinutes(5)));
        }

        /**
         * Tighter on purpose: this one means money has already left a customer, and the cost of
         * looking at a settlement that turns out to be fine is a minute of somebody's attention.
         */
        @Test
        void the_uncredited_threshold_is_tighter_than_the_pending_one() {
            assertThat(health.getUncreditedThreshold())
                    .isLessThan(health.getPendingThreshold());
        }

        @Test
        void only_pending_legs_are_counted_as_stuck() {
            health.stuckLegs();

            verify(transactions).countByStatusAndCreatedAtBefore(
                    eq(AccountingTransaction.Status.PENDING), any());
        }
    }

    @Nested
    @DisplayName("what reaches Prometheus")
    class Metrics {

        private final SettlementMetrics binder = new SettlementMetrics();

        @Test
        void both_gauges_are_registered() {
            MeterRegistry registry = new SimpleMeterRegistry();

            binder.settlementHealthMetrics(health).bindTo(registry);

            assertThat(registry.find("delivery.settlement.stuck_legs").gauge()).isNotNull();
            assertThat(registry.find("delivery.settlement.debited_without_counterpart").gauge())
                    .isNotNull();
        }

        @Test
        void the_gauge_reports_what_the_service_found() {
            when(transactions.countDebitedWithoutCounterpartOlderThan(any())).thenReturn(4L);
            MeterRegistry registry = new SimpleMeterRegistry();

            binder.settlementHealthMetrics(health).bindTo(registry);

            assertThat(registry.find("delivery.settlement.debited_without_counterpart")
                    .gauge().value()).isEqualTo(4.0);
        }

        /**
         * The contract with {@code infra/prometheus/alerts.yml}, which matches on these strings and
         * has no other connection to this code. A rename or a stray base unit leaves the rule
         * matching nothing — it does not error, it simply never fires.
         */
        @Test
        void the_exported_names_are_what_the_alert_rules_match_on() {
            PrometheusMeterRegistry prometheus =
                    new PrometheusMeterRegistry(PrometheusConfig.DEFAULT);

            binder.settlementHealthMetrics(health).bindTo(prometheus);
            String scraped = prometheus.scrape();

            assertThat(scraped).contains("delivery_settlement_stuck_legs");
            assertThat(scraped).contains("delivery_settlement_debited_without_counterpart");
            // The specific way this breaks.
            assertThat(scraped).doesNotContain("delivery_settlement_stuck_legs_legs");
            assertThat(scraped).doesNotContain("delivery_settlement_debited_without_counterpart_orders");
        }
    }
}
