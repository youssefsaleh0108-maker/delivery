package com.delivery.appnotification.client;

import java.util.UUID;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;

import com.delivery.appnotification.service.RoomExceptions.DirectoryUnavailableException;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.springframework.test.web.client.ExpectedCount.once;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.header;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.method;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withServerError;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withStatus;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;

/**
 * Asking Product Service, as the caller.
 */
class ProductDirectoryTest {

    private static final UUID MAR_MIKHAEL = UUID.fromString("11111111-1111-1111-1111-111111111111");
    private static final UUID RETIRED = UUID.fromString("22222222-2222-2222-2222-222222222222");

    private MockRestServiceServer server;
    private ProductDirectory directory;

    @BeforeEach
    void setUp() {
        RestClient.Builder builder = RestClient.builder().baseUrl("http://product-service");
        server = MockRestServiceServer.bindTo(builder).build();
        directory = new ProductDirectory(builder.build());
    }

    @AfterEach
    void tearDown() {
        SecurityContextHolder.clearContext();
    }

    private static void signedInWith(String tokenValue) {
        Jwt jwt = Jwt.withTokenValue(tokenValue).header("alg", "none").subject("customer-sub").build();
        SecurityContextHolder.getContext().setAuthentication(new JwtAuthenticationToken(jwt));
    }

    private void zonesAnswer() {
        server.expect(once(), requestTo("http://product-service/api/delivery-zones"))
                .andExpect(method(HttpMethod.GET))
                // The caller's own token, never a service identity with wider reach.
                .andExpect(header("Authorization", "Bearer customer-token"))
                .andRespond(withSuccess("""
                        [{"id":"11111111-1111-1111-1111-111111111111","name":"Mar Mikhael",
                          "region":"Beirut","sortOrder":1,"active":true},
                         {"id":"22222222-2222-2222-2222-222222222222","name":"Old Souk",
                          "region":"Beirut","sortOrder":2,"active":false}]
                        """, MediaType.APPLICATION_JSON));
    }

    @Test
    @DisplayName("finds an area the address picker offers, forwarding the caller's token")
    void finds_an_offered_area() {
        signedInWith("customer-token");
        zonesAnswer();

        assertThat(directory.activeZone(MAR_MIKHAEL))
                .hasValueSatisfying(zone -> assertThat(zone.name()).isEqualTo("Mar Mikhael"));
        server.verify();
    }

    @Test
    @DisplayName("does not offer a retired area")
    void a_retired_area_is_not_offered() {
        signedInWith("customer-token");
        zonesAnswer();

        assertThat(directory.activeZone(RETIRED)).isEmpty();
    }

    @Test
    @DisplayName("does not offer an area that is not on the list at all")
    void an_unlisted_area_is_not_offered() {
        signedInWith("customer-token");
        zonesAnswer();

        assertThat(directory.activeZone(UUID.randomUUID())).isEmpty();
    }

    @Test
    @DisplayName("refuses to guess when Product Service fails")
    void a_failure_is_not_a_guess() {
        signedInWith("customer-token");
        server.expect(once(), requestTo("http://product-service/api/delivery-zones"))
                .andRespond(withServerError());

        assertThatThrownBy(() -> directory.activeZone(MAR_MIKHAEL))
                .isInstanceOf(DirectoryUnavailableException.class);
    }

    @Test
    @DisplayName("reads a storefront the caller can see, and treats a 404 as no such shop")
    void storefront_or_nothing() {
        signedInWith("customer-token");
        UUID visible = UUID.fromString("33333333-3333-3333-3333-333333333333");
        UUID hidden = UUID.fromString("44444444-4444-4444-4444-444444444444");
        server.expect(once(), requestTo("http://product-service/api/stores/" + visible))
                .andExpect(header("Authorization", "Bearer customer-token"))
                .andRespond(withSuccess("{\"id\":\"" + visible + "\",\"name\":\"Abu Hassan Mini Market\","
                        + "\"slug\":\"abu-hassan\",\"rating\":4.6}", MediaType.APPLICATION_JSON));
        server.expect(once(), requestTo("http://product-service/api/stores/" + hidden))
                .andRespond(withStatus(HttpStatus.NOT_FOUND));

        assertThat(directory.storefront(visible))
                .hasValueSatisfying(store -> assertThat(store.name()).isEqualTo("Abu Hassan Mini Market"));
        assertThat(directory.storefront(hidden)).isEmpty();
    }

    /** The only way a shop's owner is known: Product Service answering for the merchant's own token. */
    @Test
    @DisplayName("learns a merchant's shops from /api/stores/mine asked with their own token")
    void a_merchants_own_shops() {
        signedInWith("merchant-token");
        server.expect(once(), requestTo("http://product-service/api/stores/mine?size=100"))
                .andExpect(header("Authorization", "Bearer merchant-token"))
                .andRespond(withSuccess("{\"content\":[{\"id\":\"33333333-3333-3333-3333-333333333333\","
                        + "\"name\":\"Abu Hassan Mini Market\"}],\"page\":0,\"size\":100,"
                        + "\"totalElements\":1,\"totalPages\":1}", MediaType.APPLICATION_JSON));

        assertThat(directory.storesOwnedByCaller())
                .containsExactly(UUID.fromString("33333333-3333-3333-3333-333333333333"));
    }

    @Test
    @DisplayName("a caller Product Service does not treat as a merchant owns nothing; a failure is not 'nothing'")
    void forbidden_is_nothing_and_failure_is_unavailable() {
        signedInWith("customer-token");
        server.expect(once(), requestTo("http://product-service/api/stores/mine?size=100"))
                .andRespond(withStatus(HttpStatus.FORBIDDEN));
        server.expect(once(), requestTo("http://product-service/api/stores/mine?size=100"))
                .andRespond(withServerError());

        assertThat(directory.storesOwnedByCaller()).isEmpty();
        assertThatThrownBy(() -> directory.storesOwnedByCaller())
                .isInstanceOf(DirectoryUnavailableException.class);
    }

    @Test
    @DisplayName("will not ask without a caller to ask for")
    void no_caller_no_call() {
        assertThatThrownBy(() -> directory.activeZone(MAR_MIKHAEL))
                .isInstanceOf(IllegalStateException.class);
    }
}
