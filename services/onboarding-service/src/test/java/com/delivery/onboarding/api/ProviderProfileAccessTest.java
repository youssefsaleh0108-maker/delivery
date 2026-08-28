package com.delivery.onboarding.api;

import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import com.delivery.onboarding.client.PlatformClient;
import com.delivery.onboarding.domain.ProviderProfile;
import com.delivery.onboarding.service.ProviderProfileService;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.ArgumentMatchers.anyMap;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * A carrier edits their own company's settings and nobody else's, and support can look without
 * being able to touch.
 *
 * <p>The provider id in the URL is the caller's claim; Order Manager's staff record is the
 * evidence, asked per request. The one deliberate exception — BACKOFFICE reading without the
 * staff check — is pinned here too, because it is the kind of exception that grows if untested.
 */
class ProviderProfileAccessTest {

    private static final String OWNER = "keycloak-sub-owner";

    private ProviderProfileService profiles;
    private PlatformClient platform;
    private MockMvc mvc;

    private final UUID myCompany = UUID.randomUUID();
    private final UUID rivalCompany = UUID.randomUUID();

    @BeforeEach
    void setUp() {
        profiles = mock(ProviderProfileService.class);
        platform = mock(PlatformClient.class);
        mvc = MockMvcBuilders.standaloneSetup(
                new ProviderProfileController(profiles, platform)).build();

        when(platform.isStaffOf(myCompany, OWNER)).thenReturn(true);
        when(platform.isStaffOf(rivalCompany, OWNER)).thenReturn(false);
        when(profiles.forProvider(any())).thenReturn(Optional.empty());
        when(profiles.logoUrl(any())).thenReturn(Optional.empty());
    }

    @AfterEach
    void tearDown() {
        SecurityContextHolder.clearContext();
    }

    private static void signedInAs(String subject, String... roles) {
        Jwt jwt = Jwt.withTokenValue("token")
                .header("alg", "none")
                .subject(subject)
                .build();
        List<GrantedAuthority> authorities = java.util.Arrays.stream(roles)
                .<GrantedAuthority>map(role -> new SimpleGrantedAuthority("ROLE_" + role))
                .toList();
        SecurityContextHolder.getContext().setAuthentication(
                new JwtAuthenticationToken(jwt, authorities));
    }

    private static String path(UUID providerId) {
        return "/api/onboarding/providers/" + providerId + "/profile";
    }

    @Nested
    @DisplayName("reading")
    class Reading {

        /** No row is not a 404: the settings screen has to render something to edit. */
        @Test
        void a_company_that_never_saved_settings_reads_as_empty_settings() throws Exception {
            signedInAs(OWNER, "CARRIER");
            mvc.perform(get(path(myCompany)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.providerId").value(myCompany.toString()))
                    .andExpect(jsonPath("$.logoUrl").doesNotExist())
                    .andExpect(jsonPath("$.dispatchRegions.length()").value(0));
        }

        @Test
        void a_carrier_cannot_read_a_company_they_do_not_run() throws Exception {
            signedInAs(OWNER, "CARRIER");
            mvc.perform(get(path(rivalCompany)))
                    .andExpect(status().isForbidden());

            verify(profiles, never()).forProvider(any());
        }

        /** The one exception: support may look at what the carrier is looking at, without editing. */
        @Test
        void backoffice_reads_any_company_without_the_staff_check() throws Exception {
            signedInAs("support-1", "BACKOFFICE");
            mvc.perform(get(path(rivalCompany)))
                    .andExpect(status().isOk());

            verify(platform, never()).isStaffOf(any(), anyString());
        }
    }

    @Nested
    @DisplayName("writing")
    class Writing {

        @Test
        void the_owner_saves_and_reads_back_what_was_saved() throws Exception {
            ProviderProfile saved = new ProviderProfile(myCompany);
            saved.updateSettings(List.of("Beirut"),
                    Map.of("MONDAY", Map.of("open", "08:00", "close", "22:00")), OWNER);
            when(profiles.save(any(), anyString(), anyList(), anyMap())).thenReturn(saved);

            signedInAs(OWNER, "CARRIER");
            mvc.perform(put(path(myCompany))
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{\"dispatchRegions\": [\"Beirut\"], \"operatingHours\":"
                                    + " {\"MONDAY\": {\"open\": \"08:00\", \"close\": \"22:00\"}}}"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.dispatchRegions[0]").value("Beirut"))
                    .andExpect(jsonPath("$.operatingHours.MONDAY.open").value("08:00"));
        }

        @Test
        void a_carrier_cannot_write_a_company_they_do_not_run() throws Exception {
            signedInAs(OWNER, "CARRIER");
            mvc.perform(put(path(rivalCompany))
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{\"dispatchRegions\": [], \"operatingHours\": {}}"))
                    .andExpect(status().isForbidden());

            verify(profiles, never()).save(any(), anyString(), anyList(), anyMap());
        }

        @Test
        void settings_that_break_the_rules_are_a_422_with_the_rule_in_the_message() throws Exception {
            when(profiles.save(any(), anyString(), anyList(), anyMap()))
                    .thenThrow(new ProviderProfileService.ProfileRuleException(
                            "MONDAY must open before it closes (22:00–08:00)"));

            signedInAs(OWNER, "CARRIER");
            mvc.perform(put(path(myCompany))
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{\"dispatchRegions\": [], \"operatingHours\":"
                                    + " {\"MONDAY\": {\"open\": \"22:00\", \"close\": \"08:00\"}}}"))
                    .andExpect(status().isUnprocessableEntity())
                    .andExpect(jsonPath("$.message")
                            .value("MONDAY must open before it closes (22:00–08:00)"));
        }
    }
}
