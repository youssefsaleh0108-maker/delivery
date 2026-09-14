package com.delivery.product.api.dto;

import java.time.Instant;
import java.util.UUID;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import com.delivery.product.api.dto.CatalogDtos.ProductResponse;
import com.delivery.product.domain.OfferModerationAction;
import com.delivery.product.domain.Product;
import com.delivery.product.domain.Store;

/**
 * Request and response shapes for back office's moderation of service offers (V36).
 *
 * <p>No request names an actor. Who acted is the caller's token, as for every other back office write.
 */
public final class ModerationDtos {

    private ModerationDtos() {
    }

    /**
     * Why back office takes an offer down, or restores it. Required for both acts: the trail says why,
     * not only that. A take-down's reason is also what the provider reads.
     */
    public record ModerationRequest(
            @NotBlank @Size(max = Product.MAX_TAKEDOWN_REASON_LENGTH) String reason) {
    }

    /**
     * An offer as back office's list shows it: the offer as every product read returns it, with its
     * {@code moderation} hold, plus the shop it sits in. A table row needs the shop's name, its category
     * and whether it is listed without a read per row.
     */
    public record BackofficeOfferResponse(
            ProductResponse offer,
            UUID storeId,
            String storeName,
            Store.ServiceCategory serviceCategory,
            Store.Status storeStatus) {
    }

    /** One act in an offer's trail. */
    public record ModerationActionResponse(
            UUID id,
            UUID productId,
            UUID storeId,
            OfferModerationAction.Action action,
            String reason,
            /** The staff member's Keycloak {@code sub}. */
            String actorId,
            /** Their username when the act was taken; null when their token carried none. */
            String actorName,
            Instant createdAt) {

        public static ModerationActionResponse of(OfferModerationAction act) {
            return new ModerationActionResponse(act.getId(), act.getProductId(), act.getStoreId(),
                    act.getAction(), act.getReason(), act.getActorId(), act.getActorName(),
                    act.getCreatedAt());
        }
    }
}
