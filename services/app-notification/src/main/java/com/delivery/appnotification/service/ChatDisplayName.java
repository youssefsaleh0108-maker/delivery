package com.delivery.appnotification.service;

import java.util.Locale;

import org.springframework.security.oauth2.jwt.Jwt;

/**
 * What a neighbour is called in a room: a first name and a last initial, or nothing.
 *
 * <p><strong>Built only from the name claims, never from the username, email or phone.</strong> On
 * this platform a Keycloak username can be a phone number, and a room is read by hundreds of
 * strangers who live on the same streets. So the only inputs are {@code given_name} and
 * {@code family_name}, and even those are refused if they look like contact details — a customer who
 * typed their mobile number into the first-name field at sign-up must not have it broadcast to their
 * neighbourhood. When nothing usable is left the name is null and the app draws a generic
 * "Neighbour", which is less friendly and never a leak.
 *
 * <p>The family name contributes one letter. A full name plus a neighbourhood is enough to find a
 * person's door.
 */
public final class ChatDisplayName {

    /** Room display names are short labels, not biographies. */
    static final int MAX_GIVEN_NAME = 40;

    private ChatDisplayName() {
    }

    public static String from(Jwt jwt) {
        if (jwt == null) {
            return null;
        }
        String given = usable(jwt.getClaimAsString("given_name"));
        if (given == null) {
            return null;
        }
        if (given.codePointCount(0, given.length()) > MAX_GIVEN_NAME) {
            given = given.substring(0, given.offsetByCodePoints(0, MAX_GIVEN_NAME)).strip();
        }

        String family = usable(jwt.getClaimAsString("family_name"));
        if (family == null) {
            return given;
        }
        int initial = family.codePointAt(0);
        if (!Character.isLetter(initial)) {
            return given;
        }
        return given + " " + new String(Character.toChars(initial)).toUpperCase(Locale.ROOT) + ".";
    }

    /**
     * Blank, or shaped like contact details, is unusable.
     *
     * <p>Digits are refused outright: no given or family name contains one, and every phone number
     * does. '@' catches an email pasted into a name field.
     */
    private static String usable(String raw) {
        if (raw == null) {
            return null;
        }
        String cleaned = raw.strip().replaceAll("\\s+", " ");
        if (cleaned.isEmpty()) {
            return null;
        }
        boolean contactShaped = cleaned.codePoints()
                .anyMatch(cp -> Character.isDigit(cp) || cp == '@' || Character.isISOControl(cp));
        return contactShaped ? null : cleaned;
    }
}
