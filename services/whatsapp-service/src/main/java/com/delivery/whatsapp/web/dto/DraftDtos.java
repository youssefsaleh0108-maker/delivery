package com.delivery.whatsapp.web.dto;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;
import java.util.UUID;

import com.delivery.whatsapp.domain.DraftLine;
import com.delivery.whatsapp.domain.DraftLineOption;
import com.delivery.whatsapp.domain.DraftOrder;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

public final class DraftDtos {

    private DraftDtos() {
    }

    /** Optional text — normally the customer's own words, copied from the thread. */
    public record OpenDraftRequest(@Size(max = 4000) String requestText) {
    }

    /**
     * Adding something to the draft.
     *
     * <p>A product id, never a name or a price. The catalog names and prices it; a client that could
     * send a price could send its own — the same rule that governs an order from the app.
     */
    public record AddLineRequest(
            @NotNull UUID productId,
            @Min(1) @Max(99) int qty,
            /** The options chosen, if the product has any. Empty for a product with no groups. */
            @Size(max = 50) List<UUID> optionIds) {

        public AddLineRequest {
            optionIds = optionIds == null ? List.of() : optionIds;
        }
    }

    public record DeliveryRequest(
            @NotBlank @Size(max = 500) String deliveryAddress,
            /** The area, when the merchant picks one. Optional, exactly as on an app order. */
            UUID deliveryZoneId,
            @Size(max = 32) String contactPhone,
            @Size(max = 500) String notes) {
    }

    public record DraftLineView(
            /** The line's own id. What removal names — a product can be in the basket twice. */
            UUID id,
            UUID productId,
            String productName,
            /** With the options chosen, as the catalog priced it. */
            BigDecimal unitPrice,
            int qty,
            BigDecimal lineTotal,
            List<ChosenOptionView> options,
            /** Pre-joined "Choose Size: Large" so every client renders it the same way. */
            String optionsSummary) {

        static DraftLineView of(DraftLine line) {
            return new DraftLineView(line.getId(), line.getProductId(), line.getProductName(),
                    line.getUnitPrice(), line.getQty(), line.lineTotal(),
                    line.getOptions().stream().map(ChosenOptionView::of).toList(),
                    line.optionsSummary());
        }
    }

    public record ChosenOptionView(UUID optionId, String groupName, String optionName,
                                   BigDecimal priceDelta) {

        static ChosenOptionView of(DraftLineOption option) {
            return new ChosenOptionView(option.getOptionId(), option.getGroupName(),
                    option.getOptionName(), option.getPriceDelta());
        }
    }

    public record DraftView(
            UUID id,
            UUID conversationId,
            String requestText,
            List<DraftLineView> lines,
            /**
             * What the lines add up to at the prices captured when they were added.
             *
             * <p>An estimate the merchant can read back to the customer — explicitly not what will
             * be charged. The catalog prices the real order at the moment it is placed, and naming
             * this field {@code total} would invite a client to display it as one.
             */
            BigDecimal estimatedSubtotal,
            String deliveryAddress,
            UUID deliveryZoneId,
            String contactPhone,
            String notes,
            String status,
            /** Whether it has an item and an address; everything else is checked at placement. */
            boolean placeable,
            /** Set once confirmed — the order this became. */
            UUID orderId,
            Instant createdAt,
            Instant updatedAt) {

        public static DraftView of(DraftOrder draft) {
            return new DraftView(
                    draft.getId(),
                    draft.getConversationId(),
                    draft.getRequestText(),
                    draft.getLines().stream().map(DraftLineView::of).toList(),
                    draft.estimatedSubtotal(),
                    draft.getDeliveryAddress(),
                    draft.getDeliveryZoneId(),
                    draft.getContactPhone(),
                    draft.getNotes(),
                    draft.getStatus().name(),
                    draft.isPlaceable(),
                    draft.getOrderId(),
                    draft.getCreatedAt(),
                    draft.getUpdatedAt());
        }
    }
}
