package com.delivery.product.api.dto;

import java.math.BigDecimal;
import java.util.List;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Digits;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.Size;

/** Request and response shapes for product options. */
public final class OptionDtos {

    private OptionDtos() {
    }

    // ---------------------------------------------------------------- responses

    public record OptionGroupResponse(
            UUID id,
            String name,
            int minSelect,
            int maxSelect,
            /** Convenience for the client, derived from minSelect — see ProductOptionGroup. */
            boolean required,
            boolean singleChoice,
            List<OptionResponse> options) {
    }

    public record OptionResponse(
            UUID id,
            String name,
            BigDecimal priceDelta,
            boolean isDefault,
            boolean available) {
    }

    /** What a configured line costs, and what to print on the receipt. */
    public record PriceResponse(
            BigDecimal basePrice,
            BigDecimal unitPrice,
            List<ChosenOptionResponse> options) {
    }

    public record ChosenOptionResponse(
            String groupName,
            String optionName,
            BigDecimal priceDelta) {
    }

    // ---------------------------------------------------------------- requests

    public record OptionGroupRequest(
            @NotBlank @Size(max = 120) String name,
            @Min(0) @Max(50) int minSelect,
            @Min(1) @Max(50) int maxSelect,
            @NotEmpty @Valid List<OptionRequest> options) {
    }

    public record OptionRequest(
            @NotBlank @Size(max = 120) String name,
            @Digits(integer = 10, fraction = 2) BigDecimal priceDelta,
            boolean isDefault) {
    }

    /**
     * Asks what a selection costs.
     *
     * <p>Ids only. Sending names or prices would let a client propose its own, which is the whole
     * thing this endpoint exists to prevent.
     */
    public record PriceRequest(
            List<UUID> optionIds) {
    }
}
