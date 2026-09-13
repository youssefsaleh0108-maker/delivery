package com.delivery.tracking.client;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import com.delivery.tracking.client.CarrierDirectoryClient.DirectoryUnavailableException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * Reading a fleet out of Order Manager's {@code GET /my-company/riders} answer.
 *
 * <p>The one distinction that matters: a fleet with nobody on it is a fact, and an answer with no
 * rider list at all is Order Manager contradicting itself. Reading the second as the first would
 * tell a dispatcher that every rider had left at once.
 */
@DisplayName("reading a fleet out of Order Manager's answer")
class CarrierDirectoryClientFleetTest {

    private static final ObjectMapper JSON = new ObjectMapper();

    @Test
    @DisplayName("every rider on the list is on the fleet")
    void reads_every_rider() throws Exception {
        JsonNode body = JSON.readTree(
                "{\"providerId\":\"5857ac51-0000-4000-8000-000000000001\","
                        + "\"riders\":[\"rider-a\",\"rider-b\"]}");

        assertThat(CarrierDirectoryClient.ridersIn(body)).containsExactlyInAnyOrder("rider-a", "rider-b");
    }

    @Test
    @DisplayName("an empty list is a fleet with nobody on it")
    void an_empty_list_is_an_empty_fleet() throws Exception {
        assertThat(CarrierDirectoryClient.ridersIn(JSON.readTree("{\"riders\":[]}"))).isEmpty();
    }

    @Test
    @DisplayName("an answer with no rider list is an outage, never an empty fleet")
    void no_list_is_an_outage() throws Exception {
        JsonNode noList = JSON.readTree("{\"providerId\":\"5857ac51-0000-4000-8000-000000000001\"}");

        assertThatThrownBy(() -> CarrierDirectoryClient.ridersIn(noList))
                .isInstanceOf(DirectoryUnavailableException.class);
        assertThatThrownBy(() -> CarrierDirectoryClient.ridersIn(null))
                .isInstanceOf(DirectoryUnavailableException.class);
    }
}
