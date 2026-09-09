package com.delivery.settings.api;

import java.util.List;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import com.delivery.settings.domain.ConnectorType;
import com.delivery.settings.service.ConnectorSettingsService;

import static org.assertj.core.api.Assertions.assertThat;
import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.not;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * What a caller gets for a connector name this service does not have.
 *
 * <p>The observed case: {@code GET /api/settings/connectors/NOPE} answered 422 with "No enum
 * constant com.delivery.settings.domain.ConnectorType.NOPE". Two things were wrong with that. It
 * described our packages and classes to somebody who had asked about a URL, and 422 told the caller
 * the request was understood and rejected on its merits when in fact the address does not exist.
 *
 * <p>Standalone MockMvc, so the refusal is proven against the exception Spring really raises when a
 * path variable will not bind — not one built by hand.
 */
@DisplayName("an unknown connector in the path")
class ConnectorSettingsControllerTest {

    private final ConnectorSettingsService settings = mock(ConnectorSettingsService.class);

    private final MockMvc mvc = MockMvcBuilders
            .standaloneSetup(new ConnectorSettingsController(settings))
            .build();

    @Nested
    @DisplayName("is a 400 the caller can act on")
    class Refused {

        @Test
        void names_the_parameter_rather_than_the_enum() throws Exception {
            mvc.perform(get("/api/settings/connectors/NOPE"))
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.title").value("Bad request"))
                    .andExpect(jsonPath("$.detail")
                            .value("Parameter 'type' is not a connector this service manages"));
        }

        @Test
        void is_refused_the_same_way_on_the_history_route() throws Exception {
            mvc.perform(get("/api/settings/connectors/NOPE/history"))
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.detail")
                            .value("Parameter 'type' is not a connector this service manages"));
        }

        /**
         * The whole point of the finding: an internal class name in an error body is a map of the
         * codebase handed to whoever asked for a wrong URL.
         */
        @Test
        void leaks_no_class_name_and_no_framework_message() throws Exception {
            String body = mvc.perform(get("/api/settings/connectors/NOPE"))
                    .andReturn().getResponse().getContentAsString();

            assertThat(body).doesNotContain("com.delivery", "ConnectorType", "No enum constant",
                    "java.lang");
        }

        /**
         * The sentence is written here rather than assembled from what arrived. The path itself
         * comes back in the problem's {@code instance}, which is the caller's own URL and RFC 9457's
         * business; the detail is ours and stays free of anything somebody else may have written.
         */
        @Test
        void does_not_build_the_message_out_of_the_value_it_was_given() throws Exception {
            mvc.perform(get("/api/settings/connectors/NOPE"))
                    .andExpect(jsonPath("$.detail").value(not(containsString("NOPE"))));
        }
    }

    @Nested
    @DisplayName("does not change a connector that does exist")
    class StillWorks {

        @Test
        void a_real_connector_still_reaches_the_service() throws Exception {
            when(settings.history(ConnectorType.SMS)).thenReturn(List.of());

            mvc.perform(get("/api/settings/connectors/SMS/history"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$").isArray());
        }
    }
}
