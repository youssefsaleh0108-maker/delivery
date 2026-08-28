package com.delivery.onboarding.service;

import java.time.Instant;
import java.util.List;
import java.util.Optional;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

import com.delivery.onboarding.client.KeycloakAdminClient;
import com.delivery.onboarding.domain.OnboardingApplication;
import com.delivery.onboarding.domain.OnboardingApplication.Kind;
import com.delivery.onboarding.domain.OnboardingApplicationRepository;
import com.delivery.onboarding.domain.PartnerEditEntry;
import com.delivery.onboarding.domain.PartnerEditEntryRepository;
import com.delivery.onboarding.domain.PartnerStatusChange;
import com.delivery.onboarding.domain.PartnerStatusChangeRepository;
import com.delivery.onboarding.service.OnboardingService.ApplicationRuleException;
import com.delivery.onboarding.service.PartnerManagementService.Edit;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Backoffice acting on a partner after the decision: edits that leave rows, and suspension that is
 * a real access change with a reason attached.
 *
 * <p>The two properties everything rests on: the audit trail records what actually changed and
 * nothing else, and the standing history and the Keycloak role move together — a suspend is a row
 * plus a revocation in one transaction, idempotent in both directions.
 */
class PartnerManagementServiceTest {

    private static final String ACTOR = "keycloak-sub-reviewer";
    private static final String PARTNER = "keycloak-sub-partner";

    private OnboardingApplicationRepository applications;
    private PartnerEditEntryRepository edits;
    private PartnerStatusChangeRepository statusChanges;
    private KeycloakAdminClient keycloak;
    private PartnerManagementService service;

    @BeforeEach
    void setUp() {
        applications = mock(OnboardingApplicationRepository.class);
        edits = mock(PartnerEditEntryRepository.class);
        statusChanges = mock(PartnerStatusChangeRepository.class);
        keycloak = mock(KeycloakAdminClient.class);
        service = new PartnerManagementService(applications, edits, statusChanges, keycloak);

        when(statusChanges.findFirstByApplicationIdOrderByCreatedAtDesc(any()))
                .thenReturn(Optional.empty());
        when(statusChanges.save(any(PartnerStatusChange.class)))
                .thenAnswer(call -> call.getArgument(0));
    }

    private OnboardingApplication known(OnboardingApplication application) {
        when(applications.findById(application.getId())).thenReturn(Optional.of(application));
        return application;
    }

    private static OnboardingApplication application(Kind kind) {
        return new OnboardingApplication(kind, "Sam's Shakes", "Sam Salem", "sam@example.test",
                Instant.now(), null, null, null, null, null);
    }

    /** Approved, with the account that signed up early — the shape a decided partner actually has. */
    private OnboardingApplication approvedPartner(Kind kind) {
        OnboardingApplication application = application(kind);
        application.applicantAccountCreated(PARTNER);
        application.approve("reviewer");
        return known(application);
    }

    private PartnerStatusChange suspendedRow(OnboardingApplication application) {
        return PartnerStatusChange.suspension(
                application.getId(), PARTNER, PartnerStatusChange.Reason.FRAUD, null, ACTOR);
    }

    @Nested
    @DisplayName("editing the record")
    class Editing {

        @Test
        void a_changed_field_is_applied_and_leaves_an_audit_row_with_both_values() {
            OnboardingApplication application = known(application(Kind.MERCHANT));

            service.edit(application.getId(), ACTOR,
                    new Edit("Sam's Diner", null, null, null));

            assertThat(application.getBusinessName()).isEqualTo("Sam's Diner");
            ArgumentCaptor<List<PartnerEditEntry>> trail = ArgumentCaptor.forClass(List.class);
            verify(edits).saveAll(trail.capture());
            assertThat(trail.getValue()).singleElement().satisfies(row -> {
                assertThat(row.getField()).isEqualTo("businessName");
                assertThat(row.getOldValue()).isEqualTo("Sam's Shakes");
                assertThat(row.getNewValue()).isEqualTo("Sam's Diner");
                assertThat(row.getActor()).isEqualTo(ACTOR);
            });
        }

        @Test
        void several_changed_fields_leave_one_row_each() {
            OnboardingApplication application = known(application(Kind.MERCHANT));

            service.edit(application.getId(), ACTOR,
                    new Edit("Sam's Diner", "Sam S. Salem", "new@example.test", null));

            ArgumentCaptor<List<PartnerEditEntry>> trail = ArgumentCaptor.forClass(List.class);
            verify(edits).saveAll(trail.capture());
            assertThat(trail.getValue()).extracting(PartnerEditEntry::getField)
                    .containsExactly("businessName", "contactName", "contactEmail");
        }

