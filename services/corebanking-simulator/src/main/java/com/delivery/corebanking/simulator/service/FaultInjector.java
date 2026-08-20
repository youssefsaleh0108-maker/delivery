package com.delivery.corebanking.simulator.service;

import java.time.Duration;
import java.util.concurrent.ThreadLocalRandom;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

/**
 * Makes the bank misbehave on demand.
 *
 * <p>The connector's circuit breaker, retry budget and dead-letter path are the parts of Phase 4
 * most likely to be wrong and least likely to be exercised, because the happy path always works in
 * dev. Without a way to take the bank down deliberately, the first real test of that code is a real
 * outage.
 *
 * <p>Two modes, for two different questions. A latency injection answers "what does a slow bank do
 * to the saga"; an outage answers "does a dead bank lose money or just delay it". Both are switched
 * on through an endpoint rather than configuration, so a test can turn them on and off within one
 * run.
 *
 * <p>Dev-only by construction — this whole service is (see the application class). Nothing here
 * ships to an environment where it could be triggered against real money.
 */
@Service
public class FaultInjector {

    private static final Logger log = LoggerFactory.getLogger(FaultInjector.class);

    private final AtomicReference<Mode> mode = new AtomicReference<>(Mode.HEALTHY);
    private final AtomicReference<Duration> latency = new AtomicReference<>(Duration.ZERO);

    /** Counts down when a fault is set to expire after N calls, for "fail twice then recover". */
    private final AtomicInteger remaining = new AtomicInteger(0);

    private final boolean enabled;

    public FaultInjector(@Value("${delivery.corebanking.fault-injection-enabled:true}") boolean enabled) {
        this.enabled = enabled;
    }

    public enum Mode {
        /** Behaves. */
        HEALTHY,
        /** Every call fails with a 503 — the bank is down. */
        UNAVAILABLE,
        /** Every call is slow, to trip the caller's read timeout. */
        SLOW,
        /** Fails roughly half the time, which is what actually opens a circuit breaker. */
        FLAKY
    }

    public void maybeFail() {
        if (!enabled || mode.get() == Mode.HEALTHY) {
            return;
        }

        // A fault with a countdown expires itself, so a test can assert recovery without a second
        // call to turn it off - and cannot leave the simulator broken for whatever runs next.
        if (remaining.get() > 0 && remaining.decrementAndGet() == 0) {
            log.info("Injected fault expired, back to HEALTHY");
            Mode expiring = mode.getAndSet(Mode.HEALTHY);
            applyFault(expiring);
            return;
        }

        applyFault(mode.get());
    }

    private void applyFault(Mode current) {
        switch (current) {
            case UNAVAILABLE -> throw new InjectedFaultException("Core banking is unavailable");
            case FLAKY -> {
                if (ThreadLocalRandom.current().nextBoolean()) {
                    throw new InjectedFaultException("Core banking is degraded");
                }
            }
            case SLOW -> {
                try {
                    Thread.sleep(latency.get().toMillis());
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                }
            }
            case HEALTHY -> {
                // nothing
            }
        }
    }

    /**
     * @param callCount how many calls the fault lasts for; 0 means until switched off explicitly
     */
    public void set(Mode newMode, Duration newLatency, int callCount) {
        mode.set(newMode);
        latency.set(newLatency == null ? Duration.ZERO : newLatency);
        remaining.set(Math.max(callCount, 0));
        log.warn("Fault injection set to {} (latency {}, {} calls)",
                newMode, latency.get(), callCount == 0 ? "until reset" : callCount);
    }

    public Mode mode() {
        return mode.get();
    }

    public Duration latency() {
        return latency.get();
    }

    public boolean isEnabled() {
        return enabled;
    }

    public static class InjectedFaultException extends RuntimeException {
        public InjectedFaultException(String message) {
            super(message);
        }
    }
}
