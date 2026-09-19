package com.delivery.onboarding.api;

import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.yaml.snakeyaml.Yaml;

import com.delivery.onboarding.client.PlatformClient;
import com.delivery.onboarding.service.HiringCompanies;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * GET /api/onboarding/hiring-companies — the list the rider wizard offers, over HTTP.
 *
 * <p>Pinned: nobody has to be signed in, down to the line on the permit-all list; each company comes
 * with an id, a name and its region, and an empty list for a company with none, in the same shape
 * Order Manager's own list has, so the app reads either; the list is the form's remembered one, never
 * the judgement's; and Order Manager not answering is the coded 503 the app translates.
 */
@DisplayName("the open list of who is hiring, over HTTP")
class HiringCompaniesControllerTest {

    private static final String PATH = "/api/onboarding/hiring-companies";
    private static final UUID SWIFT = UUID.fromString("8a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d");
    private static final UUID FRESH = UUID.fromString("1f2e3d4c-5b6a-4978-8695-a4b3c2d1e0f9");

    private HiringCompanies hiring;
    private MockMvc mvc;

    @BeforeEach
    void setUp() {
        hiring = mock(HiringCompanies.class);
        mvc = MockMvcBuilders.standaloneSetup(new HiringCompaniesController(hiring)).build();
        // A rider with no account: nobody is signed in.
        SecurityContextHolder.clearContext();
    }

    @Test
    @DisplayName("answers anybody with each company's id, name and region, from the form's list")
    void the_list_for_anybody() throws Exception {
        when(hiring.forTheForm()).thenReturn(List.of(
                new HiringCompanies.Company(SWIFT, "Swift Couriers", List.of("Beirut", "Mount Lebanon")),
                new HiringCompanies.Company(FRESH, "Fresh Fleet", List.of())));

        mvc.perform(get(PATH))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(2))
                .andExpect(jsonPath("$[0].id").value(SWIFT.toString()))
                .andExpect(jsonPath("$[0].name").value("Swift Couriers"))
                .andExpect(jsonPath("$[0].regions.length()").value(2))
                .andExpect(jsonPath("$[0].regions[0]").value("Beirut"))
                .andExpect(jsonPath("$[0].regions[1]").value("Mount Lebanon"))
                .andExpect(jsonPath("$[1].regions").isArray())
                .andExpect(jsonPath("$[1].regions").isEmpty());

        verify(hiring).forTheForm();
        verify(hiring, never()).find(any());
    }

    @Test
    @DisplayName("Order Manager not answering is the coded 503 the app says in its own words")
    void order_manager_not_answering() throws Exception {
        when(hiring.forTheForm()).thenThrow(new PlatformClient.CompaniesUnavailableException(
                "We could not check that delivery company just now. Please try again in a moment.",
                null));

        mvc.perform(get(PATH))
                .andExpect(status().isServiceUnavailable())
                .andExpect(jsonPath("$.code").value("hiring-companies-unavailable"));
    }

    @Test
    @DisplayName("the path is on the permit-all list, so a rider with no account is not turned away first")
    void open_to_anybody_in_the_security_config() throws IOException {
        assertThat(permitAll(Path.of("src/main/resources/application.yml"))).contains(PATH);
    }

    @SuppressWarnings("unchecked")
    private static List<String> permitAll(Path yaml) throws IOException {
        List<String> entries = new ArrayList<>();
        try (InputStream in = Files.newInputStream(yaml)) {
            for (Object document : new Yaml().loadAll(in)) {
                if (document instanceof Map<?, ?> root
                        && root.get("delivery") instanceof Map<?, ?> delivery
                        && delivery.get("security") instanceof Map<?, ?> security
                        && security.get("permit-all") instanceof List<?> list) {
                    entries.addAll((List<String>) list);
                }
            }
        }
        return entries;
    }
}
