package com.delivery.connector.corebanking.provider;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import com.delivery.connector.corebanking.BankPostingCommand;
import com.delivery.platform.notifications.DeliveryOutcome;

/**
 * The real Core Banking System.
 *
 * <p><strong>Refuses every posting until the bank's published spec and credentials exist.</strong>
 * That is the honest state of this integration, and it is written as an explicit, loud refusal
 * rather than a plausible-looking implementation guessed from the simulator's shape.
 *
 * <p>The reasoning matters. The simulator's contract is a placeholder invented by this project;
 * Section 12's open decision #5 leaves nobody owning the job of keeping it in step with the real
 * bank. A speculative implementation here would look finished, would pass any test written against
 * the simulator, and would fail on the first real posting — with money involved. A refusal that
 * names what is missing cannot be mistaken for working code.
 *
 * <p>What is real and already proven is everything around it: the provider abstraction, the runtime
 * switch, the resilience, the idempotency key, the sync log. Filling this class in is a
 * contained job once the spec lands — the same argument that has both SMS vendors built.
 */
@Component
public class RealBankClient implements BankClient {

    public static final String NAME = "REAL";

    private static final Logger log = LoggerFactory.getLogger(RealBankClient.class);

    private final String baseUrl;
    private final String clientId;
    private final String clientSecret;

    public RealBankClient(
            @Value("${delivery.corebanking.real.base-url:}") String baseUrl,
            @Value("${delivery.corebanking.real.client-id:}") String clientId,
            @Value("${delivery.corebanking.real.client-secret:}") String clientSecret) {
        this.baseUrl = baseUrl;
        this.clientId = clientId;
        this.clientSecret = clientSecret;
    }

    @Override
    public String name() {
        return NAME;
    }

    @Override
    public Response post(BankPostingCommand command) {
        String missing = whatIsMissing();

        // Permanent, so the saga compensates rather than retrying into a wall — and loud, because
        // switching CORE_BANKING to REAL before this is finished is a serious misconfiguration.
        log.error("REAL core banking provider is active but not implemented ({}). "
                + "Posting {} refused; switch CORE_BANKING back to SIMULATOR in the Backoffice.",
                missing, command.transactionId());

        return new Response(
                DeliveryOutcome.permanentFailure(NAME,
                        "real core banking integration is not implemented: " + missing),
                null,
                null);
    }

    /**
     * UNKNOWN, not REFUSED.
     *
     * <p>The distinction is the whole reason the verdict has three values. This build cannot ask
     * the real bank anything, which is a fact about this connector — refusing every carrier who
     * tried to onboard while REAL was selected would be blaming them for our missing integration.
     */
    @Override
    public AccountCheck lookup(String accountRef) {
        log.error("REAL core banking provider is active but not implemented ({}). "
                + "Account {} cannot be verified.", whatIsMissing(), accountRef);
        return AccountCheck.unknown(accountRef,
                "real core banking integration is not implemented: " + whatIsMissing());
    }

    private String whatIsMissing() {
        StringBuilder missing = new StringBuilder("the bank's published API contract is not agreed");
        if (baseUrl.isBlank()) {
            missing.append("; no base URL configured");
        }
        if (clientId.isBlank() || clientSecret.isBlank()) {
            missing.append("; no credentials in Vault at secret/corebanking-connector");
        }
        return missing.toString();
    }
}
