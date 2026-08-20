package com.delivery.platform.outbox;

import org.springframework.transaction.annotation.Transactional;

import io.micrometer.core.instrument.Gauge;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.binder.MeterBinder;

/**
 * Publishes what is sitting in this service's outbox.
 *
 * <p>The relay already writes a log line when it dead-letters something, and that line has never
 * been enough: it is one ERROR among everything else a service logs, in one of a dozen containers,
 * at whatever hour the broker had its problem. {@code DEAD_LETTERED} means an event that some other
 * service is waiting for will never arrive — an order that never notifies, never settles, never
 * projects — and the code has always said it "needs an operator" without giving anyone a way to
 * know.
 *
 * <p>Two numbers, because they fail differently. A rising <em>dead-letter</em> count is damage that
 * has already happened and will not resolve itself. A rising <em>pending</em> count is damage in
 * progress — the relay is not keeping up, or cannot reach the broker at all — and it is the one that
 * can still be caught before anything is lost.
 *
 * <p>Lives in the platform library rather than in each service, so every service that uses the
 * outbox reports these without anyone remembering to wire it up. That matters more than the saving:
 * the service most likely to be forgotten is the one nobody is thinking about.
 */
public class OutboxMetrics implements MeterBinder {

    private final OutboxEventRepository repository;

    public OutboxMetrics(OutboxEventRepository repository) {
        this.repository = repository;
    }

    @Override
    public void bindTo(MeterRegistry registry) {
        // No baseUnit: the Prometheus registry appends it to the exported name, so
        // baseUnit("events") would scrape as delivery_outbox_dead_lettered_events and every alert
        // written against the obvious name would silently match nothing.
        Gauge.builder("delivery.outbox.dead_lettered", this::deadLettered)
                .description("Outbox events that exhausted their retries and need an operator")
                .register(registry);

        Gauge.builder("delivery.outbox.pending", this::pending)
                .description("Outbox events written but not yet published")
                .register(registry);
    }

    /**
     * Counted on scrape rather than tracked incrementally.
     *
     * <p>A counter incremented by the relay would miss every row dead-lettered by a different
     * replica, and would reset to zero on restart — which is the moment the number matters most.
     * The table is the only thing that knows the real total.
     */
    @Transactional(readOnly = true)
    public long deadLettered() {
        return repository.countByStatus(OutboxEvent.Status.DEAD_LETTERED);
    }

    @Transactional(readOnly = true)
    public long pending() {
        return repository.countByStatus(OutboxEvent.Status.PENDING);
    }
}
