package com.delivery.appnotification.service;

import java.time.Instant;
import java.util.UUID;

import com.delivery.appnotification.domain.ChatShopMessage;

/**
 * One shop-thread message as either side sees it, in history and in a live frame alike.
 *
 * <p>The side, never the account: a customer is told "the shop" said something, not which of its
 * people typed it, and the shop is told "the customer", with the name the thread carries.
 */
public record ShopMessageView(
        UUID id,
        UUID threadId,
        UUID storeId,
        long sequence,
        String side,
        boolean mine,
        String text,
        UUID orderId,
        Instant sentAt,
        Instant readAt) {

    public static ShopMessageView of(ChatShopMessage message, UUID storeId, String viewerId) {
        return new ShopMessageView(
                message.getId(),
                message.getThreadId(),
                storeId,
                message.getSequenceNo(),
                message.getSenderSide().name(),
                message.getSenderId().equals(viewerId),
                message.getBody(),
                message.getOrderId(),
                message.getCreatedAt(),
                message.getReadAt());
    }
}
