package com.delivery.appnotification.service;

import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.appnotification.domain.ChatShopMessage;
import com.delivery.appnotification.domain.ShopThreadSide;

/**
 * Puts a stored shop-thread message on the other side's screen, if they are watching.
 *
 * <p>Clients subscribe to {@code /user/queue/chat.shops}. Being under {@code /user/} is the whole
 * check that subscription needs: Spring resolves it to the subscriber's own principal, and this class
 * only ever addresses a frame to the thread's customer or to the shop's confirmed owner.
 *
 * <p>No push notification yet. Notifications Manager's chat listener is built around order
 * conversations (it needs an order id to render and deep-link a push), so a shop reply reaches a
 * customer who is not in the app only when they next open the shop's chat. Named as a follow-up
 * rather than faked with an order-shaped event.
 */
@Service
public class ShopDelivery {

    private static final Logger log = LoggerFactory.getLogger(ShopDelivery.class);

    public static final String SHOP_DESTINATION = "/queue/chat.shops";

    private final SimpMessagingTemplate websocket;
    private final ShopOwnership ownership;

    public ShopDelivery(SimpMessagingTemplate websocket, ShopOwnership ownership) {
        this.websocket = websocket;
        this.ownership = ownership;
    }

    /** {@code REQUIRES_NEW} for the reason {@code ChatDelivery.deliver} gives; runs after commit. */
    @Transactional(propagation = Propagation.REQUIRES_NEW, readOnly = true)
    public void deliver(ChatShopMessage message, UUID storeId, String customerId) {
        String recipient = message.getSenderSide() == ShopThreadSide.CUSTOMER
                ? ownership.lastConfirmedOwnerOf(storeId).orElse(null)
                : customerId;
        if (recipient == null || recipient.equals(message.getSenderId())) {
            // No merchant has opened their inbox since this shop was confirmed: they will see it there.
            return;
        }
        try {
            websocket.convertAndSendToUser(recipient, SHOP_DESTINATION,
                    ShopMessageView.of(message, storeId, recipient));
        } catch (Exception e) {
            log.warn("Live shop-thread frame for message {} could not be sent", message.getId(), e);
        }
    }
}
