package com.delivery.onboarding.domain;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

public interface OnboardingApplicationRepository
        extends JpaRepository<OnboardingApplication, UUID> {

    /** How an applicant with no account finds their own application, and only their own. */
    Optional<OnboardingApplication> findByReference(String reference);

    /** The application belonging to a signed-in applicant, for the "how is mine going" screen. */
    Optional<OnboardingApplication> findByApplicantUserRef(String applicantUserRef);

    /**
     * The newest application that was provisioned onto this account.
     *
     * <p>Asked by the signed-in application path, beside {@link #findByApplicantUserRef}, because
     * a partner provisioned the old way — approved before applicants chose a passcode — has their
     * account on this column and nothing on the applicant one. Without it a suspended partner of
     * that vintage, whose live role was taken away, would look like somebody who had never applied
     * and could apply again to get the role back.
     */
    Optional<OnboardingApplication> findFirstByProvisionedUserRefOrderByCreatedAtDesc(
            String provisionedUserRef);

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