        /** An audit trail padded with no-ops is one nobody reads. */
        @Test
        void sending_the_current_value_back_changes_nothing_and_leaves_no_row() {
            OnboardingApplication application = known(application(Kind.MERCHANT));

            service.edit(application.getId(), ACTOR,
                    new Edit("Sam's Shakes", "Sam Salem", null, null));

            verify(edits, never()).saveAll(anyList());
            verify(applications, never()).save(any());
        }

        /**
         * The honesty rule: whatever code was once answered was answered on the OLD number, so a
         * corrected number must read as unchecked, not inherit the old proof.
         */
        @Test
        void correcting_the_phone_clears_the_verification_timestamp() {
            OnboardingApplication application = known(new OnboardingApplication(
                    Kind.MERCHANT, "Sam's Shakes", "Sam Salem", "sam@example.test",
                    Instant.now(), "+9613123456", Instant.now(), null, null, null));

            service.edit(application.getId(), ACTOR,
                    new Edit(null, null, null, "+9613999999"));

            assertThat(application.getContactPhone()).isEqualTo("+9613999999");
            assertThat(application.getPhoneVerifiedAt()).isNull();
        }

        /** Correcting the email does not touch the proof of the ORIGINAL address — see the domain. */
        @Test
        void correcting_the_email_keeps_the_original_verification_timestamp() {
            OnboardingApplication application = known(application(Kind.MERCHANT));
            Instant provedAt = application.getEmailVerifiedAt();

            service.edit(application.getId(), ACTOR,
                    new Edit(null, null, "corrected@example.test", null));

            assertThat(application.getContactEmail()).isEqualTo("corrected@example.test");
            assertThat(application.getEmailVerifiedAt()).isEqualTo(provedAt);
        }

        @Test
        void an_unknown_application_is_refused() {
            assertThatThrownBy(() -> service.edit(java.util.UUID.randomUUID(), ACTOR,
                    new Edit("x", null, null, null)))
                    .isInstanceOf(ApplicationRuleException.class)
                    .hasMessageContaining("No such application");
        }

        @Test
        void the_edit_history_is_returned_as_recorded_and_empty_when_there_is_none() {
            OnboardingApplication application = known(application(Kind.MERCHANT));
            when(edits.findByApplicationIdOrderByCreatedAtDesc(application.getId()))
                    .thenReturn(List.of());

            assertThat(service.editsOf(application.getId())).isEmpty();
        }
    }

    @Nested
    @DisplayName("suspending a partner")
    class Suspending {

        @Test
        void suspending_revokes_the_live_role_and_records_who_why_and_whom() {
            OnboardingApplication application = approvedPartner(Kind.MERCHANT);

            PartnerStatusChange change = service.suspend(application.getId(), ACTOR,
                    PartnerStatusChange.Reason.NON_PAYMENT, "three chargebacks");

            verify(keycloak).revokeRealmRole(PARTNER, "MERCHANT");
            verify(statusChanges).save(any(PartnerStatusChange.class));
            assertThat(change.isSuspended()).isTrue();
            assertThat(change.getReason()).isEqualTo(PartnerStatusChange.Reason.NON_PAYMENT);
            assertThat(change.getReasonNote()).isEqualTo("three chargebacks");
            assertThat(change.getActor()).isEqualTo(ACTOR);
            assertThat(change.getUserRef()).isEqualTo(PARTNER);
        }

        /** The one mapping: what approval grants is what suspension revokes, per kind. */
        @Test
        void each_kind_loses_the_role_its_approval_granted() {
            OnboardingApplication carrier = approvedPartner(Kind.CARRIER);
            service.suspend(carrier.getId(), ACTOR, PartnerStatusChange.Reason.FRAUD, null);
            verify(keycloak).revokeRealmRole(PARTNER, "CARRIER");

            OnboardingApplication rider = approvedPartner(Kind.RIDER);
            service.suspend(rider.getId(), ACTOR, PartnerStatusChange.Reason.FRAUD, null);
            verify(keycloak).revokeRealmRole(PARTNER, "DELIVERY");
        }

        /** A fully provisioned partner is suspended on the provisioned account. */
        @Test
        void a_provisioned_partner_is_suspended_on_the_provisioned_account() {
            OnboardingApplication application = application(Kind.MERCHANT);
            application.approve("reviewer");
            application.provisionedAs("provisioned-sub", null);
            known(application);

            PartnerStatusChange change = service.suspend(application.getId(), ACTOR,
                    PartnerStatusChange.Reason.FRAUD, null);

            assertThat(change.getUserRef()).isEqualTo("provisioned-sub");
            verify(keycloak).revokeRealmRole("provisioned-sub", "MERCHANT");
        }

