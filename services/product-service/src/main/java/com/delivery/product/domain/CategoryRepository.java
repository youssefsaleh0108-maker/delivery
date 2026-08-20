package com.delivery.product.domain;

import java.util.List;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

public interface CategoryRepository extends JpaRepository<Category, UUID> {

    List<Category> findByParentIdIsNullOrderByName();

    List<Category> findByParentIdOrderByName(UUID parentId);

    boolean existsByParentId(UUID parentId);
}
