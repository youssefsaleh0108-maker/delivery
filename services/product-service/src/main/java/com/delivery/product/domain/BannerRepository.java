package com.delivery.product.domain;

import java.util.List;
import java.util.UUID;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;

public interface BannerRepository extends JpaRepository<Banner, UUID> {

    /**
     * Every banner, for the Backoffice list — including withdrawn and scheduled ones, which is the
     * whole point of an admin view.
     */
    Page<Banner> findAllByOrderByPositionAscCreatedAtDesc(Pageable pageable);

    /**
     * Candidates for the customer rail, in curated order.
     *
     * <p>Only the {@code active} flag is filtered here; the date window is applied in the service
     * against an injected clock, so "is it live" stays one testable rule rather than being split
     * between SQL and Java.
     */
    @Query("SELECT b FROM Banner b WHERE b.active = true ORDER BY b.position ASC, b.startsAt DESC")
    List<Banner> findActive();
}
