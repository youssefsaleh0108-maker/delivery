package com.delivery.onboarding.domain;

import org.springframework.data.jpa.repository.JpaRepository;

import com.delivery.onboarding.domain.OnboardingApplication.Kind;

/**
 * The current auto-approval position per kind.
 *
 * <p>Keyed by the kind itself rather than a surrogate id: there is exactly one position per kind,
 * and letting the primary key say so means a second row for RIDER is impossible rather than merely
 * unexpected. Three rows at most, and an empty table is the normal state of a deployment nobody has
 * touched.
 */
public interface AutoApprovalDecisionRepository
        extends JpaRepository<AutoApprovalDecision, Kind> {
}
