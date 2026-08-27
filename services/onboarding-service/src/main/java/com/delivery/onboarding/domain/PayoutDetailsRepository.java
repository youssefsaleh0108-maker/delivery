package com.delivery.onboarding.domain;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

public interface PayoutDetailsRepository extends JpaRepository<PayoutDetails, UUID> {

    Optional<PayoutDetails> findByApplicationId(UUID applicationId);

    /**
     * For the queue and history listings, which show the masked form.
     *
     * <p>Fetched in one call rather than per row: a backoffice queue of fifty applications would
     * otherwise be fifty extra round trips to render "•••• 0002" fifty times.
     */
    List<PayoutDetails> findByApplicationIdIn(List<UUID> applicationIds);
}
