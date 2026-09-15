package com.delivery.product.domain;

import java.util.List;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

/** Back office's trail of take-downs and restores ({@link OfferModerationAction}). */
public interface OfferModerationActionRepository extends JpaRepository<OfferModerationAction, UUID> {

    /** One offer's trail, newest act first: what back office's history shows. */
    List<OfferModerationAction> findByProductIdOrderByCreatedAtDesc(UUID productId);
}
