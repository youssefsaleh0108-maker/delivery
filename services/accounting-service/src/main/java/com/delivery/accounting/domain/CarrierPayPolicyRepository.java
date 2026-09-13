package com.delivery.accounting.domain;

import java.util.List;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

/**
 * A delivery company's pay rules, every version of them.
 *
 * <p>Top-level, as every repository here is: Spring Data's scan skips an interface nested in another
 * type, and that fails at startup as a missing bean.
 */
public interface CarrierPayPolicyRepository extends JpaRepository<CarrierPayPolicy, UUID> {

    /**
     * Every version, latest start first and, for two starting the same day, the later-saved first —
     * the order "which rules are in force on a day" is answered in. A company has a handful of these,
     * so they are read whole and picked in memory rather than by a query per date.
     */
    List<CarrierPayPolicy> findByCarrierRefOrderByEffectiveFromDescCreatedAtDesc(String carrierRef);
}
