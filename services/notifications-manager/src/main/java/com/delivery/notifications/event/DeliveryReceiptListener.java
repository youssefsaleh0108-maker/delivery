package com.delivery.notifications.event;

import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.notifications.domain.NotificationLog;
import com.delivery.notifications.domain.NotificationLogRepository;
import com.delivery.notifications.domain.SuppressedAddress;
import com.delivery.notifications.domain.SuppressedAddressRepository;
import com.delivery.notifications.service.RecipientDirectory;
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
    private final SuppressedAddressRepository suppressions;
    private final RecipientDirectory recipients;
    private final ObjectMapper objectMapper;

    public DeliveryReceiptListener(NotificationLogRepository logs,
                                   SuppressedAddressRepository suppressions,
                                   RecipientDirectory recipients,
                                   ObjectMapper objectMapper) {
        this.logs = logs;
        this.suppressions = suppressions;
        this.recipients = recipients;
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
                if (receipt.addressInvalid()) {
                    suppress(entry, receipt);
                }
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

    /**
     * Stops the platform using an address the provider says is dead.
     *
     * <p>The trigger is the provider's own verdict on the ADDRESS, not merely that the message
     * failed — an outage that exhausts its retries is also dead-lettered and must not cost a
     * customer their phone number.
     *
     * <p>Recorded rather than corrected: the address stays on the user in Keycloak, and a reinstall
     * registers a new token that this table has never heard of, so the user becomes reachable again
     * on their own. Nothing here needs an operator to undo it.
     */
    private void suppress(NotificationLog entry, DeliveryReceipt receipt) {
        try {
            SuppressedAddress.Key key =
                    new SuppressedAddress.Key(entry.getChannel(), entry.getRecipient());
            if (suppressions.existsById(key)) {
                return;
            }
            suppressions.save(new SuppressedAddress(
                    entry.getChannel(), entry.getRecipient(), entry.getRecipientId(),
                    receipt.failureReason(), receipt.provider()));
            // Otherwise the address stays in the resolver's cache and keeps being handed out until
            // the TTL lapses.
            recipients.evict(entry.getRecipientId());
            log.info("Suppressed a {} address for {}: provider reported it undeliverable",
                    entry.getChannel(), entry.getRecipientId());
        } catch (Exception e) {
            // The notification's own outcome is already recorded; failing to also suppress is worth
            // a warning, not losing the receipt.
            log.warn("Could not suppress {} address for {}: {}",
                    entry.getChannel(), entry.getRecipientId(), e.getMessage());
        }
    }
}
