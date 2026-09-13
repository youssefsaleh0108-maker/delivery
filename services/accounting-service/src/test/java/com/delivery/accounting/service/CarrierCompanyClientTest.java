package com.delivery.accounting.service;

import java.net.ConnectException;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.header;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withResourceNotFound;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withServerError;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.ResourceAccessException;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;

/**
 * Finding the caller's delivery company — and, above all, that failing to find out arrives as one
 * of the two answers every caller knows how to give.
 *
 * <p>The controllers turn {@link CarrierCompanyClient.NoCompanyException} into a 403 and
 * {@link IllegalStateException} into a 503, and their tests mock exactly those two. So the one
 * thing only a test of this class can prove is that everything Order Manager can do wrong becomes
 * one of them: a refused connection that escaped as a {@link ResourceAccessException} was a 500 on
 * every carrier page, and no mocked controller test could see it.
 */
@DisplayName("finding the caller's delivery company")
class CarrierCompanyClientTest {

    private static final String ORDER_MANAGER = "http://order-manager";
    private static final String MY_COMPANY = ORDER_MANAGER + "/api/delivery-providers/my-company";

    @Test
    @DisplayName("reads the company's id, asking with the caller's own token")
    void readsTheId() {
        RestClient.Builder builder = RestClient.builder();
        MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
        server.expect(requestTo(MY_COMPANY))
                .andExpect(header(HttpHeaders.AUTHORIZATION, "Bearer caller-token"))
                .andRespond(withSuccess("{\"id\":\"provider-77\",\"name\":\"Libanex Express\"}",
                        MediaType.APPLICATION_JSON));

        assertThat(new CarrierCompanyClient(builder, ORDER_MANAGER).companyIdFor("caller-token"))
                .isEqualTo("provider-77");
        server.verify();
    }

    @Test
    @DisplayName("a 404 means the caller is staff of no company")
    void notStaff() {
        RestClient.Builder builder = RestClient.builder();
        MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
        server.expect(requestTo(MY_COMPANY)).andRespond(withResourceNotFound());

        assertThatThrownBy(() -> new CarrierCompanyClient(builder, ORDER_MANAGER)
                .companyIdFor("caller-token"))
                .isInstanceOf(CarrierCompanyClient.NoCompanyException.class);
    }

    @Test
    @DisplayName("an error from Order Manager is an outage, never 'no company'")
    void orderManagerFails() {
        RestClient.Builder builder = RestClient.builder();
        MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
        server.expect(requestTo(MY_COMPANY)).andRespond(withServerError());

        assertThatThrownBy(() -> new CarrierCompanyClient(builder, ORDER_MANAGER)
                .companyIdFor("caller-token"))
                .isInstanceOf(IllegalStateException.class);
    }

    @Test
    @DisplayName("a refused connection is an outage too, not an unhandled error")
    void connectionRefused() {
        // What a pod restart or a timeout looks like from here: RestClient wraps the I/O failure in a
        // ResourceAccessException, which is not a response exception and used to escape as a 500.
        RestClient.Builder builder = RestClient.builder().requestFactory((uri, method) -> {
            throw new ConnectException("Connection refused");
        });

        assertThatThrownBy(() -> new CarrierCompanyClient(builder, ORDER_MANAGER)
                .companyIdFor("caller-token"))
                .isInstanceOf(IllegalStateException.class)
                .hasCauseInstanceOf(ResourceAccessException.class);
    }

    @Test
    @DisplayName("an answer that cannot be read as a company is an outage too")
    void unreadableAnswer() {
        RestClient.Builder builder = RestClient.builder();
        MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
        server.expect(requestTo(MY_COMPANY))
                .andRespond(withSuccess("{\"id\":", MediaType.APPLICATION_JSON));

        assertThatThrownBy(() -> new CarrierCompanyClient(builder, ORDER_MANAGER)
                .companyIdFor("caller-token"))
                .isInstanceOf(IllegalStateException.class)
                .hasCauseInstanceOf(RestClientException.class);
    }
}
