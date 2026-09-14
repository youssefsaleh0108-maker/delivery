package com.delivery.product.service;

import java.net.ConnectException;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.util.List;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.test.web.client.ExpectedCount;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.ResourceAccessException;
import org.springframework.web.client.RestClient;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.header;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withResourceNotFound;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withServerError;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withUnauthorizedRequest;

/**
 * Asking Onboarding whether the calling merchant applied to offer services — and, above all, that
 * failing to find out never reads as "no".
 *
 * <p>"No" opens a restaurant for a merchant with no shop, and a restaurant can never become a
 * services shop. So every way Onboarding can fail to answer — an error, a refused token, a refused
 * connection, a body that is not an application, no token to ask with — must arrive as the one
 * exception the handler turns into a 503. Only a test of this class can see that; the service tests
 * mock it.
 *
 * <p>The last tests pin what is remembered: a yes, for a minute, for that account only — so a waiting
 * applicant refused on every "add product" asks Onboarding once a minute rather than once a tap.
 */
@DisplayName("asking Onboarding what a merchant applied to be")
class OnboardingApplicationClientTest {

    private static final String ONBOARDING = "http://onboarding-service";
    private static final String MINE = ONBOARDING + "/api/onboarding/applications/mine";

    private static final String SERVICES_RECEIPT = """
            {"reference":"ref-1","status":"SUBMITTED","kind":"MERCHANT",
             "service":{"category":"PRINTING","zoneId":"z-1","area":"Hamra"}}""";

    /** A clock the test moves by hand. */
    private static final class MovableClock extends Clock {

        private Instant now = Instant.parse("2026-09-14T10:00:00Z");

        void advance(Duration by) {
            now = now.plus(by);
        }

        @Override
        public ZoneId getZone() {
            return ZoneOffset.UTC;
        }

        @Override
        public Clock withZone(ZoneId zone) {
            return this;
        }

        @Override
        public Instant instant() {
            return now;
        }
    }

    private final MovableClock clock = new MovableClock();

    private RestClient.Builder builder;
    private MockRestServiceServer server;

    @BeforeEach
    void setUp() {
        builder = RestClient.builder().baseUrl(ONBOARDING);
        server = MockRestServiceServer.bindTo(builder).build();
        signInAs("merchant-sub", "caller-token");
    }

    @AfterEach
    void tearDown() {
        SecurityContextHolder.clearContext();
    }

    private static void signInAs(String subject, String token) {
        SecurityContextHolder.getContext().setAuthentication(new JwtAuthenticationToken(
                Jwt.withTokenValue(token).header("alg", "none").subject(subject).build(),
                List.of()));
    }

    private OnboardingApplicationClient client() {
        return new OnboardingApplicationClient(builder.build(), clock);
    }

    @Test
    @DisplayName("a receipt with a services block is a services applicant, asked with the caller's own token")
    void a_services_receipt() {
        server.expect(requestTo(MINE))
                .andExpect(header(HttpHeaders.AUTHORIZATION, "Bearer caller-token"))
                .andRespond(withSuccess("""
                        {"reference":"ref-1","status":"APPROVED","kind":"MERCHANT",
                         "service":{"category":"PRINTING","zoneId":"z-1","area":"Hamra"}}""",
                        MediaType.APPLICATION_JSON));

        assertThat(client().appliedToOfferServices()).isTrue();
        server.verify();
    }

    @Test
    @DisplayName("a shop's receipt, whose services block is null, is not")
    void a_shops_receipt() {
        server.expect(requestTo(MINE)).andRespond(withSuccess("""
                {"reference":"ref-2","status":"SUBMITTED","kind":"MERCHANT","service":null}""",
                MediaType.APPLICATION_JSON));

        assertThat(client().appliedToOfferServices()).isFalse();
    }

    @Test
    @DisplayName("an account with no application at all (404) is not")
    void no_application() {
        server.expect(requestTo(MINE)).andRespond(withResourceNotFound());

        assertThat(client().appliedToOfferServices()).isFalse();
    }

    @Test
    @DisplayName("an error from Onboarding is an outage, never 'not a services applicant'")
    void an_error_is_an_outage() {
        server.expect(requestTo(MINE)).andRespond(withServerError());

        assertThatThrownBy(() -> client().appliedToOfferServices())
                .isInstanceOf(OnboardingApplicationClient.OnboardingUnavailableException.class);
    }

