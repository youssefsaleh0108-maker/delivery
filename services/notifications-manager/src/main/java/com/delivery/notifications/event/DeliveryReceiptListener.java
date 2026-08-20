package com.delivery.notifications.event;

import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.notifications.domain.NotificationLog;
import com.delivery.notifications.domain.NotificationLogRepository;
import com.delivery.platform.notifications.DeliveryReceipt;
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * Closes the loop: records what the workers actually managed to deliver.
 *
 * <p>The manager writes each notification_log row as PENDING before dispatch and then hears nothing
 * — the worker is a separate process consuming off a queue. Without this listener every row would
 * stay PENDING, the "what is stuck" index would be full of messages that were delivered fine, and
 * the log would be useless for the one question it exists to answer.
 *
 * <p>Idempotent by construction. Receipts are at-least-once like everything else on the bus, and
 * applying the same terminal state twice changes nothing.
 */
@Component
public class DeliveryReceiptListener {

    private static final Logger log = LoggerFactory.getLogger(DeliveryReceiptListener.class);

    private final NotificationLogRepository logs;
    private final ObjectMapper objectMapper;

    public DeliveryReceiptListener(NotificationLogRepository logs, ObjectMapper objectMapper) {
        this.logs = logs;
        this.objectMapper = objectMapper;
    }

    @RabbitListener(queues = "${delivery.notifications.receipts-queue:notifications.receipts}")
    @Transactional
    public void onReceipt(String payload) {
        try {
            DeliveryReceipt receipt = objectMapper.readValue(payload, DeliveryReceipt.class);
            UUID notificationId = UUID.fromString(receipt.notificationId());

            NotificationLog entry = logs.findById(notificationId).orElse(null);
            if (entry == null) {
                // A receipt for a row this service has no record of. Should be impossible — the
                // row is committed before the command is published — so it is worth a warning
                // rather than a silent skip.
                log.warn("Receipt for unknown notification {}", notificationId);
                return;
            }

            if (receipt.success()) {
                entry.markSent(receipt.provider(), receipt.providerMessageId());
            } else {
                entry.markFailed(receipt.provider(), receipt.failureReason(), receipt.deadLettered());
            }
            logs.save(entry);

            log.debug("Notification {} on {} via {}: {}", notificationId, receipt.channel(),
                    receipt.provider(), entry.getStatus());

        } catch (Exception e) {
            // Acked regardless: a receipt that cannot be parsed is a bookkeeping loss, and
            // requeuing it forever would block every subsequent receipt behind it.
            log.error("Could not apply delivery receipt: {}", payload, e);
        }
    }
}
