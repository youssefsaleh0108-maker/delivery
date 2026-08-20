package com.delivery.platform.outbox;

import org.slf4j.MDC;

/**
 * Reads the correlation id that {@code platform-observability} put into the logging MDC.
 *
 * <p>Kept as a tiny local accessor rather than a dependency on that module, so a service can use
 * the outbox without pulling in the tracing stack. The MDC key is the contract between the two.
 */
public final class CorrelationId {

    public static final String MDC_KEY = "correlationId";
    public static final String HEADER = "X-Correlation-Id";

    private CorrelationId() {
    }

    /** The current correlation id, or {@code null} outside a traced request (e.g. a scheduled job). */
    public static String current() {
        return MDC.get(MDC_KEY);
    }
}
