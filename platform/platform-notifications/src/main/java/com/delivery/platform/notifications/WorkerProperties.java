package com.delivery.platform.notifications;

import java.time.Duration;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * Everything a channel worker needs to know about itself.
 *
 * <p>Setting {@code delivery.worker.channel} is what turns a plain Spring Boot service into a
 * channel worker: {@link WorkerAutoConfiguration} keys off it and contributes the channel queue,
 * the connector client, the resilience wrapper and the receipt publisher.
 */
@ConfigurationProperties(prefix = "delivery.worker")
public class WorkerProperties {

    /** SMS, EMAIL, PUSH or IN_APP. Decides the queue and the routing key this worker consumes. */
    private String channel;

    /** Base URL of this worker's own connector, inside the cluster network. */
    private String connectorUrl;

    /**
     * Resilience around the call to the connector.
     *
     * <p>Note this is a second, independent breaker from the one the connector puts around the
     * provider. They protect different things: the connector's breaker stops hammering a dead
     * vendor, this one stops the worker's threads piling up against a connector that is itself
     * unreachable or wedged.
     */
    private int maxAttempts = 3;
    private Duration initialBackoff = Duration.ofMillis(500);
    private float failureRateThreshold = 50f;
    private Duration openStateDuration = Duration.ofSeconds(30);

    /** How long to wait on the connector before treating the call as a transient failure. */
    private Duration connectorTimeout = Duration.ofSeconds(10);

    private String deadLetterQueue = "notification.dlq";

    public String getChannel() {
        return channel;
    }

    public void setChannel(String channel) {
        this.channel = channel;
    }

    public String getConnectorUrl() {
        return connectorUrl;
    }

    public void setConnectorUrl(String connectorUrl) {
        this.connectorUrl = connectorUrl;
    }

    public int getMaxAttempts() {
        return maxAttempts;
    }

    public void setMaxAttempts(int maxAttempts) {
        this.maxAttempts = maxAttempts;
    }

    public Duration getInitialBackoff() {
        return initialBackoff;
    }

    public void setInitialBackoff(Duration initialBackoff) {
        this.initialBackoff = initialBackoff;
    }

    public float getFailureRateThreshold() {
        return failureRateThreshold;
    }

    public void setFailureRateThreshold(float failureRateThreshold) {
        this.failureRateThreshold = failureRateThreshold;
    }

    public Duration getOpenStateDuration() {
        return openStateDuration;
    }

    public void setOpenStateDuration(Duration openStateDuration) {
        this.openStateDuration = openStateDuration;
    }

    public Duration getConnectorTimeout() {
        return connectorTimeout;
    }

    public void setConnectorTimeout(Duration connectorTimeout) {
        this.connectorTimeout = connectorTimeout;
    }

    public String getDeadLetterQueue() {
        return deadLetterQueue;
    }

    public void setDeadLetterQueue(String deadLetterQueue) {
        this.deadLetterQueue = deadLetterQueue;
    }

    /** {@code notification.dispatch.sms} and friends — queue name and routing key are the same. */
    public String queueName() {
        return NotificationCommand.routingKeyFor(channel);
    }
}
