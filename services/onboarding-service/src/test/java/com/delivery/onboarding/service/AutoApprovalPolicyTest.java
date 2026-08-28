package com.delivery.onboarding.service;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import com.delivery.onboarding.domain.OnboardingApplication.Kind;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Who gets onto the platform without a human deciding.
 *
 * <p>Worth pinning because the failure is silent and expensive in one direction only. A policy that
 * wrongly says "manual" leaves an applicant waiting, and somebody complains. A policy that wrongly
 * says "automatic" puts a stranger on the platform as a live merchant, and nobody notices until
 * money has moved — so every default here is asserted, not assumed.
 */
class AutoApprovalPolicyTest {

    @Nested
    @DisplayName("with nothing configured")
    class Defaults {

        private final AutoApprovalPolicy policy = new AutoApprovalPolicy(false, false, false);

        @Test
        @DisplayName("nobody is automatic — the platform reviews by default")
        void everythingIsManual() {
            for (Kind kind : Kind.values()) {
                assertThat(policy.isAutomatic(kind))
                        .as("%s must be manual unless switched on", kind)
                        .isFalse();
            }
            assertThat(policy.automaticKinds()).isEmpty();
        }
    }

    @Nested
    @DisplayName("switched on per kind")
    class PerKind {

        @Test
        @DisplayName("riders and merchants automatic leaves carriers manual")
        void onlyWhatWasAskedFor() {
            AutoApprovalPolicy policy = new AutoApprovalPolicy(true, true, false);

            assertThat(policy.isAutomatic(Kind.RIDER)).isTrue();
            assertThat(policy.isAutomatic(Kind.MERCHANT)).isTrue();
            // A carrier signs for a fleet and a payout account. Turning riders on must never carry
            // it along.
            assertThat(policy.isAutomatic(Kind.CARRIER)).isFalse();
        }

        @Test
        @DisplayName("each kind is independent")
        void independent() {
            assertThat(new AutoApprovalPolicy(true, false, false).automaticKinds())
                    .containsExactly(Kind.RIDER);
            assertThat(new AutoApprovalPolicy(false, true, false).automaticKinds())
                    .containsExactly(Kind.MERCHANT);
            assertThat(new AutoApprovalPolicy(false, false, true).automaticKinds())
                    .containsExactly(Kind.CARRIER);
        }
    }

    @Nested
    @DisplayName("edges")
    class Edges {

        @Test
        @DisplayName("a null kind is never automatic")
        void nullIsManual() {
            assertThat(new AutoApprovalPolicy(true, true, true).isAutomatic(null)).isFalse();
        }

        @Test
        @DisplayName("the reported set cannot be edited from outside")
        void setIsACopy() {
            AutoApprovalPolicy policy = new AutoApprovalPolicy(true, false, false);
            var kinds = policy.automaticKinds();
            org.junit.jupiter.api.Assertions.assertThrows(UnsupportedOperationException.class,
                    () -> kinds.add(Kind.CARRIER));
            assertThat(policy.isAutomatic(Kind.CARRIER)).isFalse();
        }

        @Test
        @DisplayName("the automatic reviewer is not a person's name")
        void reviewerIsMarkedAsSystem() {
            // The audit trail has to be able to answer "who approved this" honestly a year later.
            assertThat(AutoApprovalPolicy.AUTOMATIC_REVIEWER)
                    .isNotBlank()
                    .startsWith("system:");
        }
    }
}
