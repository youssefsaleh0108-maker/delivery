package com.delivery.whatsapp.service;

import java.util.Optional;
import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import com.delivery.whatsapp.domain.DraftOrder;
import com.delivery.whatsapp.repo.DraftOrderRepository;

/**
 * Telling the customer what happened to their order.
 *
 * <p>The confirmation sent at placement says "we will message you when it is on the way". This is
 * what keeps that promise — and keeping it matters more than it sounds, because a customer who
 * ordered over chat has no app to open and no tracking screen to refresh. The thread is the only
 * thing they have.
 */
@Service
public class OrderUpdateService {

    private static final Logger log = LoggerFactory.getLogger(OrderUpdateService.class);

    private final DraftOrderRepository drafts;
    private final OrderUpdateLog alreadySent;
    private final ConversationService conversations;

    public OrderUpdateService(DraftOrderRepository drafts,
                              OrderUpdateLog alreadySent,
                              ConversationService conversations) {
        this.drafts = drafts;
        this.alreadySent = alreadySent;
        this.conversations = conversations;
    }

    /**
     * What to say, or nothing at all.
     *
     * <p>Three statuses out of seven, and the omissions are the design. PLACED is already covered by
     * the confirmation sent at placement. ACCEPTED and PREPARING are the merchant accepting and
     * cooking an order they typed in themselves — they tell the customer nothing they were not
     * already told. READY means the food is on a counter, which is our logistics, not their
     * business.
     *
     * <p>What is left is the three things a customer genuinely cannot know and genuinely wants: it
     * has left, it has arrived, or it is not coming. Every extra message pushes their real
     * conversation with the shop further up the screen, so the bar for sending one is high.
     */
    static String messageFor(String status, String cancelReason) {
        return switch (status) {
            case "PICKED_UP" -> "Your order is on the way.";
            case "DELIVERED" -> "Your order has been delivered. Thank you!";
            case "CANCELLED" -> cancelReason == null || cancelReason.isBlank()
                    ? "Your order has been cancelled. Please contact us if this is unexpected."
                    // The reason travels with the message. "Your order was cancelled" with no
                    // explanation generates a phone call, which is the thing this feature exists
                    // to save the merchant.
                    : "Your order has been cancelled: " + cancelReason;
            default -> null;
        };
    }

    /**
     * Handles one order status event.
     *
     * <p>Silently ignores orders that did not come from WhatsApp, which is nearly all of them: the
     * queue is bound to {@code order.#} because a narrower binding would need changing every time
     * Order Manager adds an event type, and filtering here is cheap.
     */
    public void onStatus(UUID orderId, String status, String cancelReason) {
        String body = messageFor(status, cancelReason);
        if (body == null) {
            return;
        }

        Optional<DraftOrder> draft = drafts.findByOrderId(orderId);
        if (draft.isEmpty()) {
            // An ordinary app order. Its customer has the app's own notifications.
            return;
        }

        DraftOrder source = draft.get();
        if (!alreadySent.claim(orderId, status, source.getConversationId())) {
            log.debug("Already told the customer about order {} reaching {}", orderId, status);
            return;
        }

        // Claimed first, then sent. The other order — send, then record — would send the message
        // again on every redelivery whose record failed to commit, and a customer told twice that
        // their food is on the way is being told the platform is broken.
        //
        // The cost of this choice is that a failed send is not retried. That is deliberate: the
        // reply is still written into the thread with its failure attached, exactly as a merchant's
        // own failed reply is, so the shop can see it did not go out and say so themselves.
        try {
            conversations.reply(source.getConversationId(), source.getMerchantRef(), body);
            log.info("Told the customer that order {} reached {}", orderId, status);
        } catch (Exception e) {
            log.error("Could not tell the customer about order {} reaching {}", orderId, status, e);
        }
    }
}
