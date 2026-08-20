package com.delivery.whatsapp.web.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

/**
 * A merchant claiming a WhatsApp number.
 *
 * @param phoneNumberId the provider's id for the number — what arrives on the webhook, and the only
 *                      field that routes anything
 * @param label         what the merchant calls it, so a shop with two lines can tell them apart
 * @param displayNumber the readable number, for the merchant's own benefit
 */
public record ConnectNumberRequest(
        @NotBlank @Size(max = 64) String phoneNumberId,
        @Size(max = 120) String label,
        @Size(max = 32) String displayNumber) {
}
