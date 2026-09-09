package com.delivery.transfer.client;

import java.io.IOException;
import java.util.UUID;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.security.core.authority.AuthorityUtils;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;

import com.delivery.transfer.client.OrderManagerClient.OrderUnavailableException;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.header;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.method;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withException;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withStatus;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;

/**
 * The check that stands between an order id and a payment intent recorded against it.
 *
 * <p>Every answer here has to stop the transfer: an order that was never placed, an order that is
 * somebody else's, and an Order Manager that cannot be reached are all "do not record this", and
 * the only difference the customer can act on is the wording.
 */
class OrderManagerClientTest {

    private static final String BASE = "http://order-manager:8101";
    private static final String TOKEN = "the-callers-own-token";
    private static final UUID ORDER = UUID.fromString("11111111-2222-3333-4444-555555555555");

    private MockRestServiceServer server;
    private OrderManagerClient client;

    @BeforeEach
    void setUp() {
        RestClient.Builder builder = RestClient.builder().baseUrl(BASE);
        server = MockRestServiceServer.bindTo(builder).build();
        client = new OrderManagerClient(builder.build());

        Jwt jwt = Jwt.withTokenValue(TOKEN)
                .header("alg", "none")
                .subject("customer-sub")
                .build();
        SecurityContextHolder.getContext().setAuthentication(
                new JwtAuthenticationToken(jwt, AuthorityUtils.createAuthorityList("ROLE_CUSTOMER")));
    }

    @AfterEach
    void tearDown() {
        SecurityContextHolder.clearContext();
    }

    /**
     * The caller's own token, not a service account's: that is what makes Order Manager's existing
     * visibility rule the one that answers, instead of this service re-deriving ownership from
     * fields it does not own.
     */
    @Test
    @DisplayName("forwards the caller's bearer token and reads whose order it is")
    void forwardsTheCallersToken() {
        server.expect(requestTo(BASE + "/api/orders/" + ORDER))
                .andExpect(method(org.springframework.http.HttpMethod.GET))
                .andExpect(header("Authorization", "Bearer " + TOKEN))
                .andRespond(withSuccess("""
                        {"id":"%s","customerId":"customer-sub","merchantId":"merchant-sub",
                         "status":"PLACED","totalAmount":10.01,"deliveryTier":"STANDARD"}
                        """.formatted(ORDER), MediaType.APPLICATION_JSON));

        OrderManagerClient.OrderSummary order = client.fetch(ORDER);

        assertThat(order.customerId()).isEqualTo("customer-sub");
        server.verify();
    }

    @Test
    @DisplayName("an order that answers 404 is refused without saying which kind of 404 it was")
    void unknownOrderIsRefused() {
        server.expect(requestTo(BASE + "/api/orders/" + ORDER))
                .andRespond(withStatus(HttpStatus.NOT_FOUND));

        assertThatThrownBy(() -> client.fetch(ORDER))
                .isInstanceOf(OrderUnavailableException.class)
                .hasMessage("That order does not exist, or is not yours");
    }

    @Test
    @DisplayName("an unreachable Order Manager refuses rather than records")
    void unreachableOrderManagerIsRefused() {
        server.expect(requestTo(BASE + "/api/orders/" + ORDER))
                .andRespond(withException(new IOException("connect timed out")));

        assertThatThrownBy(() -> client.fetch(ORDER))
                .isInstanceOf(OrderUnavailableException.class)
                // The customer is told to try again; the framework's own words stay in the log.
                .hasMessage("The order could not be confirmed; please try again");
    }

    @Test
    @DisplayName("a 500 from Order Manager refuses rather than records")
    void brokenOrderManagerIsRefused() {
        server.expect(requestTo(BASE + "/api/orders/" + ORDER))
                .andRespond(withStatus(HttpStatus.INTERNAL_SERVER_ERROR));

        assertThatThrownBy(() -> client.fetch(ORDER))
                .isInstanceOf(OrderUnavailableException.class)
                .hasMessage("The order could not be confirmed; please try again");
    }
}
