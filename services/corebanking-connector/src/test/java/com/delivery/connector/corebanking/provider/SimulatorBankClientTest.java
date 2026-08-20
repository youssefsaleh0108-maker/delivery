package com.delivery.connector.corebanking.provider;

import java.math.BigDecimal;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;

import com.delivery.connector.corebanking.BankPostingCommand;
import com.delivery.connector.corebanking.provider.BankClient.Verdict;
import com.fasterxml.jackson.databind.ObjectMapper;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.header;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.jsonPath;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.method;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withException;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withStatus;

/**
 * How the bank's answers are classified, which is what decides whether money moves back.
 *
 * <p>Every branch here is a fork in the settlement saga. {@code retryable} true means the leg stays
 * open and the saga waits; false means it compensates — refunding a customer, or leaving the
 * platform short its own commission. Getting the classification backwards is expensive in both
 * directions: a retryable rejection treated as permanent refunds an order the bank would have
 * accepted a minute later, and a permanent rejection treated as retryable hammers the bank forever
 * with a posting it will never take.
 *
 * <p>The other half is {@link BankClient.Verdict}, which is three-valued precisely so a bank that
 * could not be reached is never reported as a bad account.
 */
class SimulatorBankClientTest {

    private static final String POSTINGS = "http://bank.test/api/core-banking/postings";

    private RestClient.Builder builder;
    private MockRestServiceServer server;
    private SimulatorBankClient client;

    @BeforeEach
    void setUp() {
        builder = RestClient.builder();
        server = MockRestServiceServer.bindTo(builder).build();
        client = new SimulatorBankClient(builder, new ObjectMapper(),
                "http://bank.test", "simulator-dev-key");
    }

    private static BankPostingCommand debit() {
        return new BankPostingCommand("txn-1", "ACC-1", BankPostingCommand.DEBIT,
                new BigDecimal("42.50"), "USD", "Order 123", "corr-1");
    }

    private void bankAnswers(HttpStatus status, String body) {
        server.expect(requestTo(POSTINGS))
                .andExpect(method(org.springframework.http.HttpMethod.POST))
                .andRespond(withStatus(status)
                        .contentType(MediaType.APPLICATION_JSON)
                        .body(body));
    }

    private void lookupAnswers(HttpStatus status, String body) {
        server.expect(requestTo("http://bank.test/api/core-banking/accounts/ACC-1"))
                .andRespond(withStatus(status).contentType(MediaType.APPLICATION_JSON).body(body));
    }

    @Nested
    @DisplayName("the request sent to the bank")
    class Request {

        /**
         * The single most important obligation on any BankClient. Without the transaction id as the
         * client reference, a retried debit is a second debit.
         */
        @Test
        void carries_the_transaction_id_as_the_client_reference() {
            server.expect(requestTo(POSTINGS))
                    .andExpect(jsonPath("$.clientReference").value("txn-1"))
                    .andRespond(withStatus(HttpStatus.OK)
                            .contentType(MediaType.APPLICATION_JSON)
                            .body("{\"postingId\":\"p-1\"}"));

            client.post(debit());

            server.verify();
        }

        /** The bank authenticates on its own key, not a Keycloak token. */
        @Test
        void authenticates_with_the_bank_api_key() {
            server.expect(requestTo(POSTINGS))
                    .andExpect(header("X-Bank-Api-Key", "simulator-dev-key"))
                    .andRespond(withStatus(HttpStatus.OK)
                            .contentType(MediaType.APPLICATION_JSON)
                            .body("{\"postingId\":\"p-1\"}"));

            client.post(debit());

            server.verify();
        }

        /** Minor units, so the bank and the platform cannot disagree about what 42.50 means. */
        @Test
        void sends_the_amount_in_minor_units() {
            server.expect(requestTo(POSTINGS))
                    .andExpect(jsonPath("$.amountMinor").value(4250))
                    .andExpect(jsonPath("$.direction").value("DEBIT"))
                    .andExpect(jsonPath("$.currency").value("USD"))
                    .andRespond(withStatus(HttpStatus.OK)
                            .contentType(MediaType.APPLICATION_JSON)
                            .body("{\"postingId\":\"p-1\"}"));

            client.post(debit());

            server.verify();
        }
    }

    @Nested
    @DisplayName("when the bank accepts")
    class Accepted {

