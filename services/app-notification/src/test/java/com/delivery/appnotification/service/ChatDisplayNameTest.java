package com.delivery.appnotification.service;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.security.oauth2.jwt.Jwt;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * The name hundreds of neighbours see. Every case that returns null here is a case where the
 * alternative would have been broadcasting something that identifies or reaches the person.
 */
class ChatDisplayNameTest {

    private static Jwt token(String given, String family) {
        Jwt.Builder builder = Jwt.withTokenValue("t").header("alg", "none").subject("sub")
                .claim("preferred_username", "96171123456")
                .claim("email", "tania@example.com");
        if (given != null) {
            builder.claim("given_name", given);
        }
        if (family != null) {
            builder.claim("family_name", family);
        }
        return builder.build();
    }

    @Test
    @DisplayName("is the first name and the family name's initial")
    void first_name_and_initial() {
        assertThat(ChatDisplayName.from(token("Tania", "Khoury"))).isEqualTo("Tania K.");
        assertThat(ChatDisplayName.from(token("ليلى", "حداد"))).isEqualTo("ليلى ح.");
        assertThat(ChatDisplayName.from(token("  Mary   Ann ", "de la Cruz"))).isEqualTo("Mary Ann D.");
    }

    @Test
    @DisplayName("is the first name alone when there is no usable family name")
    void first_name_alone() {
        assertThat(ChatDisplayName.from(token("Hadi", null))).isEqualTo("Hadi");
        assertThat(ChatDisplayName.from(token("Hadi", "  "))).isEqualTo("Hadi");
        assertThat(ChatDisplayName.from(token("Hadi", "'Saleh"))).isEqualTo("Hadi");
    }

    /** The username on this platform can be a phone number; it must never stand in for a name. */
    @Test
    @DisplayName("is nothing at all without a first name, never the username or email")
    void never_the_username_or_email() {
        assertThat(ChatDisplayName.from(token(null, "Khoury"))).isNull();
        assertThat(ChatDisplayName.from(token("", "Khoury"))).isNull();
        assertThat(ChatDisplayName.from(null)).isNull();
    }

    @Test
    @DisplayName("is nothing at all when the name field holds a phone number or an email")
    void contact_details_typed_as_a_name_are_refused() {
        assertThat(ChatDisplayName.from(token("+961 71 123 456", "Khoury"))).isNull();
        assertThat(ChatDisplayName.from(token("tania@example.com", null))).isNull();
        assertThat(ChatDisplayName.from(token("Tania", "70123456"))).isEqualTo("Tania");
    }

    @Test
    @DisplayName("is capped, so a pasted paragraph is not somebody's name")
    void long_names_are_capped() {
        String name = ChatDisplayName.from(token("A".repeat(200), "Khoury"));
        assertThat(name).isEqualTo("A".repeat(ChatDisplayName.MAX_GIVEN_NAME) + " K.");
    }
}
