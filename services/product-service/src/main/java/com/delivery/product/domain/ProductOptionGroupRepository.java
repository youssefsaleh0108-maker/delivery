package com.delivery.product.domain;

import java.util.Collection;
import java.util.List;
import java.util.UUID;

import org.springframework.data.jpa.repository.EntityGraph;
import org.springframework.data.jpa.repository.JpaRepository;

public interface ProductOptionGroupRepository extends JpaRepository<ProductOptionGroup, UUID> {

    /**
     * A product's option groups, with their choices already loaded.
     *
     * <p>The graph is not optional. {@code options} is LAZY, and every caller maps these to DTOs in
     * a controller — after the transaction has closed and the session is gone. Without it, any
     * product that actually has options answers this endpoint with a 500, while a product with none
     * answers fine, which is exactly the shape of bug that survives a test suite.
     */
    @EntityGraph(attributePaths = "options")
    List<ProductOptionGroup> findByProductIdOrderByPositionAsc(UUID productId);

    /**
     * Groups for a whole page of products at once.
     *
     * <p>A store's shelf renders forty products, and asking for each one's options separately is
     * the N+1 that {@code @BatchSize} avoids one level down. Callers group the result by product id.
     */
    @EntityGraph(attributePaths = "options")
    List<ProductOptionGroup> findByProductIdInOrderByPositionAsc(Collection<UUID> productIds);

    void deleteByProductId(UUID productId);
}
