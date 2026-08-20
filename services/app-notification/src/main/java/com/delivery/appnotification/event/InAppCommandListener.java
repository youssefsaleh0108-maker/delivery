package com.delivery.appnotification.event;

import java.time.Instant;
import java.util.Map;
import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.slf4j.MDC;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.core.MessageProperties;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import com.delivery.appnotification.service.InAppMessageService;
import com.delivery.platform.notifications.DeliveryOutcome;
import com.delivery.platform.notifications.DeliveryReceipt;
import com.delivery.platform.notifications.NotificationCommand;
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * Consumes {@code notification.dispatch.in_app} and turns each command into an inbox row.
 *
 * <p>This service is the IN_APP channel's worker and connector at once, and reasonably so: there is
 * no external provider to isolate and no credential to keep away from anything, which is the entire
 * justification for splitting those two roles on the other three channels. Applying the split here
 * anyway would add a process whose only job is to forward a message to the next process.
 *
 * <p>It still reports a {@link DeliveryReceipt} like any other channel, so the notification_log
 * treats in-app the same as everything else and does not need a special case for the one channel
 * that never reaches PENDING-to-SENT on its own.
 */
@Component
public class InAppCommandListener {

    private static final Logger log = LoggerFactory.getLogger(InAppCommandListener.class);

    private static final String PROVIDER = "IN_APP";

    private final InAppMessageService messages;
    private final RabbitTemplate rabbit;
    private final ObjectMapper objectMapper;
    private final String exchange;

    public InAppCommandListener(InAppMessageService messages, RabbitTemplate rabbit,
                                ObjectMapper objectMapper,
                                @Value("${delivery.outbox.exchange:delivery.events}") String exchange) {
        this.messages = messages;
        this.rabbit = rabbit;
        this.objectMapper = objectMapper;
        this.exchange = exchange;
    }

    @RabbitListener(queues = "#{inAppCommandQueue.name}")
    public void onCommand(String payload) {
        NotificationCommand command;
        try {
            command = objectMapper.readValue(payload, NotificationCommand.class);
        } catch (Exception e) {
            // Nothing identifiable to report a receipt against. Acked so it cannot poison the queue.
            log.error("Unreadable in-app command, dropping: {}", payload, e);
            return;
        }

        // Rejoins this work to the request that caused it. The command already carries the id — it
        // simply was not being put back into the logging context, so in-app delivery was invisible
        // to a correlation-id search until the Phase 5 review looked for it.
        boolean correlated = command.correlationId() != null;
        if (correlated) {
            MDC.put(CORRELATION_MDC_KEY, command.correlationId());
        }

        try {
            Map<String, String> metadata = command.metadata() == null ? Map.of() : command.metadata();
            String orderIdText = metadata.get("orderId");

            messages.record(
                    UUID.fromString(command.notificationId()),
                    // For IN_APP the "recipient" is the Keycloak sub, not an address.
                    command.recipient(),
                    orderIdText == null || orderIdText.isBlank() ? null : UUID.fromString(orderIdText),
                    metadata.getOrDefault("eventType", "notification"),
                    command.subject() == null || command.subject().isBlank()
                            ? "Delivery" : command.subject(),
                    command.body(),
                    metadata);

            // Reported as sent whether or not the row was new: a redelivery means the message is
            // already in the user's inbox, which is the successful state.
            report(DeliveryReceipt.from(command, PROVIDER,
                    DeliveryOutcome.sent(PROVIDER, command.notificationId())));

        } catch (Exception e) {
            log.error("Could not record in-app message {}", command.notificationId(), e);
            report(DeliveryReceipt.from(command, PROVIDER,
                    DeliveryOutcome.permanentFailure(PROVIDER, e.getMessage())));

        } finally {
            if (correlated) {
                MDC.remove(CORRELATION_MDC_KEY);
            }
        }
    }

    /** Matches the key platform-observability's filter uses on the HTTP side. */
    private static final String CORRELATION_MDC_KEY = "correlationId";

    private void report(DeliveryReceipt receipt) {
        try {
            MessageProperties props = new MessageProperties();
            props.setContentType(MessageProperties.CONTENT_TYPE_JSON);
            props.setMessageId(receipt.notificationId());
            props.setTimestamp(java.util.Date.from(Instant.now()));

            rabbit.send(exchange, DeliveryReceipt.ROUTING_KEY,
                    new Message(objectMapper.writeValueAsBytes(receipt), props));

        } catch (Exception e) {
            log.error("Could not report the outcome of in-app {}", receipt.notificationId(), e);
        }
    }
}
