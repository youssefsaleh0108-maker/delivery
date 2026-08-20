package com.delivery.connector.corebanking.provider;

import java.math.BigDecimal;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import com.delivery.connector.corebanking.BankPostingCommand;
import com.delivery.connector.corebanking.provider.BankClient.Verdict;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * The unimplemented real-bank integration, and why its refusal is a feature.
 *
 * <p>The simulator's contract is a placeholder this project invented, and nobody owns keeping it in
 * step with the bank's real spec. A speculative implementation here would look finished, would pass
 * every test written against the simulator, and would fail on the first real posting — with money
 * involved. So this class refuses, loudly, naming what is missing.
 *
 * <p>These tests exist because that refusal is easy to mistake for an oversight and "fix". The two
 * properties worth holding are that a posting fails <em>permanently</em> (so the saga compensates
 * instead of retrying into a wall), and that an account lookup answers UNKNOWN rather than REFUSED —
 * blaming a carrier for our missing integration would be the wrong party entirely.
 */
class RealBankClientTest {

    private static final BankPostingCommand POSTING = new BankPostingCommand(
            "txn-1", "ACC-1", BankPostingCommand.DEBIT, new BigDecimal("42.50"),
            "USD", "Order 123", "corr-1");

    /** Fully configured on paper — the point is that configuration is not what is missing. */
    private static RealBankClient configured() {
        return new RealBankClient("https://bank.example", "client-id", "client-secret");
    }

    private static RealBankClient unconfigured() {
        return new RealBankClient("", "", "");
    }

    @Test
    void it_registers_under_the_provider_name_connector_settings_offers() {
        // Must match the CORE_BANKING provider list, or selecting REAL finds no client at all.
        assertThat(configured().name()).isEqualTo("REAL");
    }

    @Nested
    @DisplayName("posting")
    class Posting {

        /**
         * Permanent, not transient. A retryable refusal would have the saga wait for an integration
         * that is not coming, holding the settlement open indefinitely.
         */
        @Test
        void is_refused_permanently_rather_than_retried_into_a_wall() {
            BankClient.Response response = configured().post(POSTING);

            assertThat(response.outcome().success()).isFalse();
            assertThat(response.outcome().retryable()).isFalse();
        }

        /** The refusal has to say why, or it reads as an ordinary bank rejection in the sync log. */
        @Test
        void says_it_is_the_integration_that_is_missing_not_the_posting_that_is_bad() {
            BankClient.Response response = configured().post(POSTING);

            assertThat(response.outcome().failureReason()).contains("not implemented");
        }

        /** Configuring a URL and credentials does not make the contract agreed. */
        @Test
        void is_refused_even_when_fully_configured() {
            assertThat(configured().post(POSTING).outcome().success()).isFalse();
        }

        @Test
        void names_the_missing_configuration_when_there_is_any() {
            String reason = unconfigured().post(POSTING).outcome().failureReason();

            assertThat(reason).contains("base URL").contains("Vault");
        }

        /** Nothing was sent, so there is no request payload to pretend to have. */
        @Test
        void reports_no_payloads_because_nothing_was_sent() {
            BankClient.Response response = configured().post(POSTING);

            assertThat(response.requestPayload()).isNull();
            assertThat(response.responsePayload()).isNull();
        }

        /** The outcome must name this provider, so the sync log records which one refused. */
        @Test
        void attributes_the_refusal_to_the_real_provider() {
            assertThat(configured().post(POSTING).outcome().provider()).isEqualTo("REAL");
        }
    }

    @Nested
    @DisplayName("account lookup")
    class Lookup {

        /**
         * The three-valued verdict earning its keep in the other direction. REFUSED would reject
         * every carrier who tried to onboard while REAL was selected — blaming them for our gap.
         */
        @Test
        void answers_unknown_rather_than_refusing_the_account() {
            BankClient.AccountCheck check = configured().lookup("ACC-1");

            assertThat(check.verdict()).isEqualTo(Verdict.UNKNOWN);
            assertThat(check.verdict()).isNotEqualTo(Verdict.REFUSED);
        }

        @Test
        void explains_that_the_integration_is_what_is_missing() {
            assertThat(configured().lookup("ACC-1").detail()).contains("not implemented");
        }

        @Test
        void echoes_the_account_it_could_not_check() {
            assertThat(configured().lookup("ACC-1").accountRef()).isEqualTo("ACC-1");
        }

        /** Nothing was asked, so there is no holder name to report. */
        @Test
        void reports_no_holder_name() {
            assertThat(configured().lookup("ACC-1").holderName()).isNull();
        }
    }
}
