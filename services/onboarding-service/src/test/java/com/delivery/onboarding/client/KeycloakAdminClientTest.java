package com.delivery.onboarding.client;

import java.net.URI;
import java.util.List;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatExceptionOfType;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.jsonPath;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.method;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withCreatedEntity;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withServerError;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withStatus;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;

/**
 * The admin API calls an applicant's sign-up depends on, against a Keycloak that answers as told.
 *
 * <p>Two properties the sign-up's retry rests on: Keycloak's 409 arrives as its own type, so a taken
 * address is not mistaken for an outage or the other way round; and APPLICANT is granted before the
 * role applied for, so a sign-up stopped between the two leaves an account that can do nothing — the
 * shape the retry recognises as the applicant's own.
 */
class KeycloakAdminClientTest {

    private static final String KEYCLOAK = "http://keycloak.test";
    private static final String USERS = KEYCLOAK + "/admin/realms/delivery-platform/users";

    private MockRestServiceServer server;
    private KeycloakAdminClient keycloak;

    @BeforeEach
    void setUp() {
        RestClient.Builder builder = RestClient.builder();
        server = MockRestServiceServer.bindTo(builder).build();
        keycloak = new KeycloakAdminClient(builder, KEYCLOAK, "delivery-platform",
                "onboarding-service", "service-account-secret");

        server.expect(requestTo(KEYCLOAK + "/realms/delivery-platform/protocol/openid-connect/token"))
                .andExpect(method(HttpMethod.POST))
                .andRespond(withSuccess("{\"access_token\":\"admin-token\",\"expires_in\":300}",
                        MediaType.APPLICATION_JSON));
    }

    @Test
    @DisplayName("a taken address is Keycloak's 409, and says so by its type")
    void a_taken_address_is_its_own_answer() {
        server.expect(requestTo(USERS)).andExpect(method(HttpMethod.POST))
                .andRespond(withStatus(HttpStatus.CONFLICT));

        assertThatExceptionOfType(KeycloakAdminClient.AccountExistsException.class)
                .isThrownBy(() -> keycloak.createApplicant(
                        "sam@example.test", "Sam", "Salem", "DELIVERY", "482910"));
        server.verify();
    }

    @Test
    @DisplayName("any other failure is not a taken address")
    void an_outage_is_not_a_taken_address() {
        server.expect(requestTo(USERS)).andExpect(method(HttpMethod.POST))
                .andRespond(withServerError());

        assertThatThrownBy(() -> keycloak.createApplicant(
                        "sam@example.test", "Sam", "Salem", "DELIVERY", "482910"))
                .isInstanceOf(KeycloakAdminClient.ProvisioningException.class)
                .isNotInstanceOf(KeycloakAdminClient.AccountExistsException.class);
    }

    @Test
    @DisplayName("an applicant is granted APPLICANT before the role they applied for")
    void applicant_comes_first() {
        server.expect(requestTo(USERS)).andExpect(method(HttpMethod.POST))
                .andRespond(withCreatedEntity(URI.create(USERS + "/kc-sam")));
        expectGrant("APPLICANT");
        expectGrant("DELIVERY");

        String userRef = keycloak.createApplicant(
                "sam@example.test", "Sam", "Salem", "DELIVERY", "482910");

        assertThat(userRef).isEqualTo("kc-sam");
        server.verify();
    }

    private void expectGrant(String role) {
        server.expect(requestTo(KEYCLOAK + "/admin/realms/delivery-platform/roles/" + role))
                .andExpect(method(HttpMethod.GET))
                .andRespond(withSuccess("{\"id\":\"role-" + role + "\",\"name\":\"" + role + "\"}",
                        MediaType.APPLICATION_JSON));
        server.expect(requestTo(USERS + "/kc-sam/role-mappings/realm"))
                .andExpect(method(HttpMethod.POST))
                .andExpect(jsonPath("$[0].name").value(role))
                .andRespond(withStatus(HttpStatus.NO_CONTENT));
    }

    @Test
    @DisplayName("an account's roles are read by name, Keycloak's own among them")
    void roles_are_read_by_name() {
        server.expect(requestTo(USERS + "/kc-sam/role-mappings/realm"))
                .andExpect(method(HttpMethod.GET))
                .andRespond(withSuccess("[{\"id\":\"1\",\"name\":\"APPLICANT\"},"
                                + "{\"id\":\"2\",\"name\":\"default-roles-delivery-platform\"}]",
                        MediaType.APPLICATION_JSON));

        assertThat(keycloak.realmRolesOf("kc-sam"))
                .containsExactly("APPLICANT", "default-roles-delivery-platform");
    }

    @Test
    @DisplayName("Keycloak's own roles are told apart from the platform's")
    void keycloaks_own_roles() {
        assertThat(List.of("default-roles-delivery-platform", "offline_access", "uma_authorization"))
                .allMatch(KeycloakAdminClient::isKeycloakOwnRole);
        assertThat(List.of("APPLICANT", "DELIVERY", "CUSTOMER", "BACKOFFICE", "MERCHANT_STAFF"))
                .noneMatch(KeycloakAdminClient::isKeycloakOwnRole);
    }
}
