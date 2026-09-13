package com.delivery.onboarding.service;

import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import com.delivery.onboarding.client.KeycloakAdminClient;
import com.delivery.onboarding.domain.OnboardingApplicationRepository;
import com.delivery.onboarding.domain.PartnerEditEntryRepository;
import com.delivery.onboarding.domain.PartnerStatusChange;
import com.delivery.onboarding.domain.PartnerStatusChangeRepository;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

/**
 * A whole listing's standing, in one read.
 *
 * <p>The carrier directory used to ask for each rider's standing separately. What has to stay true
 * when it is read in bulk: the newest change decides, a partner nobody touched is active, and a tie
 * never hides a suspension.
 */
@DisplayName("a whole listing's standing, in one read")
class PartnerStandingBatchTest {

    private PartnerStatusChangeRepository statusChanges;
    private PartnerManagementService service;

    @BeforeEach
    void setUp() {
        statusChanges = mock(PartnerStatusChangeRepository.class);
        service = new PartnerManagementService(mock(OnboardingApplicationRepository.class),
                mock(PartnerEditEntryRepository.class), statusChanges, mock(KeycloakAdminClient.class));
    }

    @Test
    @DisplayName("each application reads its newest change, and one nobody touched is active")
    void the_newest_change_decides() {
        UUID suspended = UUID.randomUUID();
        UUID reinstated = UUID.randomUUID();
        UUID untouched = UUID.randomUUID();
        List<UUID> ids = List.of(suspended, reinstated, untouched);
        when(statusChanges.findCurrentForApplications(ids)).thenReturn(List.of(
                PartnerStatusChange.suspension(suspended, "user-1",
                        PartnerStatusChange.Reason.POLICY_VIOLATION, null, "boss"),
                PartnerStatusChange.reinstatement(reinstated, "user-2", null, "boss")));

        assertThat(service.suspendedByApplication(ids)).containsExactlyInAnyOrderEntriesOf(
                Map.of(suspended, true, reinstated, false, untouched, false));
        // One query for the lot; the per-application read is what this replaces.
        verify(statusChanges, never()).findFirstByApplicationIdOrderByCreatedAtDesc(any());
    }

    @Test
    @DisplayName("two changes stamped at one instant read as suspended")
    void a_tie_never_hides_a_suspension() {
        UUID application = UUID.randomUUID();
        when(statusChanges.findCurrentForApplications(List.of(application))).thenReturn(List.of(
                PartnerStatusChange.reinstatement(application, "user-1", null, "boss"),
                PartnerStatusChange.suspension(application, "user-1",
                        PartnerStatusChange.Reason.OTHER, null, "boss")));

        assertThat(service.suspendedByApplication(List.of(application)))
                .containsEntry(application, true);
    }

    @Test
    @DisplayName("an empty listing asks nothing")
    void an_empty_listing_asks_nothing() {
        assertThat(service.suspendedByApplication(List.of())).isEmpty();
        verifyNoInteractions(statusChanges);
    }
}