        @Test
        void the_outcome_is_success_carrying_the_posting_id() {
            bankAnswers(HttpStatus.OK, "{\"postingId\":\"posting-99\",\"replayed\":false}");

            BankClient.Response response = client.post(debit());

            assertThat(response.outcome().success()).isTrue();
            assertThat(response.outcome().providerMessageId()).isEqualTo("posting-99");
            assertThat(response.outcome().provider()).isEqualTo("SIMULATOR");
        }

        /**
         * A replay is the idempotency key doing exactly its job — the bank recognised the reference
         * and did not move money again. It is a success, and treating it as anything else would make
         * the saga compensate an order that was already settled.
         */
        @Test
        void a_replayed_posting_is_a_success_not_a_failure() {
            bankAnswers(HttpStatus.OK, "{\"postingId\":\"posting-99\",\"replayed\":true}");

            assertThat(client.post(debit()).outcome().success()).isTrue();
        }

        /** The payloads are what make "what did we actually send" answerable in a dispute. */
        @Test
        void both_payloads_are_captured_for_the_sync_log() {
            bankAnswers(HttpStatus.OK, "{\"postingId\":\"posting-99\"}");

            BankClient.Response response = client.post(debit());

            assertThat(response.requestPayload()).contains("txn-1").contains("4250");
            assertThat(response.responsePayload()).contains("posting-99");
        }
    }

    @Nested
    @DisplayName("when the bank refuses with certainty")
    class PermanentRefusals {

        /**
         * 422 is the bank saying no and meaning it — insufficient funds, frozen account. Retrying
         * moves nothing, so the saga must compensate rather than wait.
         */
        @Test
        void a_422_is_permanent_and_carries_the_bank_s_reason() {
            bankAnswers(HttpStatus.UNPROCESSABLE_ENTITY,
                    "{\"rejectionReason\":\"INSUFFICIENT_FUNDS: Balance is below the amount\"}");

            var outcome = client.post(debit()).outcome();

            assertThat(outcome.success()).isFalse();
            assertThat(outcome.retryable()).isFalse();
            assertThat(outcome.failureReason()).contains("INSUFFICIENT_FUNDS");
        }

        /** A malformed posting will be malformed on every retry. */
        @Test
        void a_400_is_permanent() {
            bankAnswers(HttpStatus.BAD_REQUEST, "{\"detail\":\"amount must be positive\"}");

            assertThat(client.post(debit()).outcome().retryable()).isFalse();
        }

        @Test
        void a_404_is_permanent() {
            bankAnswers(HttpStatus.NOT_FOUND, "{\"detail\":\"no such account\"}");

            assertThat(client.post(debit()).outcome().retryable()).isFalse();
        }

        /**
         * A bad key is not fixed by retrying, and hammering a bank with unauthenticated requests is
         * its own problem. Permanent, loudly.
         */
        @Test
        void rejected_credentials_are_permanent_rather_than_retried_forever() {
            bankAnswers(HttpStatus.UNAUTHORIZED, "{}");

            var outcome = client.post(debit()).outcome();

            assertThat(outcome.retryable()).isFalse();
            assertThat(outcome.failureReason()).contains("credentials");
        }

        @Test
        void a_403_is_treated_the_same_as_a_401() {
            bankAnswers(HttpStatus.FORBIDDEN, "{}");

            assertThat(client.post(debit()).outcome().retryable()).isFalse();
        }
    }

    @Nested
    @DisplayName("when the bank says not now")
    class TransientFailures {

        @Test
        void a_500_is_retryable() {
            bankAnswers(HttpStatus.INTERNAL_SERVER_ERROR, "{\"detail\":\"ledger unavailable\"}");

            var outcome = client.post(debit()).outcome();

            assertThat(outcome.success()).isFalse();
            assertThat(outcome.retryable()).isTrue();
        }

        @Test
        void a_503_is_retryable() {
            bankAnswers(HttpStatus.SERVICE_UNAVAILABLE, "{}");

            assertThat(client.post(debit()).outcome().retryable()).isTrue();
        }

        /** A rate limit is the bank asking us to slow down, not to give up. */
        @Test
        void a_429_is_retryable() {
            bankAnswers(HttpStatus.TOO_MANY_REQUESTS, "{}");

            assertThat(client.post(debit()).outcome().retryable()).isTrue();
        }

        /**
         * The posting may well have been made before the connection dropped, which is exactly why
         * it is safe to retry: the client reference makes the second attempt a replay rather than a
         * second debit.
         */
        @Test
        void an_unreachable_bank_is_retryable() {
            server.expect(requestTo(POSTINGS))
                    .andRespond(withException(new java.io.IOException("connection reset")));

            var outcome = client.post(debit()).outcome();

            assertThat(outcome.retryable()).isTrue();
            assertThat(outcome.failureReason()).contains("unreachable");
        }

