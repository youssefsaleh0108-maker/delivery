package com.delivery.accounting.service;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import com.delivery.accounting.domain.CounterpartyKind;

/**
 * What to call a counterparty, and where to send them their statement.
 *
 * <p>Both answers come from Keycloak for a person or a shop, because that is where the platform's
 * accounts live and copying names and addresses into an accounting table would create a second
 * source of truth that goes stale the day somebody changes their email. Same reasoning as
 * {@link AccountDirectory}, which this delegates to rather than duplicating: one lookup, one cache,
 * one service-account token.
 *
 * <p><strong>Two kinds it genuinely cannot answer for, and it says so rather than guessing.</strong>
 *
 * <p>A CARRIER's reference is an Order Manager provider id, not a Keycloak subject — a delivery
 * company is a row in another service's table and the people who run it are separate staff accounts.
 * There is therefore no address to resolve here, and the send endpoint refuses with a 409 unless the
 * operator supplies one. Reaching into Order Manager for the company's contact address would be a
 * second cross-service dependency added on the way past; it is the right fix and it is not this
 * change.
 *
 * <p>The PLATFORM is not a user at all. Its statement goes to whichever finance mailbox is
 * configured, and to nowhere at all when nobody has configured one.
 */
@Service
public class CounterpartyDirectory {

    private final AccountDirectory accounts;
    private final String platformName;
    private final String platformRecipient;

    public CounterpartyDirectory(
            AccountDirectory accounts,
            @Value("${delivery.accounting.statements.platform-name:The platform}")
            String platformName,
            // Deliberately blank by default. A wrong default here does not fail loudly — it sends
            // the platform's own figures to somebody's stale inbox — so the absence of a value has
            // to mean "nowhere", and the endpoint refuses rather than picking a fallback.
            @Value("${delivery.accounting.statements.platform-recipient:}")
            String platformRecipient) {
        this.accounts = accounts;
        this.platformName = platformName;
        this.platformRecipient = blankToNull(platformRecipient);
    }

    /**
     * What to head the statement with.
     *
     * <p>Falls back to the reference itself rather than to null: a statement with no name at all is
     * harder to place than one headed with an id, and the caller has nothing better to substitute.
     */
    public String nameOf(CounterpartyKind kind, String ref) {
        if (kind == CounterpartyKind.PLATFORM) {
            return platformName;
        }
        if (kind == CounterpartyKind.CARRIER) {
            // Not a Keycloak subject; see the class note. Asking anyway would spend a round trip to
            // be told 404 on every carrier row in the listing.
            return ref;
        }
        String name = accounts.profileOf(ref).name();
        return name == null || name.isBlank() ? ref : name;
    }

    /**
     * Where the statement would go, or null when nothing on file yields an address.
     *
     * <p>Null is an answer and not a failure. The send endpoint turns it into a 409 with the reason,
     * which is the honest outcome: the platform does not know where to send this, and inventing a
     * best guess would mean a shop's figures arriving in a stranger's inbox.
     */
    public String recipientOf(CounterpartyKind kind, String ref) {
        if (kind == CounterpartyKind.PLATFORM) {
            return platformRecipient;
        }
        if (kind == CounterpartyKind.CARRIER) {
            return null;
        }
        return blankToNull(accounts.profileOf(ref).email());
    }

    private static String blankToNull(String value) {
        return value == null || value.isBlank() ? null : value.trim();
    }
}
