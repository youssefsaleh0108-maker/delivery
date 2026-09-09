package com.delivery.platform.observability;

import java.time.Duration;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * How long any service waits on another before giving up.
 *
 * <p>Overridable per service under {@code delivery.clients}, and deliberately the same two numbers
 * everywhere by default: a service that needs different ones is making a claim about a particular
 * dependency, and that claim is worth writing down where the dependency is configured.
 *
 * @param connectTimeout how long to wait for the far end to accept a connection
 * @param readTimeout    how long to wait for it to answer once it has
 */
@ConfigurationProperties(prefix = "delivery.clients")
public record OutboundCallDefaults(Duration connectTimeout, Duration readTimeout) {

    public OutboundCallDefaults {
        connectTimeout = connectTimeout == null ? Duration.ofSeconds(2) : connectTimeout;
        readTimeout = readTimeout == null ? Duration.ofSeconds(5) : readTimeout;
    }
}
