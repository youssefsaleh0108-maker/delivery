package com.delivery.notifications.event;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.notifications.domain.NotificationLog;
import com.delivery.notifications.domain.NotificationLogRepository;
import com.delivery.platform.notifications.ProviderDeliveryReceipt;
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * Applies what the carrier said, closing the gap between "accepted" and "arrived".
 *
 * <p>{@link DeliveryReceiptListener} beside this one records whether our worker got the message into
 * a provider's hands. This records whether the handset ever got it — the two are different facts and
 * are stored on different columns, so a message can read SENT and UNDELIVERED at once, which is
 * precisely the case worth being able to see.
 *
 * <p>Matched on the vendor's message id rather than ours: the callback comes from a system that has
 * never seen our notification ids. Scoped by provider as well, because two vendors will happily
 * issue the same id string and a cross-vendor collision would silently mark the wrong message.
 */
@Component
public class ProviderDeliveryReceiptListener {

    private static final Logger log = LoggerFactory.getLogger(ProviderDeliveryReceiptListener.class);

    private final NotificationLogRepository logs;
    private final ObjectMapper objectMapper;

    public ProviderDeliveryReceiptListener(NotificationLogRepository logs, ObjectMapper objectMapper) {
        this.logs = logs;
        this.objectMapper = objectMapper;
    }

    @RabbitListener(queues = "${delivery.notifications.dlr-queue:notifications.dlr}")
    @Transactional
    public void onProviderReceipt(String payload) {
        try {
            ProviderDeliveryReceipt receipt =
                    objectMapper.readValue(payload, ProviderDeliveryReceipt.class);

            NotificationLog entry = logs
                    .findByProviderAndProviderMessageId(receipt.provider(), receipt.providerMessageId())
                    .orElse(null);

            if (entry == null) {
                // Genuinely expected, and not an error: a carrier can deliver a receipt for a
                // message sent by another environment pointed at the same vendor account, or one
                // whose log row has aged out. Info, not warn — a real deployment sharing a vendor
                // sandbox would otherwise fill the log with alarms about nothing.
                log.info("DLR for unknown {} message {}",
                        receipt.provider(), receipt.providerMessageId());
                return;
            }

            NotificationLog.DeliveryStatus reported = receipt.delivered()
                    ? NotificationLog.DeliveryStatus.DELIVERED
                    : NotificationLog.DeliveryStatus.UNDELIVERED;

            boolean applied = entry.applyDeliveryReceipt(reported, receipt.detail(), receipt.occurredAt());
            if (!applied) {
                // Either a redelivery of the same receipt, which is normal on an at-least-once bus,
                // or the carrier contradicting itself, which is not. Only the second is worth
                // reading, so only the second is logged above debug.
                if (entry.getDeliveryStatus() != reported) {
                    log.warn("{} contradicted itself on message {}: already {}, now reports {}",
                            receipt.provider(), receipt.providerMessageId(),
                            entry.getDeliveryStatus(), reported);
                }
                return;
            }

            logs.save(entry);
            log.debug("Notification {} reported {} by {}",
                    entry.getId(), reported, receipt.provider());

        } catch (Exception e) {
            // Acked regardless, for the same reason as the worker receipts: an unparseable receipt
            // is a bookkeeping loss, and requeuing it forever blocks every later one behind it.
            log.error("Could not apply a provider delivery receipt: {}", payload, e);
        }
    }
}
