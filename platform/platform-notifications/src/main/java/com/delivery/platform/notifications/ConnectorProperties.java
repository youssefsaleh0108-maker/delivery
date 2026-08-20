package com.delivery.platform.notifications;

import java.time.Duration;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * Everything a provider connector needs to know about itself.
 *
 * <p>Setting {@code delivery.connector.type} is what turns a plain Spring Boot service into a
 * connector: {@link ConnectorAutoConfiguration} keys off it and contributes the registry, the
 * settings queue and binding, the bus listener and the refresh timer. That keeps the three
 * connectors from re-implementing the same wiring three times and drifting apart.
 */
@ConfigurationProperties(prefix = "delivery.connector")
public class ConnectorProperties {

    /** SMS, EMAIL, PUSH — must match a {@code ConnectorType} in Connector Settings. */
    private String type;

    /** What to use before Connector Settings has ever been reached. Never null in practice. */
    private String defaultProvider;

    /** This connector's own queue for {@code connector.settings_changed}. */
    private String settingsQueue;

    /** Base URL of Connector Settings, for the TTL refresh. */
    private String settingsUrl = "http://connector-settings:8109";

    /**
     * How long a cached provider stays trusted without confirmation. Short enough that a missed
     * event is corrected in minutes, long enough that Connector Settings is not polled hard by
     * every connector.
     */
    private Duration cacheTtl = Duration.ofMinutes(5);

    /** Resilience4j settings for the outbound provider call (Section 10). */
    private int maxAttempts = 3;
    private Duration initialBackoff = Duration.ofMillis(500);
    private float failureRateThreshold = 50f;
    private Duration openStateDuration = Duration.ofSeconds(30);

    /** Where a message that exhausted retries is parked for an operator. */
    private String deadLetterQueue = "notification.dlq";

    public String getType() {
        return type;
    }

    public void setType(String type) {
        this.type = type;
    }

    public String getDefaultProvider() {
        return defaultProvider;
    }

    public void setDefaultProvider(String defaultProvider) {
        this.defaultProvider = defaultProvider;
    }

    public String getSettingsQueue() {
        return settingsQueue;
    }

    public void setSettingsQueue(String settingsQueue) {
        this.settingsQueue = settingsQueue;
    }

    public String getSettingsUrl() {
        return settingsUrl;
    }

    public void setSettingsUrl(String settingsUrl) {
        this.settingsUrl = settingsUrl;
    }

    public Duration getCacheTtl() {
        return cacheTtl;
    }

    public void setCacheTtl(Duration cacheTtl) {
        this.cacheTtl = cacheTtl;
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

    public String getDeadLetterQueue() {
        return deadLetterQueue;
    }

    public void setDeadLetterQueue(String deadLetterQueue) {
        this.deadLetterQueue = deadLetterQueue;
    }
}
