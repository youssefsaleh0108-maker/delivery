package com.delivery.onboarding.domain;

import java.util.Collection;
import java.util.List;
import java.util.UUID;

import org.springframework.data.repository.Repository;

/**
 * Delivery companies' own applications, found by the company each one created.
 *
 * <p>An approved delivery company's application carries the Order Manager provider id its approval
 * created ({@code provisioned_entity_id}, recorded by {@code CreatePartnerRecord} once Order Manager
 * has registered the company). This is the one read that goes from a company back to what it said
 * when it applied — the regions it works in, which a rider applying to a company with no zones yet is
 * shown instead.
 *
 * <p>Its own interface rather than another method on {@link OnboardingApplicationRepository}, so that
 * what it offers is that read and nothing else.
 */
public interface CarrierRegistrationRepository extends Repository<OnboardingApplication, UUID> {

    /** Applications of this kind that created any of these providers. */
    List<OnboardingApplication> findByKindAndProvisionedEntityIdIn(
            OnboardingApplication.Kind kind, Collection<UUID> providerIds);
}
