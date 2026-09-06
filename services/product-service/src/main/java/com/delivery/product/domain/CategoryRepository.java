package com.delivery.product.domain;

import java.util.List;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

public interface CategoryRepository extends JpaRepository<Category, UUID> {

    List<Category> findByParentIdIsNullOrderByName();

    List<Category> findByParentIdOrderByName(UUID parentId);

    boolean existsByParentId(UUID parentId);

    /**
     * Platform taxonomy only.
     *
     * <p>What every customer-facing category surface must read. Once merchants author their own
     * sections, a plain {@code findAll()} would leak one shop's shelf into every client's picker.
     */
    List<Category> findByStoreIdIsNull();

    /** One shop's own sections, in the order the merchant dragged them into. */
    List<Category> findByStoreIdOrderByPositionAscNameAsc(UUID storeId);

    boolean existsByStoreIdAndNameIgnoreCase(UUID storeId, String name);

    long countByStoreId(UUID storeId);
}
