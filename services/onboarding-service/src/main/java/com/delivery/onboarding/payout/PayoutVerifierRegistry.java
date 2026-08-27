package com.delivery.onboarding.payout;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

/**
 * The runtime switch: which {@link PayoutAccountVerifier} is in charge.
 *
 * <p>Every verifier on the classpath registers itself here by name, and
 * {@code delivery.onboarding.payout.verifier} picks one. Same arrangement as the notification
 * connectors, and for the same reason: the day a payment processor is signed, turning it on should
 * be a configuration change and a restart, not a code change to whatever calls it.
 *
 * <p>An unknown name is fatal at startup rather than at the first bank step. Falling back to the dev
 * verifier when configuration asks for a real one would mean a deployment that believes it is
 * verifying accounts and is not — the one outcome worth crashing to avoid.
 */
@Component
public class PayoutVerifierRegistry {

    private static final Logger log = LoggerFactory.getLogger(PayoutVerifierRegistry.class);

    private final Map<String, PayoutAccountVerifier> byName = new LinkedHashMap<>();
    private final PayoutAccountVerifier active;

    public PayoutVerifierRegistry(
            List<PayoutAccountVerifier> verifiers,
            @Value("${delivery.onboarding.payout.verifier:" + DevChecksumOnlyPayoutVerifier.NAME + "}")
            String configuredName) {

        verifiers.forEach(verifier -> byName.put(verifier.name(), verifier));

        PayoutAccountVerifier chosen = byName.get(configuredName);
        if (chosen == null) {
            throw new IllegalStateException("delivery.onboarding.payout.verifier is '"
                    + configuredName + "' but this build only has " + byName.keySet()
                    + ". Refusing to start rather than quietly using a different one.");
        }
        this.active = chosen;

        if (chosen instanceof DevChecksumOnlyPayoutVerifier) {
            // WARN rather than INFO. This is the deployed state today, and it will stay the
            // deployed state until somebody provisions a processor — a line that is easy to miss is
            // a line that lets everyone forget payout accounts are unverified.
            log.warn("Payout accounts are being checked by {} — check digits only. No bank is "
                            + "contacted, so no account on this platform has been confirmed to "
                            + "exist or to belong to the applicant named.",
                    chosen.name());
        } else {
            log.info("Payout accounts are being verified by {}", chosen.name());
        }
    }

    public PayoutAccountVerifier active() {
        return active;
    }
}
