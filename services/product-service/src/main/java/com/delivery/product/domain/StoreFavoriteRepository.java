package com.delivery.product.domain;

import java.util.List;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

public interface StoreFavoriteRepository extends JpaRepository<StoreFavorite, StoreFavorite.Id> {

    List<StoreFavorite> findByIdUserId(String userId);

    /**
     * The ids a customer has starred.
     *
     * <p>Read as a set and applied in memory when rendering a page of stores, so a list of fifty
     * cards costs one extra query rather than fifty {@code existsById} round trips.
     */
    @org.springframework.data.jpa.repository.Query(
            "SELECT f.id.storeId FROM StoreFavorite f WHERE f.id.userId = :userId")
    List<UUID> findStoreIdsByUserId(@org.springframework.data.repository.query.Param("userId") String userId);
}
