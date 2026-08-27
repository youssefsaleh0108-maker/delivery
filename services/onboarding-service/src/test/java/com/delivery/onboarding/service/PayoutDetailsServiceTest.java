package com.delivery.onboarding.service;

import java.time.Instant;
import java.util.List;
import java.util.Optional;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import com.delivery.onboarding.domain.Iban;
import com.delivery.onboarding.domain.OnboardingApplication;
import com.delivery.onboarding.domain.OnboardingApplication.Kind;
import com.delivery.onboarding.domain.PayoutDetails;
import com.delivery.onboarding.domain.PayoutDetailsRepository;
import com.delivery.onboarding.payout.DevChecksumOnlyPayoutVerifier;
import com.delivery.onboarding.payout.PayoutVerifierRegistry;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatExceptionOfType;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * The bank step: what is stored, what is refused, and what the platform is honest about not knowing.
 *
 * <p>The last of those is the one that matters most. Every account recorded today is stamped
 * {@code CHECKSUM_ONLY} and attributed to the dev verifier, because no bank has been asked whether
 * these accounts exist. That is a fact about the platform's vendor arrangements rather than about
 * this code, and the test is here so the fact stays visible if somebody later assumes otherwise.
 */
class PayoutDetailsServiceTest {

    private static final String GOOD_IBAN = "EG380019000500000000263180002";

    private PayoutDetailsRepository repository;
    private PayoutDetailsService service;
    private OnboardingApplication application;

    @BeforeEach
    void setUp() {
        repository = mock(PayoutDetailsRepository.class);
        service = new PayoutDetailsService(repository, new PayoutVerifierRegistry(
                List.of(new DevChecksumOnlyPayoutVerifier()), DevChecksumOnlyPayoutVerifier.NAME));

        application = new OnboardingApplication(Kind.MERCHANT, "Sam's Shakes", "Sam Salem",
                "sam@example.test", Instant.now(), null, null, null, null, null);
        when(repository.findByApplicationId(application.getId())).thenReturn(Optional.empty());
    }

    @Test
    @DisplayName("stores the normalised number, its last four digits and the country it belongs to")
    void stores_the_normalised_number_and_its_masked_form() {
        PayoutDetails saved = service.save(application, "  Sam Salem  ",
                "eg38 0019 0005 0000 0000 2631 80002");

        assertThat(saved.getIban()).isEqualTo(GOOD_IBAN);
        assertThat(saved.getIbanLastFour()).isEqualTo("0002");
        assertThat(saved.getIbanCountry()).isEqualTo("EG");
        assertThat(saved.getAccountHolder()).isEqualTo("Sam Salem");
        assertThat(saved.getMaskedIban()).isEqualTo("EG••••0002");
    }

    @Test
    @DisplayName("records that only the check digits were verified, and which verifier said so")
    void records_that_no_bank_was_asked() {
        PayoutDetails saved = service.save(application, "Sam Salem", GOOD_IBAN);

        assertThat(saved.getVerificationState())
                .isEqualTo(PayoutDetails.VerificationState.CHECKSUM_ONLY);
        assertThat(saved.getVerifiedBy()).isEqualTo("DEV_CHECKSUM_ONLY");
        assertThat(saved.getVerifiedAt()).isNotNull();
    }

    @Test
    @DisplayName("refuses a mistyped account number without storing anything")
    void refuses_a_mistyped_number_without_storing_it() {
        assertThatExceptionOfType(Iban.InvalidIbanException.class)
                .isThrownBy(() -> service.save(application, "Sam Salem",
                        "EG380019000500000000263810002"));

        verify(repository, never()).save(any());
    }

    @Test
    @DisplayName("refuses an account with no name on it")
    void refuses_an_account_with_no_holder() {
        assertThatExceptionOfType(OnboardingService.ApplicationRuleException.class)
                .isThrownBy(() -> service.save(application, "   ", GOOD_IBAN))
                .withMessageContaining("name on the account");
    }

    @Test
    @DisplayName("replacing the account clears any verdict reached on the previous one")
    void replacing_the_account_clears_the_previous_verdict() {
        PayoutDetails existing = new PayoutDetails(application.getId(), "Sam Salem",
                Iban.parse(GOOD_IBAN));
        existing.verifiedBy("SOME_PROCESSOR", PayoutDetails.VerificationState.VERIFIED);
        when(repository.findByApplicationId(application.getId())).thenReturn(Optional.of(existing));

        PayoutDetails saved = service.save(application, "Sam Salem", "GB82WEST12345698765432");

        assertThat(saved.getIban()).isEqualTo("GB82WEST12345698765432");
        // A verdict about the old account cannot carry over to a different one.
        assertThat(saved.getVerificationState())
                .isEqualTo(PayoutDetails.VerificationState.CHECKSUM_ONLY);
        assertThat(saved.getVerifiedBy()).isEqualTo("DEV_CHECKSUM_ONLY");
    }

    @Test
    @DisplayName("refuses a change once the application has been decided")
    void refuses_a_change_after_a_decision() {
        application.approve("reviewer-1");

        assertThatExceptionOfType(OnboardingService.ApplicationRuleException.class)
                .isThrownBy(() -> service.save(application, "Sam Salem", GOOD_IBAN))
                .withMessageContaining("already been decided");
    }

    @Test
    @DisplayName("never prints an account number, so one cannot reach a log through toString")
    void never_prints_an_account_number() {
        PayoutDetails saved = service.save(application, "Sam Salem", GOOD_IBAN);

        assertThat(saved.toString())
                .doesNotContain(GOOD_IBAN)
                .doesNotContain("Sam Salem")
                .contains("EG••••0002");
    }

    @Test
    @DisplayName("refuses to start against a verifier this build does not have, rather than quietly using another")
    void refuses_to_start_with_an_unknown_verifier() {
        assertThatExceptionOfType(IllegalStateException.class)
                .isThrownBy(() -> new PayoutVerifierRegistry(
                        List.of(new DevChecksumOnlyPayoutVerifier()), "SOME_PROCESSOR"))
                .withMessageContaining("Refusing to start");
    }
}
