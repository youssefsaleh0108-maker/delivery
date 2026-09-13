package com.delivery.product.service;

import java.net.ConnectException;
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
 */
@DisplayName("asking Onboarding what a merchant applied to be")
class OnboardingApplicationClientTest {

    private static final String ONBOARDING = "http://onboarding-service";
    private static final String MINE = ONBOARDING + "/api/onboarding/applications/mine";

    private RestClient.Builder builder;
    private MockRestServiceServer server;

    @BeforeEach
    void setUp() {
        builder = RestClient.builder().baseUrl(ONBOARDING);
        server = MockRestServiceServer.bindTo(builder).build();
        SecurityContextHolder.getContext().setAuthentication(new JwtAuthenticationToken(
                Jwt.withTokenValue("caller-token").header("alg", "none").subject("merchant-sub")
                        .build(),
                List.of()));
    }

    @AfterEach
    void tearDown() {
        SecurityContextHolder.clearContext();
    }

    private OnboardingApplicationClient client() {
        return new OnboardingApplicationClient(builder.build());
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
}