    @Test
    @DisplayName("a token Onboarding refuses is an outage too")
    void a_refused_token_is_an_outage() {
        server.expect(requestTo(MINE)).andRespond(withUnauthorizedRequest());

        assertThatThrownBy(() -> client().appliedToOfferServices())
                .isInstanceOf(OnboardingApplicationClient.OnboardingUnavailableException.class);
    }

    @Test
    @DisplayName("a body that is not an application is an outage")
    void nonsense_is_an_outage() {
        server.expect(requestTo(MINE)).andRespond(withSuccess("[]", MediaType.APPLICATION_JSON));

        assertThatThrownBy(() -> client().appliedToOfferServices())
                .isInstanceOf(OnboardingApplicationClient.OnboardingUnavailableException.class);
    }

    @Test
    @DisplayName("a refused connection is an outage, not an unhandled error")
    void a_refused_connection_is_an_outage() {
        OnboardingApplicationClient unreachable = new OnboardingApplicationClient(RestClient.builder()
                .baseUrl(ONBOARDING)
                .requestFactory((uri, method) -> {
                    throw new ConnectException("Connection refused");
                })
                .build());

        assertThatThrownBy(unreachable::appliedToOfferServices)
                .isInstanceOf(OnboardingApplicationClient.OnboardingUnavailableException.class)
                .hasCauseInstanceOf(ResourceAccessException.class);
    }

    @Test
    @DisplayName("with no caller token there is nothing to ask with, and nothing is asked")
    void no_token_asks_nothing() {
        SecurityContextHolder.clearContext();

        assertThatThrownBy(() -> client().appliedToOfferServices())
                .isInstanceOf(OnboardingApplicationClient.OnboardingUnavailableException.class);
        server.verify();
    }

    @Test
    @DisplayName("a yes is remembered for a minute: a waiting applicant tapping 'add product' again asks once")
    void a_yes_is_remembered_for_a_minute() {
        server.expect(ExpectedCount.once(), requestTo(MINE))
                .andRespond(withSuccess(SERVICES_RECEIPT, MediaType.APPLICATION_JSON));
        OnboardingApplicationClient client = client();

        assertThat(client.appliedToOfferServices()).isTrue();
        clock.advance(OnboardingApplicationClient.SERVICES_APPLICANT_REMEMBERED_FOR.minusSeconds(1));
        assertThat(client.appliedToOfferServices()).isTrue();
        server.verify();
    }

    @Test
    @DisplayName("once the minute is up, Onboarding is asked again")
    void a_yes_is_asked_again_after_a_minute() {
        server.expect(ExpectedCount.twice(), requestTo(MINE))
                .andRespond(withSuccess(SERVICES_RECEIPT, MediaType.APPLICATION_JSON));
        OnboardingApplicationClient client = client();

        client.appliedToOfferServices();
        clock.advance(OnboardingApplicationClient.SERVICES_APPLICANT_REMEMBERED_FOR);
        assertThat(client.appliedToOfferServices()).isTrue();
        server.verify();
    }

    @Test
    @DisplayName("a no is not remembered: it opens a shop, and after that nobody asks")
    void a_no_is_not_remembered() {
        server.expect(ExpectedCount.twice(), requestTo(MINE)).andRespond(withResourceNotFound());
        OnboardingApplicationClient client = client();

        assertThat(client.appliedToOfferServices()).isFalse();
        assertThat(client.appliedToOfferServices()).isFalse();
        server.verify();
    }

    @Test
    @DisplayName("a remembered yes is only ever the account's own")
    void a_yes_is_the_accounts_own() {
        server.expect(ExpectedCount.once(), requestTo(MINE))
                .andExpect(header(HttpHeaders.AUTHORIZATION, "Bearer caller-token"))
                .andRespond(withSuccess(SERVICES_RECEIPT, MediaType.APPLICATION_JSON));
        server.expect(ExpectedCount.once(), requestTo(MINE))
                .andExpect(header(HttpHeaders.AUTHORIZATION, "Bearer grill-token"))
                .andRespond(withResourceNotFound());
        OnboardingApplicationClient client = client();

        assertThat(client.appliedToOfferServices()).isTrue();
        signInAs("grill-owner-sub", "grill-token");
        assertThat(client.appliedToOfferServices()).isFalse();
        server.verify();
    }
}
