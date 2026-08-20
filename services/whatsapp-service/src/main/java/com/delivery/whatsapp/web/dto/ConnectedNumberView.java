package com.delivery.whatsapp.web.dto;

import java.time.Instant;

import com.delivery.whatsapp.domain.ConnectedNumber;

public record ConnectedNumberView(
        String phoneNumberId,
        String label,
        String displayNumber,
        Instant connectedAt) {

    public static ConnectedNumberView of(ConnectedNumber number) {
        return new ConnectedNumberView(
                number.getPhoneNumberId(),
                number.getLabel(),
                number.getDisplayNumber(),
                number.getConnectedAt());
    }
}
