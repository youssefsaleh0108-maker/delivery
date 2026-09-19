package com.delivery.onboarding.client;

import java.net.URI;
import java.util.List;
import java.util.UUID;

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
 * <p>What the sign-up's retry rests on: Keycloak's 409 arrives as its own type, so a taken address is
 * not mistaken for an outage or the other way round; the account is stamped with its application's
 * id in the very request that creates it, and the stamp and any Google link are read back — the two
 * things the retry asks before it touches an account; and APPLICANT is granted before the role
 * applied for, so a sign-up stopped between the two leaves an account that can do nothing.
 */
class KeycloakAdminClientTest {

    private static final String KEYCLOAK = "http://keycloak.test";
    private static final String USERS = KEYCLOAK + "/admin/realms/delivery-platform/users";
    private static final UUID APPLICATION = UUID.fromString("5f0e8f3a-6c1d-4b8e-9a51-3d2c7b9e4a10");

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
                        "sam@example.test", "Sam", "Salem", "DELIVERY", "482910", APPLICATION));
        server.verify();
    }

    @Test
    @DisplayName("any other failure is not a taken address")
    void an_outage_is_not_a_taken_address() {
        server.expect(requestTo(USERS)).andExpect(method(HttpMethod.POST))
                .andRespond(withServerError());

        assertThatThrownBy(() -> keycloak.createApplicant(
                        "sam@example.test", "Sam", "Salem", "DELIVERY", "482910", APPLICATION))
                .isInstanceOf(KeycloakAdminClient.ProvisioningException.class)
                .isNotInstanceOf(KeycloakAdminClient.AccountExistsException.class);
    }

    @Test
    @DisplayName("an applicant is created stamped with their application's id, in the same request, "
            + "then granted APPLICANT before the role they applied for")
    void applicant_comes_first() {
        server.expect(requestTo(USERS)).andExpect(method(HttpMethod.POST))
                .andExpect(jsonPath("$.attributes.onboardingApplicationId[0]").value(APPLICATION.toString()))
                .andExpect(jsonPath("$.attributes.onboardingApplicationId.length()").value(1))
                .andRespond(withCreatedEntity(URI.create(USERS + "/kc-sam")));
        expectGrant("APPLICANT");
        expectGrant("DELIVERY");

        String userRef = keycloak.createApplicant(
                "sam@example.test", "Sam", "Salem", "DELIVERY", "482910", APPLICATION);

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
    @DisplayName("the stamp an applicant account carries is read back as the application's id")
    void the_stamp_is_read_back() {
        server.expect(requestTo(USERS + "/kc-sam")).andExpect(method(HttpMethod.GET))
                .andRespond(withSuccess("{\"id\":\"kc-sam\",\"attributes\":{\"onboardingApplicationId\":"
                                + "[\"" + APPLICATION + "\"]}}",
                        MediaType.APPLICATION_JSON));

        assertThat(keycloak.applicationStampOf("kc-sam")).contains(APPLICATION.toString());
    }

    @Test
    @DisplayName("an account this service never stamped has no stamp, whatever else it carries")
    void an_unstamped_account_has_none() {
        server.expect(requestTo(USERS + "/kc-google")).andExpect(method(HttpMethod.GET))
                .andRespond(withSuccess("{\"id\":\"kc-google\",\"attributes\":{\"fcmToken\":[\"t\"]}}",
                        MediaType.APPLICATION_JSON));

        assertThat(keycloak.applicationStampOf("kc-google")).isEmpty();
    }

    @Test
    @DisplayName("an account somebody signed in to through Google is seen as linked")
    void a_google_link_is_seen() {
        server.expect(requestTo(USERS + "/kc-google/federated-identity")).andExpect(method(HttpMethod.GET))
                .andRespond(withSuccess("[{\"identityProvider\":\"google\",\"userId\":\"1098\","
                                + "\"userName\":\"sam@gmail.example\"}]",
                        MediaType.APPLICATION_JSON));

        assertThat(keycloak.isLinkedToIdentityProvider("kc-google")).isTrue();
    }

    @Test
    @DisplayName("an account with no identity-provider link is not linked")
    void no_link_is_not_linked() {
        server.expect(requestTo(USERS + "/kc-sam/federated-identity")).andExpect(method(HttpMethod.GET))
                .andRespond(withSuccess("[]", MediaType.APPLICATION_JSON));

        assertThat(keycloak.isLinkedToIdentityProvider("kc-sam")).isFalse();
    }
}
