package com.delivery.onboarding.domain;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

public interface OnboardingApplicationRepository
        extends JpaRepository<OnboardingApplication, UUID> {

    /** How an applicant with no account finds their own application, and only their own. */
    Optional<OnboardingApplication> findByReference(String reference);

    /** The reviewer's queue: oldest first, because waiting three days should not lose to today. */
    List<OnboardingApplication> findByStatusInOrderByCreatedAtAsc(
            List<OnboardingApplication.Status> statuses);

    List<OnboardingApplication> findAllByOrderByCreatedAtDesc();

    /**
     * One delivery company's rider applications.
     *
     * <p>Scoped by the company id in the query rather than filtered after loading, because this is
     * the only thing standing between one fleet and a list of the people applying to another.
     */
    List<OnboardingApplication> findByTargetProviderIdOrderByCreatedAtAsc(UUID targetProviderId);

    List<OnboardingApplication> findByTargetProviderIdAndStatusInOrderByCreatedAtAsc(
            UUID targetProviderId, List<OnboardingApplication.Status> statuses);

    /**
     * The platform's queue: everything NOT addressed to a company.
     *
     * <p>Without the exclusion, rider applications would pile into the Backoffice queue as well as
     * the company's — two reviewers, one decision, and the platform deciding somebody else's staff
     * by accident.
     */
    List<OnboardingApplication> findByTargetProviderIdIsNullAndStatusInOrderByCreatedAtAsc(
            List<OnboardingApplication.Status> statuses);

    /**
     * Whether this business name is already taken by a live partner or a pending application.
     *
     * <p>Checked so a reviewer sees the clash while deciding rather than discovering it when
     * provisioning fails on a unique constraint half an hour later.
     */
    boolean existsByBusinessNameIgnoreCaseAndStatusIn(
            String businessName, List<OnboardingApplication.Status> statuses);
}
