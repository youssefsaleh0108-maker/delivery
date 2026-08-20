package com.delivery.accounting.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import com.delivery.accounting.service.SettlementHealthService;

import io.micrometer.core.instrument.Gauge;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.binder.MeterBinder;

/**
 * Publishes the settlement health figures so something outside this process can watch them.
 *
 * <p>Gauges rather than a scheduled job writing to a field: Micrometer calls the supplier when
 * Prometheus scrapes, so the number is computed on demand and there is no interval to tune, no
 * cached value to go stale, and nothing to keep running if the scrape stops. Two indexed counts
 * every fifteen seconds is not a load worth optimising away.
 *
 * <p>The alert rules that consume these live in {@code infra/prometheus/alerts.yml}. A metric with
 * nothing watching it is only marginally better than no metric at all — the point is not that the
 * number exists, it is that somebody is told.
 */
@Configuration(proxyBeanMethods = false)
public class SettlementMetrics {

    @Bean
    public MeterBinder settlementHealthMetrics(SettlementHealthService health) {
        return (MeterRegistry registry) -> {
            // No baseUnit on any of these on purpose: the Prometheus registry appends it to the
            // exported name, so a gauge built with baseUnit("legs") scrapes as
            // delivery_settlement_stuck_legs_legs and every alert expression written against the
            // obvious name silently matches nothing.
            Gauge.builder("delivery.settlement.stuck_legs", health::stuckLegs)
                    .description("Settlement legs still PENDING beyond the configured threshold")
                    .register(registry);

            // The one to page on. Anything above zero is money taken from a customer that has
            // reached nobody — see SettlementHealthService for why nothing else can detect it.
            Gauge.builder("delivery.settlement.debited_without_counterpart",
                            health::debitedWithoutCounterpart)
                    .description("Orders where the customer was debited and no credit has posted")
                    .register(registry);
        };
    }
}
