package com.delivery.whatsapp.web.dto;

import java.time.Instant;
import java.util.UUID;

import com.delivery.whatsapp.domain.WhatsAppMessage;

/**
 * One line of the thread.
 *
 * <p>{@code messageType} travels alongside the body so the client can be honest about a message it
 * cannot render: a voice note shows as a voice note rather than as an empty bubble the merchant
 * would read as a lost message.
 */
public record MessageView(
        UUID id,
        String direction,
        String body,
        String messageType,
        Instant sentAt) {

    public static MessageView of(WhatsAppMessage message) {
        return new MessageView(
                message.getId(),
                message.getDirection().name(),
                message.getBody(),
                message.getMessageType().name(),
                message.getSentAt());
    }
}
