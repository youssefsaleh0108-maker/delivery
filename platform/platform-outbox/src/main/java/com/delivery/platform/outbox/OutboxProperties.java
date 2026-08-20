package com.delivery.platform.outbox;

import java.time.Duration;

import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties(prefix = "delivery.outbox")
public class OutboxProperties {

    /** Whether the relay polls at all. Off in tests, and off in any read-only replica. */
    private boolean relayEnabled = true;

    /** Topic exchange every domain event is published to. */
    private String exchange = "delivery.events";

    /** How many events one relay tick claims. Bounded so a backlog drains steadily. */
    private int batchSize = 100;

    /** Gap between relay ticks. */
    private Duration pollInterval = Duration.ofSeconds(2);

    /**
     * Publish attempts before an event is marked DEAD_LETTERED and left for an operator. Section 10
     * requires exhausted retries to land somewhere visible rather than being dropped.
     *
     * <p>Read together with {@link #retryBackoff}: attempts alone say nothing about how long the
     * relay tolerates an outage. Eight attempts on the backoff schedule below spans roughly twenty
     * minutes, which is what a broker restart or a rolling upgrade actually needs.
     */
    private int maxAttempts = 8;

    /**
     * Delay before the first retry, doubling per attempt up to {@link #maxRetryBackoff}.
     *
     * <p>This exists because retrying on every tick made an outage indistinguishable from a poison
     * message: with the old 2s poll and 5 attempts, eleven seconds of broker downtime — less than a
     * restart — dead-lettered every pending event in every service.
     */
    private Duration retryBackoff = Duration.ofSeconds(10);

    /** Ceiling on the doubling, so a long outage retries steadily rather than at growing intervals. */
    private Duration maxRetryBackoff = Duration.ofMinutes(5);

    public boolean isRelayEnabled() {
        return relayEnabled;
    }

    public void setRelayEnabled(boolean relayEnabled) {
        this.relayEnabled = relayEnabled;
    }

    public String getExchange() {
        return exchange;
    }

    public void setExchange(String exchange) {
        this.exchange = exchange;
    }

    public int getBatchSize() {
        return batchSize;
    }

    public void setBatchSize(int batchSize) {
        this.batchSize = batchSize;
    }

    public Duration getPollInterval() {
        return pollInterval;
    }

    public void setPollInterval(Duration pollInterval) {
        this.pollInterval = pollInterval;
    }

    public int getMaxAttempts() {
        return maxAttempts;
    }

    public void setMaxAttempts(int maxAttempts) {
        this.maxAttempts = maxAttempts;
    }

    public Duration getRetryBackoff() {
        return retryBackoff;
    }

    public void setRetryBackoff(Duration retryBackoff) {
        this.retryBackoff = retryBackoff;
    }

    public Duration getMaxRetryBackoff() {
        return maxRetryBackoff;
    }

    public void setMaxRetryBackoff(Duration maxRetryBackoff) {
        this.maxRetryBackoff = maxRetryBackoff;
    }
}
