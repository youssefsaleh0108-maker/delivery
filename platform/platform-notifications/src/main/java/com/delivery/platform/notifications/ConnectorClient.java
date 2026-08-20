package com.delivery.platform.notifications;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.web.client.RestClient;

/**
 * A worker's call to its connector.
 *
 * <p>Synchronous HTTP rather than a second queue hop. The worker has already been handed the
 * message asynchronously off its own channel queue, so nothing is blocking a user; adding another
 * queue between worker and connector would buy nothing and would make the delivery outcome — which
 * the worker must report back — arrive by yet another route.
 *
 * <p>Any transport-level problem is reported as a <em>transient</em> failure. This is deliberate:
 * the connector may well have delivered the message before the connection dropped, and the
 * idempotency key on the command is what makes a retry safe rather than a second SMS.
 */
public class ConnectorClient {

    private static final Logger log = LoggerFactory.getLogger(ConnectorClient.class);

    private final RestClient client;
    private final String channel;

    public ConnectorClient(RestClient client, String channel) {
        this.client = client;
        this.channel = channel;
    }

    public DeliveryOutcome send(NotificationCommand command) {
        try {
            DeliveryOutcome outcome = client.post()
                    .uri(NotificationCommand.CONNECTOR_SEND_PATH)
                    .headers(headers -> {
                        headers.add(IDEMPOTENCY_KEY_HEADER, command.notificationId());
                        // Threads the correlation id across the process boundary so one customer
                        // action stays one trace all the way to the provider (Section 10). Absent
                        // for anything not triggered by a request, so it is added conditionally.
                        if (command.correlationId() != null) {
                            headers.add(CORRELATION_ID_HEADER, command.correlationId());
                        }
                    })
                    .body(command)
                    .retrieve()
                    .body(DeliveryOutcome.class);

            if (outcome == null) {
                return DeliveryOutcome.transientFailure("connector returned an empty body");
            }
            return outcome;

        } catch (Exception e) {
            log.warn("{} connector call failed for {}: {}",
                    channel, command.notificationId(), e.getMessage());
            return DeliveryOutcome.transientFailure("connector unreachable: " + e.getMessage());
        }
    }

    /** Echoed by the connector into its provider call so a retry cannot double-send. */
    public static final String IDEMPOTENCY_KEY_HEADER = "X-Idempotency-Key";

    /**
     * Matches {@code CorrelationIdFilter.HEADER} in platform-observability. Duplicated rather than
     * imported so this library does not drag the tracing stack into every service that uses it —
     * the header name is the contract between the two, the same way platform-outbox treats it.
     */
    public static final String CORRELATION_ID_HEADER = "X-Correlation-Id";
}
