package com.delivery.product.domain;

import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

/**
 * Service offers' terms, by product id.
 *
 * <p>Top-level, like every repository in this module. Spring Data's scan does not see an interface
 * nested inside another type, and this module's unit suite loads no Spring context, so a nested one
 * would pass every test and crash the first deploy ({@code RepositoriesAreTopLevelTest}).
 *
 * <p>{@code findAllById} is the read the lists use: the terms for a whole page of products in one
 * query, rather than one per card.
 */
public interface ServiceTermsRepository extends JpaRepository<ServiceTerms, UUID> {
}