        /** Idempotent: the existing row already says everything true; a second would date it twice. */
        @Test
        void suspending_twice_changes_nothing_and_adds_no_row() {
            OnboardingApplication application = approvedPartner(Kind.MERCHANT);
            PartnerStatusChange existing = suspendedRow(application);
            when(statusChanges.findFirstByApplicationIdOrderByCreatedAtDesc(application.getId()))
                    .thenReturn(Optional.of(existing));

            PartnerStatusChange change = service.suspend(application.getId(), ACTOR,
                    PartnerStatusChange.Reason.OTHER, "again");

            assertThat(change).isSameAs(existing);
            verify(statusChanges, never()).save(any());
            verify(keycloak, never()).revokeRealmRole(anyString(), anyString());
        }

        @Test
        void an_undecided_application_cannot_be_suspended() {
            OnboardingApplication application = known(application(Kind.MERCHANT));

            assertThatThrownBy(() -> service.suspend(application.getId(), ACTOR,
                    PartnerStatusChange.Reason.FRAUD, null))
                    .isInstanceOf(ApplicationRuleException.class)
                    .hasMessageContaining("approved");
            verify(keycloak, never()).revokeRealmRole(anyString(), anyString());
        }

        @Test
        void a_rejected_application_cannot_be_suspended() {
            OnboardingApplication application = application(Kind.MERCHANT);
            application.reject("reviewer", "no");
            known(application);

            assertThatThrownBy(() -> service.suspend(application.getId(), ACTOR,
                    PartnerStatusChange.Reason.FRAUD, null))
                    .isInstanceOf(ApplicationRuleException.class);
        }

        @Test
        void a_partner_without_a_signin_cannot_be_suspended() {
            OnboardingApplication application = application(Kind.MERCHANT);
            application.approve("reviewer");
            known(application);

            assertThatThrownBy(() -> service.suspend(application.getId(), ACTOR,
                    PartnerStatusChange.Reason.FRAUD, null))
                    .isInstanceOf(ApplicationRuleException.class)
                    .hasMessageContaining("no sign-in");
        }

        /** A suspension has to say why — the row cannot exist without a typed reason. */
        @Test
        void a_suspension_without_a_reason_is_refused() {
            OnboardingApplication application = approvedPartner(Kind.MERCHANT);

            assertThatThrownBy(() -> service.suspend(application.getId(), ACTOR, null, null))
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessageContaining("say why");
            verify(keycloak, never()).revokeRealmRole(anyString(), anyString());
        }
    }

    @Nested
    @DisplayName("reinstating a partner")
    class Reinstating {

        @Test
        void reinstating_grants_the_role_back_and_records_the_actor() {
            OnboardingApplication application = approvedPartner(Kind.MERCHANT);
            when(statusChanges.findFirstByApplicationIdOrderByCreatedAtDesc(application.getId()))
                    .thenReturn(Optional.of(suspendedRow(application)));

            Optional<PartnerStatusChange> change =
                    service.unsuspend(application.getId(), ACTOR, "appeal upheld");

            verify(keycloak).grantRealmRole(PARTNER, "MERCHANT");
            assertThat(change).hasValueSatisfying(row -> {
                assertThat(row.isSuspended()).isFalse();
                assertThat(row.getReason()).isNull();
                assertThat(row.getReasonNote()).isEqualTo("appeal upheld");
                assertThat(row.getActor()).isEqualTo(ACTOR);
            });
        }

        /** Idempotent the other way: reinstating an active partner grants nothing and writes nothing. */
        @Test
        void reinstating_an_active_partner_changes_nothing() {
            OnboardingApplication application = approvedPartner(Kind.MERCHANT);

            Optional<PartnerStatusChange> change =
                    service.unsuspend(application.getId(), ACTOR, null);

            assertThat(change).isEmpty();
            verify(statusChanges, never()).save(any());
            verify(keycloak, never()).grantRealmRole(anyString(), anyString());
        }
    }

    @Nested
    @DisplayName("reading the standing")
    class Reading {

        @Test
        void an_untouched_partner_reads_as_active_with_an_empty_history() {
            OnboardingApplication application = approvedPartner(Kind.MERCHANT);
            when(statusChanges.findByApplicationIdOrderByCreatedAtDesc(application.getId()))
                    .thenReturn(List.of());

            assertThat(service.standing(application.getId())).isEmpty();
            assertThat(service.standingHistory(application.getId())).isEmpty();
        }

        @Test
        void the_history_is_returned_exactly_as_recorded() {
            OnboardingApplication application = approvedPartner(Kind.MERCHANT);
            PartnerStatusChange suspension = suspendedRow(application);
            PartnerStatusChange reinstatement = PartnerStatusChange.reinstatement(
                    application.getId(), PARTNER, null, ACTOR);
            when(statusChanges.findByApplicationIdOrderByCreatedAtDesc(application.getId()))
                    .thenReturn(List.of(reinstatement, suspension));

            assertThat(service.standingHistory(application.getId()))
                    .containsExactly(reinstatement, suspension);
        }
    }
}
