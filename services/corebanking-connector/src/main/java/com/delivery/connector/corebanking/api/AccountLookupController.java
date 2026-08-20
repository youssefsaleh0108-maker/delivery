package com.delivery.connector.corebanking.api;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RestController;

import com.delivery.connector.corebanking.provider.BankClient;
import com.delivery.connector.corebanking.provider.BankClient.AccountCheck;
import com.delivery.platform.notifications.ActiveProviderRegistry;

/**
 * "Does this account exist, and could we pay into it?"
 *
 * <p>The one synchronous way into this connector, and deliberately the only one. The rule stated on
 * {@link ConnectorStatusController} — no HTTP path for postings, because that would make the bank
 * call synchronous again — is about <em>commands</em>. This is a question: it moves no money, needs
 * no idempotency key, cannot be half-done, and its caller is a person waiting at a form. Making it
 * asynchronous would buy nothing and cost the answer.
 *
 * <p>It exists because a carrier's payout account was previously taken on trust at registration and
 * first tested by a real delivery — at which point the money is already collected, the rider has
 * already been, and the {@code PROVIDER_CREDIT} leg fails with nobody to pay.
 */
@RestController
public class AccountLookupController {

    private static final Logger log = LoggerFactory.getLogger(AccountLookupController.class);

    private final Map<String, BankClient> clients = new LinkedHashMap<>();
    private final ActiveProviderRegistry registry;

    public AccountLookupController(List<BankClient> bankClients, ActiveProviderRegistry registry) {
        bankClients.forEach(client -> this.clients.put(client.name(), client));
        this.registry = registry;
    }

    /**
     * Always 200, with the verdict in the body.
     *
     * <p>Answering 404 for an account the bank has never heard of would be the obvious choice and
     * the wrong one: the caller could not then tell it apart from this endpoint being absent, a
     * gateway route being wrong, or the connector being an older build — three things that must not
     * read as "that carrier's account is bad".
     */
    @GetMapping("/api/connector/accounts/{accountRef}")
    @PreAuthorize("hasRole('BACKOFFICE')")
    public AccountCheck check(@PathVariable String accountRef) {
        String provider = registry.activeProvider();
        BankClient client = clients.get(provider);

        if (client == null) {
            log.error("No bank client for active provider {} (have {})", provider, clients.keySet());
            return AccountCheck.unknown(accountRef, "no client for provider " + provider);
        }

        AccountCheck result = client.lookup(accountRef);
        log.info("Account {} checked against {}: {}", accountRef, provider, result.verdict());
        return result;
    }
}