        /** Even with no body to read a reason from, the classification must still be made. */
        @Test
        void a_5xx_with_no_body_is_still_retryable() {
            server.expect(requestTo(POSTINGS))
                    .andRespond(withStatus(HttpStatus.BAD_GATEWAY));

            assertThat(client.post(debit()).outcome().retryable()).isTrue();
        }

        /** The request payload survives even a transport failure — the sync log still needs it. */
        @Test
        void the_request_payload_is_kept_even_when_nothing_came_back() {
            server.expect(requestTo(POSTINGS))
                    .andRespond(withException(new java.io.IOException("connection reset")));

            BankClient.Response response = client.post(debit());

            assertThat(response.requestPayload()).contains("txn-1");
            assertThat(response.responsePayload()).isNull();
        }
    }

    @Nested
    @DisplayName("looking an account up")
    class Lookup {

        @Test
        void an_active_account_is_usable_and_names_its_holder() {
            lookupAnswers(HttpStatus.OK,
                    "{\"status\":\"ACTIVE\",\"holderName\":\"Speedy Couriers SARL\"}");

            BankClient.AccountCheck check = client.lookup("ACC-1");

            assertThat(check.verdict()).isEqualTo(Verdict.USABLE);
            // The operator is the only one who can spot a valid account belonging to the wrong company.
            assertThat(check.holderName()).isEqualTo("Speedy Couriers SARL");
        }

        @Test
        void a_missing_account_is_refused() {
            lookupAnswers(HttpStatus.NOT_FOUND, "{}");

            assertThat(client.lookup("ACC-1").verdict()).isEqualTo(Verdict.REFUSED);
        }

        /**
         * Exists, but money cannot land in it — every bit as unpayable as a typo, and far more
         * confusing to discover after a delivery.
         */
        @Test
        void an_account_that_exists_but_cannot_be_paid_is_refused() {
            lookupAnswers(HttpStatus.OK, "{\"status\":\"FROZEN\",\"holderName\":\"Someone\"}");

            BankClient.AccountCheck check = client.lookup("ACC-1");

            assertThat(check.verdict()).isEqualTo(Verdict.REFUSED);
            assertThat(check.detail()).contains("FROZEN");
        }

        @Test
        void a_closed_account_is_refused_too() {
            lookupAnswers(HttpStatus.OK, "{\"status\":\"CLOSED\"}");

            assertThat(client.lookup("ACC-1").verdict()).isEqualTo(Verdict.REFUSED);
        }

        /**
         * The three-valued verdict earning its keep. Collapsing this into REFUSED would reject
         * legitimate carriers during a bank outage; collapsing it into USABLE would pass the check
         * exactly when it could not be performed.
         */
        @Test
        void an_unreachable_bank_is_unknown_rather_than_a_bad_account() {
            server.expect(requestTo("http://bank.test/api/core-banking/accounts/ACC-1"))
                    .andRespond(withException(new java.io.IOException("connection reset")));

            BankClient.AccountCheck check = client.lookup("ACC-1");

            assertThat(check.verdict()).isEqualTo(Verdict.UNKNOWN);
            assertThat(check.detail()).contains("unreachable");
        }

        /** Our misconfiguration must not be reported as the carrier's bad account. */
        @Test
        void our_own_bad_credentials_are_unknown_rather_than_blamed_on_the_carrier() {
            lookupAnswers(HttpStatus.UNAUTHORIZED, "{}");

            BankClient.AccountCheck check = client.lookup("ACC-1");

            assertThat(check.verdict()).isEqualTo(Verdict.UNKNOWN);
            assertThat(check.detail()).contains("credentials");
        }

        @Test
        void a_bank_error_is_unknown() {
            lookupAnswers(HttpStatus.INTERNAL_SERVER_ERROR, "{}");

            assertThat(client.lookup("ACC-1").verdict()).isEqualTo(Verdict.UNKNOWN);
        }

        /** An answer with no status field says nothing about the account, so it cannot be usable. */
        @Test
        void a_response_missing_the_status_field_is_not_treated_as_usable() {
            lookupAnswers(HttpStatus.OK, "{\"holderName\":\"Someone\"}");

            assertThat(client.lookup("ACC-1").verdict()).isNotEqualTo(Verdict.USABLE);
        }
    }
}
